/// Wave 4 view models: watchers, commitments, the overnight recap, held
/// outbound actions, the proactivity dial and context triggers.
///
/// Every model reads tolerant JSON (the Petasos server plugin's
/// `/api/plugins/hermes_mobile/w4/...` routes) and writes the same shape back, so the
/// phone can keep a local copy when the plugin is missing.
library;

String? _s(Object? v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

DateTime? _t(Object? v) {
  if (v == null) return null;
  if (v is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (v > 1e12 ? v : v * 1000).round(),
    );
  }
  return DateTime.tryParse(v.toString())?.toLocal();
}

String? _iso(DateTime? t) => t?.toUtc().toIso8601String();

// ── Watchers ─────────────────────────────────────────────────────────────

enum WatcherStatus { ok, changed, error, paused, pending }

WatcherStatus _watcherStatus(Object? v) => switch (_s(v)) {
  'changed' || 'alert' || 'triggered' => WatcherStatus.changed,
  'error' || 'failed' => WatcherStatus.error,
  'paused' => WatcherStatus.paused,
  'pending' || 'new' => WatcherStatus.pending,
  _ => WatcherStatus.ok,
};

/// Something the agent keeps an eye on (a price, a page, a status) and checks
/// on a schedule. On a server without the plugin a watcher is a Hermes cron
/// job named "Watch: …".
class HermesMobileWatcher {
  const HermesMobileWatcher({
    required this.id,
    required this.title,
    required this.target,
    this.every = 'Every 6 hours',
    this.status = WatcherStatus.pending,
    this.lastValue,
    this.lastChange,
    this.lastChecked,
    this.condition,
    this.cronId,
    this.history = const [],
  });

  final String id;
  final String title;

  /// What is watched: a URL, an item or a plain description.
  final String target;
  final String every;
  final WatcherStatus status;
  final String? lastValue;

  /// One line on what changed at the last alert ("Dropped to $279").
  final String? lastChange;
  final DateTime? lastChecked;

  /// When to alert ("below $300", "when it is back in stock").
  final String? condition;

  /// The cron job that runs the checks, when there is one.
  final String? cronId;
  final List<String> history;

  bool get paused => status == WatcherStatus.paused;

  HermesMobileWatcher copyWith({
    WatcherStatus? status,
    String? lastValue,
    String? lastChange,
    DateTime? lastChecked,
  }) => HermesMobileWatcher(
    id: id,
    title: title,
    target: target,
    every: every,
    status: status ?? this.status,
    lastValue: lastValue ?? this.lastValue,
    lastChange: lastChange ?? this.lastChange,
    lastChecked: lastChecked ?? this.lastChecked,
    condition: condition,
    cronId: cronId,
    history: history,
  );

  factory HermesMobileWatcher.fromJson(Map<String, dynamic> j) => HermesMobileWatcher(
    id: _s(j['id']) ?? '',
    title: _s(j['title']) ?? _s(j['name']) ?? 'Watcher',
    target: _s(j['target']) ?? _s(j['url']) ?? '',
    every: _s(j['every']) ?? _s(j['schedule']) ?? 'Every 6 hours',
    status: _watcherStatus(j['status']),
    lastValue: _s(j['last_value']),
    lastChange: _s(j['last_change']),
    lastChecked: _t(j['last_checked']),
    condition: _s(j['condition']),
    cronId: _s(j['cron_id']),
    history: [
      for (final h in (j['history'] is List ? j['history'] as List : const []))
        h.toString(),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'target': target,
    'every': every,
    'status': status.name,
    'last_value': ?lastValue,
    'last_change': ?lastChange,
    'last_checked': ?_iso(lastChecked),
    'condition': ?condition,
    'cron_id': ?cronId,
    'history': history,
  };

  /// Prefix that marks a cron job as a watcher on plugin-less servers.
  static const cronPrefix = 'Watch: ';

  /// Cron prompt for a watcher: the agent checks, compares with last time and
  /// only reports when the condition is met.
  static String cronPrompt(String target, String? condition) =>
      'Watcher check. Look at: $target. '
      '${condition == null || condition.isEmpty ? 'Tell me only if something important changed since the last check.' : 'Alert me only when: $condition.'} '
      'Start your reply with one status word: OK, CHANGED or ERROR, then one '
      'short line with the current value.';
}

/// A watcher the app suggests after the user asked the same thing again.
class WatcherProposal {
  const WatcherProposal({
    required this.topic,
    required this.count,
    required this.chatIds,
  });
  final String topic;
  final int count;
  final List<String> chatIds;
}

// ── Commitments ──────────────────────────────────────────────────────────

enum CommitmentOwner { agent, user }

/// A promise made in a chat ("I'll check back Friday", "remind me to call the
/// bank") collected into one due list.
class HermesMobileCommitment {
  const HermesMobileCommitment({
    required this.id,
    required this.text,
    this.owner = CommitmentOwner.agent,
    this.due,
    this.chatId,
    this.chatTitle,
    this.done = false,
    this.source = 'chat',
    this.quote,
  });

