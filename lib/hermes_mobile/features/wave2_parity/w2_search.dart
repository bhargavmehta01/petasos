import 'dart:async';

import 'package:flutter/material.dart';

import '../../cards/blocks.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/hermes_mobile_theme.dart';
import '../../widgets/common.dart';
import 'w2_settings.dart';

enum W2SearchKind { chat, pinned, task, panel, memory, skill }

enum W2SearchFilter {
  all,
  chats,
  starred,
  pinned,
  tasks,
  panels,
  memory,
  skills,
}

extension on W2SearchFilter {
  String get label => switch (this) {
    W2SearchFilter.all => 'All',
    W2SearchFilter.chats => 'Chats',
    W2SearchFilter.starred => 'Starred',
    W2SearchFilter.pinned => 'Pinned',
    W2SearchFilter.tasks => 'Tasks',
    W2SearchFilter.panels => 'Panels',
    W2SearchFilter.memory => 'Memory',
    W2SearchFilter.skills => 'Skills',
  };
}

class W2SearchHit {
  const W2SearchHit({
    required this.kind,
    required this.title,
    this.snippet = '',
    this.chat,
    this.chatId,
  });
  final W2SearchKind kind;
  final String title;
  final String snippet;
  final HermesMobileChat? chat;
  final String? chatId;
}

/// Searches every source the phone can reach. Each source fails on its own.
Future<List<W2SearchHit>> w2SearchAll(
  HermesMobileAppState state,
  String query,
  W2SearchFilter filter,
) async {
  final q = query.trim().toLowerCase();
  final b = state.backend;
  final s = W2Settings.current;
  final conn = b.connection.endpoint;
  bool want(W2SearchFilter f) => filter == W2SearchFilter.all || filter == f;
  bool hit(String text) => q.isEmpty || text.toLowerCase().contains(q);
  String snip(String text) {
    final plain = replyPlainText(text).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.isEmpty) {
      return plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
    }
    final i = plain.toLowerCase().indexOf(q);
    if (i < 0) {
      return plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
    }
    final start = (i - 40).clamp(0, plain.length);
    final end = (i + q.length + 80).clamp(0, plain.length);
    return '${start > 0 ? '…' : ''}${plain.substring(start, end)}${end < plain.length ? '…' : ''}';
  }

  final out = <W2SearchHit>[];
  final futures = <Future<void>>[];

  if (want(W2SearchFilter.chats) || filter == W2SearchFilter.starred) {
    futures.add(() async {
      try {
        final chats = q.isEmpty ? await b.listChats() : await b.searchChats(q);
        for (final c in chats) {
          if (filter == W2SearchFilter.starred && !s.isStarred(conn, c.id)) {
            continue;
          }
          out.add(
            W2SearchHit(
              kind: W2SearchKind.chat,
              title: c.displayTitle,
              snippet: snip(c.preview),
              chat: c,
              chatId: c.id,
            ),
          );
        }
      } catch (_) {}
    }());
  }
  if (want(W2SearchFilter.pinned)) {
    for (final p in s.allPinnedMessages()) {
      if (!hit(p.text) && !hit(p.chatTitle)) continue;
      out.add(
        W2SearchHit(
          kind: W2SearchKind.pinned,
          title: p.chatTitle.isEmpty ? 'Pinned message' : p.chatTitle,
          snippet: snip(p.text),
          chatId: p.chatId,
        ),
      );
    }
  }
  if (want(W2SearchFilter.tasks)) {
    futures.add(() async {
      try {
        for (final j in await b.listCron()) {
          if (!hit(j.name) && !hit(j.prompt)) continue;
          out.add(
            W2SearchHit(
              kind: W2SearchKind.task,
              title: j.name,
              snippet:
                  '${j.schedule}${j.paused ? ' · paused' : ''} · ${snip(j.prompt)}',
            ),
          );
        }
      } catch (_) {}
    }());
  }
  if (want(W2SearchFilter.panels)) {
    for (final p in state.panels?.panels ?? const []) {
      final body = [
        p.title,
        p.subtitle ?? '',
        p.value ?? '',
        p.text ?? '',
      ].join(' ');
      if (!hit(body)) continue;
      out.add(
        W2SearchHit(
          kind: W2SearchKind.panel,
          title: p.title,
          snippet: snip(body),
        ),
      );
    }
  }
  if (want(W2SearchFilter.memory)) {
    futures.add(() async {
      try {
        for (final m in await b.listMemory()) {
          if (!hit(m.body) && !hit(m.title)) continue;
          out.add(
            W2SearchHit(
              kind: W2SearchKind.memory,
              title: m.title,
              snippet: snip(m.body),
            ),
          );
        }
      } catch (_) {}
    }());
  }
  if (want(W2SearchFilter.skills)) {
    futures.add(() async {
      try {
        for (final k in await b.listSkills()) {
          if (!hit(k.name) && !hit(k.description)) continue;
          out.add(
            W2SearchHit(
              kind: W2SearchKind.skill,
              title: k.name,
              snippet: k.description,
            ),
          );
        }
      } catch (_) {}
    }());
  }
  await Future.wait(futures);
  const order = W2SearchKind.values;
  out.sort((a, b) => order.indexOf(a.kind).compareTo(order.indexOf(b.kind)));
  return out;
}

