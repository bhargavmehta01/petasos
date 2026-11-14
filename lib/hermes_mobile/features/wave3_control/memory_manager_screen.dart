import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cards/card_widgets.dart';
import '../../data/app_state.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'wave3_api.dart';
import 'wave3_models.dart';

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Where an entry came from, in one line.
String provenanceLine(MemoryEntry e) {
  final who = switch (e.savedBy) {
    'user' => 'Edited by you',
    'agent' => 'Saved by Hermes',
    _ => 'Saved',
  };
  final where = e.sourceTitle?.trim().isNotEmpty == true
      ? ' in “${e.sourceTitle}”'
      : (e.sourceSession != null ? ' in a chat' : '');
  final when = e.savedAt == null ? '' : ' · ${_ago(e.savedAt!)}';
  if (e.savedBy == null && e.savedAt == null && where.isEmpty) {
    return e.target.fileName;
  }
  return '$who$where$when · ${e.target.fileName}';
}

/// Memory manager: view, search, add, edit, delete and pin what Hermes
/// remembers, see where each entry came from, and turn on incognito for a
/// chat so nothing from it is saved.
class MemoryManagerScreen extends StatefulWidget {
  const MemoryManagerScreen({super.key});
  @override
  State<MemoryManagerScreen> createState() => _MemoryManagerScreenState();
}

class _MemoryManagerScreenState extends State<MemoryManagerScreen> {
  Future<(Wave3Capabilities, List<MemoryEntry>, Set<String>)>? _data;
  MemoryTarget? _filter;
  String _query = '';

  Wave3Api get _api => Wave3Api.of(HermesMobileScope.read(context).backend);

  Future<(Wave3Capabilities, List<MemoryEntry>, Set<String>)> _load() async {
    final caps = await _api.capabilities();
    final entries = await _api.listMemory();
    Set<String> inc = {};
    try {
      inc = await _api.incognitoChats();
    } catch (_) {}
    return (caps, entries, inc);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _run(Future<void> Function() f, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await f();
      m.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) _reload();
  }

  Future<void> _edit({MemoryEntry? entry}) async {
    final result = await showModalBottomSheet<(MemoryTarget, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntryEditor(entry: entry),
    );
    if (result == null) return;
    final (target, text) = result;
    if (text.trim().isEmpty) return;
    await _run(
      () async => entry == null
          ? await _api.addMemory(target, text)
          : await _api.editMemory(entry, text),
      entry == null ? 'Saved to ${target.fileName}' : 'Updated',
    );
  }

