import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/memory_fact.dart';
import 'package:hermes_android/hermes_mobile/data/app_state.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/live_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/memory_manager_screen.dart';
import 'package:hermes_android/hermes_mobile/screens/settings_screen.dart';
import 'package:hermes_android/hermes_mobile/screens/skill_memory_detail.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(HermesMobileAppState state, Widget child) => MaterialApp(
  theme: hermesMobileTheme(Brightness.light),
  // Like the app: the scope sits above the navigator so pushed routes see it.
  builder: (context, nav) => HermesMobileScope(state: state, child: nav!),
  home: child,
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('skill detail parsing', () {
    test('splits front matter and finds linked files', () {
      const raw =
          '---\nname: x\ndescription: y\n---\n\n# X\n\n'
          'See [guide](references/guide.md) and [site](https://a.b).\n'
          'Run `scripts/run.sh`. Jump to [top](#x).';
      final p = HermesMobileSkillDetail.splitFrontMatter(raw);
      expect(p.frontMatter, 'name: x\ndescription: y');
      expect(p.body.startsWith('# X'), isTrue);
      expect(
        HermesMobileSkillDetail.linkedFiles(raw),
        unorderedEquals(['references/guide.md', 'scripts/run.sh']),
      );
      expect(HermesMobileSkillDetail.splitFrontMatter('# no fm').frontMatter, '');
    });

    test('dashboard /api/skills/content payload maps to a detail', () {
      final d = LiveBackend.skillDetailFromJson({
        'name': 'github',
        'content': '---\nname: github\n---\nUse [ref](references/api.md).',
        'path': '/root/.hermes/skills/dev/github/SKILL.md',
      });
      expect(d.path, endsWith('SKILL.md'));
      expect(d.files, ['references/api.md']);
      expect(
        () => LiveBackend.skillDetailFromJson({'content': ''}),
        throwsFormatException,
      );
    });

    test('dashboard skill rows keep provenance, usage and enabled', () {
      final s = HermesMobileSkill.fromJson({
        'name': 'a',
        'description': 'd',
        'category': 'c',
        'enabled': false,
        'provenance': 'hub',
        'usage': 4,
        'locked': true,
      });
      expect(s.enabled, isFalse);
      expect(s.provenance, 'hub');
      expect(s.usage, 4);
      expect(s.locked, isTrue);
      expect(s.copyWith(enabled: true).enabled, isTrue);
    });
  });

  group('live memory mapping', () {
    test('keeps ids, flags previews at the 1,200 cap, titles from text', () {
      final long = 'x' * 1200;
      final items = LiveBackend.memoryItemsFromFacts([
        const MemoryFact(
          id: 'memory:memory:0:abcdef012345',
          source: MemoryFactSource.memory,
          content: '## Backups\nNightly to B2.',
        ),
        MemoryFact(
          id: 'memory:profile:1:0123456789ab',
          source: MemoryFactSource.profile,
          content: long,
        ),
        const MemoryFact(
          id: 'memory:profile:2',
          source: MemoryFactSource.profile,
          content: 'Old gateway entry',
        ),
      ]);
      expect(items[0].title, 'Backups');
      expect(items[0].body, '## Backups\nNightly to B2.');
      expect(items[0].scope, 'MEMORY.md');
      expect(items[0].truncated, isFalse);
      expect(items[0].editable, isTrue);
      expect(items[1].truncated, isTrue);
      expect(items[1].body.length, 1200);
      expect(items[2].editable, isFalse);
    });
  });

  testWidgets('skills: tap opens SKILL.md, toggle updates the list', (
    tester,
  ) async {
    _tall(tester);
    final state = HermesMobileAppState(DemoBackend(fast: true));
    await tester.pumpWidget(_wrap(state, const SkillsScreen()));
    await _settle(tester);
    expect(find.text('github'), findsOneWidget);
    expect(find.text('off'), findsOneWidget);

    await tester.tap(find.text('github'));
    await _settle(tester);
    expect(find.byType(SkillDetailScreen), findsOneWidget);
    expect(find.text('SKILL.md'), findsOneWidget);
    expect(find.text('When to use'), findsOneWidget);
    expect(find.text('Linked files'), findsOneWidget);
    expect(find.text('references/guide.md'), findsOneWidget);

    final sw = find.byKey(const ValueKey('skill-enabled-switch'));
    expect(tester.widget<Switch>(sw).value, isFalse);
    await tester.tap(sw);
    await _settle(tester);
    expect(tester.widget<Switch>(sw).value, isTrue);

    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(SkillsScreen), findsOneWidget);
    expect(find.text('off'), findsNothing);
  });

  testWidgets('memory: full text detail, edit, and manager entry point', (
    tester,
  ) async {
    _tall(tester);
    final state = HermesMobileAppState(DemoBackend(fast: true));
    await tester.pumpWidget(_wrap(state, const MemoryScreen()));
    await _settle(tester);
    expect(find.byKey(const ValueKey('memory-manager-entry')), findsOneWidget);
    expect(find.text('Comparisons'), findsOneWidget);

    // A preview entry loads its full text in the detail view.
    await tester.tap(find.text('Comparisons'));
    await _settle(tester);
    expect(find.byType(MemoryDetailScreen), findsOneWidget);
    expect(
      find.textContaining('Prefer a table when there are more than three'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('memory-edit')));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '## Comparisons\nShort.');
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.text('Memory saved'), findsOneWidget);
    expect(find.text('Short.'), findsOneWidget);

    await tester.pageBack();
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('memory-manager-entry')));
    await _settle(tester);
    expect(find.byType(MemoryManagerScreen), findsOneWidget);
  });

  test('error text explains a missing endpoint', () {
    expect(
      describeDetailError(Exception('HTTP 404')),
      contains('Update Hermes'),
    );
  });
}
