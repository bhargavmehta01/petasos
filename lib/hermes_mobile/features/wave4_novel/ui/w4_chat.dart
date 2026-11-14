import 'dart:async';

import 'package:flutter/material.dart';

import '../../../cards/card_widgets.dart';
import '../../../chat/chat_controller.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../theme/hermes_mobile_theme.dart';
import '../w4_controller.dart';
import '../w4_extract.dart';
import 'w4_widgets.dart';

/// The few places Wave 4 hooks into the chat surface. Each call site in the
/// shared files is one fenced line.
abstract final class Wave4ChatHooks {
  /// Before a send: when Hermes is known to be offline the message goes to
  /// the queue. Returns true when the caller must not send.
  static bool interceptSend(
    BuildContext context,
    ChatController ctl,
    String text,
    String? image,
  ) {
    final w4 = HermesMobileScope.read(context).wave4;
    if (w4.online || text.trim().isEmpty) return false;
    unawaited(w4.enqueue(ctl, text.trim(), image));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Hermes is offline. Queued; it sends when it is back.'),
      ),
    );
    return true;
  }

  /// After a send settles: a send that failed for lack of a connection moves
  /// into the offline queue instead of ending in an error.
  static void watchSend(
    BuildContext context,
    ChatController ctl,
    String text,
    String? image,
    Future<void> sending,
  ) {
    final w4 = HermesMobileScope.read(context).wave4;
    final messenger = ScaffoldMessenger.maybeOf(context);
    unawaited(
      sending.then((_) async {
        if (await w4.captureFailedSend(ctl, text, image)) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Could not reach Hermes. Queued; it sends on reconnect.'),
            ),
          );
        } else if (ctl.error == null) {
          w4.online = true;
        }
      }),
    );
  }

  /// Approval answers that let something go out (a message, an order, a
  /// payment) wait out the undo window. Deny and local commands are instant.
  static Future<void> answerWithUndo(
    BuildContext context,
    ChatController ctl,
    String choice,
  ) async {
    final a = ctl.approval;
    if (choice == 'deny' ||
        a == null ||
        !isOutboundAction(a.description, command: a.command)) {
      return ctl.answer(choice);
    }
    final w4 = HermesMobileScope.read(context).wave4;
    final what = a.description.trim();
    final ticket = w4.hold(
      'Approved${what.isEmpty ? '' : ': $what'}',
      () => ctl.answer(choice),
    );
    if (w4.undoWindow > Duration.zero) showUndoBar(context, w4, ticket);
    await ticket.result;
  }

  /// Card buttons that send or buy ("Approve and order", "Send reply") wait
  /// out the undo window before the message reaches the agent.
  static void cardActionWithUndo(
    BuildContext context,
    String message,
    void Function(String message) send,
  ) {
    if (!isOutboundAction(message)) return send(message);
    final w4 = HermesMobileScope.read(context).wave4;
    final ticket = w4.hold('Sending "$message"', () async => send(message));
    if (w4.undoWindow > Duration.zero) showUndoBar(context, w4, ticket);
  }
}

/// Banner above the composer for messages queued in this chat.
class QueuedInChat extends StatelessWidget {
  const QueuedInChat({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) {
    final w4 = HermesMobileScope.of(context).wave4;
    return ListenableBuilder(
      listenable: w4,
      builder: (context, _) {
        final items = w4.queuedFor(chatId);
        if (items.isEmpty) return const SizedBox.shrink();
        final c = context.hermesMobile;
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_queue_rounded, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  items.length == 1
                      ? 'Queued: "${items.first.text}"'
                      : '${items.length} messages queued',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: w4.flushing ? null : w4.checkOnline,
                child: Text(w4.flushing ? 'Sending' : 'Retry'),
              ),
              IconButton(
                tooltip: 'Discard',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  for (final q in items) {
                    w4.removeQueued(q);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Confidence and source chips under an agent reply.
class ProvenanceChips extends StatelessWidget {
  const ProvenanceChips({super.key, required this.message, this.run});
  final HermesMobileMessage message;
  final HermesMobileRun? run;

  @override
  Widget build(BuildContext context) {
    final p = provenanceOf(
      message,
      runTools: [for (final s in run?.steps ?? const <HermesMobileStep>[]) s.label],
    );
    if (p.isEmpty) return const SizedBox.shrink();
    final c = context.hermesMobile;
    final chips = <Widget>[];
    final conf = p.confidence;
    if (conf != null) {
      chips.add(
        W4Pill(
          label: switch (conf) {
            ConfidenceLevel.high => 'High confidence',
            ConfidenceLevel.medium => 'Medium confidence',
            ConfidenceLevel.low => 'Low confidence · verify',
          },
          icon: switch (conf) {
            ConfidenceLevel.high => Icons.verified_outlined,
            ConfidenceLevel.medium => Icons.help_outline_rounded,
            ConfidenceLevel.low => Icons.warning_amber_rounded,
          },
          color: switch (conf) {
            ConfidenceLevel.high => c.success,
            ConfidenceLevel.medium => c.warning,
            ConfidenceLevel.low => c.danger,
          },
        ),
      );
    }
    if (p.sources.isNotEmpty) {
      chips.add(
        W4Pill(
          label: '${p.sources.length} source${p.sources.length == 1 ? '' : 's'}',
          icon: Icons.link_rounded,
          color: c.accent,
          onTap: () => _showSources(context, p),
        ),
      );
    }
    if (p.fromMemory) {
      chips.add(const W4Pill(label: 'From memory', icon: Icons.psychology_outlined));
    }
    final tools = p.tools.where((t) => !t.toLowerCase().contains('memory')).toList();
    if (tools.isNotEmpty) {
      chips.add(
        W4Pill(
          label: tools.length == 1 ? tools.first : '${tools.length} tools',
          icon: Icons.build_outlined,
          onTap: () => _showSources(context, p),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  void _showSources(BuildContext context, ReplyProvenance p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const ListTile(
              title: Text(
                'Where this answer came from',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final s in p.sources)
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: Text(s.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(s.domain),
                onTap: () => openExternal(context, s.url),
              ),
            if (p.tools.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: const Text('Tools used'),
                subtitle: Text(p.tools.join(', ')),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens the same chat in the Hermes dashboard (`/chat?resume=<id>`).
Future<void> openInDashboard(BuildContext context, String chatId) async {
  final state = HermesMobileScope.read(context);
  final url = dashboardSessionUrl(state.backend.connection.dashboard, chatId);
  if (url == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Add the Hermes dashboard URL under Profile → Connection first.'),
      ),
    );
    return;
  }
  if (url.startsWith('demo://')) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Demo: would open $url')),
    );
    return;
  }
  await openExternal(context, url);
}

/// Long-press menu entry for the dashboard hand-off.
class OpenInDashboardTile extends StatelessWidget {
  const OpenInDashboardTile({super.key, required this.chatId, this.onDone});
  final String chatId;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.desktop_windows_outlined),
      title: const Text('Continue on the dashboard'),
      subtitle: const Text('Opens this same chat in the Hermes web dashboard'),
      onTap: () {
        onDone?.call();
        openInDashboard(context, chatId);
      },
    );
  }
}
