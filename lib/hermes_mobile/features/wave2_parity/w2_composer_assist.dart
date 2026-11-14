import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import 'w2_api.dart';
import 'w2_settings.dart';

/// A suggestion the composer can insert.
class W2Suggestion {
  const W2Suggestion({
    required this.label,
    required this.insert,
    this.detail = '',
    this.icon = Icons.bolt_rounded,
  });
  final String label;
  final String insert;
  final String detail;
  final IconData icon;
}

/// Where the cursor's current token is, for `/` and `@` completion.
class W2Token {
  const W2Token(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

W2Token? w2TokenAtCursor(TextEditingValue v) {
  final sel = v.selection;
  final pos = sel.isValid ? sel.baseOffset : v.text.length;
  if (pos < 0 || pos > v.text.length) return null;
  var start = pos;
  while (start > 0 && !RegExp(r'\s').hasMatch(v.text[start - 1])) {
    start--;
  }
  final text = v.text.substring(start, pos);
  if (text.isEmpty) return null;
  return W2Token(start, pos, text);
}

/// Slash suggestions for [query] (without the slash). Skills become commands.
List<W2Suggestion> w2SlashSuggestions(String query, List<HermesMobileSkill> skills) {
  final q = query.toLowerCase();
  return [
    for (final c in w2SlashCommands)
      if (c.name.startsWith(q))
        W2Suggestion(
          label: '/${c.name}${c.args.isEmpty ? '' : ' ${c.args}'}',
          insert: '/${c.name} ',
          detail: c.description,
          icon: Icons.terminal_rounded,
        ),
    for (final s in skills)
      if (s.enabled && s.name.toLowerCase().startsWith(q))
        W2Suggestion(
          label: '/${s.name}',
          insert: '/${s.name} ',
          detail: s.description.isEmpty ? 'Skill' : s.description,
          icon: Icons.extension_outlined,
        ),
  ].take(8).toList();
}

/// @mention suggestions: skills, projects and recent chats.
List<W2Suggestion> w2MentionSuggestions(
  String query, {
  required List<HermesMobileSkill> skills,
  required List<HermesMobileProject> projects,
  required List<HermesMobileChat> chats,
}) {
  final q = query.toLowerCase();
  bool m(String s) => s.toLowerCase().contains(q);
  String slug(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^\w\-.]'), '');
  return [
    for (final s in skills)
      if (m(s.name))
        W2Suggestion(
          label: '@${s.name}',
          insert: '@skill:${slug(s.name)} ',
          detail: 'Skill',
          icon: Icons.extension_outlined,
        ),
    for (final p in projects)
      if (m(p.name))
        W2Suggestion(
          label: '@${p.name}',
          insert: '@project:${slug(p.name)} ',
          detail: p.path ?? 'Project',
          icon: Icons.folder_outlined,
        ),
    for (final c in chats.take(30))
      if (m(c.displayTitle))
        W2Suggestion(
          label: '@${c.displayTitle}',
          insert: '@chat:${c.id} ',
          detail: 'Chat',
          icon: Icons.chat_bubble_outline_rounded,
        ),
  ].take(8).toList();
}

/// Replaces the token under the cursor with [insert].
void w2ApplySuggestion(TextEditingController ctl, W2Token token, String insert) {
  final text = ctl.text;
  final next = text.replaceRange(token.start, token.end, insert);
  ctl.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: token.start + insert.length),
  );
}

/// Suggestion strip shown above the composer while typing `/` or `@`.
class W2ComposerAssist extends StatefulWidget {
  const W2ComposerAssist({super.key, required this.controller});
  final TextEditingController controller;

  @override
  State<W2ComposerAssist> createState() => _W2ComposerAssistState();
}

class _W2ComposerAssistState extends State<W2ComposerAssist> {
  List<HermesMobileSkill> _skills = const [];
  List<HermesMobileProject> _projects = const [];
  bool _loaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(W2ComposerAssist old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final t = w2TokenAtCursor(widget.controller.value);
    if (t != null && (t.text.startsWith('/') || t.text.startsWith('@'))) {
      _ensureLoaded();
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    final backend = HermesMobileScope.read(context).backend;
    try {
      _skills = await backend.listSkills();
    } catch (_) {}
    try {
      _projects = await backend.listProjects() ?? const [];
    } catch (_) {}
    _loaded = true;
    _loading = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final token = w2TokenAtCursor(widget.controller.value);
    if (token == null) return const SizedBox.shrink();
    List<W2Suggestion> items;
    if (token.text.startsWith('/') && token.start == 0) {
      items = w2SlashSuggestions(token.text.substring(1), _skills);
    } else if (token.text.startsWith('@')) {
      items = w2MentionSuggestions(
        token.text.substring(1),
        skills: _skills,
        projects: _projects,
        chats: HermesMobileScope.of(context).chats,
      );
    } else {
      return const SizedBox.shrink();
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.hermesMobile;
    return Container(
      key: const ValueKey('w2-composer-assist'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HermesMobileRadius.card),
        boxShadow: hermesMobileShadow(context),
      ),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HermesMobileRadius.card),
          side: BorderSide(color: c.hairline),
        ),
        child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final s in items)
            ListTile(
              dense: true,
              leading: Icon(s.icon, size: 18),
              title: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: s.detail.isEmpty
                  ? null
                  : Text(s.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                W2Haptics.selection();
                w2ApplySuggestion(widget.controller, token, s.insert);
              },
            ),
        ],
        ),
      ),
    );
  }
}
