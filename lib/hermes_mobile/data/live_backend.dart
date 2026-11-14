import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/gateway_approval.dart';
import '../../core/models/memory_fact.dart';
import '../../core/services/connection_manager.dart';
import '../../core/services/desktop_gateway_client.dart';
import '../../core/services/memory_repository.dart';
import '../../core/services/projects_repository.dart';
import '../../core/utils/message_content.dart';
import 'backend.dart';
import 'models.dart';
import 'panels.dart';

/// Petasos adapter over the hermes-android engine. It only calls public engine
/// APIs (ApiClient, GatewayChatClient, DashboardClient, repositories) so
/// upstream engine fixes merge without touching this UI.
class LiveBackend implements HermesMobileBackend {
  LiveBackend(this.conn, this.prefs)
    : _api = ApiClient(
        baseUrl: conn.baseUrl,
        apiKey: conn.apiKey,
        pathPrefix: conn.gatewayPrefix ?? '',
        gatewayProfile: conn.gatewayProfile,
        clientCertificate: conn.clientCertificate,
      );

  final SavedConnection conn;
  final SharedPreferences prefs;
  final ApiClient _api;

  /// One SSE client per chat: a second send on a shared client would
  /// supersede (and so interrupt) another chat's running turn.
  final Map<String, GatewayChatClient> _chats = {};
  DashboardClient? _dash;
  DesktopGatewayClient? _gateway;
  ProjectsRepository? _projects;

  static const panelsUrlKey = 'hermes_mobile.panels_url';
  static const panelsTokenKey = 'hermes_mobile.panels_token';
  static const panelsUseDashboardKey = 'hermes_mobile.panels_use_dashboard';

  DashboardClient get _dashboard =>
      _dash ??= DashboardClient.fromConnection(conn);

  @override
  bool get isDemo => false;

  @override
  ConnectionSummary get connection => ConnectionSummary(
    label: conn.label,
    endpoint: _api.baseUrl,
    dashboard: DesktopGatewayClient.normalizedGatewayBaseUrl(conn),
  );

  @override
  Future<bool> checkHealth() async {
    try {
      return (await _api.checkHealth()).isHealthy;
    } catch (_) {
      return false;
    }
  }

