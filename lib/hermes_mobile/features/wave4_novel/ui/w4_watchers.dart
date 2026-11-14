import 'package:flutter/material.dart';

import '../../../cards/card_widgets.dart';
import '../../../data/app_state.dart';
import '../../../theme/hermes_mobile_theme.dart';
import '../../../widgets/common.dart';
import '../../../widgets/undo.dart';
import '../w4_controller.dart';
import '../w4_models.dart';
import 'w4_widgets.dart';
import '../../wave2_parity/w2_settings.dart';

/// All watchers as status cards, with a button to add one.
class WatchersScreen extends StatelessWidget {
  const WatchersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w4 = HermesMobileScope.of(context).wave4;
    return Scaffold(
      appBar: AppBar(title: const Text('Watchers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewWatcherSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Watch something'),
      ),
      body: SelectionArea(
        child: ListenableBuilder(
          listenable: w4,
          builder: (context, _) {
            if (w4.watchersLoading && w4.watchers.isEmpty) {
              return const SkeletonList(count: 4);
            }
            return RefreshIndicator(
              onRefresh: w4.refreshWatchers,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (w4.proposal != null) ...[
                    WatcherProposalCard(w4: w4),
                    const SizedBox(height: 10),
                  ],
                  if (!w4.pluginAvailable &&
                      w4.pluginChecked &&
                      !HermesMobileScope.of(context).backend.isDemo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Watchers run as Hermes scheduled tasks named "Watch: …". '
                        'Install the Petasos server plugin for change history and '
                        'alerts on the card.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (w4.watchersError != null && w4.watchers.isEmpty)
                    EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load watchers',
                      body: w4.watchersError!,
                      action: TextButton(
                        onPressed: w4.refreshWatchers,
                        child: const Text('Retry'),
                      ),
                    )
                  else if (w4.watchers.isEmpty)
                    const EmptyState(
                      icon: Icons.visibility_outlined,
                      title: 'Nothing watched yet',
                      body:
                          'Ask Hermes to keep an eye on a price, a page or a '
                          'status, and it checks on a schedule and tells you '
                          'only when it changes.',
                    )
                  else
                    for (final w in w4.watchers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: WatcherCard(watcher: w),
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

/// One watcher: title, status pill, last value, what changed, actions.
class WatcherCard extends StatelessWidget {
  const WatcherCard({super.key, required this.watcher, this.compact = false});
  final HermesMobileWatcher watcher;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final w = watcher;
    final color = watcherColor(context, w.status);
    final w4 = HermesMobileScope.of(context).wave4;
    return HermesMobileCardFrame(
      onTap: compact ? () => _openDetails(context, w) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  w.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              W4Pill(label: watcherLabel(w.status), color: color),
            ],
          ),
          if (w.lastValue != null) ...[
            const SizedBox(height: 8),
            Text(
              w.lastValue!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (compact ? t.titleMedium : t.titleLarge)?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ],
          if (w.lastChange != null) ...[
            const SizedBox(height: 2),
            Text(
              w.lastChange!,
              maxLines: compact ? 1 : 3,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: c.text),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            [
              w.every,
              if (w.condition != null) 'alert ${w.condition}',
              if (w.lastChecked != null)
                'checked ${relativeTime(w.lastChecked)} ago',
            ].join(' · '),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: t.labelSmall?.copyWith(color: c.textTertiary),
          ),
          if (!compact) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: w.paused
                      ? null
                      : () =>
                            _run(context, () => w4.checkNow(w), 'Checking now'),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Check now'),
                ),
                TextButton.icon(
                  onPressed: () => _run(
                    context,
                    () => w4.togglePaused(w),
                    w.paused ? 'Resumed' : 'Paused',
                  ),
                  icon: Icon(
                    w.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 16,
                  ),
                  label: Text(w.paused ? 'Resume' : 'Pause'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Stop watching',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: c.textTertiary,
                  ),
                  // Undo instead of a confirm dialog: the host delete waits
                  // until the snackbar closes.
                  onPressed: () {
                    W2Haptics.medium();
                    final i = w4.stageDeleteWatcher(w);
                    showUndoSnackBar(
                      context,
                      message: 'Stopped watching',
                      onUndo: () => w4.undoDeleteWatcher(w, i),
                      onCommit: () => w4.commitDeleteWatcher(w),
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, HermesMobileWatcher w) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WatchersScreen()));
  }

  static Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      messenger?.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not do that: $e')));
    }
  }
}

/// "You asked about X three times. Watch it?"
class WatcherProposalCard extends StatelessWidget {
  const WatcherProposalCard({super.key, required this.w4});
  final Wave4Controller w4;

  @override
  Widget build(BuildContext context) {
    final p = w4.proposal;
    if (p == null) return const SizedBox.shrink();
    final c = context.hermesMobile;
    return HermesMobileCardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 16, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Watch "${p.topic}"?',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You have asked about this ${p.count} times. I can check it on a '
            'schedule and tell you only when it changes.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () => showNewWatcherSheet(
                  context,
                  title: p.topic,
                  target: p.topic,
                ),
                child: const Text('Set up watcher'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: w4.dismissProposal,
                child: const Text('Not now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to create a watcher.
Future<void> showNewWatcherSheet(
  BuildContext context, {
  String? title,
  String? target,
}) async {
  final w4 = HermesMobileScope.read(context).wave4;
  final titleCtl = TextEditingController(text: title ?? '');
  final targetCtl = TextEditingController(text: target ?? '');
  final condCtl = TextEditingController();
  var every = 'Every 6 hours';
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(sheet).bottom,
      ),
      child: StatefulBuilder(
        builder: (sheet, setSheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Watch something',
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: targetCtl,
              decoration: const InputDecoration(
                labelText: 'What to look at',
                hintText: 'A link, an item, or a description',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: condCtl,
              decoration: const InputDecoration(
                labelText: 'Alert me when (optional)',
                hintText: 'below \$300, back in stock, status changes',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final e in const [
                  'Every hour',
                  'Every 6 hours',
                  'Every day',
                ])
                  ChoiceChip(
                    label: Text(e),
                    selected: every == e,
                    onSelected: (_) => setSheet(() => every = e),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (titleCtl.text.trim().isEmpty ||
                    targetCtl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(sheet, true);
              },
              child: const Text('Start watching'),
            ),
          ],
        ),
      ),
    ),
  );
  if (created != true) return;
  try {
    await w4.createWatcher(
      title: titleCtl.text.trim(),
      target: targetCtl.text.trim(),
      every: every,
      condition: condCtl.text.trim().isEmpty ? null : condCtl.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Watching "${titleCtl.text.trim()}"')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not create the watcher: $e')),
      );
    }
  }
}