/// Opens search; picking a chat opens it.
Future<void> openW2Search(
  BuildContext context, {
  String initialQuery = '',
}) async {
  final state = HermesMobileScope.read(context);
  final chat = await Navigator.of(context).push<HermesMobileChat>(
    MaterialPageRoute(
      builder: (_) => W2SearchScreen(initialQuery: initialQuery),
    ),
  );
  if (chat != null) state.open(chat);
}

class W2SearchScreen extends StatefulWidget {
  const W2SearchScreen({
    super.key,
    this.initialQuery = '',
    this.initialFilter = W2SearchFilter.all,
  });
  final String initialQuery;
  final W2SearchFilter initialFilter;

  @override
  State<W2SearchScreen> createState() => _W2SearchScreenState();
}

class _W2SearchScreenState extends State<W2SearchScreen> {
  late final _q = TextEditingController(text: widget.initialQuery);
  late W2SearchFilter _filter = widget.initialFilter;
  Timer? _debounce;
  Future<List<W2SearchHit>>? _results;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty || _filter != W2SearchFilter.all) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  void _run() {
    if (!mounted) return;
    final q = _q.text;
    setState(() {
      _results = q.trim().isEmpty && _filter == W2SearchFilter.all
          ? null
          : w2SearchAll(HermesMobileScope.read(context), q, _filter);
    });
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _open(W2SearchHit h) async {
    await W2Settings.current.addRecentSearch(_q.text);
    if (!mounted) return;
    if (h.chat != null) {
      Navigator.of(context).pop(h.chat);
      return;
    }
    if (h.chatId != null) {
      final state = HermesMobileScope.read(context);
      final chat =
          state.chats.where((c) => c.id == h.chatId).firstOrNull ??
          HermesMobileChat(id: h.chatId!, title: h.title);
      Navigator.of(context).pop(chat);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(h.title, style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 10),
            SelectableText(h.snippet),
          ],
        ),
      ),
    );
  }

  IconData _icon(W2SearchKind k) => switch (k) {
    W2SearchKind.chat => Icons.chat_bubble_outline_rounded,
    W2SearchKind.pinned => Icons.push_pin_outlined,
    W2SearchKind.task => Icons.event_repeat_rounded,
    W2SearchKind.panel => Icons.dashboard_outlined,
    W2SearchKind.memory => Icons.psychology_outlined,
    W2SearchKind.skill => Icons.extension_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final recents = W2Settings.current.recentSearches;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            key: const ValueKey('w2-search-field'),
            controller: _q,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (_) => _run(),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search chats, tasks, memory, skills',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final f in W2SearchFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _run();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: SelectionArea(
        child: _results == null
            ? ListView(
                children: [
                  if (recents.isNotEmpty) ...[
                    const SectionHeader('Recent'),
                    for (final r in recents)
                      ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: Text(r),
                        onTap: () {
                          _q.text = r;
                          _run();
                        },
                      ),
                  ] else
                    const EmptyState(
                      icon: Icons.search_rounded,
                      title: 'Search everything',
                      body:
                          'Chats, pinned messages, tasks, panels, memory and skills.',
                    ),
                ],
              )
            : FutureBuilder<List<W2SearchHit>>(
                future: _results,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SkeletonList(count: 4);
                  }
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      body: 'Try another word or filter.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final h = list[i];
                      return ListTile(
                        leading: Icon(_icon(h.kind), color: c.textSecondary),
                        title: Text(
                          h.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: h.snippet.isEmpty
                            ? null
                            : Text(
                                h.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => _open(h),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
