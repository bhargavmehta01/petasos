import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cards/card_widgets.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/undo.dart';
import 'w1_controller.dart';
import 'w1_dismissed.dart';
import 'w1_models.dart';
import 'w1_settings.dart';
import '../wave2_parity/w2_settings.dart';

/// Opens the Brief tab; resolves to a chat the user chose to open.
Future<HermesMobileChat?> openBrief(BuildContext context, {int tab = 0}) =>
    Navigator.of(context).push<HermesMobileChat>(
      MaterialPageRoute(builder: (_) => BriefScreen(initialTab: tab)),
    );

/// Brief tab: morning/evening digests, then the proactive card feed.
class BriefScreen extends StatefulWidget {
  const BriefScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends State<BriefScreen> {
  ProactiveController? _ctl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctl = ProactiveController.of(HermesMobileScope.read(context));
    if (!identical(ctl, _ctl)) {
      _ctl = ctl;
      if (!ctl.loaded && !ctl.loading) ctl.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _ctl!;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final feedCount = ctl.cards.where((c) => !c.read).length;
        return DefaultTabController(
          length: 2,
          initialIndex: widget.initialTab,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Brief'),
              actions: [
                IconButton(
                  key: const ValueKey('w1-dismissed-button'),
                  tooltip: 'Dismissed cards',
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DismissedCardsScreen(controller: ctl),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Notification settings',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          Wave1NotificationSettings(controller: ctl),
                    ),
                  ),
                ),
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(text: 'Today'),
                  Tab(
                    child: Badge(
                      isLabelVisible: feedCount > 0,
                      label: Text('$feedCount'),
                      offset: const Offset(14, -4),
                      child: const Text('For you'),
                    ),
                  ),
                ],
              ),
            ),
            // Long-press any card text to select and copy it.
            body: SelectionArea(
              child: TabBarView(
                children: [
                  _BriefTab(ctl: ctl),
                  _FeedTab(ctl: ctl),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SetupHelp extends StatelessWidget {
  const _SetupHelp();
  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.extension_outlined,
      title: 'Briefs need the Petasos server plugin',
      body:
          'Install server/hermes_mobile_plugin on your Hermes host (copy it to '
          '~/.hermes/plugins/hermes_mobile and restart the dashboard), and set the '
          'dashboard URL under Profile → Connection. Approvals still show '
          'up here without it.',
    );
  }
}

class _BriefTab extends StatelessWidget {
  const _BriefTab({required this.ctl});
  final ProactiveController ctl;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final briefs = ctl.briefs;
    final morning = briefs.where((b) => b.period != 'evening').toList();
    final evening = briefs.where((b) => b.period == 'evening').toList();
    return RefreshIndicator(
      onRefresh: ctl.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            _greeting(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ctl.needsYou == 0
                ? 'Nothing needs you right now.'
                : '${ctl.needsYou} thing${ctl.needsYou == 1 ? '' : 's'} need${ctl.needsYou == 1 ? 's' : ''} you.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: c.textSecondary),
          ),
          if (ctl.pluginMissing) ...[
            const SizedBox(height: 10),
            const _Note(
              text:
                  'Briefs from your scheduled tasks. Install the Petasos server '
                  'plugin for feedback to memory, agent cards and file uploads.',
              info: true,
            ),
          ],
          if (ctl.lastFeedback != null) ...[
            const SizedBox(height: 10),
            _Note(text: 'Saved to memory: ${ctl.lastFeedback}'),
          ],
          if (ctl.loading && !ctl.loaded)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: SkeletonCard(height: 160),
            )
          else if (!ctl.available)
            const _SetupHelp()
          else if (briefs.isEmpty)
            const EmptyState(
              icon: Icons.wb_twilight_rounded,
              title: 'No brief yet today',
              body:
                  'Any scheduled task named "brief", "digest" or "recap" '
                  'shows up here after it runs.',
            ),
          if (morning.isNotEmpty) const SectionHeader('Morning'),
          for (final b in morning) _BriefCard(ctl: ctl, card: b),
          if (evening.isNotEmpty) const SectionHeader('Evening'),
          for (final b in evening) _BriefCard(ctl: ctl, card: b),
          if (ctl.error != null) ...[
            const SizedBox(height: 12),
            _Note(text: ctl.error!, danger: true),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: ctl.loading ? null : ctl.refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Swipe-dismiss with a 6 s Undo. The server only hears about it once the
/// snackbar closes without Undo.
void dismissWithUndo(
  BuildContext context,
  ProactiveController ctl,
  ProactiveCard card,
) {
  W2Haptics.medium();
  if (!ctl.stageDismiss(card)) return;
  showUndoSnackBar(
    context,
    message: 'Card dismissed',
    onUndo: () => ctl.undoDismiss(card.id),
    onCommit: () => ctl.commitDismiss(card.id),
  );
}

void _copyCard(BuildContext context, ProactiveCard card) {
  final text = [card.title, if (card.body.isNotEmpty) card.body].join('\n\n');
  Clipboard.setData(ClipboardData(text: text));
  W2Haptics.selection();
  showHermesMobileSnack(context, 'Copied');
}

/// Overflow menu on a card: Copy, Dismiss (a non-swipe way to dismiss).
class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.ctl, required this.card});
  final ProactiveController ctl;
  final ProactiveCard card;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Card options',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'copy':
            _copyCard(context, card);
          case 'dismiss':
            dismissWithUndo(context, ctl, card);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.copy_rounded),
            title: Text('Copy'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (!card.local)
          const PopupMenuItem(
            value: 'dismiss',
            child: ListTile(
              leading: Icon(Icons.done_all_rounded),
              title: Text('Dismiss'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.danger = false, this.info = false});
  final String text;
  final bool danger;
  final bool info;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final color = danger
        ? c.danger
        : info
        ? c.textSecondary
        : c.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

/// Swipe to dismiss; more/less feedback; one action.
class _BriefCard extends StatelessWidget {
  const _BriefCard({required this.ctl, required this.card});
  final ProactiveController ctl;
  final ProactiveCard card;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('brief-${card.id}'),
        direction: DismissDirection.horizontal,
        background: _swipeBg(context, Alignment.centerLeft),
        secondaryBackground: _swipeBg(context, Alignment.centerRight),
        onDismissed: (_) => dismissWithUndo(context, ctl, card),
        child: HermesMobileCardFrame(
          icon: card.period == 'evening'
              ? Icons.nights_stay_outlined
              : Icons.wb_sunny_outlined,
          title: card.title,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _ago(card.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              _CardMenu(ctl: ctl, card: card),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HermesMobileMarkdown(card.body),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'More like this?',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: c.textTertiary),
                  ),
                  IconButton(
                    tooltip: 'More like this',
                    icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                    onPressed: () {
                      W2Haptics.selection();
                      ctl.feedback(card, true);
                    },
                  ),
                  IconButton(
                    tooltip: 'Less like this',
                    icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                    onPressed: () {
                      W2Haptics.selection();
                      ctl.feedback(card, false);
                    },
                  ),
                  const Spacer(),
                  if (card.action != null)
                    _ActionButton(ctl: ctl, card: card, compact: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _swipeBg(BuildContext context, Alignment a) {
  final c = context.hermesMobile;
  return Container(
    alignment: a,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: c.surfaceMuted,
      borderRadius: BorderRadius.circular(HermesMobileRadius.card),
    ),
    child: Icon(Icons.done_all_rounded, color: c.textSecondary),
  );
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

class _FeedTab extends StatelessWidget {
  const _FeedTab({required this.ctl});
  final ProactiveController ctl;

  @override
  Widget build(BuildContext context) {
    final cards = ctl.cards;
    return RefreshIndicator(
      onRefresh: ctl.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (!ctl.available && cards.isEmpty) const _SetupHelp(),
          if (ctl.error != null && cards.isEmpty)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load the feed',
              body: ctl.error!,
              action: FilledButton.tonalIcon(
                onPressed: ctl.loading ? null : ctl.refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ),
          if (ctl.available && cards.isEmpty && ctl.loaded && ctl.error == null)
            const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'All caught up',
              body: 'Approvals, alerts and suggestions from Hermes land here.',
            ),
          for (final card in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ProactiveCardView(ctl: ctl, card: card),
            ),
        ],
      ),
    );
  }
}

/// One feed card with exactly one action. Swipe to dismiss (with Undo);
/// tap to mark read and show the whole text; long-press text to select.
class ProactiveCardView extends StatefulWidget {
  const ProactiveCardView({super.key, required this.ctl, required this.card});
  final ProactiveController ctl;
  final ProactiveCard card;

  @override
  State<ProactiveCardView> createState() => _ProactiveCardViewState();
}

class _ProactiveCardViewState extends State<ProactiveCardView> {
  bool _expanded = false;

  ProactiveController get ctl => widget.ctl;
  ProactiveCard get card => widget.card;

  IconData get _icon => switch (card.kind) {
    'approval' => Icons.shield_outlined,
    'alert' => Icons.error_outline_rounded,
    'reminder' => Icons.alarm_rounded,
    'watch' => Icons.visibility_outlined,
    _ => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final tint = card.kind == 'approval'
        ? c.warning
        : card.kind == 'alert'
        ? c.danger
        : c.accent;
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(_icon, size: 20, color: tint),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!card.read)
                    Container(
                      key: const ValueKey('unread-dot'),
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      card.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    card.source,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  _CardMenu(ctl: ctl, card: card),
                ],
              ),
              if (card.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  card.body,
                  maxLines: _expanded ? null : 3,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (card.action != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: _ActionButton(ctl: ctl, card: card),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final frame = HermesMobileCardFrame(
      onTap: () {
        ctl.markRead(card);
        setState(() => _expanded = !_expanded);
      },
      child: body,
    );
    if (card.local) return frame;
    return Dismissible(
      key: ValueKey('card-${card.id}'),
      background: _swipeBg(context, Alignment.centerLeft),
      secondaryBackground: _swipeBg(context, Alignment.centerRight),
      onDismissed: (_) => dismissWithUndo(context, ctl, card),
      child: frame,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.ctl,
    required this.card,
    this.compact = false,
  });
  final ProactiveController ctl;
  final ProactiveCard card;
  final bool compact;

  Future<void> _run(BuildContext context) async {
    W2Haptics.light();
    String? reply;
    if (card.action!.kind == ProactiveActionKind.reply) {
      reply = await showReplySheet(context, card.title);
      if (reply == null || reply.trim().isEmpty) return;
    }
    final chat = await ctl.act(card, reply: reply);
    if (chat != null && context.mounted) Navigator.of(context).pop(chat);
  }

  @override
  Widget build(BuildContext context) {
    final a = card.action!;
    final icon = switch (a.kind) {
      ProactiveActionKind.approve => Icons.check_rounded,
      ProactiveActionKind.snooze => Icons.snooze_rounded,
      ProactiveActionKind.reply => Icons.reply_rounded,
      ProactiveActionKind.run => Icons.play_arrow_rounded,
      ProactiveActionKind.open => Icons.open_in_new_rounded,
    };
    if (compact) {
      return TextButton.icon(
        onPressed: () => _run(context),
        icon: Icon(icon, size: 18),
        label: Text(a.label),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: () => _run(context),
      icon: Icon(icon, size: 18),
      label: Text(a.label),
    );
  }
}

/// Bottom sheet with one text field; resolves to the reply text.
Future<String?> showReplySheet(BuildContext context, String about) {
  final ctl = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(c).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            about,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(c).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Reply to Hermes'),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctl.text),
            child: const Text('Send'),
          ),
        ],
      ),
    ),
  );
}

