import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/connection_manager.dart';
import '../../../core/utils/message_content.dart';
import '../../data/models.dart';
import '../../data/backend.dart';
import '../../data/demo_backend.dart';
import '../../data/live_backend.dart';
import 'w1_models.dart';

/// Where proactive cards come from. Live: the Petasos server plugin at
/// `/api/plugins/hermes_mobile/w1/...`. Demo: sample cards kept in memory.
abstract class ProactiveSource {
  Future<ProactiveFeed> load();
  Future<void> dismiss(String id);

  /// Undoes [dismiss] on the server. Throws when the host cannot (an older
  /// Petasos plugin); the caller then keeps the card restored on the phone.
  Future<void> restore(String id);
  Future<void> markRead(String id);
  Future<void> snooze(String id, Duration d);
  Future<void> acted(String id, ProactiveActionKind action);

  /// Saves "more/less of this" to Hermes memory. Returns the saved line.
  Future<String?> feedback(ProactiveCard card, bool more);

  /// Uploads a file to the host; returns the host path the agent can read,
  /// or null when uploads are not available.
  Future<String?> upload(String name, Uint8List bytes, {String? mime});
}

/// Answers a native prompt (sudo, secret, clarify).
typedef PromptResponder =
    Future<void> Function(HermesMobilePrompt prompt, String value);

/// Wave 1 capabilities for whichever backend is active.
class Wave1Services {
  Wave1Services._(this.source, this.respond);

  final ProactiveSource source;
  final PromptResponder respond;

  static final Expando<Wave1Services> _cache = Expando('wave1');

  static Wave1Services of(HermesMobileBackend backend) =>
      _cache[backend] ??= _build(backend);

  static Wave1Services _build(HermesMobileBackend backend) {
    if (backend is LiveBackend) {
      final dash = backend.wave1Dashboard;
      final api = backend.wave1Api;
      return Wave1Services._(
        PluginProactiveSource(
          dash.apiGet,
          (e, b) => dash.apiPost(e, body: b),
          fallback: () => cronFallbackCards(
            dash.getCronJobs,
            (id) async => [
              for (final s in await dash.getCronJobRuns(id, limit: 1))
                (id: s.id, at: s.lastActive > 0 ? s.lastActive : s.startedAt),
            ],
            (sid) => api.getMessages(sid, limit: 20, latest: true),
          ),
        ),
        (p, v) => answerPromptLive(
          api.apiGet,
          (e, b) => api.apiPost(e, body: b),
          p,
          v,
        ),
      );
    }
    final demo = DemoProactiveSource();
    return Wave1Services._(demo, (p, v) async {
      if (backend is DemoBackend) backend.wave1AnswerPrompt(p.chatId, v);
    });
  }
}

typedef JsonGet = Future<Map<String, dynamic>> Function(String endpoint);
typedef JsonPost =
    Future<Map<String, dynamic>> Function(
      String endpoint,
      Map<String, dynamic> body,
    );

/// Answers a clarify (and, where the server supports it, sudo/secret) prompt
/// through the run control API: `POST /v1/runs/{run_id}/{clarify|sudo|secret}`
/// with `{request_id, execution_generation, answer}`.
Future<void> answerPromptLive(
  JsonGet get,
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>) post,
  HermesMobilePrompt p,
  String value,
) async {
  final runId = p.runId;
  if (runId == null || runId.isEmpty) {
    throw StateError(
      'This prompt has no run id. Answer it on the host or in classic view.',
    );
  }
  final endpoint = 'v1/runs/${Uri.encodeComponent(runId)}';
  var generation = p.executionGeneration;
  if (generation == null) {
    final run = await get(endpoint);
    final g = run['execution_generation'];
    generation = g is int ? g : int.tryParse('${g ?? ''}');
  }
  await post('$endpoint/${p.kind.name}', {
    'request_id': p.requestId,
    'execution_generation': ?generation,
    'answer': value,
  });
}

final RegExp _briefName = RegExp(
  r'\b(brief|briefing|digest|recap|summary|morning|evening)\b',
  caseSensitive: false,
);

