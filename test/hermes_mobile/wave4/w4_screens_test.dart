import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/app_state.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_chat.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_home.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_settings.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_watchers.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_api.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_controller.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_models.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(HermesMobileAppState, Wave4Controller, DemoWave4Api)> _ready() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final app = HermesMobileAppState(DemoBackend(fast: true));
  final api = DemoWave4Api();
  final w4 = Wave4Controller(app, api: api, preferences: prefs);
  w4.recapSince = DateTime.now().subtract(const Duration(days: 2));
  app.wave4 = w4;
  await w4.start();
  return (app, w4, api);
}

Widget _host(HermesMobileAppState app, Widget child) => HermesMobileScope(
  state: app,
  child: MaterialApp(
    theme: hermesMobileTheme(Brightness.light),
    home: Scaffold(body: child),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Home section: recap with revert, watchers, promises', (tester) async {
    final (app, w4, _) = await tester.runAsync(_ready) as (HermesMobileAppState, Wave4Controller, DemoWave4Api);
    await tester.pumpWidget(
      _host(
        app,
        ListView(children: [Wave4HomeSection(onOpenChat: (_) {})]),
      ),
    );
    await _settle(tester);
    expect(find.text('Autopilot'), findsOneWidget);
    expect(find.textContaining('done on autopilot'), findsOneWidget);
    expect(find.text('Archived 23 promo emails'), findsOneWidget);
    expect(find.text('Revert'), findsWidgets);
    expect(find.textContaining('Watch "'), findsOneWidget);
    expect(find.text('Watching'), findsOneWidget);
    expect(find.text('Promised'), findsOneWidget);

    await tester.tap(find.text('Revert').first);
    await _settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Revert').last);
    await _settle(tester);
    expect(find.text('Reverted'), findsWidgets);

    // Quiet dial trims Home to what needs the user.
    await tester.runAsync(() => w4.setLevel(ProactivityLevel.quiet));
    await _settle(tester);
    expect(find.textContaining('Watch "'), findsNothing);
    app.dispose();
  });

  testWidgets('Urgent slot: held outbound with Undo, then the offline queue', (tester) async {
    final (app, w4, api) = await tester.runAsync(_ready) as (HermesMobileAppState, Wave4Controller, DemoWave4Api);
    api.simulateOutbound('Email the landlord');
    await tester.runAsync(w4.refreshHeld);
    await tester.pumpWidget(
      _host(
        app,
        ListView(
          children: [Wave4HomeSection(onOpenChat: (_) {}, urgentOnly: true)],
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Going out'), findsOneWidget);
    expect(find.text('Email the landlord'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(find.text('Email the landlord'), findsNothing);
    expect(find.text('Stopped. Nothing was sent.'), findsOneWidget);
    app.dispose();
  });

  testWidgets('Watchers screen lists status cards and creates one', (tester) async {
    final (app, _, _) = await tester.runAsync(_ready) as (HermesMobileAppState, Wave4Controller, DemoWave4Api);
    await tester.pumpWidget(_host(app, const WatchersScreen()));
    await _settle(tester);
    expect(find.text('Sony WH-1000XM6 price'), findsOneWidget);
    expect(find.text('Changed'), findsOneWidget);
    await tester.tap(find.text('Watch something'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Fox lottery');
    await tester.enterText(
      find.widgetWithText(TextField, 'What to look at'),
      'foxtheatre.org/lottery',
    );
    await tester.tap(find.text('Start watching'));
    await _settle(tester);
    expect(find.text('Fox lottery'), findsOneWidget);
    app.dispose();
  });

  testWidgets('Settings group, dial and triggers screen', (tester) async {
    final (app, w4, _) = await tester.runAsync(_ready) as (HermesMobileAppState, Wave4Controller, DemoWave4Api);
    await tester.pumpWidget(
      _host(app, ListView(children: const [Wave4SettingsGroup()])),
    );
    await _settle(tester);
    expect(find.text('Proactivity'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('0 on'), findsOneWidget);

    await tester.tap(find.text('Proactivity'));
    await _settle(tester);
    await tester.tap(find.text('Chatty'));
    await _settle(tester);
    expect(w4.level, ProactivityLevel.chatty);
    expect(find.text('Hermes has this as a standing rule.'), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);

    await tester.tap(find.text('Context triggers'));
    await _settle(tester);
    expect(find.text('Arrive home'), findsOneWidget);
    expect(find.text('Charging at night'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(2));
    await _settle(tester);
    expect(
      w4.triggers.firstWhere((t) => t.kind == ContextTriggerKind.chargingAtNight).enabled,
      isTrue,
    );
    expect(find.text('Test now'), findsOneWidget);
    app.dispose();
  });

  testWidgets('Provenance chips under a sourced reply', (tester) async {
    final (app, _, _) = await tester.runAsync(_ready) as (HermesMobileAppState, Wave4Controller, DemoWave4Api);
    final msg = HermesMobileMessage(
      role: HermesMobileRole.assistant,
      text: DemoBackend.sampleReply,
      toolNames: const ['web_search'],
    );
    await tester.pumpWidget(_host(app, ProvenanceChips(message: msg)));
    await _settle(tester);
    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('3 sources'), findsOneWidget);
    await tester.tap(find.text('3 sources'));
    await _settle(tester);
    expect(find.text('Where this answer came from'), findsOneWidget);
    app.dispose();
  });

  testWidgets('Queued banner in chat and undo bar for an outbound card action', (tester) async {
    final (app, w4, _) = await tester.runAsync(_ready) as (HermesMobileAppState, Wave4Controller, DemoWave4Api);
    final ctl = app.controllerFor(const HermesMobileChat(id: 'q1', title: 'Chat', isDraft: true));
    await tester.runAsync(() => w4.enqueue(ctl, 'Send the rent reminder', null));
    final sent = <String>[];
    await tester.pumpWidget(
      _host(
        app,
        Builder(
          builder: (context) => Column(
            children: [
              const QueuedInChat(chatId: 'q1'),
              TextButton(
                onPressed: () => Wave4ChatHooks.cardActionWithUndo(
                  context,
                  'Approve and order',
                  sent.add,
                ),
                child: const Text('card'),
              ),
              TextButton(
                onPressed: () => Wave4ChatHooks.cardActionWithUndo(
                  context,
                  'Show me the list',
                  sent.add,
                ),
                child: const Text('local'),
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.textContaining('Queued: "Send the rent reminder"'), findsOneWidget);

    // Not outbound: goes straight through.
    await tester.tap(find.text('local'));
    await tester.pump();
    expect(sent, ['Show me the list']);

    // Outbound: waits for the undo window; Undo cancels it.
    await tester.tap(find.text('card'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Undo'), findsOneWidget);
    expect(w4.tickets, hasLength(1));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(w4.tickets, isEmpty);
    expect(sent, ['Show me the list']);
    // Dismiss the queued message.
    await tester.tap(find.byTooltip('Discard'));
    await _settle(tester);
    expect(find.textContaining('Queued:'), findsNothing);
    app.dispose();
  });
}
