/// Plain view models for the Petasos UI. The engine's own models stay the source
/// of truth; these are projections the screens can render without knowing
/// which transport (live gateway or demo) produced them.
library;

class HermesMobileChat {
  const HermesMobileChat({
    required this.id,
    required this.title,
    this.preview = '',
    this.updatedAt,
    this.isActive = false,
    this.source = '',
    this.pinned = false,
    this.messageCount = 0,
    this.isDraft = false,
  });

  final String id;
  final String title;
  final String preview;
  final DateTime? updatedAt;
  final bool isActive;
  final String source;
  final bool pinned;
  final int messageCount;

  /// A chat created on the phone that the gateway has not stored yet.
  final bool isDraft;

  String get displayTitle {
    final t = title.trim();
    if (t.isNotEmpty && t != 'Untitled') return t;
    final p = preview.trim();
    if (p.isNotEmpty) return p.length > 48 ? '${p.substring(0, 48)}…' : p;
    return 'New chat';
  }

  HermesMobileChat copyWith({String? title, bool? isActive, String? preview}) =>
      HermesMobileChat(
        id: id,
        title: title ?? this.title,
        preview: preview ?? this.preview,
        updatedAt: updatedAt,
        isActive: isActive ?? this.isActive,
        source: source,
        pinned: pinned,
        messageCount: messageCount,
        isDraft: isDraft,
      );
}

enum HermesMobileRole { user, assistant }

class HermesMobileMessage {
  HermesMobileMessage({
    required this.role,
    required this.text,
    DateTime? createdAt,
    this.imageDataUrls = const [],
    this.reasoning = '',
    this.toolNames = const [],
    this.failed = false,
  }) : createdAt = createdAt ?? DateTime.now();

  final HermesMobileRole role;
  String text;
  final DateTime createdAt;
  final List<String> imageDataUrls;
  String reasoning;

  /// Tools that ran before this reply (history only), shown as a done task.
  final List<String> toolNames;
  bool failed;

  bool get isUser => role == HermesMobileRole.user;
}

class HermesMobileProject {
  const HermesMobileProject({
    required this.id,
    required this.name,
    this.description,
    this.path,
    this.chatCount,
  });
  final String id;
  final String name;
  final String? description;
  final String? path;
  final int? chatCount;
}

class HermesMobileCronJob {
  const HermesMobileCronJob({
    required this.id,
    required this.name,
    required this.schedule,
    required this.prompt,
    this.paused = false,
    this.nextRun,
    this.lastRun,
    this.lastStatus,
    this.deliver = 'local',
  });
  final String id;
  final String name;
  final String schedule;
  final String prompt;
  final bool paused;
  final String? nextRun;
  final String? lastRun;
  final String? lastStatus;
  final String deliver;

  factory HermesMobileCronJob.fromJson(Map<String, dynamic> j) {
    String? s(Object? v) => v?.toString();
    final schedule = j['schedule'];
    return HermesMobileCronJob(
      id: s(j['id']) ?? s(j['job_id']) ?? '',
      name: s(j['name'])?.trim().isNotEmpty == true
          ? s(j['name'])!
          : (s(j['prompt']) ?? 'Task'),
      schedule: schedule is Map
          ? (s(schedule['display']) ?? s(schedule['expr']) ?? '')
          : (s(j['schedule_display']) ?? s(schedule) ?? ''),
      prompt: s(j['prompt']) ?? '',
      paused:
          j['paused'] == true ||
          j['enabled'] == false ||
          j['state'] == 'paused',
      nextRun: s(j['next_run_at']) ?? s(j['next_run']),
      lastRun: s(j['last_run_at']) ?? s(j['last_run']),
      lastStatus: s(j['last_status']),
      deliver: s(j['deliver']) ?? 'local',
    );
  }
}

class HermesMobileSkill {
  const HermesMobileSkill({
    required this.name,
    this.description = '',
    this.category = '',
    this.enabled = true,
    this.provenance = '',
    this.usage,
    this.locked = false,
  });
  final String name;
  final String description;
  final String category;
  final bool enabled;

  /// Where the skill came from on the host: hub, bundled, external or agent.
  final String provenance;

  /// Recent activity count reported by the dashboard, when present.
  final int? usage;

  /// Locked against agent edits (the user can still edit it).
  final bool locked;

  HermesMobileSkill copyWith({bool? enabled}) => HermesMobileSkill(
    name: name,
    description: description,
    category: category,
    enabled: enabled ?? this.enabled,
    provenance: provenance,
    usage: usage,
    locked: locked,
  );

  factory HermesMobileSkill.fromJson(Map<String, dynamic> j) => HermesMobileSkill(
    name: (j['name'] ?? j['id'] ?? 'skill').toString(),
    description: (j['description'] ?? '').toString(),
    category: (j['category'] ?? '').toString(),
    enabled: j['enabled'] != false,
    provenance: (j['provenance'] ?? j['source'] ?? '').toString(),
    usage: j['usage'] is num ? (j['usage'] as num).toInt() : null,
    locked: j['locked'] == true,
  );
}

