import 'dart:async';

import '../../../core/services/connection_manager.dart';
import '../../../core/utils/message_content.dart';
import '../../data/backend.dart';
import '../../data/live_backend.dart';
import '../../data/models.dart';
import 'wave3_demo_api.dart';
import 'wave3_models.dart';

/// Everything Wave 3 screens need beyond [HermesMobileBackend]. Kept out of the shared
/// backend interface so the wave merges without touching it: [Wave3Api.of]
/// picks the demo or live implementation from the backend in use.
abstract class Wave3Api {
  static final Expando<Wave3Api> _cache = Expando('wave3');

  /// The Wave 3 API for [backend], cached per backend instance.
  static Wave3Api of(HermesMobileBackend backend) => _cache[backend] ??=
      backend is LiveBackend ? LiveWave3Api(backend) : DemoWave3Api();

  /// Test hook: force an implementation for a backend.
  static void override(HermesMobileBackend backend, Wave3Api api) =>
      _cache[backend] = api;

  Future<Wave3Capabilities> capabilities();

  // Cron studio
  Future<CronJobDetail> cronDetail(HermesMobileCronJob job);
  Future<String?> runOutput(String runId);

  // Memory manager
  Future<List<MemoryEntry>> listMemory();
  Future<MemoryEntry> addMemory(MemoryTarget target, String content);
  Future<MemoryEntry> editMemory(MemoryEntry entry, String content);
  Future<void> deleteMemory(MemoryEntry entry);
  Future<void> setPinned(MemoryEntry entry, bool pinned);
  Future<Set<String>> incognitoChats();
  Future<void> setIncognito(String chatId, bool enabled);

  // Approval rules
  Future<List<ApprovalRule>> listRules();
  Future<void> addRule(String pattern, {DateTime? expiresAt, String? note});
  Future<void> removeRule(String pattern);

  // Usage
  Future<UsageWindow?> usageWindow({int days = 30});
}

/// Thrown when a feature needs the Petasos server plugin and it is not installed.
class PluginMissing implements Exception {
  const PluginMissing(this.feature);
  final String feature;
  @override
  String toString() =>
      '$feature needs the Petasos server plugin (server/hermes_mobile_plugin). '
      'Install it on the Hermes host and enable "hermes_mobile" in plugins.enabled.';
}

/// Live implementation over the Hermes dashboard API and the Petasos plugin
/// routes at `/api/plugins/hermes_mobile/w3/...`.
class LiveWave3Api implements Wave3Api {
  LiveWave3Api(this.backend);
  final LiveBackend backend;
  DashboardClient? _dash;
  ApiClient? _api;
  Wave3Capabilities? _caps;

  SavedConnection get _conn => backend.conn;
  DashboardClient get _d => _dash ??= DashboardClient.fromConnection(_conn);
  ApiClient get _a => _api ??= ApiClient(
    baseUrl: _conn.baseUrl,
    apiKey: _conn.apiKey,
    pathPrefix: _conn.gatewayPrefix ?? '',
    gatewayProfile: _conn.gatewayProfile,
    clientCertificate: _conn.clientCertificate,
  );

  static const _p = 'plugins/hermes_mobile/w3';

  Map<String, String>? get _profileQuery {
    final p = _conn.gatewayProfile?.trim();
    return p == null || p.isEmpty ? null : {'profile': p};
  }

  @override
  Future<Wave3Capabilities> capabilities() async {
    final cached = _caps;
    if (cached != null) return cached;
    try {
      final j = await _d.apiGet('$_p/capabilities');
      return _caps = Wave3Capabilities(
        plugin: j['plugin'] == true,
        memoryWrite: j['memory_write'] == true,
        incognito: j['incognito'] == true,
        approvalRules: j['approval_rules'] == true,
        cronRuns: j['cron_runs'] != false,
      );
    } catch (_) {
      // Not cached: the user may install the plugin and come back.
      return const Wave3Capabilities();
    }
  }

