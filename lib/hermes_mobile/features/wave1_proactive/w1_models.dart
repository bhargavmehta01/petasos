/// Wave 1 view models: proactive cards, the feed, and native agent prompts.
library;

/// The one action a proactive card offers.
enum ProactiveActionKind { approve, snooze, reply, run, open }

class ProactiveAction {
  const ProactiveAction({
    required this.kind,
    required this.label,
    this.payload = const {},
  });
  final ProactiveActionKind kind;
  final String label;
  final Map<String, dynamic> payload;

  static ProactiveAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = ProactiveActionKind.values
        .where((k) => k.name == raw['kind']?.toString())
        .firstOrNull;
    if (kind == null) return null;
    final payload = raw['payload'];
    return ProactiveAction(
      kind: kind,
      label: (raw['label'] ?? defaultLabel(kind)).toString(),
      payload: payload is Map ? Map<String, dynamic>.from(payload) : const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'label': label,
    if (payload.isNotEmpty) 'payload': payload,
  };

  static String defaultLabel(ProactiveActionKind k) => switch (k) {
    ProactiveActionKind.approve => 'Approve',
    ProactiveActionKind.snooze => 'Snooze',
    ProactiveActionKind.reply => 'Reply',
    ProactiveActionKind.run => 'Run',
    ProactiveActionKind.open => 'Open',
  };
}

/// A card the agent (or a cron job) put in front of the user.
class ProactiveCard {
  const ProactiveCard({
    required this.id,
    required this.title,
    this.body = '',
    this.kind = 'suggestion',
    this.period,
    this.source = 'agent',
    required this.createdAt,
    this.priority = 0,
    this.chatId,
    this.action,
    this.read = false,
    this.local = false,
  });

  final String id;
  final String title;
  final String body;

  /// brief, approval, alert, reminder, watch, suggestion, digest.
  final String kind;

  /// morning or evening for briefs.
  final String? period;
  final String source;
  final DateTime createdAt;
  final int priority;
  final String? chatId;
  final ProactiveAction? action;
  final bool read;

  /// Built on the phone (a pending approval), not stored by the server.
  final bool local;

  bool get isBrief => kind == 'brief' || kind == 'digest';

  ProactiveCard copyWith({bool? read}) => ProactiveCard(
    id: id,
    title: title,
    body: body,
    kind: kind,
    period: period,
    source: source,
    createdAt: createdAt,
    priority: priority,
    chatId: chatId,
    action: action,
    read: read ?? this.read,
    local: local,
  );

  /// Round-trips through [ProactiveCard.fromJson] (used by the local
  /// Dismissed store).
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'kind': kind,
    if (period != null) 'period': period,
    'source': source,
    'created_at': createdAt.millisecondsSinceEpoch,
    'priority': priority,
    if (chatId != null) 'chat_id': chatId,
    if (action != null) 'action': action!.toJson(),
    'read': read,
  };

  factory ProactiveCard.fromJson(Map<String, dynamic> j) {
    final ts = j['created_at'];
    final created = ts is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (ts > 1e12 ? ts : ts * 1000).round(),
          )
        : (ts is String ? DateTime.tryParse(ts)?.toLocal() : null);
    return ProactiveCard(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      kind: (j['kind'] ?? 'suggestion').toString(),
      period: j['period']?.toString(),
      source: (j['source'] ?? 'agent').toString(),
      createdAt: created ?? DateTime.now(),
      priority: (j['priority'] as num?)?.toInt() ?? 0,
      chatId: j['chat_id']?.toString(),
      action: ProactiveAction.fromJson(j['action']),
      read: j['read'] == true,
    );
  }
}

/// The feed as one load returned it.
class ProactiveFeed {
  const ProactiveFeed({
    this.cards = const [],
    this.available = true,
    this.error,
    this.pluginMissing = false,
  });

  /// Cards came from the no-plugin fallback (cron runs); feedback and
  /// uploads are unavailable.
  final bool pluginMissing;

