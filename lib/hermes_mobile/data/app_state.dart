import 'package:flutter/material.dart';

import '../chat/chat_controller.dart';
import '../features/wave4_novel/w4_controller.dart'; // --- wave4 ---
import 'backend.dart';
import 'models.dart';
import 'panels.dart';

/// App-wide Petasos state: the backend, the chat list, open conversations, and
/// what needs the user (pending approvals) or is running now.
class HermesMobileAppState extends ChangeNotifier {
  HermesMobileAppState(this.backend);

  final HermesMobileBackend backend;

  List<HermesMobileChat> chats = [];
  bool chatsLoading = false;
  String? chatsError;

  PanelsResult? panels;
  bool panelsLoading = false;

  /// Open conversations stay alive so a running turn keeps streaming while
  /// the user looks at Home or another chat.
  final Map<String, ChatController> _controllers = {};
  final Map<String, HermesMobileApproval> pendingApprovals = {};
  final Set<String> runningChats = {};

  ChatController? current;

  /// Called when a turn settles: (chatId, title, reply, failed). The root
  /// uses it to post the engine's turn notification while backgrounded.
  void Function(String chatId, String title, String reply, bool failed)?
  onTurnSettled;

  ChatController controllerFor(HermesMobileChat chat) {
    return _controllers.putIfAbsent(chat.id, () {
      final c = ChatController(
        backend: backend,
        chatId: chat.id,
        title: chat.displayTitle == 'New chat' ? '' : chat.displayTitle,
        isNew: chat.isDraft,
        onRunStateChanged: _onRun,
        onApprovalChanged: _onApproval,
      );
      if (!chat.isDraft) c.load();
      return c;
    });
  }

  ChatController newChat() {
    final id = backend.newChatId();
    final c = controllerFor(HermesMobileChat(id: id, title: '', isDraft: true));
    current = c;
    notifyListeners();
    return c;
  }

  void open(HermesMobileChat chat) {
    current = controllerFor(chat);
    notifyListeners();
  }

  void openController(ChatController c) {
    current = c;
    notifyListeners();
  }

  ChatController? controllerById(String id) => _controllers[id];

  void _onRun(String chatId, bool running) {
    if (running) {
      runningChats.add(chatId);
    } else {
      runningChats.remove(chatId);
      final ctl = _controllers[chatId];
      if (ctl != null && ctl.messages.isNotEmpty) {
        final last = ctl.messages.last;
        onTurnSettled?.call(
          chatId,
          ctl.title,
          last.text,
          last.failed || ctl.error != null,
        );
      }
      // Pick up the server title and ordering once the turn settles.
      refreshChats(quiet: true);
    }
    notifyListeners();
  }

  void _onApproval(String chatId, HermesMobileApproval? approval) {
    if (approval == null) {
      pendingApprovals.remove(chatId);
    } else {
      pendingApprovals[chatId] = approval;
    }
    notifyListeners();
  }

  Future<void> refreshChats({bool quiet = false}) async {
    if (!quiet) {
      chatsLoading = true;
      notifyListeners();
    }
    try {
      chats = [
        for (final c in await backend.listChats())
          if (!_archiving.contains(c.id)) c,
      ];
      chatsError = null;
    } catch (e) {
      chatsError = '$e';
    } finally {
      chatsLoading = false;
      notifyListeners();
    }
  }

  /// Chats hidden while their Archive Undo window is open.
  final Set<String> _archiving = {};

  /// Hides [chat] now; the server archive waits for [commitArchive].
  /// Returns the chat's old index, or -1 when it is not in the list.
  int stageArchive(HermesMobileChat chat) {
    final i = chats.indexWhere((c) => c.id == chat.id);
    _archiving.add(chat.id);
    if (i >= 0) {
      chats = [...chats]..removeAt(i);
      notifyListeners();
    }
    return i;
  }

  /// Puts a staged chat back at [index]. Nothing reaches the server.
  void undoArchive(HermesMobileChat chat, int index) {
    _archiving.remove(chat.id);
    if (chats.any((c) => c.id == chat.id)) return;
    chats = [...chats]
      ..insert(index < 0 ? 0 : index.clamp(0, chats.length), chat);
    notifyListeners();
  }

  /// Archives a staged chat on the server; on failure it comes back.
  Future<void> commitArchive(HermesMobileChat chat, int index) async {
    try {
      await backend.setChatArchived(chat.id, true);
      _archiving.remove(chat.id);
    } catch (e) {
      chatsError = 'Could not archive: $e';
      undoArchive(chat, index);
    }
  }

  /// Moves an archived chat back to the chats list.
  Future<void> unarchiveChat(HermesMobileChat chat) async {
    await backend.setChatArchived(chat.id, false);
    await refreshChats(quiet: true);
  }

  Future<void> refreshPanels() async {
    panelsLoading = true;
    notifyListeners();
    panels = await backend.panels.load();
    panelsLoading = false;
    notifyListeners();
  }

  /// Chats that are running now: live turns on this phone plus sessions the
  /// gateway reports as active.
  List<HermesMobileChat> get runningNow {
    final ids = <String>{...runningChats};
    final out = <HermesMobileChat>[];
    for (final c in chats) {
      if (c.isActive || ids.contains(c.id)) {
        out.add(c);
        ids.remove(c.id);
      }
    }
    for (final id in ids) {
      final ctl = _controllers[id];
      if (ctl != null) {
        out.add(HermesMobileChat(id: id, title: ctl.title, isActive: true));
      }
    }
    return out;
  }

  String titleFor(String chatId) {
    final ctl = _controllers[chatId];
    if (ctl != null) return ctl.title;
    return chats
            .where((c) => c.id == chatId)
            .map((c) => c.displayTitle)
            .firstOrNull ??
        'Chat';
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    disposeWave4(); // --- wave4 ---
    backend.dispose();
    super.dispose();
  }
}

/// Exposes [HermesMobileAppState] down the tree.
class HermesMobileScope extends InheritedNotifier<HermesMobileAppState> {
  const HermesMobileScope({
    super.key,
    required HermesMobileAppState state,
    required super.child,
  }) : super(notifier: state);

  static HermesMobileAppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HermesMobileScope>()!.notifier!;

  static HermesMobileAppState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<HermesMobileScope>()!.widget
              as HermesMobileScope)
          .notifier!;
}