  Future<void> _need(bool Function(Wave3Capabilities) has, String f) async {
    if (!has(await capabilities())) throw PluginMissing(f);
  }

  // ── Cron ─────────────────────────────────────────────────────────────

  @override
  Future<CronJobDetail> cronDetail(HermesMobileCronJob job) async {
    Map<String, dynamic> raw = const {};
    try {
      raw = await _d.apiGet(
        'cron/jobs/${Uri.encodeComponent(job.id)}',
        queryParameters: _profileQuery,
      );
    } catch (_) {}
    var runs = <CronRunRecord>[];
    try {
      final data = await _d.apiGet(
        'cron/jobs/${Uri.encodeComponent(job.id)}/runs',
        queryParameters: {...?_profileQuery, 'limit': '20'},
      );
      final list = data['runs'] as List? ?? const [];
      runs = list.whereType<Map>().map((m) {
        return parseCronRun(Map<String, dynamic>.from(m));
      }).toList();
    } catch (_) {}
    final job0 = raw['job'] is Map
        ? Map<String, dynamic>.from(raw['job'] as Map)
        : raw;
    return CronJobDetail(
      lastError: (job0['last_error'] ?? job0['error'])?.toString(),
      lastOutput: (job0['last_output'] ?? job0['last_response'])?.toString(),
      runs: runs,
      raw: job0,
    );
  }

  /// Tolerant reader for one cron run session row.
  static CronRunRecord parseCronRun(Map<String, dynamic> m) {
    DateTime? t(Object? v) => v is num
        ? DateTime.fromMillisecondsSinceEpoch(
            (v > 1e12 ? v : v * 1000).round(),
          )
        : (v is String ? DateTime.tryParse(v)?.toLocal() : null);
    final reason = (m['end_reason'] ?? m['status'] ?? '').toString();
    final err = m['error']?.toString();
    bool? ok;
    if (err != null && err.isNotEmpty) {
      ok = false;
    } else if (reason.isNotEmpty) {
      ok = !RegExp(
        r'error|fail|timeout|crash|cancel',
        caseSensitive: false,
      ).hasMatch(reason);
    } else if (m['ended_at'] != null) {
      ok = true;
    }
    return CronRunRecord(
      id: (m['id'] ?? m['session_id'] ?? '').toString(),
      startedAt: t(m['started_at']) ?? DateTime.now(),
      endedAt: t(m['ended_at']),
      ok: ok,
      title: (m['title'] ?? '').toString(),
      preview: (m['preview'] ?? '').toString(),
      error: err ?? (ok == false && reason.isNotEmpty ? reason : null),
    );
  }