  final String id;
  final String text;
  final CommitmentOwner owner;
  final DateTime? due;
  final String? chatId;
  final String? chatTitle;
  final bool done;

  /// Where it came from: "chat" (extracted on the phone) or "server".
  final String source;

  /// The sentence it was extracted from.
  final String? quote;

  bool overdue(DateTime now) => !done && due != null && due!.isBefore(now);

  HermesMobileCommitment copyWith({bool? done, DateTime? due}) => HermesMobileCommitment(
    id: id,
    text: text,
    owner: owner,
    due: due ?? this.due,
    chatId: chatId,
    chatTitle: chatTitle,
    done: done ?? this.done,
    source: source,
    quote: quote,
  );

  factory HermesMobileCommitment.fromJson(Map<String, dynamic> j) => HermesMobileCommitment(
    id: _s(j['id']) ?? '',
    text: _s(j['text']) ?? '',
    owner: _s(j['owner']) == 'user'
        ? CommitmentOwner.user
        : CommitmentOwner.agent,
    due: _t(j['due']),
    chatId: _s(j['chat_id']) ?? _s(j['session_id']),
    chatTitle: _s(j['chat_title']),
    done: j['done'] == true || j['status'] == 'done',
    source: _s(j['source']) ?? 'server',
    quote: _s(j['quote']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'owner': owner.name,
    'due': ?_iso(due),
    'chat_id': ?chatId,
    'chat_title': ?chatTitle,
    'done': done,
    'source': source,
    'quote': ?quote,
  };
}

// ── Overnight recap ──────────────────────────────────────────────────────

/// One thing the agent did on its own (a cron run, a sent message, a file
/// change), shown in "While you slept" with Revert when the server can undo it.
class AutonomousAction {
  const AutonomousAction({
    required this.id,
    required this.summary,
    required this.at,
    this.kind = 'task',
    this.detail,
    this.revertible = false,
    this.reverted = false,
    this.chatId,
    this.ok = true,
  });

  final String id;
  final String summary;
  final DateTime at;

  /// cron | message | file | purchase | watcher | task
  final String kind;
  final String? detail;
  final bool revertible;
  final bool reverted;
  final String? chatId;
  final bool ok;

  AutonomousAction copyWith({bool? reverted}) => AutonomousAction(
    id: id,
    summary: summary,
    at: at,
    kind: kind,
    detail: detail,
    revertible: revertible,
    reverted: reverted ?? this.reverted,
    chatId: chatId,
    ok: ok,
  );

