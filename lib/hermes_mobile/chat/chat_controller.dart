import 'package:flutter/foundation.dart';

import '../../core/models/gateway_activity.dart';
import '../../core/models/gateway_approval.dart';
import '../data/backend.dart';
import '../data/models.dart';
import '../features/wave1_proactive/w1_models.dart'; // wave1
import '../features/wave1_proactive/w1_services.dart'; // wave1

/// State for one open conversation: transcript, the live run (task card),
/// and any approval the agent is waiting on.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.backend,
    required this.chatId,
    String title = '',
    this.isNew = false,
    this.onRunStateChanged,
    this.onApprovalChanged,
  }) {
    _title = title;
  }

  final HermesMobileBackend backend;
  final String chatId;
  final bool isNew;
  final void Function(String chatId, bool running)? onRunStateChanged;
  final void Function(String chatId, HermesMobileApproval? approval)? onApprovalChanged;

  String _title = '';
  String get title => _title.trim().isEmpty ? 'New chat' : _title;

  final List<HermesMobileMessage> messages = [];

  /// Run (task card) attached to the assistant reply it produced.
  final Map<HermesMobileMessage, HermesMobileRun> runs = {};
  HermesMobileRun? liveRun;
  HermesMobileMessage? _liveReply;
  final List<GatewayToolActivity> _activities = [];

  HermesMobileApproval? approval;

  // --- wave1 ---
  /// A sudo / secret / clarify prompt the agent is blocked on.
  HermesMobilePrompt? prompt;

  Future<void> answerPrompt(String value) async {
    final p = prompt;
    if (p == null) return;
    try {
      await Wave1Services.of(backend).respond(p, value);
      prompt = null;
      if (liveRun != null) liveRun!.statusLine = 'Answered';
    } catch (e) {
      error = '$e';
    }
    _notify();
  }

  /// Adds messages produced on the phone (e.g. a schedule confirmation).
  void wave1AddLocal(List<HermesMobileMessage> list) {
    messages.addAll(list);
    _notify();
  }
  // --- end wave1 ---
  bool loading = false;
  String? error;
  bool get running => liveRun?.status == HermesMobileRunStatus.running;
  bool _disposed = false;

  Future<void> load() async {
    if (isNew) return;
    loading = true;
    error = null;
    _notify();
    try {
      final list = await backend.loadMessages(chatId);
      messages
        ..clear()
        ..addAll(list);
    } catch (e) {
      error = 'Could not load this chat. $e';
    } finally {
      loading = false;
      _notify();
    }
  }

  // --- wave2 ---
  /// Project instructions sent as a system message with each turn of a
  /// project chat (set by Wave 2 when the plugin is not injecting them).
  String? w2Preamble;

  /// Lets Wave 2 extensions (branches, undo) repaint the thread.
  void w2Notify() => _notify();
  // --- end wave2 ---

  List<Map<String, dynamic>> _history() => [
    // --- wave2 ---
    if (w2Preamble?.trim().isNotEmpty == true)
      {'role': 'system', 'content': w2Preamble!.trim()},
    // --- end wave2 ---
    for (final m in messages)
      if (m.text.trim().isNotEmpty)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
  ];

  Future<void> send(String text, {String? imageDataUrl}) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && imageDataUrl == null) || running) return;
    final history = _history();
    if (_title.trim().isEmpty) {
      _title = trimmed.length > 40 ? '${trimmed.substring(0, 40)}…' : trimmed;
    }
    messages.add(
      HermesMobileMessage(
        role: HermesMobileRole.user,
        text: trimmed,
        imageDataUrls: [?imageDataUrl],
      ),
    );
    final reply = HermesMobileMessage(role: HermesMobileRole.assistant, text: '');
    messages.add(reply);
    _liveReply = reply;
    final run = HermesMobileRun(title: _runTitle(trimmed));
    liveRun = run;
    runs[reply] = run;
    _activities.clear();
    error = null;
    onRunStateChanged?.call(chatId, true);
    _notify();

    bool current() => identical(liveRun, run) && !_disposed;

    await backend.send(
      chatId: chatId,
      text: trimmed,
      history: history,
      imageDataUrl: imageDataUrl,
      callbacks: HermesMobileTurnCallbacks(
        onToken: (t) {
          if (!current()) return;
          reply.text += t;
          run.statusLine = null;
          _notify();
        },
        onReasoning: (t) {
          if (!current()) return;
          run.reasoning += t;
          reply.reasoning += t;
          _notify();
        },
        onTool: (p) {
          if (!current()) return;
          _applyTool(run, p);
          _notify();
        },
        onStatus: (s) {
          if (!current()) return;
          // --- wave1 ---
          if (s['hermes_mobile_control'] != null) {
            final p = HermesMobilePrompt.fromControl(chatId, s);
            if (p != null) {
              prompt = p;
              run.statusLine = 'Waiting for your answer';
              _notify();
            }
            return;
          }
          // --- end wave1 ---
          final text = (s['text'] ?? s['message'] ?? s['status'] ?? '')
              .toString();
          if (text.isNotEmpty) run.statusLine = text;
          _notify();
        },
        onApproval: (raw) {
          if (!current()) return;
          final req = GatewayApprovalRequest.fromEventData(raw);
          approval = HermesMobileApproval(
            chatId: chatId,
            command: req.command,
            description: req.description,
            choices: req.choices.map((c) => c.wireValue).toList(),
            raw: raw,
          );
          run.statusLine = 'Waiting for your approval';
          onApprovalChanged?.call(chatId, approval);
          _notify();
        },
        onDone: () {
          if (!current()) return;
          _finish(run, HermesMobileRunStatus.done);
        },
        onError: (e) {
          if (!current()) return;
          reply.failed = reply.text.trim().isEmpty;
          if (reply.failed) reply.text = '';
          error = e;
          _finish(run, HermesMobileRunStatus.failed);
        },
      ),
    );
    // A cancelled stream settles silently; make sure the card stops spinning.
    if (identical(liveRun, run) && run.status == HermesMobileRunStatus.running) {
      _finish(run, HermesMobileRunStatus.stopped);
    }
  }

  void _applyTool(HermesMobileRun run, Map<String, dynamic> p) {
    final eventType = p['status'] == 'running' ? 'tool.start' : 'tool.update';
    final update = GatewayToolActivity.fromGatewayEvent(
      eventType,
      p,
      observedAt: DateTime.now(),
    );
    if (update == null) return;
    final idx = toolActivityUpdateIndex(_activities, update, eventType);
    final activity = idx >= 0 ? _activities[idx].merge(update) : update;
    if (idx >= 0) {
      _activities[idx] = activity;
    } else {
      _activities.add(activity);
    }
    final state = activity.isFailed
        ? HermesMobileStepState.failed
        : activity.isTerminal
        ? HermesMobileStepState.done
        : HermesMobileStepState.running;
    final existing = run.steps.where((s) => s.id == activity.identity);
    if (existing.isNotEmpty) {
      existing.first
        ..label = activity.displayName
        ..detail = activity.detail
        ..state = state;
    } else {
      run.steps.add(
        HermesMobileStep(
          id: activity.identity,
          label: activity.displayName,
          detail: activity.detail,
          emoji: activity.emoji,
          state: state,
        ),
      );
    }
    run.statusLine = null;
  }

  void _finish(HermesMobileRun run, HermesMobileRunStatus status) {
    run.status = status;
    for (final s in run.steps) {
      if (s.state == HermesMobileStepState.running) {
        s.state = status == HermesMobileRunStatus.done
            ? HermesMobileStepState.done
            : HermesMobileStepState.failed;
      }
    }
    final reply = _liveReply;
    if (reply != null &&
        reply.text.trim().isEmpty &&
        status == HermesMobileRunStatus.stopped) {
      reply.text = '_Stopped._';
    }
    if (approval != null) {
      approval = null;
      onApprovalChanged?.call(chatId, null);
    }
    prompt = null; // wave1
    liveRun = null;
    _liveReply = null;
    onRunStateChanged?.call(chatId, false);
    _notify();
  }

  Future<void> stop() async {
    final run = liveRun;
    if (run == null) return;
    await backend.stop(chatId);
    if (identical(liveRun, run)) _finish(run, HermesMobileRunStatus.stopped);
  }

  Future<void> answer(String choice) async {
    final a = approval;
    if (a == null) return;
    try {
      await backend.answerApproval(a, choice);
      approval = null;
      onApprovalChanged?.call(chatId, null);
      if (liveRun != null) {
        liveRun!.statusLine = choice == 'deny' ? 'Denied' : 'Approved';
      }
    } catch (e) {
      error = '$e';
    }
    _notify();
  }

  void retryLast() {
    final lastUser = messages.lastWhere(
      (m) => m.isUser,
      orElse: () => HermesMobileMessage(role: HermesMobileRole.user, text: ''),
    );
    if (lastUser.text.isEmpty) return;
    // Drop the failed exchange and resend.
    final i = messages.lastIndexOf(lastUser);
    messages.removeRange(i, messages.length);
    send(lastUser.text);
  }

  static String _runTitle(String prompt) {
    final t = prompt.replaceAll('\n', ' ').trim();
    if (t.isEmpty) return 'Working on it';
    return t.length > 60 ? '${t.substring(0, 60)}…' : t;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // --- wave4 ---
  /// Repaints after Wave 4 moved a failed exchange into the offline queue.
  void wave4Refresh() => _notify();
  // --- /wave4 ---

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
