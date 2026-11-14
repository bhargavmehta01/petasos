import 'models.dart';
import 'panels.dart';

/// Callbacks for one streamed turn. Mirrors the engine's SSE callbacks.
class HermesMobileTurnCallbacks {
  const HermesMobileTurnCallbacks({
    required this.onToken,
    required this.onReasoning,
    required this.onTool,
    required this.onStatus,
    required this.onApproval,
    required this.onDone,
    required this.onError,
  });
  final void Function(String token) onToken;
  final void Function(String text) onReasoning;

  /// Raw `hermes.tool.progress` payload.
  final void Function(Map<String, dynamic> progress) onTool;
  final void Function(Map<String, dynamic> status) onStatus;
  final void Function(Map<String, dynamic> approval) onApproval;
  final void Function() onDone;
  final void Function(String error) onError;
}

/// Everything the Petasos screens need. [LiveBackend] adapts the hermes-android
/// engine; [DemoBackend] serves sample data with no server.
abstract class HermesMobileBackend {
  bool get isDemo;
  ConnectionSummary get connection;

  Future<bool> checkHealth();

  // Chats
  Future<List<HermesMobileChat>> listChats();
  Future<List<HermesMobileChat>> searchChats(String query);
  Future<List<HermesMobileMessage>> loadMessages(String chatId);
  String newChatId();
  Future<void> renameChat(String chatId, String title);
  Future<void> deleteChat(String chatId);

  /// Archives or unarchives a chat on the server (hidden from [listChats]).
  Future<void> setChatArchived(String chatId, bool archived);

  /// Recently archived chats, newest first.
  Future<List<HermesMobileChat>> listArchivedChats();

  /// Streams one turn. [history] is the prior transcript in wire form.
  Future<void> send({
    required String chatId,
    required String text,
    required List<Map<String, dynamic>> history,
    String? imageDataUrl,
    required HermesMobileTurnCallbacks callbacks,
  });

  /// Interrupts the current turn. Returns false when nothing was running.
  Future<bool> stop(String chatId);

  Future<void> answerApproval(HermesMobileApproval approval, String choice);

  // Projects (folders with their own chats)
  Future<List<HermesMobileProject>?> listProjects();
  Future<List<HermesMobileChat>> projectChats(String projectId);

  // Scheduled tasks (Hermes cron)
  Future<List<HermesMobileCronJob>> listCron();
  Future<void> createCron({
    required String name,
    required String schedule,
    required String prompt,
  });
  Future<void> updateCron(String id, Map<String, dynamic> updates);
  Future<void> setCronPaused(String id, bool paused);
  Future<void> runCron(String id);
  Future<void> deleteCron(String id);

  Future<List<HermesMobileSkill>> listSkills();
  Future<List<HermesMobileMemoryItem>> listMemory();

  /// Raw SKILL.md and linked files for one skill. Throws when the server has
  /// no skill-content endpoint; callers fall back to the list fields.
  Future<HermesMobileSkillDetail> skillDetail(String name);

  /// Turns a skill on or off on the host (dashboard `PUT /api/skills/toggle`).
  Future<void> setSkillEnabled(String name, bool enabled);

  /// Full text of a memory entry; [HermesMobileMemoryItem.body] may be a preview.
  Future<String> memoryFullText(HermesMobileMemoryItem item);

  /// Rewrites one memory entry in place. Only for [HermesMobileMemoryItem.editable].
  Future<void> editMemoryItem(HermesMobileMemoryItem item, String content);
  Future<HermesMobileUsage?> usage();

  PanelsSource get panels;

  void dispose();
}
