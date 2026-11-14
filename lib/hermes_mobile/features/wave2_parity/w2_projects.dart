import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'w2_api.dart';
import 'w2_settings.dart';

/// Wraps project instructions as the system message for project chats.
String w2ProjectPreamble(HermesMobileProject p, String instructions) {
  final t = instructions.trim();
  if (t.isEmpty) return '';
  return 'Project "${p.name}"${p.path == null ? '' : ' (${p.path})'} '
      'instructions from the user:\n$t';
}

/// A project: its standing instructions, files and chats. Pops a [HermesMobileChat]
/// to open.
class W2ProjectScreen extends StatefulWidget {
  const W2ProjectScreen({super.key, required this.project});
  final HermesMobileProject project;

  @override
  State<W2ProjectScreen> createState() => _W2ProjectScreenState();
}

class _W2ProjectScreenState extends State<W2ProjectScreen> {
  final _instructions = TextEditingController();
  W2ProjectDetails? _details;
  List<HermesMobileChat>? _chats;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  HermesMobileProject get p => widget.project;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _instructions.addListener(() {
      if (!_dirty && _details != null && _instructions.text != _details!.instructions) {
        setState(() => _dirty = true);
      }
    });
  }

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = HermesMobileScope.read(context);
    try {
      final d = await state.backend.wave2.projectDetails(p);
      if (!mounted) return;
      _instructions.text = d.instructions;
      setState(() {
        _details = d;
        _dirty = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    try {
      final chats = await state.backend.projectChats(p.id);
      if (mounted) setState(() => _chats = chats);
    } catch (_) {
      if (mounted) setState(() => _chats = const []);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await HermesMobileScope.read(context).backend.wave2.saveProjectInstructions(
        p.id,
        _instructions.text.trim(),
      );
      W2Haptics.light();
      if (mounted) {
        setState(() {
          _dirty = false;
          _details = W2ProjectDetails(
            instructions: _instructions.text.trim(),
            files: _details?.files ?? const [],
            serverBacked: _details?.serverBacked ?? false,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Instructions saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save. $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _newChat() {
    final state = HermesMobileScope.read(context);
    final ctl = state.newChat();
    ctl.w2Preamble = w2ProjectPreamble(p, _instructions.text);
    Navigator.of(context).pop(HermesMobileChat(id: ctl.chatId, title: '', isDraft: true));
  }

  void _openChat(HermesMobileChat chat) {
    final state = HermesMobileScope.read(context);
    state.controllerFor(chat).w2Preamble = w2ProjectPreamble(p, _instructions.text);
    Navigator.of(context).pop(chat);
  }

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final d = _details;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('w2-project-new-chat'),
        onPressed: _newChat,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New chat'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (p.path != null || p.description != null)
            Text(
              [p.description, p.path].whereType<String>().join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          SectionHeader(
            'Instructions',
            trailing: _dirty
                ? TextButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  )
                : null,
          ),
          TextField(
            key: const ValueKey('w2-project-instructions'),
            controller: _instructions,
            minLines: 3,
            maxLines: 10,
            enabled: d != null,
            decoration: const InputDecoration(
              hintText: 'How Hermes should work in this project: stack, tone, '
                  'rules, what to avoid…',
            ),
          ),
          if (d != null && !d.serverBacked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Saved on this phone and sent with each chat in this project. '
                'Install the Petasos plugin to keep them on the host.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: TextStyle(color: c.danger)),
            ),
          const SectionHeader('Files'),
          if (d == null)
            const LinearProgressIndicator()
          else if (d.files.isEmpty)
            Text(
              d.serverBacked
                  ? 'No files in this project folder yet.'
                  : 'Project files show here with the Petasos plugin.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final f in d.files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(f.name),
                subtitle: Text(
                  [f.path, _size(f.size)].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          const SectionHeader('Chats'),
          if (_chats == null)
            const LinearProgressIndicator()
          else if (_chats!.isEmpty)
            Text('No chats in this project yet.', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final chat in _chats!)
              ChatTile(chat: chat, onTap: () => _openChat(chat)),
        ],
      ),
    );
  }
}
