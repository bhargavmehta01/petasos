import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/hermes_mobile_theme.dart';
import '../w4_controller.dart';
import '../w4_models.dart';

/// Small rounded label used for statuses and chips.
class W4Pill extends StatelessWidget {
  const W4Pill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.onTap,
  });
  final String label;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final tint = color ?? c.textSecondary;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(HermesMobileRadius.chip),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(HermesMobileRadius.chip),
      onTap: onTap,
      child: pill,
    );
  }
}

Color watcherColor(BuildContext context, WatcherStatus s) {
  final c = context.hermesMobile;
  return switch (s) {
    WatcherStatus.changed => c.accent,
    WatcherStatus.error => c.danger,
    WatcherStatus.paused => c.textTertiary,
    WatcherStatus.pending => c.warning,
    WatcherStatus.ok => c.success,
  };
}

String watcherLabel(WatcherStatus s) => switch (s) {
  WatcherStatus.changed => 'Changed',
  WatcherStatus.error => 'Needs a look',
  WatcherStatus.paused => 'Paused',
  WatcherStatus.pending => 'First check soon',
  WatcherStatus.ok => 'No change',
};

/// Seconds left until [deadline], repainting every second.
class W4Countdown extends StatefulWidget {
  const W4Countdown({super.key, required this.deadline, this.style});
  final DateTime deadline;
  final TextStyle? style;

  @override
  State<W4Countdown> createState() => _W4CountdownState();
}

class _W4CountdownState extends State<W4Countdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.deadline.difference(DateTime.now());
    final s = left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
    return Text('${s}s', style: widget.style);
  }
}

/// Shows the undo bar for a local [UndoTicket]: label, countdown, Undo.
void showUndoBar(BuildContext context, Wave4Controller w4, UndoTicket ticket) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: ticket.remaining(DateTime.now()),
      behavior: SnackBarBehavior.floating,
      content: Row(
        children: [
          Expanded(
            child: Text(
              ticket.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          W4Countdown(deadline: ticket.deadline),
        ],
      ),
      action: SnackBarAction(label: 'Undo', onPressed: () => w4.undo(ticket)),
    ),
  );
}
