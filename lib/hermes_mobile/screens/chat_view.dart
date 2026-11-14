import 'package:flutter/material.dart';

import '../cards/card_widgets.dart';
import '../chat/chat_controller.dart';
import '../data/app_state.dart';
import '../features/wave1_proactive/w1_chat_hooks.dart'; // wave1
import '../features/wave4_novel/ui/w4_chat.dart'; // --- wave4 ---
import '../theme/hermes_mobile_theme.dart';
import '../widgets/composer.dart';
import '../widgets/message_views.dart';
import '../widgets/run_widgets.dart';
// --- wave2 ---
import '../features/wave2_parity/w2_chat_extras.dart';
import '../features/wave2_parity/w2_composer_assist.dart';
import '../features/wave2_parity/w2_message_actions.dart';
import '../features/wave2_parity/w2_model_switcher.dart';
import '../features/wave2_parity/w2_settings.dart';
import '../features/wave2_parity/w2_voice.dart';
// --- end wave2 ---
// --- wave3 ---
import '../features/wave3_control/live_run_screen.dart';
// --- end wave3 ---

/// The main surface: a texting-style thread plus the composer.
class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.controller});
  final ChatController controller;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scroll = ScrollController();
  final _w2Text = TextEditingController(); // --- wave2 ---

  ChatController get ctl => widget.controller;

  // --- wave2 --- slash commands, auto read-aloud
  Future<void> _w2Send(String text, String? image) async {
    if (image == null && await w2HandleSlash(context, ctl, text)) return;
    _send(text, image);
  }

  Future<void> _w2AfterTurn(Future<void> turn) async {
    await turn;
    if (!mounted || !W2Settings.current.autoReadAloud) return;
    final last = ctl.messages.isEmpty ? null : ctl.messages.last;
    if (last != null && !last.isUser && !last.failed) {
      await W2ReadAloud.instance.speak(last.text);
    }
  }
  // --- end wave2 ---

  void _send(String text, String? image) {
    // --- wave1 --- schedule intent → cron preview card first
    if (image == null && w1InterceptSchedule(context, ctl, text, _sendNow)) {
      return;
    }
    _sendNow(text, image);
  }

  void _sendNow(String text, String? image) {
    // --- end wave1 ---
    // --- wave4 --- offline queue
    if (Wave4ChatHooks.interceptSend(context, ctl, text, image)) return;
    // --- /wave4 ---
    W2Haptics.light(); // --- wave2 ---
    final sending = ctl.send(text, imageDataUrl: image);
    Wave4ChatHooks.watchSend(context, ctl, text, image, sending); // --- wave4 ---
    _w2AfterTurn(sending); // --- wave2 ---
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _w2Text.dispose(); // --- wave2 ---
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HermesMobileCardScope(
      // --- wave4 --- undo window on card actions
      onAction: (message) => Wave4ChatHooks.cardActionWithUndo(
        context,
        message,
        (m) => _send(m, null),
      ),
      child: ListenableBuilder(
        listenable: ctl,
        builder: (context, _) {
          final items = <Widget>[];
          // --- wave2 --- message actions, branch arrows, reply action row
          for (var i = 0; i < ctl.messages.length; i++) {
            final m = ctl.messages[i];
            final isLive = ctl.running && identical(m, ctl.messages.last);
            void actions() => showW2MessageActions(context, ctl, i);
            items.add(
              W2MessageFrame(
                ctl: ctl,
                index: i,
                streaming: isLive,
                child: m.isUser
                    ? UserBubble(message: m, onLongPress: actions)
                    : AgentReply(
                        message: m,
                        run: ctl.runs[m],
                        streaming: isLive,
                        onStop: ctl.stop,
                        onLongPress: actions,
                      ),
              ),
            );
          }
          // --- end wave2 ---
          final reversed = items.reversed.toList();
          final empty = ctl.messages.isEmpty && !ctl.loading;
          return Column(
            children: [
              W2PinnedStrip(ctl: ctl), // --- wave2 ---
              Expanded(
                child: ctl.loading && ctl.messages.isEmpty
                    ? const _ThreadSkeleton()
                    : empty
                    ? _ChatEmpty(onPick: (s) => _send(s, null))
                    : ListView.separated(
                        controller: _scroll,
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: reversed.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (_, i) => reversed[i],
                      ),
              ),
              if (ctl.error != null && !ctl.running)
                _ErrorBar(
                  message: ctl.error!,
                  onRetry: ctl.messages.isEmpty ? ctl.load : ctl.retryLast,
                ),
              // --- wave1 ---
              if (ctl.prompt != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                  child: HermesMobilePromptCard(
                    key: ValueKey(ctl.prompt!.requestId),
                    prompt: ctl.prompt!,
                    onAnswer: ctl.answerPrompt,
                  ),
                ),
              // --- end wave1 ---
              // --- wave3 ---
              if (ctl.running) LiveRunBar(controller: ctl),
              // --- end wave3 ---
              if (ctl.approval != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                  child: ApprovalCard(
                    approval: ctl.approval!,
                    // --- wave4 --- undo window on approvals
                    onAnswer: (choice) =>
                        Wave4ChatHooks.answerWithUndo(context, ctl, choice),
                  ),
                ),
              QueuedInChat(chatId: ctl.chatId), // --- wave4 ---
              HermesMobileComposer(
                running: ctl.running,
                // --- wave2 ---
                onSend: _w2Send,
                controller: _w2Text,
                w2Above: (t) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    W2ComposerAssist(controller: t),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: W2ModelChip(
                          key: ValueKey('w2-model-${ctl.chatId}'),
                          chat: ctl,
                        ),
                      ),
                    ),
                  ],
                ),
                w2Accessory: W2VoiceButton(
                  onOpenVoiceMode: () => openW2VoiceMode(context, ctl),
                  onHeld: (text) => _send(text, null),
                ),
                // --- end wave2 ---
                onStop: ctl.stop,
                onUploadFile: w1Uploader(context), // wave1
                hint: HermesMobileScope.of(context).backend.isDemo
                    ? 'Message demo Hermes'
                    : 'Message Hermes',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: c.danger,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ThreadSkeleton extends StatelessWidget {
  const _ThreadSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 200, child: SkeletonCard(height: 44)),
        ),
        SizedBox(height: 14),
        SizedBox(width: 280, child: SkeletonCard(height: 96)),
        SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 160, child: SkeletonCard(height: 44)),
        ),
        SizedBox(height: 14),
        SkeletonCard(height: 140),
      ],
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty({required this.onPick});
  final void Function(String) onPick;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    const suggestions = [
      'What needs my attention today?',
      'Summarise my overnight email',
      'Check on last night\'s backups',
      'Plan something fun this weekend',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      children: [
        Text(
          _greeting(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'What can Hermes take off your plate?',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: 24),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HermesMobileCardFrame(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              onTap: () => onPick(s),
              child: Row(
                children: [
                  Expanded(child: Text(s)),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: c.textTertiary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