/// Without the Petasos plugin: briefs from the newest run of brief-like cron
/// jobs (dashboard `cron/jobs/{id}/runs` + the run session's last reply),
/// and an alert card for each job whose last run failed.
Future<List<ProactiveCard>> cronFallbackCards(
  Future<List<Map<String, dynamic>>> Function() jobs,
  Future<List<({String id, double at})>> Function(String jobId) latestRun,
  Future<List<Map<String, dynamic>>> Function(String sessionId) messages, {
  DateTime? now,
}) async {
  final clock = now ?? DateTime.now();
  final out = <ProactiveCard>[];
  var briefsFetched = 0;
  for (final raw in await jobs()) {
    final job = HermesMobileCronJob.fromJson(raw);
    if (job.id.isEmpty) continue;
    final status = (job.lastStatus ?? '').toLowerCase();
    if (status == 'error' || status == 'failed' || status == 'failure') {
      out.add(
        ProactiveCard(
          id: 'cronfail:${job.id}:${job.lastRun ?? ''}',
          kind: 'alert',
          source: 'cron',
          title: '${job.name} failed',
          body: (raw['last_error'] ?? 'The last run failed.').toString(),
          createdAt: clock,
          priority: 2,
          action: ProactiveAction(
            kind: ProactiveActionKind.run,
            label: 'Run again',
            payload: {'cron_id': job.id},
          ),
        ),
      );
    }
    if (!_briefName.hasMatch(job.name) || briefsFetched >= 4) continue;
    briefsFetched++;
    try {
      final runs = await latestRun(job.id);
      if (runs.isEmpty) continue;
      final run = runs.first;
      final at = DateTime.fromMillisecondsSinceEpoch((run.at * 1000).round());
      if (clock.difference(at) > const Duration(hours: 36)) continue;
      final msgs = await messages(run.id);
      final reply = msgs.reversed
          .where((m) => m['role'] == 'assistant')
          .map((m) => messageContentToText(m['content']).trim())
          .where((t) => t.isNotEmpty)
          .firstOrNull;
      if (reply == null) continue;
      out.add(
        ProactiveCard(
          id: 'brief:${job.id}:${run.id}',
          kind: 'brief',
          period: at.hour < 15 ? 'morning' : 'evening',
          source: 'cron',
          title: job.name,
          body: reply.length > 4000 ? '${reply.substring(0, 4000)}…' : reply,
          createdAt: at,
          priority: 1,
          action: const ProactiveAction(
            kind: ProactiveActionKind.reply,
            label: 'Ask about this',
          ),
        ),
      );
    } catch (_) {
      // One job's history failing must not hide the others.
    }
  }
  return out;
}

/// Card state kept on the phone when there is no plugin to store it.
class _LocalCardState {
  static const _key = 'hermes_mobile.w1.local_card_state';

  static Future<Map<String, dynamic>> _read() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return {};
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> set(String id, Map<String, dynamic> change) async {
    final all = await _read();
    final cur = all[id] is Map
        ? Map<String, dynamic>.from(all[id] as Map)
        : <String, dynamic>{};
    all[id] = {...cur, ...change};
    while (all.length > 300) {
      all.remove(all.keys.first);
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(all));
  }

  static Future<List<ProactiveCard>> apply(List<ProactiveCard> cards) async {
    final all = await _read();
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final c in cards)
        if (all[c.id] is! Map ||
            ((all[c.id] as Map)['dismissed'] != true &&
                ((all[c.id] as Map)['snoozed_until'] as num? ?? 0) < now))
          c.copyWith(
            read: all[c.id] is Map && (all[c.id] as Map)['read'] == true,
          ),
    ];
  }
}

/// Talks to the Petasos server plugin through the dashboard client. When the
/// plugin is missing and a [fallback] is given, briefs come from cron runs
/// and card state stays on the phone.
class PluginProactiveSource implements ProactiveSource {
  PluginProactiveSource(this._get, this._post, {this.fallback});

