import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cards/blocks.dart';
import '../../chat/chat_controller.dart';
import '../../data/app_state.dart';
import '../../theme/hermes_mobile_theme.dart';
import 'w2_branches.dart';
import 'w2_canvas.dart';
import 'w2_message_actions.dart';
import 'w2_model_switcher.dart';
import 'w2_search.dart';
import 'w2_settings.dart';
import 'w2_voice.dart';

/// Wraps one message in the thread with Wave 2 affordances: branch arrows on
/// edited/regenerated turns and a quiet action row under finished replies.
class W2MessageFrame extends StatelessWidget {
  const W2MessageFrame({
    super.key,
    required this.ctl,
    required this.index,
    required this.child,
    this.streaming = false,
  });
  final ChatController ctl;
  final int index;
  final Widget child;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final m = ctl.messages[index];
    final c = context.hermesMobile;
    final branch = m.isUser ? ctl.branchInfo(index) : null;
    final pinned = W2Settings.current.isMessagePinned(ctl.chatId, m.text);
    // Long-press inside a bubble selects text (its toolbar has More…); the
    // action row's More actions button opens the same sheet.
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: m.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.stretch,
        children: [
          child,
          if (branch != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: W2BranchArrows(
                current: branch.$1,
                total: branch.$2,
                onPrev: ctl.running ? null : () => ctl.switchBranch(index, -1),
                onNext: ctl.running ? null : () => ctl.switchBranch(index, 1),
              ),
            ),
          if (!m.isUser && !streaming && m.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  _mini(context, Icons.copy_rounded, 'Copy', () {
                    Clipboard.setData(
                      ClipboardData(text: replyPlainText(m.text)),
                    );
                    W2Haptics.selection();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied')));
                  }),
                  ListenableBuilder(
                    listenable: W2ReadAloud.instance,
                    builder: (context, _) {
                      final on = W2ReadAloud.instance.isSpeaking(m.text);
                      return _mini(
                        context,
                        on
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_outlined,
                        on ? 'Stop reading' : 'Read aloud',
                        () => W2ReadAloud.instance.speak(m.text),
                        color: on ? c.accent : null,
                      );
                    },
                  ),
                  if (!ctl.running)
                    _mini(
                      context,
                      Icons.refresh_rounded,
                      'Regenerate',
                      () => ctl.regenerate(index),
                    ),
                  if (pinned)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.push_pin, size: 14, color: c.accent),
                    ),
                  _mini(
                    context,
                    Icons.more_horiz_rounded,
                    'More actions',
                    () => showW2MessageActions(context, ctl, index),
                  ),
                ],
              ),
            ),
          if (m.isUser && pinned)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Icon(Icons.push_pin, size: 13, color: c.accent),
            ),
        ],
      ),
    );
  }

  Widget _mini(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color? color,
  }) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: 17,
    // 48dp touch target around a small glyph.
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    padding: EdgeInsets.zero,
    onPressed: onTap,
    icon: Icon(icon, color: color ?? context.hermesMobile.textTertiary),
  );
}

/// ‹ 2 / 3 › under a branched user message.
class W2BranchArrows extends StatelessWidget {
  const W2BranchArrows({
    super.key,
    required this.current,
    required this.total,
    this.onPrev,
    this.onNext,
  });
  final int current;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Row(
      key: const ValueKey('w2-branch-arrows'),
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous version',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: current > 1 ? onPrev : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '$current / $total',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: c.textSecondary),
        ),
        IconButton(
          tooltip: 'Next version',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: current < total ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

/// "2 pinned" strip at the top of a chat with pinned messages.
class W2PinnedStrip extends StatelessWidget {
  const W2PinnedStrip({super.key, required this.ctl});
  final ChatController ctl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: W2Settings.current,
      builder: (context, _) {
        final pins = W2Settings.current.pinnedMessages(ctl.chatId);
        if (pins.isEmpty) return const SizedBox.shrink();
        final c = context.hermesMobile;
        return Material(
          color: c.accentSoft,
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              builder: (sc) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in pins)
                      ListTile(
                        leading: Icon(
                          p.fromUser
                              ? Icons.person_outline
                              : Icons.auto_awesome_outlined,
                        ),
                        title: Text(
                          replyPlainText(
                            p.text,
                          ).replaceAll(RegExp(r'\s+'), ' '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Unpin',
                          icon: const Icon(Icons.push_pin),
                          onPressed: () {
                            W2Settings.current.toggleMessagePin(p);
                            Navigator.pop(sc);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin, size: 15, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pins.length == 1
                          ? replyPlainText(
                              pins.first.text,
                            ).replaceAll(RegExp(r'\s+'), ' ')
                          : '${pins.length} pinned messages',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens full-screen voice mode for [ctl].
Future<void> openW2VoiceMode(BuildContext context, ChatController ctl) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => W2VoiceModeScreen(chat: ctl),
      ),
    );

/// Handles phone-side slash commands. Returns true when [text] was consumed.
Future<bool> w2HandleSlash(
  BuildContext context,
  ChatController ctl,
  String text,
) async {
  final t = text.trim();
  if (!t.startsWith('/')) return false;
  final space = t.indexOf(' ');
  final name = (space < 0 ? t.substring(1) : t.substring(1, space))
      .toLowerCase();
  final rest = space < 0 ? '' : t.substring(space + 1).trim();
  final state = HermesMobileScope.read(context);
  switch (name) {
    case 'new':
      state.newChat();
      return true;
    case 'model':
      await showW2ModelSwitcher(context, ctl);
      return true;
    case 'voice':
      await openW2VoiceMode(context, ctl);
      return true;
    case 'canvas':
      final out = await openW2Canvas(context, W2CanvasDoc.doc(rest));
      if (out != null) await ctl.send(out);
      return true;
    case 'search':
      await openW2Search(context, initialQuery: rest);
      return true;
    case 'retry':
      final last = ctl.messages.lastIndexWhere((m) => !m.isUser);
      if (last >= 0) await ctl.regenerate(last);
      return true;
    case 'undo':
      ctl.undoLast();
      return true;
    case 'remind':
      if (rest.isEmpty) return false;
      await showW2ReminderSheet(context, rest);
      return true;
  }
  return false;
}
