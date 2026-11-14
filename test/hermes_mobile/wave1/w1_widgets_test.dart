import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_brief_screen.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_controller.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_prompt_cards.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_schedule_card.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_services.dart';
import 'package:hermes_android/hermes_mobile/hermes_mobile_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<HermesMobileRootController> _demoRoot() async {
  SharedPreferences.setMockInitialValues({'hermes_mobile.demo': true});
  final prefs = await SharedPreferences.getInstance();
  final root = HermesMobileRootController(
    prefs: prefs,
    demoFactory: () => DemoBackend(fast: true),
  );
  await root.rebuild();
  return root;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('Brief tab: digests, swipe dismiss, feedback, unread badge', (
    tester,
  ) async {
    final root = await _demoRoot();
    await tester.pumpWidget(HermesMobileBootstrap(controller: root));
    await _settle(tester);

    // The app bar shows the Brief button with an unread badge (6 demo cards).
    final button = find.byKey(const ValueKey('w1-brief-button'));
    expect(button, findsOneWidget);
    expect(find.byTooltip('Brief, 6 new'), findsOneWidget);

    await tester.tap(button);
    await _settle(tester);
    expect(find.text('Good morning: 3 things today'), findsOneWidget);
    expect(find.text('Evening recap: backups ok, 1 price drop'), findsOneWidget);

    // More like this → saved to memory.
    await tester.tap(find.byTooltip('More like this').first);
    await _settle(tester);
    expect(find.textContaining('Saved to memory'), findsOneWidget);

    // Swipe the morning brief away.
    await tester.drag(
      find.text('Good morning: 3 things today'),
      const Offset(-600, 0),
    );
    await _settle(tester);
    expect(find.text('Good morning: 3 things today'), findsNothing);

    // For you: one action per card, unread dots.
    await tester.tap(find.text('For you'));
    await _settle(tester);
    expect(find.text('Costco cart is ready: \$26.95'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot')), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Run again'), findsOneWidget);

    // Run again triggers the cron job and removes the card.
    await tester.tap(find.widgetWithText(FilledButton, 'Run again'));
    await _settle(tester);
    expect(find.text('Price watch failed'), findsNothing);

    // Approve sends the card's prompt in a new chat and returns to it.
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await _settle(tester);
    expect(find.byType(BriefScreen), findsNothing);
    expect(
      find.textContaining('Place the Costco same-day order'),
      findsWidgets,
    );
  });

  testWidgets('pending approvals show as feed cards and in Needs you', (
    tester,
  ) async {
    final root = await _demoRoot();
    await tester.pumpWidget(HermesMobileBootstrap(controller: root));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'deploy the fix');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    final feed = ProactiveController.of(root.state!);
    expect(feed.needsYou, greaterThanOrEqualTo(1));
    expect(feed.cards.first.kind, 'approval');
    expect(feed.cards.first.local, isTrue);
    await feed.act(feed.cards.first);
    await _settle(tester);
    expect(root.state!.pendingApprovals, isEmpty);
  });

  testWidgets('composer: schedule intent shows the cron preview and creates it', (
    tester,
  ) async {
    final root = await _demoRoot();
    await tester.pumpWidget(HermesMobileBootstrap(controller: root));
    await _settle(tester);
    await tester.enterText(
      find.byType(TextField),
      'Remind me to stretch every day at 3pm',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await _settle(tester);
    expect(find.byType(SchedulePreviewCard), findsOneWidget);
    expect(find.text('Every day at 3:00 PM'), findsOneWidget);
    expect(find.text('schedule: 0 15 * * *'), findsOneWidget);
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    expect(find.byType(SchedulePreviewCard), findsNothing);
    expect(find.textContaining('Scheduled **'), findsNothing); // rendered as markdown
    expect(find.textContaining('Every day at 3:00 PM'), findsWidgets);
    final jobs = await root.state!.backend.listCron();
    expect(jobs.any((j) => j.prompt == 'Send me a reminder: stretch'), isTrue);
  });

  testWidgets('composer: "Just send it" sends the text as a message', (
    tester,
  ) async {
    final root = await _demoRoot();
    await tester.pumpWidget(HermesMobileBootstrap(controller: root));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'every monday check the backups');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await _settle(tester);
    await tester.tap(find.text('Just send it'));
    await _settle(tester);
    expect(root.state!.current!.messages.first.text, 'every monday check the backups');
  });

  testWidgets('sudo prompt renders as a native card and answers', (tester) async {
    final root = await _demoRoot();
    await tester.pumpWidget(HermesMobileBootstrap(controller: root));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'sudo apt upgrade');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HermesMobilePromptCard), findsOneWidget);
    expect(find.text('Administrator password needed'), findsOneWidget);
    final field = find.descendant(
      of: find.byType(HermesMobilePromptCard),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    await tester.enterText(field, 'pw');
    await tester.tap(find.text('Send securely'));
    await _settle(tester);
    expect(find.byType(HermesMobilePromptCard), findsNothing);
    expect(find.textContaining('did not store'), findsOneWidget);
  });

  test('demo services are per backend', () {
    final b = DemoBackend(fast: true);
    expect(identical(Wave1Services.of(b), Wave1Services.of(b)), isTrue);
    expect(identical(Wave1Services.of(b), Wave1Services.of(DemoBackend())), isFalse);
  });
}
