import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/session.dart';
import '../../core/screens/chat_screen.dart';
import '../../core/theme/hermes_theme.dart';
import '../../core/services/mobile_push_service.dart';
import '../hermes_mobile_app.dart';
import '../data/app_state.dart';
import '../data/live_backend.dart';
import '../data/models.dart';
import '../features/wave1_proactive/w1_shell.dart'; // wave1
import '../features/wave4_novel/ui/w4_chat.dart'; // --- wave4 ---
import '../theme/hermes_mobile_theme.dart';
import '../widgets/common.dart';
import 'archived_chats.dart';
import 'chat_view.dart';
import 'cron_push_result_screen.dart';
import 'home_screen.dart';
// import 'search_screen.dart'; // --- wave2 --- replaced by W2SearchScreen
import 'settings_screen.dart';
// --- wave2 ---
import '../features/wave2_parity/w2_chats_pane.dart';
import '../features/wave2_parity/w2_projects.dart';
import '../features/wave2_parity/w2_search.dart';
// --- end wave2 ---

/// Petasos navigation: house (Home) top-left, conversation title in the middle,
/// search and profile top-right. Chat is the main surface; a drawer lists
/// Chats and Projects.
class HermesMobileShell extends StatefulWidget {
  const HermesMobileShell({super.key, this.startOnHome = false});
  final bool startOnHome;

  @override
  State<HermesMobileShell> createState() => _HermesMobileShellState();
}

class _HermesMobileShellState extends State<HermesMobileShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  late bool _home = widget.startOnHome;
  bool _handlingPush = false;

  void _pushChanged() {
    if (mounted && MobilePushService.shared.hasPendingTap && !_handlingPush) {
      unawaited(_consumePushTap());
    }
  }

  Future<void> _consumePushTap() async {
    if (_handlingPush || !mounted) return;
    _handlingPush = true;
    try {
      final push = MobilePushService.shared;
      final route = await push.takePendingNotificationRoute();
      if (route == null || !mounted) return;
      if (!await push.isRouteCurrent(route)) return;
      if (!mounted) return;
      if (route.sessionId == '__hermes_mobile_cron__') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HermesMobileCronPushResultScreen(route: route),
          ),
        );
        return;
      }
      // A normal chat tap is also resolved from an authenticated event, never
      // from an arbitrary intent URL. Keep Petasos's live chat surface intact.
      final root = HermesMobileRoot.of(context);
      if (root.activeConnection?.id != route.connection.id) {
        await root.useConnection(route.connection.id);
      }
      if (!mounted) return;
      if (!await push.isRouteCurrent(route)) return;
      if (!mounted) return;
      final state = HermesMobileScope.read(context);
      final chats = await state.backend.listChats();
      if (!mounted) return;
      if (!await push.isRouteCurrent(route)) return;
      if (!mounted) return;
      final chat = chats.where((item) => item.id == route.sessionId).firstOrNull;
      if (chat != null) _openChat(chat);
    } catch (_) {
      // An expired/revoked tap fails closed. The saved cron/chat remains in Hermes.
    } finally {
      _handlingPush = false;
    }
  }

  @override
  void dispose() {
    MobilePushService.shared.removeListener(_pushChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    MobilePushService.shared.addListener(_pushChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushChanged();
      final state = HermesMobileScope.read(context);
      if (state.current == null) state.newChat();
      state.refreshChats();
      state.refreshPanels();
    });
  }

  void _openChat(HermesMobileChat chat) {
    HermesMobileScope.read(context).open(chat);
    setState(() => _home = false);
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _newChat() {
    HapticFeedback.selectionClick();
    HermesMobileScope.read(context).newChat();
    setState(() => _home = false);
    if (_scaffold.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  // --- wave2 ---
  Widget _w2Body(BuildContext context, Widget body) {
    if (!w2UseTwoPane(context)) return body;
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: W2ChatsPane(
            onOpen: _openChat,
            onNew: _newChat,
            onLongPress: (chat) => showChatActions(context, chat),
          ),
        ),
        VerticalDivider(width: 1, color: context.hermesMobile.hairline),
        Expanded(child: body),
      ],
    );
  }
  // --- end wave2 ---

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    final c = context.hermesMobile;
    final current = state.current;
    final needsYou = state.pendingApprovals.length;
    return PopScope(
      canPop: _home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_home) setState(() => _home = true);
      },
      child: Wave1Binder(
        // wave1
        onOpenChat: _openChat,
        child: Scaffold(
          key: _scaffold,
          drawer: _ChatsDrawer(
            onOpen: _openChat,
            onNew: _newChat,
            onHome: () {
              Navigator.of(context).pop();
              setState(() => _home = true);
            },
          ),
          appBar: AppBar(
            leading: Badge(
              isLabelVisible: needsYou > 0 && !_home,
              smallSize: 8,
              backgroundColor: c.warning,
              alignment: const AlignmentDirectional(0.45, -0.45),
              child: IconButton(
                tooltip: 'Home',
                icon: Icon(
                  _home ? Icons.home_rounded : Icons.home_outlined,
                  color: _home ? c.accent : c.text,
                ),
                onPressed: () => setState(() => _home = true),
              ),
            ),
            title: _home
                ? const Text('Home')
                : InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _scaffold.currentState?.openDrawer(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: ListenableBuilder(
                        listenable: current ?? ValueNotifier(0),
                        builder: (context, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                current?.title ?? 'New chat',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                              color: c.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            actions: [
              Wave1BriefButton(onOpenChat: _openChat), // wave1
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search_rounded),
                onPressed: () async {
                  final chat = await Navigator.of(context).push<HermesMobileChat>(
                    // --- wave2 --- global search with filters
                    MaterialPageRoute(builder: (_) => const W2SearchScreen()),
                  );
                  if (chat != null) _openChat(chat);
                },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  tooltip: 'Profile and settings',
                  icon: ProfileAvatar(
                    label: state.backend.connection.label,
                    demo: state.backend.isDemo,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ),
            ],
          ),
          // --- wave2 --- two panes on tablets and unfolded foldables
          body: _w2Body(
            context,
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              child: _home
                  ? HomeScreen(
                      key: const ValueKey('home'),
                      onOpenChat: _openChat,
                      onNewChat: _newChat,
                    )
                  : current == null
                  ? const SizedBox.shrink()
                  : ChatView(
                      key: ValueKey(current.chatId),
                      controller: current,
                    ),
            ),
          ),
          // --- end wave2 ---
        ),
      ), // wave1: Wave1Binder
    );
  }
}