  factory AutonomousAction.fromJson(Map<String, dynamic> j) => AutonomousAction(
    id: _s(j['id']) ?? '',
    summary: _s(j['summary']) ?? _s(j['title']) ?? 'Action',
    at: _t(j['at']) ?? _t(j['created_at']) ?? DateTime.now(),
    kind: _s(j['kind']) ?? 'task',
    detail: _s(j['detail']),
    revertible: j['revertible'] == true,
    reverted: j['reverted'] == true,
    chatId: _s(j['chat_id']) ?? _s(j['session_id']),
    ok: j['ok'] != false && j['status'] != 'error',
  );
}

/// An outbound action the server is holding for its undo window (an email,
/// a message, an order) before it really goes out.
class HeldOutbound {
  const HeldOutbound({
    required this.id,
    required this.summary,
    required this.releaseAt,
    this.kind = 'message',
  });
  final String id;
  final String summary;
  final DateTime releaseAt;
  final String kind;

  Duration remaining(DateTime now) {
    final d = releaseAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  factory HeldOutbound.fromJson(Map<String, dynamic> j) => HeldOutbound(
    id: _s(j['id']) ?? '',
    summary: _s(j['summary']) ?? 'Outbound action',
    releaseAt: _t(j['release_at']) ?? DateTime.now(),
    kind: _s(j['kind']) ?? 'message',
  );
}

// ── Proactivity dial ─────────────────────────────────────────────────────

enum ProactivityLevel { quiet, balanced, chatty }

extension ProactivityLevelX on ProactivityLevel {
  String get label => switch (this) {
    ProactivityLevel.quiet => 'Quiet',
    ProactivityLevel.balanced => 'Balanced',
    ProactivityLevel.chatty => 'Chatty',
  };

  String get blurb => switch (this) {
    ProactivityLevel.quiet =>
      'Only what needs you: approvals, failures and alerts you set up.',
    ProactivityLevel.balanced =>
      'Alerts plus a short daily recap and the odd useful suggestion.',
    ProactivityLevel.chatty =>
      'Suggestions, watcher ideas and context nudges as they come up.',
  };

  /// The standing rule written to the agent's memory.
  String get rule => switch (this) {
    ProactivityLevel.quiet =>
      'Proactivity: quiet. Only reach out for approvals, failures and alerts '
          'the user set up. No suggestions or unrequested summaries.',
    ProactivityLevel.balanced =>
      'Proactivity: balanced. Reach out for approvals, failures and alerts, '
          'one short daily recap, and a suggestion only when clearly useful.',
    ProactivityLevel.chatty =>
      'Proactivity: chatty. Proactive suggestions, watcher ideas and context '
          'nudges are welcome, still batched and never more than hourly.',
  };

  static ProactivityLevel parse(Object? v) => switch (_s(v)) {
    'quiet' => ProactivityLevel.quiet,
    'chatty' => ProactivityLevel.chatty,
    _ => ProactivityLevel.balanced,
  };
}

// ── Context triggers ─────────────────────────────────────────────────────

enum ContextTriggerKind { arriveHome, carBluetooth, chargingAtNight, calendarEnd }

extension ContextTriggerKindX on ContextTriggerKind {
  String get label => switch (this) {
    ContextTriggerKind.arriveHome => 'Arrive home',
    ContextTriggerKind.carBluetooth => 'Car Bluetooth connects',
    ContextTriggerKind.chargingAtNight => 'Charging at night',
    ContextTriggerKind.calendarEnd => 'Calendar event ends',
  };

  String get explain => switch (this) {
    ContextTriggerKind.arriveHome =>
      'Uses a geofence around home. Needs location, "Allow all the time".',
    ContextTriggerKind.carBluetooth =>
      'Runs when the phone connects to your car\'s Bluetooth.',
    ContextTriggerKind.chargingAtNight =>
      'Runs when you plug in between 9 pm and 2 am.',
    ContextTriggerKind.calendarEnd =>
      'Runs when a meeting on this phone\'s calendar ends.',
  };

