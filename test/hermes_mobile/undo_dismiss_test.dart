import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/app_state.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_brief_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_controller.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_dismissed.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_models.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_services.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_commitments.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_recap.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_watchers.dart';
import 'package:hermes_android/hermes_mobile/hermes_mobile_app.dart';
import 'package:hermes_android/hermes_mobile/screens/settings_screen.dart';
import 'package:hermes_android/hermes_mobile/screens/skill_memory_detail.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:hermes_android/hermes_mobile/widgets/message_views.dart';
import 'package:hermes_android/hermes_mobile/widgets/undo.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records calls; optionally refuses restore like an older Petasos plugin.
class _FakeSource implements ProactiveSource {
  _FakeSource(this.cards, {this.canRestore = true});
  List<ProactiveCard> cards;
  final bool canRestore;
  final List<String> dismissed = [];
  final List<String> restored = [];

  @override
  Future<ProactiveFeed> load() async => ProactiveFeed(
    cards: [
      for (final c in cards)
        if (!dismissed.contains(c.id) || restored.contains(c.id)) c,
    ],
  );

  @override
  Future<void> dismiss(String id) async {
    restored.remove(id);
    dismissed.add(id);
  }

  @override
  Future<void> restore(String id) async {
    if (!canRestore) throw StateError('404');
    restored.add(id);
  }

  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> snooze(String id, Duration d) async {}
  @override
  Future<void> acted(String id, ProactiveActionKind action) async {}
  @override
  Future<String?> feedback(ProactiveCard card, bool more) async => null;
  @override
  Future<String?> upload(String name, Uint8List bytes, {String? mime}) async =>
      null;
}

ProactiveCard _card(String id, {int priority = 0, int hour = 7}) =>
    ProactiveCard(
      id: id,
      title: 'Card $id',
      body: 'Body of $id',
      kind: 'suggestion',
      createdAt: DateTime(2026, 11, 4, hour),
      priority: priority,
    );

