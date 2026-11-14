import '../../data/models.dart';
import 'wave3_api.dart';
import 'wave3_models.dart';

/// Sample data for every Wave 3 feature, so demo mode shows it all with no
/// server. State lives for the life of the demo backend.
class DemoWave3Api implements Wave3Api {
  DemoWave3Api({this.fixedNow}) {
    final n = now;
    _memory.addAll([
      MemoryEntry(
        id: 'm1',
        target: MemoryTarget.user,
        content: 'Lives in Springfield. Uses a Pixel 9.',
        pinned: true,
        sourceTitle: 'Phone setup',
        sourceSession: 'demo-phone',
        savedAt: n.subtract(const Duration(days: 12)),
        savedBy: 'agent',
      ),
      MemoryEntry(
        id: 'm2',
        target: MemoryTarget.user,
        content: 'Prefers short answers with a clear pick.',
        savedAt: n.subtract(const Duration(days: 3)),
        savedBy: 'user',
      ),
      MemoryEntry(
        id: 'm3',
        target: MemoryTarget.memory,
        content: 'Nightly backups go to B2 at 03:00.',
        sourceTitle: 'Backup check',
        sourceSession: 'demo-backup',
        savedAt: n.subtract(const Duration(days: 1, hours: 4)),
        savedBy: 'agent',
      ),
      MemoryEntry(
        id: 'm4',
        target: MemoryTarget.memory,
        content: 'Home panels live in ~/.hermes/panels.',
        savedBy: 'agent',
        savedAt: n.subtract(const Duration(hours: 5)),
        sourceTitle: 'Panels',
        sourceSession: 'demo-panels',
      ),
    ]);
    _rules.addAll([
      ApprovalRule(
        pattern: 'git push',
        addedAt: n.subtract(const Duration(days: 4)),
        expiresAt: n.add(const Duration(days: 3)),
        note: 'Deploys for the app',
      ),
      ApprovalRule(
        pattern: 'sudo systemctl restart hermes-gateway',
        addedAt: n.subtract(const Duration(hours: 20)),
        expiresAt: n.add(const Duration(hours: 4)),
      ),
      ApprovalRule(pattern: 'ls -la', addedAt: n.subtract(const Duration(days: 30))),
    ]);
  }

  final DateTime? fixedNow;
  DateTime get now => fixedNow ?? DateTime.now();
  final List<MemoryEntry> _memory = [];
  final List<ApprovalRule> _rules = [];
  final Set<String> _incognito = {};
  int _seq = 10;

  @override
  Future<Wave3Capabilities> capabilities() async => const Wave3Capabilities(
    plugin: true,
    memoryWrite: true,
    incognito: true,
    approvalRules: true,
  );

  @override
  Future<CronJobDetail> cronDetail(HermesMobileCronJob job) async {
    final n = now;
    final failing = job.lastStatus == 'error' || job.id == 'backup';
    final runs = <CronRunRecord>[
      for (var i = 0; i < 8; i++)
        CronRunRecord(
          id: 'cron_${job.id}_$i',
          startedAt: n.subtract(Duration(days: i, hours: 2)),
          endedAt: n.subtract(Duration(days: i, hours: 2)).add(
            Duration(seconds: 40 + i * 7),
          ),
          ok: !(failing && (i == 0 || i == 3)),
          title: job.name,
          preview: failing && (i == 0 || i == 3)
              ? ''
              : 'Finished ${job.name.toLowerCase()} in ${40 + i * 7}s.',
          error: failing && (i == 0 || i == 3)
              ? 'B2 upload failed: 401 Unauthorized (application key expired)'
              : null,
        ),
    ];
    return CronJobDetail(
      lastError: failing ? runs.first.error : null,
      lastOutput: failing
          ? null
          : '**${job.name}**\n\n• 3 meetings today, first at 9:30.\n'
                '• 68°F and clear.\n• 2 emails need a reply.',
      runs: runs,
    );
  }

  @override
  Future<String?> runOutput(String runId) async =>
      runId.endsWith('_0') || runId.endsWith('_3')
      ? null
      : 'Run $runId finished. Everything looked normal.';

  @override
  Future<List<MemoryEntry>> listMemory() async {
    final list = List.of(_memory)
      ..sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
    return list;
  }

  @override
  Future<MemoryEntry> addMemory(MemoryTarget target, String content) async {
    final e = MemoryEntry(
      id: 'm${_seq++}',
      target: target,
      content: content.trim(),
      savedBy: 'user',
      savedAt: now,
    );
    _memory.add(e);
    return e;
  }

  @override
  Future<MemoryEntry> editMemory(MemoryEntry entry, String content) async {
    final i = _memory.indexWhere((e) => e.id == entry.id);
    final e = MemoryEntry(
      id: 'm${_seq++}',
      target: entry.target,
      content: content.trim(),
      pinned: entry.pinned,
      savedBy: 'user',
      savedAt: now,
    );
    if (i >= 0) _memory[i] = e;
    return e;
  }

  @override
  Future<void> deleteMemory(MemoryEntry entry) async =>
      _memory.removeWhere((e) => e.id == entry.id);

  @override
  Future<void> setPinned(MemoryEntry entry, bool pinned) async {
    final i = _memory.indexWhere((e) => e.id == entry.id);
    if (i >= 0) _memory[i] = _memory[i].copyWith(pinned: pinned);
  }

  @override
  Future<Set<String>> incognitoChats() async => Set.of(_incognito);

  @override
  Future<void> setIncognito(String chatId, bool enabled) async =>
      enabled ? _incognito.add(chatId) : _incognito.remove(chatId);

  @override
  Future<List<ApprovalRule>> listRules() async {
    _rules.removeWhere((r) => r.isExpired(now));
    final list = List.of(_rules)
      ..sort((a, b) => a.risk.index == b.risk.index
          ? a.pattern.compareTo(b.pattern)
          : b.risk.index - a.risk.index);
    return list;
  }

  @override
  Future<void> addRule(String pattern, {DateTime? expiresAt, String? note}) async {
    _rules.removeWhere((r) => r.pattern == pattern);
    _rules.add(
      ApprovalRule(
        pattern: pattern.trim(),
        expiresAt: expiresAt,
        addedAt: now,
        note: note,
      ),
    );
  }

  @override
  Future<void> removeRule(String pattern) async =>
      _rules.removeWhere((r) => r.pattern == pattern);

  @override
  Future<UsageWindow?> usageWindow({int days = 30}) async {
    final n = now;
    final today = DateTime(n.year, n.month, n.day);
    final daily = [
      for (var i = days - 1; i >= 0; i--)
        MapEntry(
          today.subtract(Duration(days: i)),
          // A steady base with a busy streak; deterministic for tests.
          0.35 + ((i * 37) % 11) / 20 + (i < 4 ? 0.6 : 0),
        ),
    ];
    return UsageWindow(
      costUsd: daily.fold(0.0, (a, e) => a + e.value),
      days: days,
      daily: daily,
      inputTokens: 4820000,
      outputTokens: 612000,
      sessions: 142,
    );
  }
}