class _ChatsDrawer extends StatefulWidget {
  const _ChatsDrawer({
    required this.onOpen,
    required this.onNew,
    required this.onHome,
  });
  final void Function(HermesMobileChat) onOpen;
  final VoidCallback onNew;
  final VoidCallback onHome;

  @override
  State<_ChatsDrawer> createState() => _ChatsDrawerState();
}

class _ChatsDrawerState extends State<_ChatsDrawer> {
  int _tab = 0;
  Future<List<HermesMobileProject>?>? _projects;

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    final c = context.hermesMobile;
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.86,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text('Hermes', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Home',
                    onPressed: widget.onHome,
                    icon: const Icon(Icons.home_outlined),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: widget.onNew,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('New chat'),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Chats')),
                  ButtonSegment(value: 1, label: Text('Projects')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() {
                  _tab = s.first;
                  if (_tab == 1) {
                    _projects ??= state.backend.listProjects();
                  }
                }),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _tab == 0
                  ? RefreshIndicator(
                      onRefresh: state.refreshChats,
                      child: state.chatsLoading && state.chats.isEmpty
                          ? const SkeletonList()
                          : state.chats.isEmpty
                          ? ListView(
                              children: [
                                EmptyState(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  title: 'No chats yet',
                                  body:
                                      state.chatsError ??
                                      'Start one with New chat.',
                                ),
                              ],
                            )
                          // --- wave2 --- pinned chats first, star marks
                          : W2ChatsList(
                              onOpen: widget.onOpen,
                              onLongPress: (chat) =>
                                  showChatActions(context, chat),
                            ),
                      // --- end wave2 ---
                    )
                  : _ProjectsList(
                      future: _projects ??= state.backend.listProjects(),
                      onRefresh: () => setState(
                        () => _projects = state.backend.listProjects(),
                      ),
                      onOpen: widget.onOpen,
                    ),
            ),
            if (_tab == 0)
              ListTile(
                key: const ValueKey('archived-chats-tile'),
                leading: const Icon(Icons.archive_outlined, size: 20),
                title: const Text('Archived chats'),
                onTap: () async {
                  final chat = await openArchivedChats(context);
                  if (chat != null) widget.onOpen(chat);
                },
              ),
            Divider(color: c.hairline),
            ListTile(
              dense: true,
              leading: Icon(
                state.backend.isDemo
                    ? Icons.science_outlined
                    : Icons.dns_outlined,
                size: 20,
              ),
              title: Text(state.backend.connection.label),
              subtitle: Text(
                state.backend.connection.endpoint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectsList extends StatelessWidget {
  const _ProjectsList({
    required this.future,
    required this.onRefresh,
    required this.onOpen,
  });
  final Future<List<HermesMobileProject>?> future;
  final VoidCallback onRefresh;
  final void Function(HermesMobileChat) onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HermesMobileProject>?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SkeletonList();
        }
        if (snap.hasError) {
          return ListView(
            children: [
              EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load projects',
                body: '${snap.error}',
                action: TextButton(
                  onPressed: onRefresh,
                  child: const Text('Retry'),
                ),
              ),
            ],
          );
        }
        final list = snap.data;
        if (list == null) {
          return ListView(
            children: const [
              EmptyState(
                icon: Icons.folder_outlined,
                title: 'Projects need the dashboard',
                body:
                    'Projects live on the Hermes dashboard gateway. Add its URL '
                    'under Profile → Connection to see project folders here.',
              ),
            ],
          );
        }
        if (list.isEmpty) {
          return ListView(
            children: const [
              EmptyState(
                icon: Icons.folder_outlined,
                title: 'No projects yet',
                body: 'Create projects in Hermes Desktop or the dashboard.',
              ),
            ],
          );
        }
        return ListView(
          children: [
            for (final p in list)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(p.name),
                subtitle: Text(
                  p.description ?? p.path ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final chat = await Navigator.of(context).push<HermesMobileChat>(
                    MaterialPageRoute(
                      // --- wave2 --- instructions, files and chats
                      builder: (_) => W2ProjectScreen(project: p),
                    ),
                  );
                  if (chat != null) onOpen(chat);
                },
              ),
          ],
        );
      },
    );
  }
}