  final Future<Map<String, dynamic>> Function(String) _get;
  final JsonPost _post;
  final Future<List<ProactiveCard>> Function()? fallback;
  bool _local = false;
  static const _base = 'plugins/hermes_mobile/w1';

  static bool _missing(Object e) =>
      e is DashboardHttpException &&
      (e.statusCode == 404 || e.statusCode == 405);

  @override
  Future<ProactiveFeed> load() async {
    try {
      final data = await _get('$_base/feed');
      final raw = data['cards'];
      final cards = raw is List
          ? [
              for (final c in raw)
                if (c is Map)
                  ProactiveCard.fromJson(Map<String, dynamic>.from(c)),
            ]
          : <ProactiveCard>[];
      _local = false;
      return ProactiveFeed(cards: cards);
    } catch (e) {
      if (!_missing(e)) return ProactiveFeed(available: true, error: '$e');
      final fb = fallback;
      if (fb == null) return ProactiveFeed.unavailable;
      _local = true;
      try {
        return ProactiveFeed(
          cards: await _LocalCardState.apply(await fb()),
          pluginMissing: true,
        );
      } catch (_) {
        return ProactiveFeed.unavailable;
      }
    }
  }

  Future<void> _card(String id, String verb, [Map<String, dynamic>? body]) {
    if (_local) {
      final until = DateTime.now()
          .add(Duration(minutes: (body?['minutes'] as num?)?.toInt() ?? 0))
          .millisecondsSinceEpoch;
      return _LocalCardState.set(id, switch (verb) {
        'dismiss' || 'act' => {'dismissed': true},
        'restore' => {'dismissed': false, 'snoozed_until': 0},
        'read' => {'read': true},
        'snooze' => {'snoozed_until': until, 'read': true},
        _ => {},
      });
    }
    return _post(
      '$_base/cards/${Uri.encodeComponent(id)}/$verb',
      body ?? const {},
    );
  }

  @override
  Future<void> dismiss(String id) => _card(id, 'dismiss');

  @override
  Future<void> restore(String id) => _card(id, 'restore');

  @override
  Future<void> markRead(String id) => _card(id, 'read');

  @override
  Future<void> snooze(String id, Duration d) =>
      _card(id, 'snooze', {'minutes': d.inMinutes});

  @override
  Future<void> acted(String id, ProactiveActionKind action) =>
      _card(id, 'act', {'action': action.name});

  @override
  Future<String?> feedback(ProactiveCard card, bool more) async {
    if (_local) {
      throw StateError(
        'Saving feedback to memory needs the Petasos server plugin.',
      );
    }
    final out = await _post('$_base/feedback', {
      'card_id': card.id,
      'signal': more ? 'more' : 'less',
      'source': card.source,
      'kind': card.kind,
      'title': card.title,
    });
    return out['entry']?.toString();
  }

  @override
  Future<String?> upload(String name, Uint8List bytes, {String? mime}) async {
    try {
      final out = await _post('$_base/upload', {
        'name': name,
        'data_b64': base64Encode(bytes),
        'mime': ?mime,
      });
      return out['path']?.toString();
    } catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }
}