/// Cards dismissed in the last 14 days, with Restore. Kept on the phone.
class DismissedCardsScreen extends StatelessWidget {
  const DismissedCardsScreen({super.key, required this.controller});
  final ProactiveController controller;

  Future<void> _restore(BuildContext context, DismissedEntry e) async {
    W2Haptics.selection();
    final synced = await controller.restore(e);
    if (!context.mounted) return;
    showHermesMobileSnack(
      context,
      synced
          ? 'Restored to your Brief'
          : 'Restored on this phone. Update the Petasos plugin to sync it.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dismissed')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final list = controller.dismissed;
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (list.isEmpty)
                    const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'Nothing dismissed',
                      body:
                          'Cards you swipe away stay here for 14 days, '
                          'so you can bring them back.',
                    ),
                  for (final e in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DismissedTile(
                        entry: e,
                        onRestore: () => _restore(context, e),
                        onForget: () => controller.forgetDismissed(e.card.id),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DismissedTile extends StatelessWidget {
  const _DismissedTile({
    required this.entry,
    required this.onRestore,
    required this.onForget,
  });
  final DismissedEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final card = entry.card;
    return HermesMobileCardFrame(
      icon: card.isBrief
          ? Icons.wb_sunny_outlined
          : Icons.auto_awesome_outlined,
      title: card.title,
      trailing: Text(
        '${card.source} · ${_ago(entry.dismissedAt)} ago',
        style: Theme.of(context).textTheme.labelSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.body.isNotEmpty)
            Text(
              card.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                onPressed: onForget,
                child: const Text('Remove from list'),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Restore'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
