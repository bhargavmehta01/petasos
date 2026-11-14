/// Wave 3 (Control and trust) view models. Kept apart from data/models.dart so
/// the wave merges without touching shared files.
library;

/// Health of one scheduled task, shown as a coloured dot.
enum CronHealth { healthy, failing, paused, unknown }

/// One past run of a scheduled task.
class CronRunRecord {
  const CronRunRecord({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.ok,
    this.title = '',
    this.preview = '',
    this.error,
  });

  /// Run session id (`cron_<job>_<timestamp>` on Hermes).
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// true = finished ok, false = failed, null = unknown or still running.
  final bool? ok;
  final String title;
  final String preview;
  final String? error;

  Duration? get duration => endedAt?.difference(startedAt);
}

/// Detail for the cron studio: job metadata the list does not carry.
class CronJobDetail {
  const CronJobDetail({
    this.lastError,
    this.lastOutput,
    this.runs = const [],
    this.raw = const {},
  });
  final String? lastError;
  final String? lastOutput;
  final List<CronRunRecord> runs;
  final Map<String, dynamic> raw;
}

/// Where a memory entry lives on the host.
enum MemoryTarget { user, memory }

extension MemoryTargetX on MemoryTarget {
  String get wire => this == MemoryTarget.user ? 'user' : 'memory';
  String get fileName => this == MemoryTarget.user ? 'USER.md' : 'MEMORY.md';
  static MemoryTarget parse(Object? v) {
    final s = v?.toString().toLowerCase() ?? '';
    return s == 'user' || s.startsWith('user') ? MemoryTarget.user : MemoryTarget.memory;
  }
}

/// One saved memory entry with where it came from.
class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.target,
    required this.content,
    this.pinned = false,
    this.sourceSession,
    this.sourceTitle,
    this.savedAt,
    this.savedBy,
  });

  /// Stable fingerprint id from the plugin (sha of the content).
  final String id;
  final MemoryTarget target;
  final String content;
  final bool pinned;

  /// Provenance: the chat that wrote it, when the plugin saw it happen.
  final String? sourceSession;
  final String? sourceTitle;
  final DateTime? savedAt;

  /// 'agent', 'user' (edited on the phone) or null when unknown.
  final String? savedBy;

  MemoryEntry copyWith({String? content, bool? pinned}) => MemoryEntry(
    id: id,
    target: target,
    content: content ?? this.content,
    pinned: pinned ?? this.pinned,
    sourceSession: sourceSession,
    sourceTitle: sourceTitle,
    savedAt: savedAt,
    savedBy: savedBy,
  );

  factory MemoryEntry.fromJson(Map<String, dynamic> j) {
    final p = j['provenance'] is Map
        ? Map<String, dynamic>.from(j['provenance'] as Map)
        : const <String, dynamic>{};
    final at = p['saved_at'] ?? j['saved_at'];
    return MemoryEntry(
      id: (j['id'] ?? '').toString(),
      target: MemoryTargetX.parse(j['target']),
      content: (j['content'] ?? '').toString(),
      pinned: j['pinned'] == true,
      sourceSession: p['session_id']?.toString(),
      sourceTitle: p['session_title']?.toString(),
      savedAt: at is num
          ? DateTime.fromMillisecondsSinceEpoch((at * 1000).round())
          : (at is String ? DateTime.tryParse(at) : null),
      savedBy: p['by']?.toString(),
    );
  }
}

/// Risk of an always-allow rule.
enum RuleRisk { low, medium, high }

/// One always-allow approval rule.
class ApprovalRule {
  const ApprovalRule({
    required this.pattern,
    this.expiresAt,
    this.addedAt,
    this.note,
    this.riskOverride,
  });

  /// Hermes `command_allowlist` pattern key, e.g. `git push` or `rm -rf`.
  final String pattern;
  final DateTime? expiresAt;
  final DateTime? addedAt;
  final String? note;
  /// Risk the server computed; falls back to [riskFor].
  final RuleRisk? riskOverride;

  RuleRisk get risk => riskOverride ?? riskFor(pattern);

  bool isExpired([DateTime? now]) =>
      expiresAt != null && !expiresAt!.isAfter(now ?? DateTime.now());

  factory ApprovalRule.fromJson(Map<String, dynamic> j) {
    DateTime? t(Object? v) => v is num
        ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round())
        : (v is String ? DateTime.tryParse(v) : null);
    final r = j['risk']?.toString();
    return ApprovalRule(
      pattern: (j['pattern'] ?? '').toString(),
      expiresAt: t(j['expires_at']),
      addedAt: t(j['added_at']),
      note: j['note']?.toString(),
      riskOverride: switch (r) {
        'high' => RuleRisk.high,
        'medium' => RuleRisk.medium,
        'low' => RuleRisk.low,
        _ => null,
      },
    );
  }

  /// Same heuristic as the plugin's `risk_for`, so demo and live agree.
  static RuleRisk riskFor(String pattern) {
    final p = pattern.toLowerCase();
    const high = [
      'rm ', 'rm -', 'rmdir', 'sudo', 'mkfs', 'dd ', 'chmod', 'chown',
      'shutdown', 'reboot', 'kill', 'curl', 'wget', '| sh', '|sh', 'bash -c',
      'drop ', 'truncate', 'format', 'git push --force', 'reset --hard',
      'systemctl', 'iptables', 'ssh ',
    ];
    const medium = [
      'git push', 'git commit', 'git reset', 'npm install', 'pip install',
      'apt', 'brew', 'docker', 'mv ', 'cp ', 'write', 'send', 'email',
      'delete', 'post', 'deploy', 'crontab',
    ];
    if (high.any(p.contains)) return RuleRisk.high;
    if (medium.any(p.contains)) return RuleRisk.medium;
    return RuleRisk.low;
  }
}

/// Usage snapshot for the meter.
class UsageWindow {
  const UsageWindow({
    required this.costUsd,
    required this.days,
    this.daily = const [],
    this.inputTokens,
    this.outputTokens,
    this.sessions,
  });
  final double costUsd;
  final int days;

  /// Oldest first: (day, cost).
  final List<MapEntry<DateTime, double>> daily;
  final int? inputTokens;
  final int? outputTokens;
  final int? sessions;

  /// Cost for the current calendar month, from the daily series when present.
  double monthToDate(DateTime now) {
    if (daily.isEmpty) return costUsd;
    return daily
        .where((e) => e.key.year == now.year && e.key.month == now.month)
        .fold(0.0, (a, e) => a + e.value);
  }

  /// Straight-line forecast to month end.
  double forecastMonth(DateTime now) {
    final mtd = monthToDate(now);
    final daysIn = DateTime(now.year, now.month + 1, 0).day;
    final elapsed = now.day.clamp(1, daysIn);
    return mtd / elapsed * daysIn;
  }
}

/// What the server plugin can do, from `GET /api/plugins/hermes_mobile/wave3/capabilities`.
class Wave3Capabilities {
  const Wave3Capabilities({
    this.plugin = false,
    this.memoryWrite = false,
    this.incognito = false,
    this.approvalRules = false,
    this.cronRuns = true,
  });
  final bool plugin;
  final bool memoryWrite;
  final bool incognito;
  final bool approvalRules;
  final bool cronRuns;
}