  @override
  Future<String?> runOutput(String runId) async {
    final raw = await _a.getMessages(runId, limit: 40, latest: true);
    for (final m in raw.reversed) {
      if (m['role'] == 'assistant') {
        final text = normaliseDisplayText(
          messageContentToText(m['content']),
        ).trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  // ── Memory ───────────────────────────────────────────────────────────

  @override
  Future<List<MemoryEntry>> listMemory() async {
    final caps = await capabilities();
    if (caps.memoryWrite) {
      final j = await _d.apiGet('$_p/memory');
      final list = j['entries'] as List? ?? const [];
      return list
          .whereType<Map>()
          .map((m) => MemoryEntry.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    // Read-only fallback through the engine's memory facts.
    final items = await backend.listMemory();
    var i = 0;
    return [
      for (final it in items)
        MemoryEntry(
          id: 'ro-${i++}',
          target: MemoryTargetX.parse(it.scope ?? it.title),
          content: it.body,
        ),
    ];
  }

  @override
  Future<MemoryEntry> addMemory(MemoryTarget target, String content) async {
    await _need((c) => c.memoryWrite, 'Editing memory');
    final j = await _d.apiPost(
      '$_p/memory',
      body: {'target': target.wire, 'content': content},
    );
    return MemoryEntry.fromJson(j);
  }

  @override
  Future<MemoryEntry> editMemory(MemoryEntry entry, String content) async {
    await _need((c) => c.memoryWrite, 'Editing memory');
    final j = await _d.apiPut(
      '$_p/memory/${Uri.encodeComponent(entry.id)}',
      body: {'content': content},
    );
    return MemoryEntry.fromJson({...j, 'pinned': entry.pinned});
  }

  @override
  Future<void> deleteMemory(MemoryEntry entry) async {
    await _need((c) => c.memoryWrite, 'Deleting memory');
    await _d.apiDelete('$_p/memory/${Uri.encodeComponent(entry.id)}');
  }

  @override
  Future<void> setPinned(MemoryEntry entry, bool pinned) async {
    await _need((c) => c.memoryWrite, 'Pinning memory');
    await _d.apiPost(
      '$_p/memory/${Uri.encodeComponent(entry.id)}/pin',
      body: {'pinned': pinned},
    );
  }

  @override
  Future<Set<String>> incognitoChats() async {
    if (!(await capabilities()).incognito) return {};
    final j = await _d.apiGet('$_p/incognito');
    return {...(j['sessions'] as List? ?? const []).map((e) => '$e')};
  }

  @override
  Future<void> setIncognito(String chatId, bool enabled) async {
    await _need((c) => c.incognito, 'Incognito chat');
    await _d.apiPut(
      '$_p/incognito/${Uri.encodeComponent(chatId)}',
      body: {'enabled': enabled},
    );
  }

  // ── Approval rules ───────────────────────────────────────────────────

  @override
  Future<List<ApprovalRule>> listRules() async {
    await _need((c) => c.approvalRules, 'Approval rules');
    final j = await _d.apiGet('$_p/approvals/rules');
    return (j['rules'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ApprovalRule.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  @override
  Future<void> addRule(String pattern, {DateTime? expiresAt, String? note}) async {
    await _need((c) => c.approvalRules, 'Approval rules');
    await _d.apiPost(
      '$_p/approvals/rules',
      body: {
        'pattern': pattern,
        if (expiresAt != null)
          'expires_at': expiresAt.millisecondsSinceEpoch / 1000,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  @override
  Future<void> removeRule(String pattern) async {
    await _need((c) => c.approvalRules, 'Approval rules');
    await _d.apiDelete(
      '$_p/approvals/rules',
      queryParameters: {'pattern': pattern},
    );
  }

  // ── Usage ────────────────────────────────────────────────────────────

  @override
  Future<UsageWindow?> usageWindow({int days = 30}) async {
    final data = await _d.getAnalytics(days: days);
    return parseUsageWindow(data, days: days);
  }

  /// Reads the dashboard's `analytics/usage` payload (`daily` + `totals`).
  static UsageWindow parseUsageWindow(
    Map<String, dynamic> data, {
    int days = 30,
  }) {
    double cost(Map m, [String prefix = '']) {
      final actual = m['${prefix}actual_cost'];
      final est = m['${prefix}estimated_cost'];
      final a = actual is num ? actual.toDouble() : 0.0;
      final e = est is num ? est.toDouble() : 0.0;
      return a > 0 ? a : e;
    }

    final daily = <MapEntry<DateTime, double>>[];
    final rows = data['daily'];
    if (rows is List) {
      for (final r in rows.whereType<Map>()) {
        final day = DateTime.tryParse('${r['day'] ?? r['date'] ?? ''}');
        if (day != null) daily.add(MapEntry(day, cost(r)));
      }
      daily.sort((a, b) => a.key.compareTo(b.key));
    }
    final totals = data['totals'] is Map
        ? Map<String, dynamic>.from(data['totals'] as Map)
        : const <String, dynamic>{};
    int? n(Object? v) => v is num ? v.toInt() : null;
    final total = totals.isNotEmpty
        ? cost(totals, 'total_')
        : daily.fold(0.0, (a, e) => a + e.value);
    return UsageWindow(
      costUsd: total,
      days: days,
      daily: daily,
      inputTokens: n(totals['total_input']),
      outputTokens: n(totals['total_output']),
      sessions: n(totals['total_sessions']),
    );
  }
}