  String get defaultPrompt => switch (this) {
    ContextTriggerKind.arriveHome =>
      'I just got home. Anything I should know or do this evening?',
    ContextTriggerKind.carBluetooth =>
      'I\'m starting a drive. Traffic to my next place and anything urgent, '
          'short enough to hear.',
    ContextTriggerKind.chargingAtNight =>
      'Wrapping up for the night. Recap today and what is due tomorrow.',
    ContextTriggerKind.calendarEnd =>
      'My meeting just ended. Capture follow-ups and promises from it.',
  };

  String get wire => switch (this) {
    ContextTriggerKind.arriveHome => 'arrive_home',
    ContextTriggerKind.carBluetooth => 'car_bluetooth',
    ContextTriggerKind.chargingAtNight => 'charging_night',
    ContextTriggerKind.calendarEnd => 'calendar_end',
  };

  static ContextTriggerKind? parse(String? wire) {
    for (final k in ContextTriggerKind.values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

/// One opt-in trigger. Everything is off until the user turns it on.
class ContextTrigger {
  const ContextTrigger({
    required this.kind,
    this.enabled = false,
    this.prompt,
    this.param,
    this.lastFired,
  });
  final ContextTriggerKind kind;
  final bool enabled;
  final String? prompt;

  /// Bluetooth device name for the car, or "lat,lng,radiusM" for home.
  final String? param;
  final DateTime? lastFired;

  String get effectivePrompt =>
      (prompt?.trim().isNotEmpty ?? false) ? prompt!.trim() : kind.defaultPrompt;

  ContextTrigger copyWith({
    bool? enabled,
    String? prompt,
    String? param,
    DateTime? lastFired,
  }) => ContextTrigger(
    kind: kind,
    enabled: enabled ?? this.enabled,
    prompt: prompt ?? this.prompt,
    param: param ?? this.param,
    lastFired: lastFired ?? this.lastFired,
  );

  factory ContextTrigger.fromJson(Map<String, dynamic> j) => ContextTrigger(
    kind:
        ContextTriggerKindX.parse(_s(j['kind'])) ?? ContextTriggerKind.arriveHome,
    enabled: j['enabled'] == true,
    prompt: _s(j['prompt']),
    param: _s(j['param']),
    lastFired: _t(j['last_fired']),
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.wire,
    'enabled': enabled,
    'prompt': ?prompt,
    'param': ?param,
    'last_fired': ?_iso(lastFired),
  };
}

// ── Offline queue ────────────────────────────────────────────────────────

/// A message typed while Hermes was unreachable. It sends on reconnect.
class QueuedMessage {
  const QueuedMessage({
    required this.id,
    required this.chatId,
    required this.text,
    required this.queuedAt,
    this.chatTitle,
    this.imageDataUrl,
  });
  final String id;
  final String chatId;
  final String text;
  final DateTime queuedAt;
  final String? chatTitle;
  final String? imageDataUrl;

  factory QueuedMessage.fromJson(Map<String, dynamic> j) => QueuedMessage(
    id: _s(j['id']) ?? '',
    chatId: _s(j['chat_id']) ?? '',
    text: (j['text'] ?? '').toString(),
    queuedAt: _t(j['queued_at']) ?? DateTime.now(),
    chatTitle: _s(j['chat_title']),
    imageDataUrl: _s(j['image']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'chat_id': chatId,
    'text': text,
    'queued_at': _iso(queuedAt),
    'chat_title': ?chatTitle,
    'image': ?imageDataUrl,
  };
}

/// A snapshot for small surfaces: the Wear OS tile and widgets.
class Wave4Glance {
  const Wave4Glance({
    this.watchersChanged = 0,
    this.commitmentsDue = 0,
    this.overnightActions = 0,
    this.queued = 0,
    this.headline,
  });
  final int watchersChanged;
  final int commitmentsDue;
  final int overnightActions;
  final int queued;
  final String? headline;

  Map<String, dynamic> toJson() => {
    'watchers_changed': watchersChanged,
    'commitments_due': commitmentsDue,
    'overnight_actions': overnightActions,
    'queued': queued,
    'headline': ?headline,
  };
}
