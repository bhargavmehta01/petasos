import 'dart:async';

import '../../../core/services/connection_manager.dart';
import '../../data/backend.dart';
import '../../data/live_backend.dart';
import '../../data/models.dart';
import 'w4_models.dart';

/// One request to the Petasos plugin: method, path under
/// `/api/plugins/hermes_mobile/w4/`, optional JSON body.
typedef PluginCall =
    Future<Map<String, dynamic>> Function(
      String method,
      String path, [
      Map<String, dynamic>? body,
    ]);

/// Server side of Wave 4. [LiveWave4Api] talks to the Petasos plugin and falls
/// back to plain Hermes cron when the plugin is missing; [DemoWave4Api] serves
/// sample data.
abstract class Wave4Api {
  /// True when the Petasos plugin's Wave 4 routes answer.
  Future<bool> probe();
  bool get pluginAvailable;

  Future<List<HermesMobileWatcher>> watchers();
  Future<HermesMobileWatcher> createWatcher({
    required String title,
    required String target,
    String every = 'Every 6 hours',
    String? condition,
  });
  Future<void> setWatcherPaused(HermesMobileWatcher w, bool paused);
  Future<void> checkWatcherNow(HermesMobileWatcher w);
  Future<void> deleteWatcher(HermesMobileWatcher w);

  /// Commitments the server extracted across all chats (empty without the
  /// plugin; the phone extracts from chats it has open).
  Future<List<HermesMobileCommitment>> commitments();
  Future<void> saveCommitment(HermesMobileCommitment c);

  /// What the agent did on its own since [since].
  Future<List<AutonomousAction>> recap(DateTime since);
  Future<bool> revert(AutonomousAction a);

  /// Outbound actions held for their undo window right now.
  Future<List<HeldOutbound>> heldOutbound();
  Future<bool> undoOutbound(HeldOutbound h);

  Future<ProactivityLevel?> proactivity();

  /// Saves the dial on the server as a standing rule. False when there is no
  /// plugin to write it.
  Future<bool> setProactivity(ProactivityLevel level);

  /// Logs a context trigger firing (for the recap). Best effort.
  Future<void> logTrigger(ContextTrigger t);

  void dispose() {}
}

/// Live Hermes. Plugin routes when present, cron fallbacks otherwise.
class LiveWave4Api extends Wave4Api {
  LiveWave4Api({required this.backend, PluginCall? call})
    : _call = call ?? _dashboardCall(backend);

  final HermesMobileBackend backend;
  final PluginCall? _call;
  bool _plugin = false;
  DateTime? _probedAt;

  static const base = 'plugins/hermes_mobile/w4';

  static PluginCall? _dashboardCall(HermesMobileBackend backend) {
    if (backend is! LiveBackend) return null;
    DashboardClient? client;
    DashboardClient dash() => client ??= DashboardClient.fromConnection(backend.conn);
    return (method, path, [body]) async {
      final endpoint = '$base/$path';
      switch (method) {
        case 'GET':
          return dash().apiGet(endpoint);
        case 'PUT':
          return dash().apiPut(endpoint, body: body);
        case 'DELETE':
          await dash().apiDelete(endpoint);
          return const {};
        default:
          return dash().apiPost(endpoint, body: body);
      }
    };
  }

  @override
  bool get pluginAvailable => _plugin;

  @override
  Future<bool> probe() async {
    final call = _call;
    if (call == null) return _plugin = false;
    final at = _probedAt;
    if (at != null && DateTime.now().difference(at).inMinutes < 5) {
      return _plugin;
    }
    try {
      final r = await call('GET', 'status');
      _plugin = r['ok'] == true || r['features'] is List;
    } catch (_) {
      _plugin = false;
    }
    _probedAt = DateTime.now();
    return _plugin;
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> r, String key) => [
    for (final e in (r[key] is List ? r[key] as List : const []))
      if (e is Map) Map<String, dynamic>.from(e),
  ];

  // ── Watchers ───────────────────────────────────────────────────────

  static HermesMobileWatcher _fromCron(HermesMobileCronJob j) {
    final status = (j.lastStatus ?? '').toLowerCase();
    return HermesMobileWatcher(
      id: 'cron:${j.id}',
      cronId: j.id,
      title: j.name.substring(HermesMobileWatcher.cronPrefix.length).trim(),
      target: _targetFromPrompt(j.prompt),
      every: j.schedule,
      status: j.paused
          ? WatcherStatus.paused
          : status.contains('error') || status.contains('fail')
          ? WatcherStatus.error
          : j.lastRun == null
          ? WatcherStatus.pending
          : WatcherStatus.ok,
      lastChecked: j.lastRun == null ? null : DateTime.tryParse(j.lastRun!),
    );
  }

