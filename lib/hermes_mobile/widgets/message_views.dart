import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cards/blocks.dart';
import '../cards/card_widgets.dart';
import '../data/models.dart';
import '../features/wave4_novel/ui/w4_chat.dart'; // --- wave4 ---
import '../theme/hermes_mobile_theme.dart';
import 'run_widgets.dart';

/// Right-aligned accent bubble for the user's own message.
class UserBubble extends StatelessWidget {
  const UserBubble({
    super.key,
    required this.message,
    this.onLongPress, // --- wave2 ---
  });
  final HermesMobileMessage message;

  /// Replaces the default copy-on-long-press (Wave 2 message actions).
  final VoidCallback? onLongPress; // --- wave2 ---

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: MessageSelection(
          text: message.text,
          onActions: onLongPress, // --- wave2 ---
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final url in message.imageDataUrls)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _dataImage(url),
                  ),
                ),
              if (message.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.userBubble,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(HermesMobileRadius.bubble),
                      topRight: Radius.circular(HermesMobileRadius.bubble),
                      bottomLeft: Radius.circular(HermesMobileRadius.bubble),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: c.onUserBubble),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dataImage(String url) {
    final comma = url.indexOf(',');
    if (url.startsWith('data:') && comma > 0) {
      try {
        return Image.memory(
          base64Decode(url.substring(comma + 1)),
          width: 200,
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }
    return const SizedBox.shrink();
  }
}

/// Makes one message's text selectable: long-press picks a word, the
/// handles extend it. The selection toolbar adds "Copy message" (the whole
/// reply as plain text) and, when [onActions] is set, "More…" for the message
/// actions sheet that long-press used to open.
class MessageSelection extends StatelessWidget {
  const MessageSelection({
    super.key,
    required this.text,
    required this.child,
    this.onActions,
  });
  final String text;
  final Widget child;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (menuContext, region) {
        void close() => region.hideToolbar();
        final items = [...region.contextMenuButtonItems];
        // Narrow phones show ~3 items before the overflow; keep More… right
        // after Copy so it stays visible.
        final at = items.isEmpty ? 0 : 1;
        items.insertAll(at, [
          if (onActions != null)
            ContextMenuButtonItem(
              label: 'More…',
              onPressed: () {
                close();
                region.clearSelection();
                onActions!();
              },
            ),
        ]);
        items.add(
          ContextMenuButtonItem(
            label: 'Copy message',
            onPressed: () {
              close();
              _copy(context, text);
            },
          ),
        );
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: items,
        );
      },
      child: child,
    );
  }
}

void _copy(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: replyPlainText(text)));
  HapticFeedback.selectionClick();
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Copied')));
}

/// The agent's reply: short left bubbles for prose, cards for everything else.
class AgentReply extends StatelessWidget {
  const AgentReply({
    super.key,
    required this.message,
    this.run,
    this.streaming = false,
    this.onStop,
    this.onLongPress, // --- wave2 ---
  });
  final HermesMobileMessage message;
  final HermesMobileRun? run;
  final bool streaming;
  final VoidCallback? onStop;

  /// Replaces the default copy-on-long-press (Wave 2 message actions).
  final VoidCallback? onLongPress; // --- wave2 ---

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final blocks = parseHermesMobileBlocks(message.text, isFinal: !streaming);
    final children = <Widget>[];

    final r = run;
    if (r != null &&
        (r.status == HermesMobileRunStatus.running || r.steps.isNotEmpty)) {
      children.add(TaskCard(run: r, onStop: onStop));
    } else if (r == null && message.toolNames.isNotEmpty) {
      final done = HermesMobileRun(title: 'Done')..status = HermesMobileRunStatus.done;
      for (var i = 0; i < message.toolNames.length; i++) {
        done.steps.add(
          HermesMobileStep(
            id: '$i',
            label: message.toolNames[i],
            state: HermesMobileStepState.done,
          ),
        );
      }
      done.reasoning = message.reasoning;
      children.add(TaskCard(run: done));
    } else if (message.reasoning.trim().isNotEmpty && !streaming) {
      children.add(ThinkingDisclosure(text: message.reasoning));
    }

    if (streaming &&
        message.text.trim().isEmpty &&
        (r?.steps.isEmpty ?? true)) {
      children.add(
        const Align(alignment: Alignment.centerLeft, child: TypingIndicator()),
      );
    }

    for (final b in blocks) {
      if (b is ProseBlock) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.86,
              ),
              child: MessageSelection(
                text: message.text,
                onActions: onLongPress, // --- wave2 ---
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.agentBubble,
                    border: Border.all(color: c.hairline),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(HermesMobileRadius.bubble),
                      topRight: Radius.circular(HermesMobileRadius.bubble),
                      bottomRight: Radius.circular(HermesMobileRadius.bubble),
                      bottomLeft: Radius.circular(6),
                    ),
                  ),
                  child: HermesMobileMarkdown(b.markdown),
                ),
              ),
            ),
          ),
        );
      } else {
        children.add(HermesMobileSelectable(child: HermesMobileBlockView(b)));
      }
    }

    // --- wave4 --- confidence and source chips
    if (!streaming && !message.failed) {
      children.add(ProvenanceChips(message: message, run: run));
    }
    // --- /wave4 ---

    if (message.failed) {
      children.add(
        Text(
          'No reply. The run ended with an error.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: c.danger),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          children[i],
        ],
      ],
    );
  }
}