/// Full content of one skill: the raw SKILL.md and the files it links to.
class HermesMobileSkillDetail {
  const HermesMobileSkillDetail({
    required this.content,
    this.path,
    this.files = const [],
  });

  /// Raw SKILL.md text, front matter included.
  final String content;

  /// Path of SKILL.md on the host, when the server reports it.
  final String? path;

  /// Relative files the SKILL.md links to (references, scripts, templates).
  final List<String> files;

  /// SKILL.md split into its YAML front matter and markdown body.
  ({String frontMatter, String body}) get parts => splitFrontMatter(content);

  static ({String frontMatter, String body}) splitFrontMatter(String raw) {
    final text = raw.replaceFirst('\uFEFF', '');
    final m = RegExp(
      r'^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)',
    ).firstMatch(text);
    if (m == null) return (frontMatter: '', body: text);
    return (
      frontMatter: m.group(1)!.trim(),
      body: text.substring(m.end).trimLeft(),
    );
  }

  /// Relative paths a SKILL.md points at: markdown links and backticked
  /// paths under the usual skill folders. URLs and anchors are ignored.
  static List<String> linkedFiles(String raw) {
    final out = <String>{};
    for (final m in RegExp(r'\]\(([^)\s]+)\)').allMatches(raw)) {
      final href = m.group(1)!;
      if (href.contains('://') ||
          href.startsWith('#') ||
          href.startsWith('mailto:') ||
          href.startsWith('/')) {
        continue;
      }
      out.add(href.split('#').first);
    }
    for (final m in RegExp(
      r'`((?:references|scripts|templates|assets|examples)/[^`\s]+)`',
    ).allMatches(raw)) {
      out.add(m.group(1)!);
    }
    out.removeWhere((f) => f.isEmpty);
    return out.toList();
  }
}

class HermesMobileMemoryItem {
  const HermesMobileMemoryItem({
    required this.title,
    required this.body,
    this.scope,
    this.id,
    this.truncated = false,
  });
  final String title;
  final String body;
  final String? scope;

  /// Server identity of the entry (for example a learning-graph node id).
  final String? id;

  /// True when [body] is a preview and the full text must be fetched.
  final bool truncated;

  /// Live entries can be edited in place only with a fingerprinted id, so an
  /// edit can never land on a different entry that moved into its slot.
  bool get editable =>
      id != null &&
      (id!.startsWith('demo:') ||
          RegExp(
            r'^memory:(profile|memory):[0-9]+:[a-f0-9]{12}$',
          ).hasMatch(id!));

  /// A short title from the first line of an entry.
  static String titleFrom(String body, {String fallback = 'Memory'}) {
    for (final line in body.split('\n')) {
      final t = line.trim().replaceFirst(RegExp(r'^[#>*\-\s]+'), '').trim();
      if (t.isEmpty) continue;
      return t.length > 80 ? '${t.substring(0, 80)}…' : t;
    }
    return fallback;
  }
}

class HermesMobileUsage {
  const HermesMobileUsage({
    this.sessions,
    this.inputTokens,
    this.outputTokens,
    this.costUsd,
    this.days = 30,
    this.topModels = const [],
  });
  final int? sessions;
  final int? inputTokens;
  final int? outputTokens;
  final double? costUsd;
  final int days;
  final List<MapEntry<String, int>> topModels;
}

/// A pending approval the agent is waiting on.
class HermesMobileApproval {
  const HermesMobileApproval({
    required this.chatId,
    required this.command,
    required this.description,
    required this.choices,
    this.raw = const {},
  });
  final String chatId;
  final String command;
  final String description;

  /// Wire values: once, session, always, deny.
  final List<String> choices;
  final Map<String, dynamic> raw;
}

enum HermesMobileStepState { running, done, failed }

class HermesMobileStep {
  HermesMobileStep({
    required this.id,
    required this.label,
    this.detail,
    this.emoji,
    this.state = HermesMobileStepState.running,
  });
  final String id;
  String label;
  String? detail;
  String? emoji;
  HermesMobileStepState state;
}

enum HermesMobileRunStatus { running, done, failed, stopped }

/// One live agent run shown as a single compact task card.
class HermesMobileRun {
  HermesMobileRun({required this.title});
  String title;
  final List<HermesMobileStep> steps = [];
  String? statusLine;
  HermesMobileRunStatus status = HermesMobileRunStatus.running;
  String reasoning = '';
  final DateTime startedAt = DateTime.now();

  String get currentLine {
    if (statusLine != null && statusLine!.trim().isNotEmpty) {
      return statusLine!;
    }
    final running = steps.where((s) => s.state == HermesMobileStepState.running);
    if (running.isNotEmpty) return running.last.label;
    if (steps.isNotEmpty) return steps.last.label;
    return 'Thinking…';
  }
}

class ConnectionSummary {
  const ConnectionSummary({
    required this.label,
    required this.endpoint,
    this.dashboard,
    this.healthy,
    this.detail,
  });
  final String label;
  final String endpoint;
  final String? dashboard;
  final bool? healthy;
  final String? detail;
}
