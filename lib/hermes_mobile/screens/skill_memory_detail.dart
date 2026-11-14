import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/connection_manager.dart';
import '../cards/card_widgets.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../features/wave3_control/memory_manager_screen.dart';
import '../theme/hermes_mobile_theme.dart';
import '../widgets/common.dart';
import '../features/wave2_parity/w2_settings.dart';

/// Plain words for a failed dashboard call on these screens.
String describeDetailError(Object e) {
  final code = e is DashboardHttpException
      ? e.statusCode
      : int.tryParse(RegExp(r'HTTP (\d{3})').firstMatch('$e')?.group(1) ?? '');
  return switch (code) {
    404 =>
      'This Hermes server does not offer this yet (404). Update Hermes '
          'on the host to see it here.',
    405 => 'This Hermes server does not support this action (405).',
    401 || 403 =>
      'The dashboard refused the request ($code). Check the '
          'dashboard sign-in in Connection settings.',
    _ => '$e',
  };
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.muted = false});
  final String label;
  final bool muted;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? c.surfaceMuted : c.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: muted ? c.textSecondary : c.accent,
        ),
      ),
    );
  }
}

/// One skill: description, category, on/off switch and the full SKILL.md.
/// Pops with the skill's latest state so the list can update.
class SkillDetailScreen extends StatefulWidget {
  const SkillDetailScreen({super.key, required this.skill});
  final HermesMobileSkill skill;
  @override
  State<SkillDetailScreen> createState() => _SkillDetailScreenState();
}