  final List<ProactiveCard> cards;

  /// False when the Petasos server plugin is not installed (show setup help).
  final bool available;
  final String? error;

  static const unavailable = ProactiveFeed(available: false);
}

/// A native prompt the agent is blocked on: sudo password, secret, or a
/// clarifying question.
enum HermesMobilePromptKind { sudo, secret, clarify }

class HermesMobilePrompt {
  const HermesMobilePrompt({
    required this.kind,
    required this.chatId,
    required this.requestId,
    required this.title,
    required this.description,
    this.choices = const [],
    this.multiSelect = false,
    this.questionId,
    this.runId,
    this.executionGeneration,
    this.raw = const {},
  });

  final HermesMobilePromptKind kind;
  final String chatId;
  final String requestId;
  final String title;
  final String description;
  final List<String> choices;
  final bool multiSelect;
  final String? questionId;
  final String? runId;
  final int? executionGeneration;
  final Map<String, dynamic> raw;

  bool get isSensitive => kind != HermesMobilePromptKind.clarify;

  /// Status payloads tagged `hermes_mobile_control` carry prompts (the engine routes
  /// `clarify.request` / `sudo.request` / `secret.request` SSE events there).
  static HermesMobilePrompt? fromControl(String chatId, Map<String, dynamic> data) {
    final type = (data['hermes_mobile_control'] ?? data['type'] ?? '').toString();
    final kind = type.startsWith('sudo')
        ? HermesMobilePromptKind.sudo
        : type.startsWith('secret')
        ? HermesMobilePromptKind.secret
        : type.startsWith('clarify')
        ? HermesMobilePromptKind.clarify
        : null;
    if (kind == null) return null;
    final requestId = (data['request_id'] ?? data['prompt_id'] ?? '')
        .toString()
        .trim();
    if (requestId.isEmpty) return null;
    String? questionId;
    var question = (data['question'] ?? data['prompt'] ?? '').toString();
    var choices = <String>[];
    var multi = data['multi_select'] == true;
    final qs = data['questions'];
    if (qs is List && qs.isNotEmpty && qs.first is Map) {
      final q = Map<String, dynamic>.from(qs.first as Map);
      questionId = q['qid']?.toString();
      question = (q['question'] ?? question).toString();
      multi = q['multi_select'] == true;
      if (q['choices'] is List) {
        choices = [for (final c in q['choices'] as List) _choice(c)];
      }
    } else if (data['choices'] is List) {
      choices = [for (final c in data['choices'] as List) _choice(c)];
    }
    choices = choices.where((c) => c.trim().isNotEmpty).toList();
    final gen = data['execution_generation'];
    final envVar = (data['env_var'] ?? '').toString().trim();
    return HermesMobilePrompt(
      kind: kind,
      chatId: chatId,
      requestId: requestId,
      title: switch (kind) {
        HermesMobilePromptKind.sudo => 'Administrator password needed',
        HermesMobilePromptKind.secret => envVar.isEmpty ? 'Secret needed' : envVar,
        HermesMobilePromptKind.clarify => 'Hermes has a question',
      },
      description: switch (kind) {
        HermesMobilePromptKind.sudo =>
          question.isEmpty
              ? 'Hermes needs a sudo password for the pending terminal command.'
              : question,
        HermesMobilePromptKind.secret =>
          question.isEmpty
              ? 'Hermes needs a secret for the pending skill.'
              : question,
        HermesMobilePromptKind.clarify =>
          question.isEmpty ? 'Hermes needs more detail.' : question,
      },
      choices: choices,
      multiSelect: multi,
      questionId: questionId,
      runId: data['run_id']?.toString(),
      executionGeneration: gen is int ? gen : int.tryParse('${gen ?? ''}'),
      raw: data,
    );
  }

  static String _choice(Object? c) {
    if (c is Map) {
      return (c['label'] ?? c['value'] ?? c['text'] ?? '').toString();
    }
    return '${c ?? ''}';
  }
}