  static String _targetFromPrompt(String prompt) {
    final m = RegExp(r'Look at: (.+?)\. ').firstMatch(prompt);
    return m?.group(1) ?? prompt;
  }

  @override
  Future<List<HermesMobileWatcher>> watchers() async {
    if (await probe()) {
      final r = await _call!('GET', 'watchers');
      return _list(r, 'watchers').map(HermesMobileWatcher.fromJson).toList();
    }
    final jobs = await backend.listCron();
    return [
      for (final j in jobs)
        if (j.name.startsWith(HermesMobileWatcher.cronPrefix)) _fromCron(j),
    ];
  }

  @override
  Future<HermesMobileWatcher> createWatcher({
    required String title,
    required String target,
    String every = 'Every 6 hours',
    String? condition,
  }) async {
    if (await probe()) {
      final r = await _call!('POST', 'watchers', {
        'title': title,
        'target': target,
        'every': every,
        'condition': ?condition,
      });
      return HermesMobileWatcher.fromJson(
        r['watcher'] is Map ? Map<String, dynamic>.from(r['watcher']) : r,
      );
    }
    await backend.createCron(
      name: '${HermesMobileWatcher.cronPrefix}$title',
      schedule: _cronSchedule(every),
      prompt: HermesMobileWatcher.cronPrompt(target, condition),
    );
    return HermesMobileWatcher(
      id: 'cron:new',
      title: title,
      target: target,
      every: every,
      condition: condition,
    );
  }

  /// Hermes cron accepts "every 6h" style and 5-field expressions.
  static String _cronSchedule(String every) {
    final m = RegExp(r'every (\d+) (minute|hour|day)', caseSensitive: false)
        .firstMatch(every);
    if (m == null) {
      return every.toLowerCase().contains('day') ? 'every 1d' : 'every 6h';
    }
    final unit = switch (m.group(2)!.toLowerCase()) {
      'minute' => 'm',
      'day' => 'd',
      _ => 'h',
    };
    return 'every ${m.group(1)}$unit';
  }

  @override
  Future<void> setWatcherPaused(HermesMobileWatcher w, bool paused) async {
    if (w.cronId != null && w.id.startsWith('cron:')) {
      return backend.setCronPaused(w.cronId!, paused);
    }
    await _call!('POST', 'watchers/${w.id}/${paused ? 'pause' : 'resume'}');
  }

  @override
  Future<void> checkWatcherNow(HermesMobileWatcher w) async {
    if (w.cronId != null) return backend.runCron(w.cronId!);
    await _call!('POST', 'watchers/${w.id}/check');
  }

  @override
  Future<void> deleteWatcher(HermesMobileWatcher w) async {
    if (w.id.startsWith('cron:') && w.cronId != null) {
      return backend.deleteCron(w.cronId!);
    }
    await _call!('DELETE', 'watchers/${w.id}');
  }

  // ── Commitments ────────────────────────────────────────────────────

  @override
  Future<List<HermesMobileCommitment>> commitments() async {
    if (!await probe()) return const [];
    final r = await _call!('GET', 'commitments');
    return _list(r, 'commitments').map(HermesMobileCommitment.fromJson).toList();
  }

  @override
  Future<void> saveCommitment(HermesMobileCommitment c) async {
    if (!await probe()) return;
    await _call!('PUT', 'commitments/${c.id}', c.toJson());
  }

  // ── Recap and undo ─────────────────────────────────────────────────

