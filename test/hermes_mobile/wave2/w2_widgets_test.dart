import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/app_state.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_canvas.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_chats_pane.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_projects.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_search.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_settings.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_settings_screen.dart';
import 'package:hermes_android/hermes_mobile/hermes_mobile_app.dart';
import 'package:hermes_android/hermes_mobile/screens/chat_view.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Widget _app(HermesMobileAppState state, Widget home) => MaterialApp(
  theme: hermesMobileTheme(Brightness.light),
  home: home,
  builder: (context, child) => HermesMobileScope(state: state, child: child!),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    W2Settings.forPrefs(await SharedPreferences.getInstance());
  });

  testWidgets('chat: model chip, action row, message actions and pinning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = HermesMobileAppState(DemoBackend(fast: true));
    final ctl = state.controllerFor(
      const HermesMobileChat(id: 'demo-research', title: 'EV'),
    );
    await tester.pumpWidget(
      _app(state, Scaffold(body: ChatView(controller: ctl))),
    );
    await _settle(tester);

    expect(find.text('deepseek-v4-flash'), findsOneWidget);
    expect(find.byTooltip('Regenerate'), findsOneWidget);
    expect(find.byTooltip('Read aloud'), findsOneWidget);
    expect(find.byKey(const ValueKey('w2-voice-button')), findsOneWidget);

    // Long-press selects text; the selection toolbar's More… opens actions.
    await tester.longPress(
      find.text('Compare level 2 chargers for the garage.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('More…'), findsOneWidget);
    await tester.tap(find.text('More…'));
    await tester.pumpAndSettle();
    expect(find.text('Edit and resend'), findsOneWidget);
    expect(find.text('Turn into reminder'), findsOneWidget);
    await tester.tap(find.text('Pin message'));
    await tester.pumpAndSettle();
    expect(
      W2Settings.current.isMessagePinned(
        'demo-research',
        'Compare level 2 chargers for the garage.',
      ),
      isTrue,
    );
    expect(find.byIcon(Icons.push_pin), findsWidgets);

    // Edit and resend makes a branch with arrows.
    // The pinned strip repeats the text at the top; the bubble is last.
    await tester.longPress(
      find.text('Compare level 2 chargers for the garage.').last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit and resend'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Plan our Springfield weekend',
    );
    await tester.tap(find.text('Resend'));
    await _settle(tester);
    expect(find.text('1 / 2'), findsNothing);
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous version'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('composer: slash suggestions and a local /undo', (tester) async {
    final state = HermesMobileAppState(DemoBackend(fast: true));
    final ctl = state.newChat();
    await tester.pumpWidget(
      _app(state, Scaffold(body: ChatView(controller: ctl))),
    );
    await _settle(tester, 2);
    final field = find.byType(TextField);
    await tester.enterText(field, '/mo');
    await tester.pump();
    expect(find.byKey(const ValueKey('w2-composer-assist')), findsOneWidget);
    expect(find.text('/model'), findsOneWidget);
    await tester.enterText(field, '@home');
    await _settle(tester, 2);
    expect(find.text('@home-panels'), findsOneWidget);

    await tester.enterText(field, 'hello there');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await _settle(tester, 2);
    expect(ctl.messages, hasLength(2));
    await tester.enterText(field, '/undo');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await _settle(tester, 2);
    expect(ctl.messages, isEmpty);
  });

  testWidgets('canvas edits a table and sends it back', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesMobileTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await openW2Canvas(
                context,
                W2CanvasDoc.fromMessage(DemoBackend.sampleReply),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Canvas · Table'), findsOneWidget);
    await tester.tap(find.text('Row'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('w2-canvas-send')));
    await tester.pumpAndSettle();
    expect(result, contains('Here is my edited table'));
    expect(result, contains('Braves Fest'));
  });

  testWidgets('appearance settings toggle AMOLED and haptics', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: hermesMobileTheme(Brightness.light),
        home: const W2AppearanceScreen(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('w2-amoled')));
    await tester.pump();
    expect(W2Settings.current.amoled, isTrue);
    await tester.tap(find.byKey(const ValueKey('w2-haptics')));
    await tester.pump();
    expect(W2Settings.current.haptics, isFalse);
  });

  testWidgets('search filters across sources', (tester) async {
    final state = HermesMobileAppState(DemoBackend(fast: true));
    await state.refreshChats();
    await tester.pumpWidget(_app(state, const W2SearchScreen()));
    await tester.enterText(
      find.byKey(const ValueKey('w2-search-field')),
      'backup',
    );
    await _settle(tester, 4);
    expect(find.text('Nightly backup check'), findsOneWidget);
    expect(find.text('Nightly backup audit'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tasks'));
    await _settle(tester, 4);
    expect(find.text('Nightly backup check'), findsOneWidget);
    expect(find.text('Nightly backup audit'), findsNothing);
  });

  testWidgets('project screen saves instructions and starts a project chat', (
    tester,
  ) async {
    final state = HermesMobileAppState(DemoBackend(fast: true));
    HermesMobileChat? opened;
    const project = HermesMobileProject(
      id: 'p-hermes_mobile',
      name: 'Petasos app',
      path: '~/code/petasos',
    );
    await tester.pumpWidget(
      _app(
        state,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              opened = await Navigator.of(context).push<HermesMobileChat>(
                MaterialPageRoute(
                  builder: (_) => const W2ProjectScreen(project: project),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('WAVES.md'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('w2-project-instructions')),
      'Small fenced edits only.',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('w2-project-new-chat')));
    await _settle(tester, 2);
    expect(opened, isNotNull);
    final ctl = state.controllerById(opened!.id)!;
    expect(ctl.w2Preamble, contains('Small fenced edits only.'));
    expect(w2ProjectPreamble(project, ''), isEmpty);
  });

  testWidgets('two panes on a tablet, pinned chats first', (tester) async {
    SharedPreferences.setMockInitialValues({'hermes_mobile.demo': true});
    final prefs = await SharedPreferences.getInstance();
    final root = HermesMobileRootController(
      prefs: prefs,
      demoFactory: () => DemoBackend(fast: true),
    );
    await root.rebuild();
    await W2Settings.forPrefs(
      prefs,
    ).togglePinned('demo://hermes', 'demo-research');
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(HermesMobileBootstrap(controller: root));
    await _settle(tester);
    expect(find.byKey(const ValueKey('w2-chats-pane')), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Home EV charger research'), findsOneWidget);
    await tester.tap(find.text('Weekend plans'));
    await _settle(tester);
    expect(find.text('This weekend'), findsOneWidget);
    expect(kW2TwoPaneWidth, 840);
  });
}
