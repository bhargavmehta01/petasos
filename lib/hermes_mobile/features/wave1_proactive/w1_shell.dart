import 'package:flutter/material.dart';

import '../../cards/card_widgets.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import 'w1_brief_screen.dart';
import 'w1_controller.dart';

export 'w1_binder.dart' show Wave1Binder;

/// App-bar button for the Brief tab with an unread badge.
class Wave1BriefButton extends StatelessWidget {
  const Wave1BriefButton({super.key, required this.onOpenChat});
  final void Function(HermesMobileChat chat) onOpenChat;

  @override
  Widget build(BuildContext context) {
    final feed = ProactiveController.of(HermesMobileScope.of(context));
    final c = context.hermesMobile;
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final n = feed.unread;
        return IconButton(
          key: const ValueKey('w1-brief-button'),
          tooltip: n == 0 ? 'Brief' : 'Brief, $n new',
          onPressed: () async {
            final chat = await openBrief(
              context,
              tab: feed.state.pendingApprovals.isEmpty ? 0 : 1,
            );
            if (chat != null) onOpenChat(chat);
          },
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 9 ? '9+' : '$n'),
            backgroundColor: c.accent,
            textColor: c.onAccent,
            child: const Icon(Icons.wb_twilight_rounded),
          ),
        );
      },
    );
  }
}

/// Compact brief row at the top of Home.
class Wave1HomeBriefCard extends StatelessWidget {
  const Wave1HomeBriefCard({super.key, required this.onOpenChat});
  final void Function(HermesMobileChat chat) onOpenChat;

  @override
  Widget build(BuildContext context) {
    final feed = ProactiveController.of(HermesMobileScope.of(context));
    final c = context.hermesMobile;
    return ListenableBuilder(
      listenable: feed,
      builder: (context, _) {
        final briefs = feed.briefs;
        final unreadCards = feed.cards.where((x) => !x.read && !x.local).length;
        if (briefs.isEmpty && unreadCards == 0) return const SizedBox.shrink();
        final latest = briefs.isEmpty
            ? null
            : (briefs.toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
                  .first;
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: HermesMobileCardFrame(
            onTap: () async {
              final chat = await openBrief(context);
              if (chat != null) onOpenChat(chat);
            },
            child: Row(
              children: [
                Icon(Icons.wb_twilight_rounded, color: c.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latest?.title ?? 'Your brief',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        unreadCards == 0
                            ? 'Read today\'s brief'
                            : '$unreadCards new card${unreadCards == 1 ? '' : 's'} for you',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
          ),
        );
      },
    );
  }
}