  @override
  Future<List<AutonomousAction>> recap(DateTime since) async {
    if (await probe()) {
      final r = await _call!(
        'GET',
        'recap?since=${since.toUtc().millisecondsSinceEpoch ~/ 1000}',
      );
      return _list(r, 'actions').map(AutonomousAction.fromJson).toList();
    }
    // Without the plugin: cron runs since [since], read-only.
    final jobs = await backend.listCron();
    final out = <AutonomousAction>[];
    for (final j in jobs) {
      final at = j.lastRun == null ? null : DateTime.tryParse(j.lastRun!);
      if (at == null || at.isBefore(since)) continue;
      final status = (j.lastStatus ?? '').toLowerCase();
      out.add(
        AutonomousAction(
          id: 'cron:${j.id}',
          summary: 'Ran "${j.name}"',
          at: at.toLocal(),
          kind: 'cron',
          ok: !(status.contains('error') || status.contains('fail')),
          detail: j.lastStatus,
        ),
      );
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  @override
  Future<bool> revert(AutonomousAction a) async {
    if (!a.revertible || !await probe()) return false;
    final r = await _call!('POST', 'actions/${a.id}/revert');
    return r['ok'] == true;
  }

  @override
  Future<List<HeldOutbound>> heldOutbound() async {
    if (!await probe()) return const [];
    final r = await _call!('GET', 'outbound');
    return _list(r, 'held').map(HeldOutbound.fromJson).toList();
  }

  @override
  Future<bool> undoOutbound(HeldOutbound h) async {
    if (!await probe()) return false;
    final r = await _call!('POST', 'outbound/${h.id}/undo');
    return r['ok'] == true;
  }

  // ── Proactivity ────────────────────────────────────────────────────

  @override
  Future<ProactivityLevel?> proactivity() async {
    if (!await probe()) return null;
    final r = await _call!('GET', 'proactivity');
    return r['level'] == null ? null : ProactivityLevelX.parse(r['level']);
  }

  @override
  Future<bool> setProactivity(ProactivityLevel level) async {
    if (!await probe()) return false;
    final r = await _call!('PUT', 'proactivity', {'level': level.name});
    return r['ok'] == true;
  }

  @override
  Future<void> logTrigger(ContextTrigger t) async {
    if (!await probe()) return;
    try {
      await _call!('POST', 'triggers/fired', {
        'kind': t.kind.wire,
        'prompt': t.effectivePrompt,
      });
    } catch (_) {}
  }
}

/// Sample data for demo mode and tests.
class DemoWave4Api extends Wave4Api {
  DemoWave4Api({DateTime? now}) : _now = now ?? DateTime.now() {
    _seed();
  }

  final DateTime _now;
  final List<HermesMobileWatcher> _watchers = [];
  final List<HermesMobileCommitment> _commitments = [];
  final List<AutonomousAction> _actions = [];
  final List<HeldOutbound> _held = [];
  ProactivityLevel _level = ProactivityLevel.balanced;
  final List<ContextTrigger> fired = [];
  int _seq = 0;

  void _seed() {
    final today = DateTime(_now.year, _now.month, _now.day);
    _watchers.addAll([
      HermesMobileWatcher(
        id: 'w1',
        title: 'Sony WH-1000XM6 price',
        target: 'https://www.bestbuy.com/site/sony-wh1000xm6',
        every: 'Every 6 hours',
        condition: 'below \$300',
        status: WatcherStatus.changed,
        lastValue: '\$279.99',
        lastChange: 'Dropped \$120 overnight. Below your \$300 line.',
        lastChecked: _now.subtract(const Duration(minutes: 40)),
        history: const ['\$399.99', '\$349.99', '\$279.99'],
      ),
      HermesMobileWatcher(
        id: 'w2',
        title: 'Passport renewal status',
        target: 'travel.state.gov application status',
        every: 'Every day',
        status: WatcherStatus.ok,
        lastValue: 'In process',
        lastChecked: _now.subtract(const Duration(hours: 5)),
      ),
      HermesMobileWatcher(
        id: 'w3',
        title: 'Nightly backup freshness',
        target: 'restic snapshots on the home server',
        every: 'Every day',
        status: WatcherStatus.error,
        lastValue: 'Last snapshot 31h ago',
        lastChange: 'Missed last night\'s run.',
        lastChecked: _now.subtract(const Duration(hours: 2)),
      ),
      HermesMobileWatcher(
        id: 'w4',
        title: 'Costco rotisserie oven deal',
        target: 'costco.com item 1789',
        every: 'Every 12 hours',
        status: WatcherStatus.paused,
      ),
    ]);
    _commitments.addAll([
      HermesMobileCommitment(
        id: 'k1',
        text: "I'll check the Delta fare again on Friday",
        owner: CommitmentOwner.agent,
        due: today.add(Duration(days: (5 - _now.weekday) % 7, hours: 9)),
        chatId: 'demo-1',
        chatTitle: 'Thanksgiving flights',
        source: 'server',
      ),
      HermesMobileCommitment(
        id: 'k2',
        text: 'Call the pediatrician about the flu shot',
        owner: CommitmentOwner.user,
        due: today.add(const Duration(hours: 17)),
        chatId: 'demo-2',
        chatTitle: 'This week',
        source: 'server',
      ),
      HermesMobileCommitment(
        id: 'k3',
        text: "I'll send the backup report once the rerun finishes",
        owner: CommitmentOwner.agent,
        due: today.subtract(const Duration(hours: 3)),
        chatId: 'demo-3',
        chatTitle: 'Backup check',
        source: 'server',
      ),
    ]);
    final night = today.subtract(const Duration(hours: 2));
    _actions.addAll([
      AutonomousAction(
        id: 'a1',
        summary: 'Archived 23 promo emails',
        detail: 'Gmail: moved to "Promotions/Archived". All 23 can be restored.',
        at: night.add(const Duration(hours: 3, minutes: 10)),
        kind: 'message',
        revertible: true,
      ),
      AutonomousAction(
        id: 'a2',
        summary: 'Ran "Nightly backup check"',
        detail: 'Restic snapshot missing; I reran it at 3:12 and it passed.',
        at: night.add(const Duration(hours: 5, minutes: 12)),
        kind: 'cron',
      ),
      AutonomousAction(
        id: 'a3',
        summary: 'Updated the price-watch panel',
        detail: 'Sony headphones dropped to \$279.99.',
        at: night.add(const Duration(hours: 6)),
        kind: 'watcher',
      ),
      AutonomousAction(
        id: 'a4',
        summary: 'Declined a calendar invite: "Vendor sync"',
        detail: 'Conflicted with daycare pickup. I can re-accept it.',
        at: night.add(const Duration(hours: 7, minutes: 30)),
        kind: 'message',
        revertible: true,
      ),
    ]);
  }

  bool _available = true;

  /// Tests flip this to see the plugin-missing paths.
  set available(bool v) => _available = v;

  @override
  bool get pluginAvailable => _available;

  @override
  Future<bool> probe() async => _available;

  @override
  Future<List<HermesMobileWatcher>> watchers() async => List.of(_watchers);

  @override
  Future<HermesMobileWatcher> createWatcher({
    required String title,
    required String target,
    String every = 'Every 6 hours',
    String? condition,
  }) async {
    final w = HermesMobileWatcher(
      id: 'w${100 + _seq++}',
      title: title,
      target: target,
      every: every,
      condition: condition,
      status: WatcherStatus.pending,
    );
    _watchers.insert(0, w);
    return w;
  }

  int _indexOf(HermesMobileWatcher w) => _watchers.indexWhere((x) => x.id == w.id);

  @override
  Future<void> setWatcherPaused(HermesMobileWatcher w, bool paused) async {
    final i = _indexOf(w);
    if (i < 0) return;
    _watchers[i] = _watchers[i].copyWith(
      status: paused ? WatcherStatus.paused : WatcherStatus.pending,
    );
  }

  @override
  Future<void> checkWatcherNow(HermesMobileWatcher w) async {
    final i = _indexOf(w);
    if (i < 0) return;
    _watchers[i] = _watchers[i].copyWith(
      status: WatcherStatus.ok,
      lastChecked: DateTime.now(),
      lastValue: _watchers[i].lastValue ?? 'No change',
    );
  }

  @override
  Future<void> deleteWatcher(HermesMobileWatcher w) async =>
      _watchers.removeWhere((x) => x.id == w.id);

  @override
  Future<List<HermesMobileCommitment>> commitments() async => List.of(_commitments);

  @override
  Future<void> saveCommitment(HermesMobileCommitment c) async {
    final i = _commitments.indexWhere((x) => x.id == c.id);
    if (i >= 0) _commitments[i] = c;
  }

  @override
  Future<List<AutonomousAction>> recap(DateTime since) async =>
      _actions.where((a) => !a.at.isBefore(since)).toList()
        ..sort((a, b) => b.at.compareTo(a.at));

  @override
  Future<bool> revert(AutonomousAction a) async {
    final i = _actions.indexWhere((x) => x.id == a.id);
    if (i < 0 || !_actions[i].revertible) return false;
    _actions[i] = _actions[i].copyWith(reverted: true);
    return true;
  }

  @override
  Future<List<HeldOutbound>> heldOutbound() async {
    final now = DateTime.now();
    _held.removeWhere((h) => !h.releaseAt.isAfter(now));
    return List.of(_held);
  }

  /// Demo: pretend the agent is about to send an email.
  HeldOutbound simulateOutbound(String summary) {
    final h = HeldOutbound(
      id: 'h${_seq++}',
      summary: summary,
      releaseAt: DateTime.now().add(const Duration(seconds: 10)),
      kind: 'email',
    );
    _held.add(h);
    return h;
  }

  @override
  Future<bool> undoOutbound(HeldOutbound h) async {
    final before = _held.length;
    _held.removeWhere((x) => x.id == h.id);
    return _held.length < before;
  }

  @override
  Future<ProactivityLevel?> proactivity() async => _level;

  @override
  Future<bool> setProactivity(ProactivityLevel level) async {
    _level = level;
    return _available;
  }

  @override
  Future<void> logTrigger(ContextTrigger t) async => fired.add(t);
}

/// The right API for a backend.
Wave4Api wave4ApiFor(HermesMobileBackend backend) =>
    backend.isDemo ? DemoWave4Api() : LiveWave4Api(backend: backend);
