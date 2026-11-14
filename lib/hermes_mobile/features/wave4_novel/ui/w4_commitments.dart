import 'package:flutter/material.dart';

import '../../../cards/card_widgets.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../theme/hermes_mobile_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/undo.dart';
import '../w4_controller.dart';
import '../w4_models.dart';
import 'w4_widgets.dart';
import '../../wave2_parity/w2_settings.dart';

String dueLabel(DateTime? due, DateTime now) {
  if (due == null) return 'No date';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  final diff = day.difference(today).inDays;
  final h = due.hour == 0 ? 12 : (due.hour > 12 ? due.hour - 12 : due.hour);
  final m = due.minute.toString().padLeft(2, '0');
  final time = '$h:$m ${due.hour >= 12 ? 'pm' : 'am'}';
  if (due.isBefore(now)) {
    if (diff == 0) return 'Overdue · today $time';
    return 'Overdue · ${-diff}d';
  }
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Tomorrow $time';
  if (diff < 7) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[due.weekday - 1]} $time';
  }
  return '${due.month}/${due.day}';
}

/// Promises from chats, agent's and user's, sorted by due date.
class CommitmentsScreen extends StatefulWidget {
  const CommitmentsScreen({super.key, this.onOpenChat});
  final void Function(HermesMobileChat chat)? onOpenChat;

  @override
  State<CommitmentsScreen> createState() => _CommitmentsScreenState();
}

class _CommitmentsScreenState extends State<CommitmentsScreen> {
  int _tab = 0; // 0 open, 1 done

  @override
  Widget build(BuildContext context) {
    final w4 = HermesMobileScope.of(context).wave4;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commitments'),
        actions: [
          IconButton(
            tooltip: 'Scan recent chats',
            icon: const Icon(Icons.manage_search_rounded),
            onPressed: () => w4.refreshCommitments(scanChats: true),
          ),
        ],
      ),
      body: SelectionArea(
        child: ListenableBuilder(
          listenable: w4,
          builder: (context, _) {
            final now = DateTime.now();
            final list = w4.commitments
                .where((c) => c.done == (_tab == 1))
                .toList();
            return RefreshIndicator(
              onRefresh: () => w4.refreshCommitments(scanChats: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Open')),
                      ButtonSegment(value: 1, label: Text('Done')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (w4.commitmentsLoading && w4.commitments.isEmpty)
                    const SkeletonCard(height: 140)
                  else if (list.isEmpty)
                    EmptyState(
                      icon: Icons.handshake_outlined,
                      title: _tab == 0
                          ? 'No open promises'
                          : 'Nothing done yet',
                      body: _tab == 0
                          ? 'When Hermes says "I\'ll check back Friday" or you say '
                                '"remind me to…", it lands here with its due date.'
                          : 'Ticked-off commitments show here.',
                    )
                  else
                    HermesMobileCardFrame(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final k in list)
                            CommitmentTile(
                              commitment: k,
                              now: now,
                              w4: w4,
                              onOpenChat: widget.onOpenChat,
                            ),
                        ],
                      ),
                    ),
                  if (!w4.pluginAvailable &&
                      w4.pluginChecked &&
                      !HermesMobileScope.of(context).backend.isDemo)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Found in chats opened on this phone. Install the Petasos '
                        'server plugin to collect promises from every chat, '
                        'including Telegram and cron runs.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class CommitmentTile extends StatelessWidget {
  const CommitmentTile({
    super.key,
    required this.commitment,
    required this.now,
    required this.w4,
    this.onOpenChat,
  });
  final HermesMobileCommitment commitment;
  final DateTime now;
  final Wave4Controller w4;
  final void Function(HermesMobileChat chat)? onOpenChat;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final k = commitment;
    final overdue = k.overdue(now);
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: k.done,
        onChanged: (v) {
          final done = v ?? false;
          W2Haptics.selection();
          w4.setCommitmentDone(k, done);
          // Ticking moves the row to the other tab, so offer Undo.
          showUndoSnackBar(
            context,
            message: done ? 'Marked done' : 'Moved back to open',
            onUndo: () => w4.setCommitmentDone(k, !done),
          );
        },
      ),
      title: Text(
        k.text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          decoration: k.done ? TextDecoration.lineThrough : null,
          color: k.done ? c.textTertiary : null,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            W4Pill(
              label: dueLabel(k.due, now),
              color: overdue ? c.danger : (k.due == null ? null : c.accent),
              icon: Icons.event_outlined,
            ),
            W4Pill(
              label: k.owner == CommitmentOwner.agent ? 'Hermes' : 'You',
              icon: k.owner == CommitmentOwner.agent
                  ? Icons.smart_toy_outlined
                  : Icons.person_outline_rounded,
            ),
            if (k.chatTitle != null)
              W4Pill(
                label: k.chatTitle!,
                icon: Icons.chat_bubble_outline_rounded,
                onTap: k.chatId == null || onOpenChat == null
                    ? null
                    : () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        onOpenChat!(
                          HermesMobileChat(id: k.chatId!, title: k.chatTitle!),
                        );
                      },
              ),
          ],
        ),
      ),
    );
  }
}
