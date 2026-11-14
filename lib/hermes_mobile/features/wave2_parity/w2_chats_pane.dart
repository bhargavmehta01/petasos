import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'w2_settings.dart';

/// Width at which Petasos shows chats and the conversation side by side.
const double kW2TwoPaneWidth = 840;

bool w2UseTwoPane(BuildContext context) =>
    W2Settings.current.twoPane &&
    MediaQuery.sizeOf(context).width >= kW2TwoPaneWidth;

/// Chats split into pinned (device order) and the rest (server order).
({List<HermesMobileChat> pinned, List<HermesMobileChat> others}) w2SplitPinned(
  List<HermesMobileChat> chats,
  String connection,
) {
  final s = W2Settings.current;
  final order = s.pinnedChats(connection);
  final byId = {for (final c in chats) c.id: c};
  final pinned = [
    for (final id in order)
      if (byId[id] != null) byId[id]!,
  ];
  final pinnedIds = pinned.map((c) => c.id).toSet();
  return (
    pinned: pinned,
    others: [
      for (final c in chats)
        if (!pinnedIds.contains(c.id)) c,
    ],
  );
}

/// Chat tile with pin and star marks.
class W2ChatTile extends StatelessWidget {
  const W2ChatTile({
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
    final state = HermesMobileScope.of(context);
    final conn = state.backend.connection.endpoint;
    final s = W2Settings.current;
    final starred = s.isStarred(conn, chat.id);
    final tile = ChatTile(
      chat: chat,
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      running: running,
      needsYou: needsYou,
    );
    if (!starred) return tile;
    return Stack(
      children: [
        tile,
        Positioned(
          left: 4,
          top: 6,
          child: Icon(Icons.star_rounded, size: 12, color: context.hermesMobile.warning),
        ),
      ],
    );
  }
}

/// The chats list used in the drawer and the left pane: pinned first.
class W2ChatsList extends StatelessWidget {
  const W2ChatsList({
    super.key,
    required this.onOpen,
    this.onLongPress,
    this.starredOnly = false,
  });
  final void Function(HermesMobileChat) onOpen;
  final void Function(HermesMobileChat)? onLongPress;
  final bool starredOnly;

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    return ListenableBuilder(
      listenable: W2Settings.current,
      builder: (context, _) {
        final conn = state.backend.connection.endpoint;
        var chats = state.chats;
        if (starredOnly) {
          chats = chats.where((c) => W2Settings.current.isStarred(conn, c.id)).toList();
        }
        final split = w2SplitPinned(chats, conn);
        Widget tile(HermesMobileChat chat) => W2ChatTile(
          chat: chat,
          selected: state.current?.chatId == chat.id,
          running: state.runningChats.contains(chat.id) || chat.isActive,
          needsYou: state.pendingApprovals.containsKey(chat.id),
          onTap: () => onOpen(chat),
          onLongPress: onLongPress == null ? null : () => onLongPress!(chat),
        );
        if (chats.isEmpty) {
          return ListView(
            children: [
              EmptyState(
                icon: starredOnly ? Icons.star_outline_rounded : Icons.chat_bubble_outline_rounded,
                title: starredOnly ? 'No starred chats' : 'No chats yet',
                body: starredOnly
                    ? 'Long-press a chat and choose Star.'
                    : (state.chatsError ?? 'Start one with New chat.'),
              ),
            ],
          );
        }
        return ListView(
          key: const ValueKey('w2-chats-list'),
          children: [
            if (split.pinned.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SectionHeader('Pinned'),
              ),
              for (final c in split.pinned) tile(c),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SectionHeader('Recent'),
              ),
            ],
            for (final c in split.others) tile(c),
          ],
        );
      },
    );
  }
}

/// Left pane for tablets and unfolded foldables.
class W2ChatsPane extends StatefulWidget {
  const W2ChatsPane({super.key, required this.onOpen, required this.onNew, this.onLongPress});
  final void Function(HermesMobileChat) onOpen;
  final VoidCallback onNew;
  final void Function(HermesMobileChat)? onLongPress;

  @override
  State<W2ChatsPane> createState() => _W2ChatsPaneState();
}

class _W2ChatsPaneState extends State<W2ChatsPane> {
  bool _starred = false;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Material(
      key: const ValueKey('w2-chats-pane'),
      color: c.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: FilledButton.icon(
              onPressed: widget.onNew,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('New chat'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('All')),
                ButtonSegment(value: true, label: Text('Starred')),
              ],
              selected: {_starred},
              onSelectionChanged: (s) => setState(() => _starred = s.first),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: W2ChatsList(
              onOpen: widget.onOpen,
              onLongPress: widget.onLongPress,
              starredOnly: _starred,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pin/Star rows for the chat long-press sheet. Returns true when handled.
Future<bool> w2HandleChatAction(BuildContext context, String action, HermesMobileChat chat) async {
  final state = HermesMobileScope.read(context);
  final conn = state.backend.connection.endpoint;
  final s = W2Settings.current;
  switch (action) {
    case 'w2pin':
      await s.togglePinned(conn, chat.id);
    case 'w2star':
      await s.toggleStarred(conn, chat.id);
    default:
      return false;
  }
  W2Haptics.selection();
  return true;
}

List<Widget> w2ChatActionRows(BuildContext sheetContext, HermesMobileChat chat, String connection) {
  final s = W2Settings.current;
  final pinned = s.isPinned(connection, chat.id);
  final starred = s.isStarred(connection, chat.id);
  return [
    ListTile(
      leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      title: Text(pinned ? 'Unpin' : 'Pin to top'),
      onTap: () => Navigator.pop(sheetContext, 'w2pin'),
    ),
    ListTile(
      leading: Icon(starred ? Icons.star_rounded : Icons.star_outline_rounded),
      title: Text(starred ? 'Unstar' : 'Star'),
      onTap: () => Navigator.pop(sheetContext, 'w2star'),
    ),
  ];
}
