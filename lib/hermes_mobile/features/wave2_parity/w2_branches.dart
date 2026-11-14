import '../../chat/chat_controller.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// One alternative continuation from a user message: the messages from that
/// point on, their task cards, and any deeper branches inside it.
class W2Variant {
  W2Variant(this.tail, this.runs, this.nested);
  final List<HermesMobileMessage> tail;
  final Map<HermesMobileMessage, HermesMobileRun> runs;
  final Map<int, W2Slot> nested;
}

/// The alternatives at one position. `variants[selected]` is always the one
/// shown, whose live content is the controller's transcript.
class W2Slot {
  W2Slot(this.variants, this.selected);
  final List<W2Variant> variants;
  int selected;
}

class W2BranchState {
  final Map<int, W2Slot> slots = {};
}

final Expando<W2BranchState> _branches = Expando('w2branches');

/// Edit-and-resend, regenerate, branch arrows, fork and undo, built only on
/// ChatController's public surface so the shared file stays untouched.
extension W2Branching on ChatController {
  W2BranchState get w2Branches => _branches[this] ??= W2BranchState();

  /// Branch info for the user message at [index]: (current 1-based, total),
  /// or null when there is only one version.
  (int, int)? branchInfo(int index) {
    final slot = w2Branches.slots[index];
    if (slot == null || slot.variants.length < 2) return null;
    return (slot.selected + 1, slot.variants.length);
  }

  W2Variant _snapshot(int index) {
    final tail = messages.sublist(index);
    final tailRuns = <HermesMobileMessage, HermesMobileRun>{
      for (final m in tail)
        if (runs[m] != null) m: runs[m]!,
    };
    final nested = <int, W2Slot>{};
    final slots = w2Branches.slots;
    for (final k in slots.keys.where((k) => k > index).toList()) {
      nested[k] = slots.remove(k)!;
    }
    return W2Variant(List.of(tail), tailRuns, nested);
  }

  void _restore(int index, W2Variant v) {
    messages.removeRange(index, messages.length);
    messages.addAll(v.tail);
    runs.addAll(v.runs);
    w2Branches.slots.addAll(v.nested);
  }

  /// Opens a new branch at the user message [index] and sends [text] there.
  Future<void> editAndResend(int index, String text, {String? imageDataUrl}) async {
    if (running || index < 0 || index >= messages.length) return;
    if (!messages[index].isUser || text.trim().isEmpty) return;
    final slots = w2Branches.slots;
    final snap = _snapshot(index);
    final slot = slots[index];
    if (slot == null) {
      slots[index] = W2Slot([snap], 0);
    } else {
      slot.variants[slot.selected] = snap;
    }
    final s = slots[index]!;
    messages.removeRange(index, messages.length);
    s.variants.add(W2Variant(const [], const {}, const {}));
    s.selected = s.variants.length - 1;
    w2Notify();
    await send(text, imageDataUrl: imageDataUrl);
  }

  /// Regenerates the assistant reply at [replyIndex] as a new branch.
  Future<void> regenerate(int replyIndex) async {
    final userIndex = _userBefore(replyIndex);
    if (userIndex == null) return;
    final user = messages[userIndex];
    await editAndResend(
      userIndex,
      user.text,
      imageDataUrl: user.imageDataUrls.firstOrNull,
    );
  }

  /// Shows the previous (-1) or next (+1) branch at user message [index].
  void switchBranch(int index, int delta) {
    if (running) return;
    final slot = w2Branches.slots[index];
    if (slot == null) return;
    final next = slot.selected + delta;
    if (next < 0 || next >= slot.variants.length) return;
    slot.variants[slot.selected] = _snapshot(index);
    slot.selected = next;
    _restore(index, slot.variants[next]);
    w2Notify();
  }

  /// Removes the last exchange from the phone's view (the `/undo` command).
  bool undoLast() {
    if (running) return false;
    final i = messages.lastIndexWhere((m) => m.isUser);
    if (i < 0) return false;
    messages.removeRange(i, messages.length);
    w2Branches.slots.removeWhere((k, _) => k >= i);
    w2Notify();
    return true;
  }

  int? _userBefore(int replyIndex) {
    for (var i = replyIndex - 1; i >= 0; i--) {
      if (messages[i].isUser) return i;
    }
    return null;
  }

  /// Index of the user message that starts the turn containing [index].
  int? turnStart(int index) =>
      index >= 0 && index < messages.length && messages[index].isUser
      ? index
      : _userBefore(index);
}

extension W2Forking on HermesMobileAppState {
  /// Starts a new chat seeded with [source]'s transcript up to and including
  /// [index]. The seeded messages travel as history on the first send, so the
  /// gateway stores the fork as its own session.
  ChatController forkChat(ChatController source, int index, {String? title}) {
    final fork = newChat();
    final upto = source.messages.take(index + 1);
    for (final m in upto) {
      fork.messages.add(
        HermesMobileMessage(
          role: m.role,
          text: m.text,
          createdAt: m.createdAt,
          imageDataUrls: m.imageDataUrls,
          reasoning: m.reasoning,
          toolNames: m.toolNames,
        ),
      );
    }
    fork.w2Preamble = source.w2Preamble;
    fork.w2ForkTitle = title ?? 'Fork of ${source.title}';
    fork.w2Notify();
    return fork;
  }
}

final Expando<String> _forkTitles = Expando('w2forkTitle');

extension W2ForkTitle on ChatController {
  String? get w2ForkTitle => _forkTitles[this];
  set w2ForkTitle(String? v) => _forkTitles[this] = v;
}
