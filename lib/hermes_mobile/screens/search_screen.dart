import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../widgets/common.dart';

/// Search chats by title (server) with a local preview fallback.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  Future<List<HermesMobileChat>>? _results;

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _results = v.trim().isEmpty
            ? null
            : HermesMobileScope.read(context).backend.searchChats(v);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _q,
            autofocus: true,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search chats',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
          ),
        ),
      ),
      body: _results == null
          ? const EmptyState(
              icon: Icons.search_rounded,
              title: 'Find a conversation',
              body: 'Search by title or words from the chat.',
            )
          : FutureBuilder<List<HermesMobileChat>>(
              future: _results,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SkeletonList(count: 4);
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Search failed',
                    body: '${snap.error}',
                  );
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    body: 'Try another word.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final chat in list)
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