/// Sample proactive cards for demo mode.
class DemoProactiveSource implements ProactiveSource {
  DemoProactiveSource() {
    final now = DateTime.now();
    _cards.addAll([
      ProactiveCard(
        id: 'demo-brief-am',
        kind: 'brief',
        period: 'morning',
        source: 'Morning brief',
        title: 'Good morning: 3 things today',
        body:
            '**Calendar**: Daycare pickup 5:15 pm, dentist Thu 9:00.\n\n'
            '**Weather**: 64°F and clear in Springfield, rain after 8 pm.\n\n'
            '**Inbox**: Xfinity refund confirmed (\$42). Two recruiter '
            'emails can wait.',
        createdAt: DateTime(now.year, now.month, now.day, 7),
        priority: 1,
        action: const ProactiveAction(
          kind: ProactiveActionKind.reply,
          label: 'Ask about this',
        ),
      ),
      ProactiveCard(
        id: 'demo-brief-pm',
        kind: 'brief',
        period: 'evening',
        source: 'Evening recap',
        title: 'Evening recap: backups ok, 1 price drop',
        body:
            'Nightly backup verified (restic + B2, 2.1 GB). The Sony '
            'WH-1000XM6 dropped to \$328 at Costco. Tomorrow: 2 meetings, '
            'first at 9:30.',
        createdAt: DateTime(now.year, now.month, now.day, 19),
        priority: 1,
        action: const ProactiveAction(
          kind: ProactiveActionKind.reply,
          label: 'Ask about this',
        ),
      ),
      ProactiveCard(
        id: 'demo-cart',
        kind: 'approval',
        source: 'shopping',
        title: 'Costco cart is ready: \$26.95',
        body: 'Milk 3-pack, bananas, rotisserie chicken. Delivery 5–6 pm.',
        createdAt: now.subtract(const Duration(minutes: 12)),
        priority: 2,
        action: const ProactiveAction(
          kind: ProactiveActionKind.approve,
          label: 'Approve',
          payload: {'prompt': 'Approved. Place the Costco same-day order.'},
        ),
      ),
      ProactiveCard(
        id: 'demo-cron-fail',
        kind: 'alert',
        source: 'cron',
        title: 'Price watch failed',
        body: 'The script exited with code 127: jq not found.',
        createdAt: now.subtract(const Duration(minutes: 40)),
        priority: 2,
        action: const ProactiveAction(
          kind: ProactiveActionKind.run,
          label: 'Run again',
          payload: {'cron_id': 'prices'},
        ),
      ),
      ProactiveCard(
        id: 'demo-watch',
        kind: 'watch',
        source: 'price watch',
        title: 'Flights ATL → AMD under \$1,100',
        body:
            'Qatar via DOH, Dec 18, \$1,064 round trip. Fare rose twice '
            'this week.',
        createdAt: now.subtract(const Duration(hours: 2)),
        action: const ProactiveAction(
          kind: ProactiveActionKind.snooze,
          label: 'Snooze 1 day',
          payload: {'minutes': 1440},
        ),
      ),
      ProactiveCard(
        id: 'demo-reminder',
        kind: 'reminder',
        source: 'reminders',
        title: 'Reply to the daycare about Friday',
        body: 'They asked if Maya is coming on the teacher work day.',
        createdAt: now.subtract(const Duration(hours: 3)),
        action: const ProactiveAction(
          kind: ProactiveActionKind.reply,
          label: 'Reply',
        ),
      ),
    ]);
  }

  final List<ProactiveCard> _cards = [];
  final Set<String> _read = {};
  final List<String> savedFeedback = [];

  @override
  Future<ProactiveFeed> load() async => ProactiveFeed(
    cards: [for (final c in _cards) c.copyWith(read: _read.contains(c.id))],
  );

  @override
  Future<void> dismiss(String id) async {
    for (final c in _cards.where((c) => c.id == id)) {
      _gone[id] = c;
    }
    _cards.removeWhere((c) => c.id == id);
  }

  final Map<String, ProactiveCard> _gone = {};

  @override
  Future<void> restore(String id) async {
    final c = _gone.remove(id);
    if (c != null && !_cards.any((x) => x.id == id)) _cards.add(c);
  }

  @override
  Future<void> markRead(String id) async => _read.add(id);

  @override
  Future<void> snooze(String id, Duration d) async => dismiss(id);

  @override
  Future<void> acted(String id, ProactiveActionKind action) async =>
      dismiss(id);

  @override
  Future<String?> feedback(ProactiveCard card, bool more) async {
    final line =
        'Proactivity preference: the user wants ${more ? 'more' : 'less'} '
        '${card.source} updates.';
    savedFeedback.add(line);
    return line;
  }

  @override
  Future<String?> upload(String name, Uint8List bytes, {String? mime}) async =>
      '~/.hermes/hermes_mobile/uploads/demo/$name';
}
