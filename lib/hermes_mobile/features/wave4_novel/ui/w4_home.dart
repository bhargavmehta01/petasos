import 'package:flutter/material.dart';

import '../../../cards/card_widgets.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../theme/hermes_mobile_theme.dart';
import '../../../widgets/common.dart';
import '../w4_controller.dart';
import '../w4_models.dart';
import 'w4_commitments.dart';
import 'w4_recap.dart';
import 'w4_watchers.dart';

/// Wave 4 on Home: held outbound actions, the overnight recap, the offline
/// queue, a watcher suggestion, watchers that changed and promises due.
/// How much shows follows the proactivity dial.
class Wave4HomeSection extends StatelessWidget {
  const Wave4HomeSection({
    super.key,
    required this.onOpenChat,
    this.urgentOnly = false,
  });
  final void Function(HermesMobileChat chat) onOpenChat;

  /// True for the slot above Panels: only held outbound actions and the
  /// offline queue. False for the slot below: everything else.
  final bool urgentOnly;

  @override
  Widget build(BuildContext context) {
    final w4 = HermesMobileScope.of(context).wave4;
    return ListenableBuilder(
      listenable: w4,
      builder: (context, _) {
        final now = DateTime.now();
        final quiet = w4.level == ProactivityLevel.quiet;
        final c = context.hermesMobile;
        final children = <Widget>[];

        void gap() => children.add(const SizedBox(height: 8));

        if (urgentOnly) {
          for (final h in w4.held) {
            children.add(HeldOutboundCard(held: h, w4: w4));
            gap();
          }
          if (w4.queue.isNotEmpty) {
            children.add(QueueCard(w4: w4));
            gap();
          }
          if (children.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [const SectionHeader('Going out'), ...children],
          );
        }

        if (w4.showRecap(now)) {
          children.add(RecapCard(w4: w4, maxItems: quiet ? 2 : 4));
          gap();
        }

        if (!quiet && w4.proposal != null) {
          children.add(WatcherProposalCard(w4: w4));
          gap();
        }

        final watchers = quiet
            ? w4.watchers
                  .where(
                    (w) =>
                        w.status == WatcherStatus.changed ||
                        w.status == WatcherStatus.error,
                  )
                  .toList()
            : w4.watchers.where((w) => !w.paused).toList();
        final due = w4.commitments
            .where(
              (k) =>
                  !k.done &&
                  (quiet
                      ? k.overdue(now)
                      : (k.due == null ||
                            k.due!.isBefore(now.add(const Duration(days: 2))))),
            )
            .toList();

        if (children.isEmpty && watchers.isEmpty && due.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (children.isNotEmpty) ...[
              const SectionHeader('Autopilot'),
              ...children,
            ],
            if (watchers.isNotEmpty) ...[
              SectionHeader(
                'Watching',
                trailing: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WatchersScreen()),
                  ),
                  child: Text(
                    w4.watchersNeedingYou > 0
                        ? '${w4.watchersNeedingYou} need you · All'
                        : 'All',
                  ),
                ),
              ),
              SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: watchers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => SizedBox(
                    width: 250,
                    child: WatcherCard(watcher: watchers[i], compact: true),
                  ),
                ),
              ),
            ],
            if (due.isNotEmpty) ...[
              SectionHeader(
                'Promised',
                trailing: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CommitmentsScreen(onOpenChat: onOpenChat),
                    ),
                  ),
                  child: const Text('All'),
                ),
              ),
              HermesMobileCardFrame(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final k in due.take(3))
                      CommitmentTile(
                        commitment: k,
                        now: now,
                        w4: w4,
                        onOpenChat: onOpenChat,
                      ),
                    if (due.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '+${due.length - 3} more',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Messages waiting for Hermes to come back.
class QueueCard extends StatelessWidget {
  const QueueCard({super.key, required this.w4});
  final Wave4Controller w4;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final n = w4.queue.length;
    return HermesMobileCardFrame(
      child: Row(
        children: [
          Icon(Icons.cloud_queue_rounded, color: c.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n message${n == 1 ? '' : 's'} waiting to send',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  w4.flushing
                      ? 'Sending now…'
                      : 'Hermes is unreachable. They go out on their own when it is back.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: w4.flushing ? null : w4.checkOnline,
            child: const Text('Try now'),
          ),
        ],
      ),
    );
  }
}
