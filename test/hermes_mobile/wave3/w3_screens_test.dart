import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/chat/chat_controller.dart';
import 'package:hermes_android/hermes_mobile/data/app_state.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/approval_rules_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/cron_studio_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/live_run_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/memory_manager_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/usage_meter_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave3_control/wave3_settings_section.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(HermesMobileAppState state, Widget child) => MaterialApp(
  theme: hermesMobileTheme(Brightness.light),
  home: HermesMobileScope(state: state, child: child),
);

/// A tall surface so whole screens build (ListView builds lazily).
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

  testWidgets('cron studio: health dots, failure reason, run timeline', (
    tester,
  ) async {
    _tall(tester);
    final state = HermesMobileAppState(DemoBackend(fast: true));
    await tester.pumpWidget(_wrap(state, const CronStudioScreen()));
    await _settle(tester);
    expect(find.text('Cron studio'), findsOneWidget);
    expect(find.text('Morning brief'), findsOneWidget);
    expect(find.byType(CronHealthDot), findsWidgets);
    expect(find.text('Failing'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byType(RunStrip), findsWidgets);

    await tester.tap(find.text('Failing'));
    await _settle(tester);
    expect(find.text('Why it failed'), findsOneWidget);
    expect(find.textContaining('401 Unauthorized'), findsWidgets);
    expect(find.text('Run history'), findsOneWidget);
    expect(find.text('Run now'), findsOneWidget);
    await tester.tap(find.text('Run now'));
    await _settle(tester);
    expect(find.text('Started a run'), findsOneWidget);
  });

  testWidgets('memory manager: add, pin, incognito', (tester) async {
    _tall(tester);
    final state = HermesMobileAppState(DemoBackend(fast: true));
    state.newChat();
    await tester.pumpWidget(_wrap(state, const MemoryManagerScreen()));
    await _settle(tester);
    expect(find.textContaining('Lives in Springfield'), findsOneWidget);
    expect(find.textContaining('Saved by Hermes'), findsWidgets);
    expect(find.text('Incognito for this chat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('w3-memory-add')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('w3-memory-field')), 'Drives a Grand Highlander');
    await tester.tap(find.byKey(const Key('w3-memory-save')));
    await _settle(tester);
    expect(find.text('Drives a Grand Highlander'), findsOneWidget);
    expect(find.textContaining('Edited by you'), findsWidgets);

    await tester.tap(find.byKey(const Key('w3-incognito')));
    await _settle(tester);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('w3-incognito')));
    expect(sw.value, isTrue);

    await tester.enterText(find.byKey(const Key('w3-memory-search')), 'backups');
    await _settle(tester);
    expect(find.textContaining('Nightly backups'), findsOneWidget);
    expect(find.textContaining('Lives in Springfield'), findsNothing);
  });

  testWidgets('approval rules: risk labels, expiry, add', (tester) async {
    _tall(tester);
    final state = HermesMobileAppState(DemoBackend(fast: true));
    await tester.pumpWidget(_wrap(state, const ApprovalRulesScreen()));
    await _settle(tester);
    expect(find.text('High risk'), findsOneWidget);
    expect(find.text('Medium risk'), findsOneWidget);
    expect(find.text('Never expires'), findsOneWidget);
    expect(find.textContaining('Expires in'), findsWidgets);

    await tester.tap(find.byKey(const Key('w3-rule-add')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('w3-rule-pattern')), 'rm -rf build');
    await tester.pump();
    expect(find.text('High risk'), findsWidgets);
    await tester.tap(find.byKey(const Key('w3-rule-save')));
    await _settle(tester);
    expect(find.text('rm -rf build'), findsOneWidget);
  });

  testWidgets('usage meter: set a budget and see the alert', (tester) async {
    _tall(tester);
    final state = HermesMobileAppState(DemoBackend(fast: true));
    await tester.pumpWidget(_wrap(state, const UsageMeterScreen()));
    await _settle(tester);
    expect(find.byKey(const Key('w3-mtd')), findsOneWidget);
    await tester.tap(find.byKey(const Key('w3-budget-edit')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('w3-budget-field')), '1');
    await tester.tap(find.byKey(const Key('w3-budget-save')));
    await _settle(tester);
    expect(find.byKey(const Key('w3-budget-alert')), findsOneWidget);
    expect(find.textContaining('Over budget'), findsOneWidget);
    final b = await UsageBudget.load();
    expect(b.monthlyUsd, 1);
  });

  testWidgets('live run: steps, files, commands, pause and steer', (
    tester,
  ) async {
    _tall(tester);
    final backend = DemoBackend(fast: true);
    final state = HermesMobileAppState(backend);
    final ctl = ChatController(backend: backend, chatId: 'r1', isNew: true);
    // Waits on an approval, so the run stays live.
    final turn = ctl.send('deploy the fix');
    await tester.pumpWidget(_wrap(state, LiveRunScreen(controller: ctl)));
    await _settle(tester);
    expect(ctl.running, isTrue);
    expect(find.text('Live run'), findsOneWidget);
    expect(find.text('Files changed'), findsOneWidget);
    expect(find.text('scripts/panels_publish.sh'), findsWidgets);
    expect(find.text('Commands'), findsOneWidget);
    expect(find.textContaining('journalctl'), findsWidgets);

    await tester.tap(find.byKey(const Key('w3-pause')));
    await _settle(tester);
    await turn;
    expect(ctl.running, isFalse);
    expect(find.byKey(const Key('w3-resume')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('w3-run-status'))).data,
      'Paused',
    );

    await tester.tap(find.byKey(const Key('w3-steer')));
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('w3-steer-field')), 'use rsync instead');
    await tester.tap(find.byKey(const Key('w3-steer-send')));
    await _settle(tester);
    final lastUser = ctl.messages.lastWhere((m) => m.isUser);
    expect(lastUser.text, contains('use rsync instead'));
    await _settle(tester);
    ctl.dispose();
  });

  testWidgets('settings section lists the wave 3 tools', (tester) async {
    _tall(tester);
    final state = HermesMobileAppState(DemoBackend(fast: true));
    await tester.pumpWidget(
      _wrap(state, const Scaffold(body: SingleChildScrollView(child: Wave3SettingsSection()))),
    );
    await _settle(tester);
    expect(find.text('Control and trust'), findsOneWidget);
    expect(find.text('Cron studio'), findsOneWidget);
    expect(find.text('Approval rules'), findsOneWidget);
    expect(find.byType(LiveRunBar), findsNothing);
  });
}