  static HermesMobileChat _chatFrom(Session s) => HermesMobileChat(
    id: s.id,
    title: s.title,
    preview: s.preview,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      ((s.lastActive > 0 ? s.lastActive : s.startedAt) * 1000).round(),
    ),
    isActive: s.isActive,
    source: s.source,
    pinned: s.pinned,
    messageCount: s.messageCount,
    isDraft: s.isLocalDraft,
  );

  @override
  Future<List<HermesMobileChat>> listChats() async {
    final page = await _api.getSessionsPage(limit: 60);
    return page.sessions
        .where((s) => !s.archived && !s.isUntitledCronShell)
        .map(_chatFrom)
        .toList();
  }

  @override
  Future<void> setChatArchived(String chatId, bool archived) async {
    final ok = await _api.setSessionArchived(
      sessionId: chatId,
      archived: archived,
    );
    if (!ok) throw StateError('This server cannot archive chats.');
  }

  @override
  Future<List<HermesMobileChat>> listArchivedChats() async {
    final page = await _api.getSessionsPage(limit: 100);
    return page.sessions
        .where((s) => s.archived && !s.isUntitledCronShell)
        .map(_chatFrom)
        .toList();
  }

  @override
  Future<List<HermesMobileChat>> searchChats(String query) async {
    final q = query.trim();
    if (q.isEmpty) return listChats();
    final page = await _api.getSessionsPage(limit: 50, title: q);
    final byTitle = page.sessions.map(_chatFrom).toList();
    if (byTitle.isNotEmpty) return byTitle;
    // Fall back to a local filter over recent chats (title + preview).
    final recent = await listChats();
    final lower = q.toLowerCase();
    return recent
        .where(
          (c) =>
              c.displayTitle.toLowerCase().contains(lower) ||
              c.preview.toLowerCase().contains(lower),
        )
        .toList();
  }

  @override
  Future<List<HermesMobileMessage>> loadMessages(String chatId) async {
    final raw = await _api.getMessages(chatId, limit: 200, latest: true);
    return projectHistory(raw);
  }

  /// Turns gateway history rows into chat bubbles. Tool rows are folded into
  /// the next assistant reply as a finished task summary, never shown raw.
  static List<HermesMobileMessage> projectHistory(List<Map<String, dynamic>> raw) {
    final out = <HermesMobileMessage>[];
    var pendingTools = <String>[];
    for (final m in raw) {
      final role = m['role']?.toString();
      if (role == 'tool' || isToolResultMessage(m)) continue;
      final calls = m['tool_calls'];
      if (calls is List && calls.isNotEmpty) {
        for (final c in calls) {
          if (c is Map) {
            final fn = c['function'];
            final name = (fn is Map ? fn['name'] : c['name'])?.toString();
            if (name != null && name.isNotEmpty) pendingTools.add(name);
          }
        }
      }
      final text = normaliseDisplayText(
        stripToolResultText(messageContentToText(m['content'])),
      ).trim();
      final ts = m['timestamp'] ?? m['created_at'];
      final at = ts is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (ts > 1e12 ? ts : ts * 1000).round(),
            )
          : (ts is String ? DateTime.tryParse(ts)?.toLocal() : null);
      if (role == 'user') {
        if (text.isEmpty) continue;
        out.add(HermesMobileMessage(role: HermesMobileRole.user, text: text, createdAt: at));
      } else if (role == 'assistant') {
        if (text.isEmpty) continue;
        out.add(
          HermesMobileMessage(
            role: HermesMobileRole.assistant,
            text: text,
            createdAt: at,
            reasoning: (m['reasoning'] ?? m['reasoning_content'] ?? '')
                .toString(),
            toolNames: pendingTools,
          ),
        );
        pendingTools = <String>[];
      }
    }
    return out;
  }

  @override
  String newChatId() => GatewayChatClient.generateSessionId();

  @override
  Future<void> renameChat(String chatId, String title) async {
    await _api.renameSession(sessionId: chatId, title: title);
  }

  @override
  Future<void> deleteChat(String chatId) => _api.deleteSession(chatId);

  @override
  Future<void> send({
    required String chatId,
    required String text,
    required List<Map<String, dynamic>> history,
    String? imageDataUrl,
    required HermesMobileTurnCallbacks callbacks,
  }) {
    final chat = _chats.putIfAbsent(chatId, () => GatewayChatClient(_api));
    return chat.sendMessageStreaming(
      message: text,
      sessionId: chatId,
      history: history,
      imageDataUrl: imageDataUrl,
      onToken: callbacks.onToken,
      onToolProgress: callbacks.onTool,
      onReasoning: callbacks.onReasoning,
      onStatus: callbacks.onStatus,
      onApproval: callbacks.onApproval,
      onDone: callbacks.onDone,
      onError: callbacks.onError,
    );
  }

  @override
  Future<bool> stop(String chatId) async =>
      await _chats[chatId]?.cancelActiveMessage() ?? false;

  @override
  Future<void> answerApproval(HermesMobileApproval approval, String choice) async {
    final req = GatewayApprovalRequest.fromEventData(approval.raw);
    final runId = req.runId;
    if (runId == null) {
      throw StateError('This approval has no run id; answer it on the host.');
    }
    await _api.respondToRunApproval(
      runId: runId,
      choice: choice,
      requestId: req.requestId,
      executionGeneration: req.executionGeneration,
      canonicalControl: req.canonicalControl,
    );
  }

  // ── Projects ────────────────────────────────────────────────────────

  ProjectsRepository? _projectsRepo() {
    if (_projects != null) return _projects;
    final url = conn.desktopGatewayUrl?.trim() ?? '';
    if (url.isEmpty) return null;
    _gateway = DesktopGatewayClient.fromConnection(conn);
    return _projects = ProjectsRepository(
      client: _gateway!.projects,
      preferences: prefs,
      connectionId: conn.id,
    );
  }

  @override
  Future<List<HermesMobileProject>?> listProjects() async {
    final repo = _projectsRepo();
    if (repo == null) return null;
    final view = await repo.refresh();
    if (view.support == ProjectsSupport.unsupported) return null;
    return [
      for (final p in view.projects)
        HermesMobileProject(
          id: p.id,
          name: p.name,
          description: p.description,
          path: p.primaryPath,
        ),
    ];
  }

  @override
  Future<List<HermesMobileChat>> projectChats(String projectId) async {
    final repo = _projectsRepo();
    if (repo == null) return const [];
    final view = await repo.projectSessions(projectId, refresh: true);
    return view.sessions.map(_chatFrom).toList();
  }

  // ── Cron ────────────────────────────────────────────────────────────

  @override
  Future<List<HermesMobileCronJob>> listCron() async {
    final jobs = await _dashboard.getCronJobs();
    return jobs.map(HermesMobileCronJob.fromJson).toList();
  }

  @override
  Future<void> createCron({
    required String name,
    required String schedule,
    required String prompt,
  }) => _dashboard.createJob(prompt: prompt, schedule: schedule, name: name);

  @override
  Future<void> updateCron(String id, Map<String, dynamic> updates) =>
      _dashboard.updateJob(id, updates);

  @override
  Future<void> setCronPaused(String id, bool paused) =>
      _dashboard.setJobPaused(id, paused: paused);

  @override
  Future<void> runCron(String id) => _dashboard.triggerJob(id);

  @override
  Future<void> deleteCron(String id) => _dashboard.deleteJob(id);

  // ── Skills / memory / usage ─────────────────────────────────────────

  @override
  Future<List<HermesMobileSkill>> listSkills() async {
    List<Map<String, dynamic>> raw;
    try {
      raw = await _api.getSkills();
    } catch (_) {
      raw = await _dashboard.getSkills();
    }
    final skills = raw.map(HermesMobileSkill.fromJson).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return skills;
  }

  Map<String, String>? get _profileQuery {
    final p = conn.gatewayProfile?.trim();
    return p == null || p.isEmpty ? null : {'profile': p};
  }

  /// Dashboard `GET /api/skills/content?name=` returns the raw SKILL.md for
  /// any skill. Older hosts without it fall back to `GET /api/learning/node`,
  /// which only knows learned (agent-made or used) skills.
  @override
  Future<HermesMobileSkillDetail> skillDetail(String name) async {
    Object? firstError;
    try {
      final j = await _dashboard.apiGet(
        'skills/content',
        queryParameters: {'name': name, ...?_profileQuery},
      );
      return skillDetailFromJson(j);
    } catch (e) {
      firstError = e;
    }
    try {
      final j = await _dashboard.apiGet(
        'learning/node',
        queryParameters: {'id': name, ...?_profileQuery},
      );
      if (j['ok'] == true && j['kind'] == 'skill') {
        return skillDetailFromJson(j);
      }
    } catch (_) {}
    throw firstError;
  }

  /// Tolerant reader for a skill-content payload.
  static HermesMobileSkillDetail skillDetailFromJson(Map<String, dynamic> j) {
    final content = j['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('The server returned no SKILL.md text');
    }
    final path = j['path']?.toString();
    final listed = j['linked_files'] ?? j['files'];
    final files = <String>{
      if (listed is List)
        ...listed.map((f) => f is Map ? '${f['path'] ?? f['name']}' : '$f'),
      ...HermesMobileSkillDetail.linkedFiles(content),
    }.where((f) => f.isNotEmpty && f != 'null').toList();
    return HermesMobileSkillDetail(content: content, path: path, files: files);
  }

  @override
  Future<void> setSkillEnabled(String name, bool enabled) async {
    await _dashboard.apiPut(
      'skills/toggle',
      body: {'name': name, 'enabled': enabled},
      queryParameters: _profileQuery,
    );
  }

  /// Saved memory comes from the dashboard learning graph
  /// (`GET /api/learning/graph`), which caps each entry at 1,200 characters.
  /// Entries at the cap are marked [HermesMobileMemoryItem.truncated] and the full
  /// text is read from `GET /api/learning/node` when opened.
  @override
  Future<List<HermesMobileMemoryItem>> listMemory() async {
    final repo = MemoryRepository.fromConnection(conn);
    try {
      final facts = await repo.loadFacts();
      return memoryItemsFromFacts(facts);
    } finally {
      repo.close();
    }
  }

  static List<HermesMobileMemoryItem> memoryItemsFromFacts(List<MemoryFact> facts) => [
    for (final f in facts)
      HermesMobileMemoryItem(
        id: f.id,
        title: HermesMobileMemoryItem.titleFrom(f.content, fallback: f.source.fileName),
        body: f.content,
        scope: f.source.fileName,
        truncated: f.mayBeTruncated,
      ),
  ];

  @override
  Future<String> memoryFullText(HermesMobileMemoryItem item) async {
    final id = item.id;
    if (!item.truncated || id == null) return item.body;
    final source = id.startsWith('memory:profile:')
        ? MemoryFactSource.profile
        : MemoryFactSource.memory;
    final fact = MemoryFact(id: id, source: source, content: item.body);
    if (!fact.hasStableIdentity) {
      throw const FormatException(
        'This Hermes version only returns the first 1,200 characters of long '
        'entries. Update Hermes to read the rest.',
      );
    }
    final repo = MemoryRepository.fromConnection(conn);
    try {
      return await repo.loadFullFact(fact);
    } finally {
      repo.close();
    }
  }

  /// Dashboard `PUT /api/learning/node` rewrites one entry, addressed by its
  /// fingerprinted id, so a stale screen can never overwrite another entry.
  @override
  Future<void> editMemoryItem(HermesMobileMemoryItem item, String content) async {
    if (!item.editable) {
      throw StateError('This entry cannot be edited from the phone.');
    }
    await _dashboard.apiPut(
      'learning/node',
      body: {'id': item.id, 'content': content},
      queryParameters: _profileQuery,
    );
  }

  @override
  Future<HermesMobileUsage?> usage() async {
    final data = await _dashboard.getAnalytics(days: 30);
    return parseUsage(data);
  }

  /// Tolerant reader for the dashboard's analytics payload.
  static HermesMobileUsage parseUsage(Map<String, dynamic> data) {
    final totals = data['totals'] is Map
        ? Map<String, dynamic>.from(data['totals'] as Map)
        : data;
    num? pick(List<String> keys) {
      for (final k in keys) {
        final v = totals[k];
        if (v is num) return v;
      }
      return null;
    }

    final models = <MapEntry<String, int>>[];
    final byModel = data['by_model'] ?? data['models'];
    if (byModel is List) {
      for (final m in byModel) {
        if (m is! Map) continue;
        final name = (m['model'] ?? m['name'] ?? '').toString();
        final tokens =
            ((m['input_tokens'] ?? 0) as num) +
            ((m['output_tokens'] ?? 0) as num);
        if (name.isNotEmpty) models.add(MapEntry(name, tokens.toInt()));
      }
      models.sort((a, b) => b.value.compareTo(a.value));
    }
    return HermesMobileUsage(
      sessions: pick(['total_sessions', 'sessions'])?.toInt(),
      inputTokens: pick(['total_input', 'input_tokens'])?.toInt(),
      outputTokens: pick(['total_output', 'output_tokens'])?.toInt(),
      costUsd: pick([
        'total_actual_cost',
        'total_estimated_cost',
        'cost',
      ])?.toDouble(),
      topModels: models.take(5).toList(),
    );
  }

  // ── Panels ──────────────────────────────────────────────────────────

  @override
  PanelsSource get panels {
    final url = prefs.getString(panelsUrlKey)?.trim() ?? '';
    if (url.isNotEmpty) {
      return UrlPanelsSource(url, bearer: prefs.getString(panelsTokenKey));
    }
    if (prefs.getBool(panelsUseDashboardKey) ?? false) {
      return DashboardPanelsSource(
        () => _dashboard.apiGet('plugins/home-dashboard/panels'),
        label: 'Hermes dashboard',
      );
    }
    return const UnconfiguredPanelsSource();
  }

  // --- wave1 ---
  /// Engine clients for Wave 1 features (Petasos plugin routes, run prompts).
  DashboardClient get wave1Dashboard => _dashboard;
  ApiClient get wave1Api => _api;
  // --- end wave1 ---

  @override
  void dispose() {
    // Running turns are left to finish server-side; the clients are dropped.
    _chats.clear();
    _dash?.close();
    _gateway?.close();
    unawaited(_projects?.close());
  }
}
