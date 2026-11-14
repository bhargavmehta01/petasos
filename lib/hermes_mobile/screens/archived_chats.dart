import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../widgets/common.dart';
import '../widgets/undo.dart';
import '../features/wave2_parity/w2_settings.dart';

/// Archive with a 6 s Undo: the chat leaves the list now, the server archive
/// happens when the snackbar closes without Undo.
void archiveChatWithUndo(BuildContext context, HermesMobileChat chat) {
  final state = HermesMobileScope.read(context);
  W2Haptics.medium();
  final index = state.stageArchive(chat);
  showUndoSnackBar(
    context,
    message: 'Chat archived',
    onUndo: () => state.undoArchive(chat, index),
    onCommit: () => state.commitArchive(chat, index),
  );
}

/// Opens the Archived chats list; resolves to a chat the user chose to open.
Future<HermesMobileChat?> openArchivedChats(BuildContext context) =>
    Navigator.of(context).push<HermesMobileChat>(
      MaterialPageRoute(builder: (_) => const ArchivedChatsScreen()),
    );

/// Archived chats with Unarchive.
class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  Future<List<HermesMobileChat>>? _load;
  final Set<String> _busy = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load ??= HermesMobileScope.read(context).backend.listArchivedChats();
  }

  Future<void> _reload() async {
    final f = HermesMobileScope.read(context).backend.listArchivedChats();
    setState(() => _load = f);
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _unarchive(HermesMobileChat chat) async {
    final state = HermesMobileScope.read(context);
    W2Haptics.selection();
    setState(() => _busy.add(chat.id));
    try {
      await state.unarchiveChat(chat);
      if (!mounted) return;
      showHermesMobileSnack(context, 'Moved back to Chats');
      await _reload();
    } catch (e) {
      if (mounted) showHermesMobileSnack(context, 'Could not unarchive: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(chat.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived chats')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<HermesMobileChat>>(
          future: _load,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList();
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load archived chats',
                    body: '${snap.error}',
                    action: FilledButton.tonalIcon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              );
            }
            final chats = snap.data ?? const <HermesMobileChat>[];
            if (chats.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(
                    icon: Icons.archive_outlined,
                    title: 'No archived chats',
                    body:
                        'Long-press a chat and choose Archive to tuck it away.',
                  ),
                ],
              );
            }
            return ListView(
              children: [
                for (final chat in chats)
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(
                      chat.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: chat.preview.isEmpty
                        ? null
                        : Text(
                            chat.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => Navigator.of(context).pop(chat),
                    trailing: _busy.contains(chat.id)
                        ? const SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : TextButton(
                            onPressed: () => _unarchive(chat),
                            child: const Text('Unarchive'),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