class ProjectChatsScreen extends StatelessWidget {
  const ProjectChatsScreen({super.key, required this.project});
  final HermesMobileProject project;

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: FutureBuilder<List<HermesMobileChat>>(
        future: state.backend.projectChats(project.id),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonList();
          }
          final chats = snap.data ?? const [];
          if (chats.isEmpty) {
            return const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No chats in this project',
              body: 'Chats started in this project folder show up here.',
            );
          }
          return ListView(
            children: [
              if (project.path != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    project.path!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final chat in chats)
                ChatTile(
                  chat: chat,
                  onTap: () => Navigator.of(context).pop(chat),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Long-press actions for a chat: rename, delete, or open it in the original
/// hermes-android chat screen (file attachments, sudo/clarify prompts and turn
/// recovery live there until the Petasos view covers them).
Future<void> showChatActions(BuildContext context, HermesMobileChat chat) async {
  final state = HermesMobileScope.read(context);
  final backend = state.backend;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              chat.displayTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(c, 'rename'),
          ),
          ...w2ChatActionRows(
            c,
            chat,
            backend.connection.endpoint,
          ), // --- wave2 ---
          if (backend is LiveBackend)
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open in classic view'),
              subtitle: const Text(
                'Full engine chat: files, prompts, recovery',
              ),
              onTap: () => Navigator.pop(c, 'classic'),
            ),
          // --- wave4 --- dashboard hand-off
          if (!chat.isDraft)
            ListTile(
              leading: const Icon(Icons.desktop_windows_outlined),
              title: const Text('Continue on the dashboard'),
              subtitle: const Text(
                'Opens this same chat in the Hermes web dashboard',
              ),
              onTap: () => Navigator.pop(c, 'wave4_dashboard'),
            ),
          // --- /wave4 ---
          if (!chat.isDraft)
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              subtitle: const Text('Undo for a few seconds; restore any time'),
              onTap: () => Navigator.pop(c, 'archive'),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: c.hermesMobile.danger),
            title: Text('Delete', style: TextStyle(color: c.hermesMobile.danger)),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (await w2HandleChatAction(context, action, chat)) return; // --- wave2 ---
  if (!context.mounted) return; // --- wave2 ---
  switch (action) {
    case 'archive':
      archiveChatWithUndo(context, chat);
      if (state.current?.chatId == chat.id) state.newChat();
    case 'wave4_dashboard': // --- wave4 ---
      await openInDashboard(context, chat.id);
    case 'rename':
      final ctl = TextEditingController(text: chat.displayTitle);
      final title = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Rename chat'),
          content: TextField(controller: ctl, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (title == null || title.isEmpty) return;
      try {
        await backend.renameChat(chat.id, title);
      } catch (_) {}
      await state.refreshChats(quiet: true);
    case 'delete':
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Delete this chat?'),
          content: Text(chat.displayTitle),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await backend.deleteChat(chat.id);
      } catch (_) {}
      if (state.current?.chatId == chat.id) state.newChat();
      await state.refreshChats(quiet: true);
    case 'classic':
      if (backend is! LiveBackend) return;
      final brightness = Theme.of(context).brightness;
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Theme(
            data: hermesTheme(brightness, palette: HermesPalette.indigo),
            child: ChatScreen(
              connection: backend.conn,
              session: Session(
                id: chat.id,
                title: chat.title,
                model: '',
                source: chat.source.isEmpty ? 'api_server' : chat.source,
                messageCount: chat.messageCount,
                isActive: chat.isActive,
                preview: chat.preview,
                startedAt: chat.updatedAt == null
                    ? now
                    : chat.updatedAt!.millisecondsSinceEpoch / 1000,
              ),
            ),
          ),
        ),
      );
      if (context.mounted) await state.refreshChats(quiet: true);
  }
}
