import 'package:flutter/material.dart';

import '../../../cards/card_widgets.dart';
import '../../../data/app_state.dart';
import '../../../theme/hermes_mobile_theme.dart';
import '../w4_controller.dart';
import '../w4_models.dart';
import 'w4_widgets.dart';

IconData recapIcon(String kind) => switch (kind) {
  'cron' => Icons.schedule_rounded,
  'message' || 'email' => Icons.mail_outline_rounded,
  'file' => Icons.description_outlined,
  'purchase' => Icons.shopping_bag_outlined,
  'watcher' => Icons.visibility_outlined,
  'trigger' => Icons.sensors_rounded,
  _ => Icons.bolt_outlined,
};

String clockTime(DateTime t) {
  final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'pm' : 'am'}';
}

/// "While you slept": what the agent did on its own, with Revert.
class RecapCard extends StatelessWidget {
  const RecapCard({super.key, required this.w4, this.maxItems = 4});
  final Wave4Controller w4;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final items = w4.recap;
    final now = DateTime.now();
    final title = now.hour >= 5 && now.hour < 12
        ? 'While you slept'
        : 'Since you last looked';
    final failures = items.where((a) => !a.ok).length;
    return HermesMobileCardFrame(
      title: title,
      icon: Icons.nightlight_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failures > 0) ...[
            W4Pill(label: '$failures failed', color: c.danger),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: 'Mark as seen',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.done_all_rounded,
              size: 18,
              color: c.textSecondary,
            ),
            onPressed: w4.markRecapSeen,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${items.length} thing${items.length == 1 ? '' : 's'} done on '
            'autopilot${items.any((a) => a.revertible && !a.reverted) ? '. Revert any you did not want.' : '.'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          for (final a in items.take(maxItems)) RecapRow(action: a, w4: w4),
          if (items.length > maxItems)
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const RecapScreen())),
              child: Text('See all ${items.length}'),
            ),
        ],
      ),
    );
  }
}

class RecapRow extends StatefulWidget {
  const RecapRow({super.key, required this.action, required this.w4});
  final AutonomousAction action;
  final Wave4Controller w4;

  @override
  State<RecapRow> createState() => _RecapRowState();
}

class _RecapRowState extends State<RecapRow> {
  bool _busy = false;

  Future<void> _revert() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Revert this?'),
        content: Text(widget.action.detail ?? widget.action.summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    bool done;
    try {
      done = await widget.w4.revert(widget.action);
    } catch (_) {
      done = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger?.showSnackBar(
      SnackBar(content: Text(done ? 'Reverted' : 'Could not revert that one')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final a = widget.action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: (a.ok ? c.accentSoft : c.danger.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              recapIcon(a.kind),
              size: 15,
              color: a.ok ? c.accent : c.danger,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.summary,
                  style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: a.reverted ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (a.detail != null)
                  Text(
                    a.detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                Text(
                  clockTime(a.at),
                  style: t.labelSmall?.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          if (a.reverted)
            W4Pill(label: 'Reverted', color: c.textTertiary)
          else if (a.revertible)
            _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(onPressed: _revert, child: const Text('Revert')),
        ],
      ),
    );
  }
}

class RecapScreen extends StatelessWidget {
  const RecapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w4 = HermesMobileScope.of(context).wave4;
    return Scaffold(
      appBar: AppBar(title: const Text('Autopilot log')),
      body: SelectionArea(
        child: ListenableBuilder(
          listenable: w4,
          builder: (context, _) => RefreshIndicator(
            onRefresh: w4.refreshRecap,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                HermesMobileCardFrame(
                  child: Column(
                    children: [
                      for (final a in w4.recap) RecapRow(action: a, w4: w4),
                      if (w4.recap.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Nothing ran on its own since you last looked.',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A server-held outbound action counting down, with Undo.
class HeldOutboundCard extends StatelessWidget {
  const HeldOutboundCard({super.key, required this.held, required this.w4});
  final HeldOutbound held;
  final Wave4Controller w4;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return HermesMobileCardFrame(
      child: Row(
        children: [
          Icon(Icons.outbox_outlined, color: c.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  held.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Text(
                      'Sending in ',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    W4Countdown(
                      deadline: held.releaseAt,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final ok = await w4.undoHeld(held);
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Stopped. Nothing was sent.'
                        : 'Too late, it already went out.',
                  ),
                ),
              );
            },
            child: const Text('Undo'),
          ),
        ],
      ),
    );
  }
}
