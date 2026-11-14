import 'package:flutter/material.dart';

import '../cards/card_widgets.dart';
import '../data/models.dart';
import '../theme/hermes_mobile_theme.dart';

String relativeTime(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 60) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${t.month}/${t.day}';
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.label, this.demo = false});
  final String label;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final letter = label.trim().isEmpty ? 'H' : label.trim()[0].toUpperCase();
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: c.accentSoft,
        shape: BoxShape.circle,
        border: Border.all(color: c.hairline),
      ),
      alignment: Alignment.center,
      child: demo
          ? Icon(Icons.science_outlined, size: 16, color: c.accent)
          : Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: c.accent,
                fontSize: 13,
              ),
            ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: c.accent),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            hermesMobileExplainError(body),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6});
  final int count;
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const SkeletonCard(height: 56),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: c.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.running = false,
    this.needsYou = false,
  });
  final HermesMobileChat chat;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool running;
  final bool needsYou;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (chat.preview.trim().isNotEmpty)
                        Text(
                          chat.preview
                              .replaceAll(RegExp(r'```[\s\S]*?```'), '')
                              .replaceAll(RegExp(r'[#*_`|>]'), '')
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (needsYou)
                  Icon(Icons.shield_outlined, size: 16, color: c.warning)
                else if (running)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: c.accent,
                    ),
                  )
                else
                  Text(
                    relativeTime(chat.updatedAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Turns known engine errors into a next step the user can act on.
String hermesMobileExplainError(String text) {
  if (text.contains('Session token not found')) {
    return 'Your Hermes dashboard has a sign-in. Open Profile, then '
        'Connection, and add the dashboard username and password.';
  }
  if (text.contains('Dashboard not reachable')) {
    return '$text\nCheck the dashboard URL (usually port 9119) and that '
        'the dashboard service is running on your Hermes host.';
  }
  return text;
}