class _SkillDetailScreenState extends State<SkillDetailScreen> {
  late HermesMobileSkill _skill = widget.skill;
  Future<HermesMobileSkillDetail>? _detail;
  bool _toggling = false;
  bool _showFrontMatter = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= HermesMobileScope.read(context).backend.skillDetail(_skill.name);
  }

  Future<void> _toggle(bool on) async {
    W2Haptics.selection();
    final m = ScaffoldMessenger.of(context);
    final before = _skill;
    setState(() {
      _toggling = true;
      _skill = _skill.copyWith(enabled: on);
    });
    try {
      await HermesMobileScope.read(context).backend.setSkillEnabled(_skill.name, on);
      m.showSnackBar(
        SnackBar(
          content: Text(
            '${_skill.name} ${on ? 'turned on' : 'turned off'}. '
            'New chats pick up the change.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _skill = before);
      m.showSnackBar(SnackBar(content: Text(describeDetailError(e))));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    return PopScope<HermesMobileSkill>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_skill);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_skill.name, overflow: TextOverflow.ellipsis),
          actions: [
            FutureBuilder<HermesMobileSkillDetail>(
              future: _detail,
              builder: (context, snap) => IconButton(
                tooltip: 'Copy SKILL.md',
                icon: const Icon(Icons.copy_rounded),
                onPressed: snap.hasData
                    ? () {
                        Clipboard.setData(
                          ClipboardData(text: snap.data!.content),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('SKILL.md copied')),
                        );
                      }
                    : null,
              ),
            ),
          ],
        ),
        body: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              HermesMobileCardFrame(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (_skill.category.isNotEmpty) _Chip(_skill.category),
                        if (_skill.provenance.isNotEmpty)
                          _Chip(_skill.provenance, muted: true),
                        if (_skill.usage != null)
                          _Chip('used ${_skill.usage}×', muted: true),
                        if (_skill.locked) const _Chip('locked', muted: true),
                      ],
                    ),
                    if (_skill.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SelectableText(_skill.description, style: t.bodyMedium),
                    ],
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enabled',
                                style: t.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _skill.enabled
                                    ? 'Hermes can load this skill.'
                                    : 'Hermes will not load this skill.',
                                style: t.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          key: const ValueKey('skill-enabled-switch'),
                          value: _skill.enabled,
                          onChanged: _toggling ? null : _toggle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              FutureBuilder<HermesMobileSkillDetail>(
                future: _detail,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: LinearProgressIndicator(minHeight: 2),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: HermesMobileCardFrame(
                        icon: Icons.info_outline_rounded,
                        title: 'Full SKILL.md not available',
                        child: Text(
                          describeDetailError(snap.error!),
                          style: t.bodySmall,
                        ),
                      ),
                    );
                  }
                  final d = snap.data!;
                  final parts = d.parts;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        'SKILL.md',
                        trailing: parts.frontMatter.isEmpty
                            ? null
                            : TextButton(
                                onPressed: () => setState(
                                  () => _showFrontMatter = !_showFrontMatter,
                                ),
                                child: Text(
                                  _showFrontMatter
                                      ? 'Hide front matter'
                                      : 'Front matter',
                                ),
                              ),
                      ),
                      if (_showFrontMatter && parts.frontMatter.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: c.surfaceMuted,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              parts.frontMatter,
                              style: t.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      HermesMobileCardFrame(
                        child: HermesMobileMarkdown(
                          parts.body.trim().isEmpty ? '_(empty)_' : parts.body,
                        ),
                      ),
                      if (d.files.isNotEmpty) ...[
                        const SectionHeader('Linked files'),
                        HermesMobileCardFrame(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final f in d.files)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.description_outlined,
                                        size: 16,
                                        color: c.textTertiary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: SelectableText(
                                          f,
                                          style: t.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (d.path != null && d.path!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SelectableText(
                            d.path!,
                            style: t.labelSmall?.copyWith(
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One memory entry with its full text, rendered as markdown. Pops `true`
/// when the entry was changed so the list reloads.
class MemoryDetailScreen extends StatefulWidget {
  const MemoryDetailScreen({super.key, required this.item});
  final HermesMobileMemoryItem item;
  @override
  State<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends State<MemoryDetailScreen> {
  Future<String>? _text;
  bool _raw = false;
  bool _changed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _text ??= HermesMobileScope.read(context).backend.memoryFullText(widget.item);
  }

  Future<void> _edit(String current) async {
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _EditMemoryDialog(initial: current),
    );
    if (next == null || next.trim().isEmpty || next == current || !mounted) {
      return;
    }
    final m = ScaffoldMessenger.of(context);
    try {
      await HermesMobileScope.read(context).backend.editMemoryItem(widget.item, next);
      setState(() {
        _changed = true;
        _text = Future.value(next);
      });
      m.showSnackBar(const SnackBar(content: Text('Memory saved')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text(describeDetailError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final t = Theme.of(context).textTheme;
    final item = widget.item;
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(item.scope ?? 'Memory'),
          actions: [
            IconButton(
              tooltip: _raw ? 'Show formatted' : 'Show raw text',
              icon: Icon(_raw ? Icons.article_outlined : Icons.code_rounded),
              onPressed: () => setState(() => _raw = !_raw),
            ),
          ],
        ),
        body: SelectionArea(
          child: FutureBuilder<String>(
            future: _text,
            builder: (context, snap) {
              final waiting = snap.connectionState != ConnectionState.done;
              final full = snap.data;
              final text = full ?? item.body;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    item.title,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.scope ?? ''}${text.isEmpty ? '' : ' · ${text.runes.length} characters'}',
                    style: t.labelSmall?.copyWith(color: c.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  if (waiting) const LinearProgressIndicator(minHeight: 2),
                  if (snap.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: HermesMobileCardFrame(
                        icon: Icons.info_outline_rounded,
                        title: 'Showing the first part only',
                        child: Text(
                          describeDetailError(snap.error!),
                          style: t.bodySmall,
                        ),
                      ),
                    ),
                  HermesMobileCardFrame(
                    child: _raw
                        ? SelectableText(
                            text,
                            style: t.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          )
                        : HermesMobileMarkdown(text),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied')),
                          );
                        },
                      ),
                      if (item.editable && !waiting && !snap.hasError)
                        FilledButton.icon(
                          key: const ValueKey('memory-edit'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                          onPressed: () => _edit(text),
                        ),
                      TextButton.icon(
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Memory manager'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MemoryManagerScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Owns its controller so it is disposed only after the dialog's exit
/// animation, never while the closing TextField still reads it.
class _EditMemoryDialog extends StatefulWidget {
  const _EditMemoryDialog({required this.initial});
  final String initial;
  @override
  State<_EditMemoryDialog> createState() => _EditMemoryDialogState();
}

class _EditMemoryDialogState extends State<_EditMemoryDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit memory'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _ctl,
          maxLines: 12,
          minLines: 4,
          autofocus: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctl.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