  Future<void> _delete(MemoryEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Forget this?'),
        content: Text(
          e.pinned
              ? 'This entry is pinned. Hermes will no longer know:\n\n${e.content}'
              : 'Hermes will no longer know:\n\n${e.content}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _api.deleteMemory(e), 'Forgotten');
  }

  @override
  Widget build(BuildContext context) {
    final state = HermesMobileScope.of(context);
    final currentChat = state.current?.chatId;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Memory')),
      body: SelectionArea(
        child: FutureBuilder<(Wave3Capabilities, List<MemoryEntry>, Set<String>)>(
          future: _data,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SkeletonList();
            }
            if (snap.hasError) {
              return EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load memory',
                body: '${snap.error}',
                action: TextButton(
                  onPressed: _reload,
                  child: const Text('Retry'),
                ),
              );
            }
            final (caps, entries, incognito) = snap.data!;
            final writable = caps.memoryWrite;
            final q = _query.toLowerCase();
            final shown = entries
                .where((e) => _filter == null || e.target == _filter)
                .where((e) => q.isEmpty || e.content.toLowerCase().contains(q))
                .toList();
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _data;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  if (!writable) const _PluginHelp(),
                  if (caps.incognito && currentChat != null)
                    _IncognitoCard(
                      on: incognito.contains(currentChat),
                      onChanged: (v) => _run(
                        () => _api.setIncognito(currentChat, v),
                        v
                            ? 'Incognito on: this chat will not be remembered'
                            : 'Incognito off',
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('w3-memory-search'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search memory',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text('All · ${entries.length}'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      ChoiceChip(
                        label: const Text('About you'),
                        selected: _filter == MemoryTarget.user,
                        onSelected: (_) =>
                            setState(() => _filter = MemoryTarget.user),
                      ),
                      ChoiceChip(
                        label: const Text('Notes'),
                        selected: _filter == MemoryTarget.memory,
                        onSelected: (_) =>
                            setState(() => _filter = MemoryTarget.memory),
                      ),
                    ],
                  ),
                  if (shown.isEmpty)
                    const EmptyState(
                      icon: Icons.psychology_outlined,
                      title: 'Nothing here',
                      body:
                          'Hermes saves facts as it learns. You can add one too.',
                    ),
                  for (final e in shown)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _EntryCard(
                        entry: e,
                        writable: writable,
                        onEdit: () => _edit(entry: e),
                        onDelete: () => _delete(e),
                        onPin: () => _run(
                          () => _api.setPinned(e, !e.pinned),
                          e.pinned
                              ? 'Unpinned'
                              : 'Pinned: Hermes cannot change or remove it',
                        ),
                      ),
                    ),
                  if (shown.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        writable
                            ? 'Pinned entries stay first, and Hermes cannot change or remove them.'
                            : 'Read-only: install the Petasos plugin to edit.',
                        style: t.labelSmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FutureBuilder(
        future: _data,
        builder: (context, snap) => snap.data?.$1.memoryWrite == true
            ? FloatingActionButton.extended(
                key: const Key('w3-memory-add'),
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _PluginHelp extends StatelessWidget {
  const _PluginHelp();
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(HermesMobileRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Viewing only',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'To edit, delete, pin, or use incognito chats, install the Petasos '
            'plugin on your Hermes host: copy server/hermes_mobile_plugin to '
            '~/.hermes/plugins/hermes_mobile, add "hermes_mobile" to plugins.enabled, then '
            'restart the dashboard.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _IncognitoCard extends StatelessWidget {
  const _IncognitoCard({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HermesMobileCardFrame(
        padding: EdgeInsets.zero,
        child: SwitchListTile(
          key: const Key('w3-incognito'),
          secondary: Icon(
            on ? Icons.visibility_off_rounded : Icons.visibility_outlined,
            color: on ? c.accent : null,
          ),
          title: const Text('Incognito for this chat'),
          subtitle: const Text(
            'Hermes will not save anything from it to memory.',
          ),
          value: on,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.writable,
    required this.onEdit,
    required this.onDelete,
    required this.onPin,
  });
  final MemoryEntry entry;
  final bool writable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    return HermesMobileCardFrame(
      onTap: writable ? onEdit : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.pinned)
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 2),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: c.accent,
                  ),
                ),
              Expanded(child: Text(entry.content, style: t.bodyMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  provenanceLine(entry),
                  style: t.labelSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: entry.content));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Copied')));
                },
              ),
              if (writable) ...[
                IconButton(
                  tooltip: entry.pinned ? 'Unpin' : 'Pin',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    entry.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    size: 18,
                  ),
                  onPressed: onPin,
                ),
                IconButton(
                  tooltip: 'Forget',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: c.danger,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({this.entry});
  final MemoryEntry? entry;
  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final _text = TextEditingController(text: widget.entry?.content ?? '');
  late MemoryTarget _target = widget.entry?.target ?? MemoryTarget.user;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            editing ? 'Edit memory' : 'Add to memory',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (!editing)
            SegmentedButton<MemoryTarget>(
              segments: const [
                ButtonSegment(
                  value: MemoryTarget.user,
                  label: Text('About me'),
                ),
                ButtonSegment(value: MemoryTarget.memory, label: Text('Note')),
              ],
              selected: {_target},
              onSelectionChanged: (s) => setState(() => _target = s.first),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('w3-memory-field'),
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'One short fact'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('w3-memory-save'),
            onPressed: () => Navigator.of(context).pop((_target, _text.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