Future<(ProactiveController, _FakeSource, DismissedStore)> _ctl({
  bool canRestore = true,
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = DismissedStore(prefs, clock: clock);
  final src = _FakeSource([
    _card('a', hour: 9),
    _card('b', hour: 8),
    _card('c', hour: 7),
  ], canRestore: canRestore);
  final ctl = ProactiveController(
    HermesMobileAppState(DemoBackend(fast: true)),
    source: src,
    dismissedStore: store,
  );
  await ctl.refresh();
  return (ctl, src, store);
}

void main() {
  group('PendingUndo', () {
    test('undo wins once; a late commit is a no-op', () async {
      var undone = 0, committed = 0;
      final p = PendingUndo(undo: () => undone++, commit: () => committed++);
      await p.runUndo();
      await p.runCommit();
      await p.runUndo();
      expect((undone, committed), (1, 0));
      expect(p.outcome, UndoOutcome.undone);
    });

    test('commit wins once; a late undo is a no-op', () async {
      var undone = 0, committed = 0;
      final p = PendingUndo(undo: () => undone++, commit: () => committed++);
      await p.runCommit();
      await p.runUndo();
      expect((undone, committed), (0, 1));
      expect(p.outcome, UndoOutcome.committed);
    });
  });

  group('ProactiveController undo', () {
    test('stage hides the card without telling the server', () async {
      final (ctl, src, store) = await _ctl();
      expect(ctl.stageDismiss(ctl.cards[1]), isTrue);
      expect(ctl.cards.map((c) => c.id), ['a', 'c']);
      expect(src.dismissed, isEmpty);
      expect(store.list(), isEmpty);
      expect(ctl.isStaged('b'), isTrue);
    });

    test('undo restores the card in place, server untouched', () async {
      final (ctl, src, store) = await _ctl();
      ctl.stageDismiss(ctl.cards[1]);
      ctl.undoDismiss('b');
      expect(ctl.cards.map((c) => c.id), ['a', 'b', 'c']);
      expect(src.dismissed, isEmpty);
      expect(store.list(), isEmpty);
      // A second undo or a late commit does nothing.
      ctl.undoDismiss('b');
      await ctl.commitDismiss('b');
      expect(src.dismissed, isEmpty);
    });

    test('commit posts the dismiss and files it under Dismissed', () async {
      final (ctl, src, store) = await _ctl();
      ctl.stageDismiss(ctl.cards[0]);
      await ctl.commitDismiss('a');
      expect(src.dismissed, ['a']);
      expect(store.list().map((e) => e.card.id), ['a']);
      expect(ctl.dismissed.single.card.title, 'Card a');
    });

    test(
      'refresh during the undo window keeps the staged card hidden',
      () async {
        final (ctl, _, _) = await _ctl();
        ctl.stageDismiss(ctl.cards[0]);
        await ctl.refresh();
        expect(ctl.cards.map((c) => c.id), ['b', 'c']);
        ctl.undoDismiss('a');
        expect(ctl.cards.map((c) => c.id), ['a', 'b', 'c']);
      },
    );

    test('restore un-dismisses on the server and leaves Dismissed', () async {
      final (ctl, src, store) = await _ctl();
      await ctl.dismiss(ctl.cards[0]);
      expect(ctl.cards.map((c) => c.id), ['b', 'c']);
      final synced = await ctl.restore(store.list().single);
      expect(synced, isTrue);
      expect(src.restored, ['a']);
      expect(store.list(), isEmpty);
      expect(ctl.cards.map((c) => c.id), containsAll(['a', 'b', 'c']));
      await ctl.refresh();
      expect(ctl.cards.map((c) => c.id), containsAll(['a', 'b', 'c']));
    });

    test('restore on an old plugin pins the card on the phone', () async {
      final (ctl, src, store) = await _ctl(canRestore: false);
      await ctl.dismiss(ctl.cards[0]);
      final synced = await ctl.restore(store.list().single);
      expect(synced, isFalse);
      expect(store.list(), isEmpty, reason: 'pinned entries are not listed');
      expect(store.pinnedCards().map((c) => c.id), ['a']);
      // The server still hides it, but refresh merges the pinned card back.
      await ctl.refresh();
      expect(ctl.cards.map((c) => c.id), contains('a'));
      // Dismissing it again un-pins it and files it under Dismissed.
      await ctl.dismiss(ctl.cards.firstWhere((c) => c.id == 'a'));
      expect(store.pinnedCards(), isEmpty);
      expect(store.list().map((e) => e.card.id), ['a']);
      expect(src.dismissed, ['a', 'a']);
    });

    test('local approval cards cannot be staged', () async {
      final (ctl, _, _) = await _ctl();
      final local = ProactiveCard(
        id: 'approval:x',
        title: 'x',
        createdAt: DateTime(2026),
        local: true,
      );
      expect(ctl.stageDismiss(local), isFalse);
    });
  });

  group('DismissedStore', () {
    test('keeps entries for the retention window, newest first', () async {
      var now = DateTime(2026, 11, 4, 12);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = DismissedStore(prefs, clock: () => now);
      await store.add(_card('old'));
      now = now.add(const Duration(days: 8));
      await store.add(_card('new'));
      // 8 days later both are still there (promise: at least 7 days).
      expect(store.list().map((e) => e.card.id), ['new', 'old']);
      now = now.add(const Duration(days: 7));
      // 15 days after the first: it is pruned, the second is kept.
      expect(store.list().map((e) => e.card.id), ['new']);
      expect(store.contains('old'), isFalse);
    });

    test('round-trips the card and survives a new store instance', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final card = ProactiveCard(
        id: 'brief:1',
        kind: 'brief',
        period: 'evening',
        title: 'Evening recap',
        body: '**All** good',
        source: 'Evening brief',
        createdAt: DateTime(2026, 11, 3, 20),
        priority: 2,
        chatId: 'c1',
        action: const ProactiveAction(
          kind: ProactiveActionKind.run,
          label: 'Run again',
          payload: {'cron_id': 'j1'},
        ),
      );
      await DismissedStore(prefs).add(card);
      final back = DismissedStore(prefs).list().single.card;
      expect(back.id, card.id);
      expect(back.kind, 'brief');
      expect(back.period, 'evening');
      expect(back.body, card.body);
      expect(back.createdAt, card.createdAt);
      expect(back.priority, 2);
      expect(back.chatId, 'c1');
      expect(back.action!.payload['cron_id'], 'j1');
    });

    test(
      're-adding replaces, remove deletes, corrupt data is ignored',
      () async {
        SharedPreferences.setMockInitialValues({
          DismissedStore.key: 'not json',
        });
        final prefs = await SharedPreferences.getInstance();
        final store = DismissedStore(prefs);
        expect(store.list(), isEmpty);
        await store.add(_card('a'));
        await store.add(_card('a'));
        expect(store.list(), hasLength(1));
        await store.remove('a');
        expect(store.list(), isEmpty);
      },
    );

    test('caps the number of entries', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = DismissedStore(prefs);
      for (var i = 0; i < DismissedStore.maxEntries + 5; i++) {
        await store.add(_card('c$i'));
      }
      expect(store.list(), hasLength(DismissedStore.maxEntries));
      expect(store.contains('c0'), isFalse);
    });
  });

  group('chat archive undo', () {
    test('stage hides, undo puts back in place, commit archives', () async {
      final state = HermesMobileAppState(DemoBackend(fast: true));
      await state.refreshChats();
      final before = state.chats.map((c) => c.id).toList();
      expect(before.length, greaterThan(1));
      final chat = state.chats[1];
      final i = state.stageArchive(chat);
      expect(state.chats.map((c) => c.id), isNot(contains(chat.id)));
      // A refresh inside the window keeps it hidden.
      await state.refreshChats(quiet: true);
      expect(state.chats.map((c) => c.id), isNot(contains(chat.id)));
      state.undoArchive(chat, i);
      expect(state.chats.map((c) => c.id), before);

      final j = state.stageArchive(chat);
      await state.commitArchive(chat, j);
      await state.refreshChats(quiet: true);
      expect(state.chats.map((c) => c.id), isNot(contains(chat.id)));
      final archived = await state.backend.listArchivedChats();
      expect(archived.map((c) => c.id), [chat.id]);

      await state.unarchiveChat(chat);
      expect(state.chats.map((c) => c.id), contains(chat.id));
      expect(await state.backend.listArchivedChats(), isEmpty);
    });
  });

  group('widgets', () {
    Future<HermesMobileRootController> demoRoot() async {
      SharedPreferences.setMockInitialValues({'hermes_mobile.demo': true});
      final prefs = await SharedPreferences.getInstance();
      final root = HermesMobileRootController(
        prefs: prefs,
        demoFactory: () => DemoBackend(fast: true),
      );
      await root.rebuild();
      return root;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    testWidgets('swipe a brief card, Undo brings it back, server untouched', (
      tester,
    ) async {
      final root = await demoRoot();
      await tester.pumpWidget(HermesMobileBootstrap(controller: root));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('w1-brief-button')));
      await settle(tester);
      expect(find.byType(SelectionArea), findsWidgets);

      const title = 'Good morning: 3 things today';
      await tester.drag(find.text(title), const Offset(-600, 0));
      await settle(tester);
      expect(find.text(title), findsNothing);
      expect(find.text('Card dismissed'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text(title), findsOneWidget);

      // Swipe again and let the window lapse: it lands in Dismissed.
      await tester.drag(find.text(title), const Offset(-600, 0));
      await settle(tester);
      await tester.pump(const Duration(seconds: 7));
      await settle(tester);
      expect(find.text('Card dismissed'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('w1-dismissed-button')));
      await settle(tester);
      expect(find.byType(DismissedCardsScreen), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await settle(tester);
      expect(find.text('Nothing dismissed'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(find.text(title), findsOneWidget);
      // Let the confirmation snackbar finish.
      await tester.pump(const Duration(seconds: 5));
    });

    Widget host(HermesMobileAppState state, Widget child) => MaterialApp(
      theme: hermesMobileTheme(Brightness.light),
      builder: (context, nav) => HermesMobileScope(state: state, child: nav!),
      home: child,
    );

    testWidgets('content screens are selectable', (tester) async {
      final state = HermesMobileAppState(DemoBackend(fast: true));
      final skills = await state.backend.listSkills();
      final memory = await state.backend.listMemory();
      final screens = <Widget>[
        const SkillsScreen(),
        SkillDetailScreen(skill: skills.first),
        const MemoryScreen(),
        MemoryDetailScreen(item: memory.first),
        const CommitmentsScreen(),
        const RecapScreen(),
        const WatchersScreen(),
      ];
      for (final s in screens) {
        await tester.pumpWidget(host(state, s));
        await settle(tester);
        expect(
          find.byType(SelectionArea),
          findsWidgets,
          reason: '${s.runtimeType} should be selectable',
        );
      }
    });

    testWidgets('chat messages: long-press selects; toolbar has More…', (
      tester,
    ) async {
      final m = HermesMobileMessage(
        role: HermesMobileRole.user,
        text: 'Select these words please',
      );
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesMobileTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: UserBubble(message: m, onLongPress: () => opened++),
            ),
          ),
        ),
      );
      expect(find.byType(MessageSelection), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      await tester.longPress(find.text('Select these words please'));
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('More…'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}
