import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/chat/chat_controller.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/live_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/hermes_mobile_app.dart';
import 'package:hermes_android/hermes_mobile/widgets/run_widgets.dart';
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

/// Home and running chats show spinners, so pumpAndSettle would never end.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  group('ChatController with the demo backend', () {
    test('streams a reply with steps and settles the run', () async {
      final ctl = ChatController(
        backend: DemoBackend(fast: true),
        chatId: 'c1',
        isNew: true,
      );
      await ctl.send('Plan our Springfield weekend');
      expect(ctl.title, 'Plan our Springfield weekend');
      expect(ctl.messages, hasLength(2));
      final reply = ctl.messages.last;
      expect(reply.text, contains('Botanical Garden'));
      final run = ctl.runs[reply]!;
      expect(run.status, HermesMobileRunStatus.done);
      expect(run.steps, hasLength(2));
      expect(run.steps.every((s) => s.state == HermesMobileStepState.done), isTrue);
      expect(ctl.running, isFalse);
    });

    test('approval pauses the run until answered', () async {
      final approvals = <HermesMobileApproval?>[];
      final ctl = ChatController(
        backend: DemoBackend(fast: true),
        chatId: 'c2',
        isNew: true,
        onApprovalChanged: (_, a) => approvals.add(a),
      );
      final done = ctl.send('deploy the fix');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(ctl.approval, isNotNull);
      expect(ctl.approval!.choices, contains('always'));
      expect(ctl.running, isTrue);
      await ctl.answer('once');
      await done;
      expect(ctl.approval, isNull);
      expect(ctl.running, isFalse);
      expect(approvals.first, isNotNull);
      expect(approvals.last, isNull);
    });

    test('deny ends with the agent acknowledging', () async {
      final ctl = ChatController(
        backend: DemoBackend(fast: true),
        chatId: 'c3',
        isNew: true,
      );
      final done = ctl.send('delete old logs');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await ctl.answer('deny');
      await done;
      expect(ctl.messages.last.text, contains("won't restart"));
    });
  });

  test('LiveBackend.projectHistory folds tool rows into the reply', () {
    final msgs = LiveBackend.projectHistory([
      {'role': 'user', 'content': 'hi', 'timestamp': 1762180000},
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'function': {'name': 'web_search'},
          },
        ],
      },
      {'role': 'tool', 'content': '{"results": []}'},
      {'role': 'assistant', 'content': 'Found it.'},
    ]);
    expect(msgs, hasLength(2));
    expect(msgs.last.text, 'Found it.');
    expect(msgs.last.toolNames, ['web_search']);
  });

  test('LiveBackend.parseUsage reads dashboard totals', () {
    final u = LiveBackend.parseUsage({
      'totals': {
        'total_sessions': 12,
        'total_input': 1000,
        'total_output': 50,
        'total_estimated_cost': 1.5,
      },
      'by_model': [
        {'model': 'a', 'input_tokens': 10, 'output_tokens': 5},
        {'model': 'b', 'input_tokens': 100, 'output_tokens': 5},
      ],
    });
    expect(u.sessions, 12);
    expect(u.costUsd, 1.5);
    expect(u.topModels.first.key, 'b');
  });

  testWidgets('shell: chat, Home, drawer and approval card in demo mode', (
    tester,
  ) async {
    final root = await _demoRoot();
    await tester.pumpWidget(HermesMobileBootstrap(controller: root));
    await _settle(tester);

    // Chat is the main surface with a greeting for a new chat.
    expect(find.text('What can Hermes take off your plate?'), findsOneWidget);
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);

    // Send a message that needs approval.
    await tester.enterText(find.byType(TextField), 'deploy the fix');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ApprovalCard), findsOneWidget);
    expect(find.text('Hermes needs your OK'), findsOneWidget);
    expect(find.byType(TaskCard), findsOneWidget);

    // Home shows it under Needs you.
    await tester.tap(find.byTooltip('Home'));
    await _settle(tester);
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Panels'), findsOneWidget);
    expect(find.text('API spend · month'), findsOneWidget);

    // Back to the chat via Needs you, then approve.
    await tester.tap(find.text('Review'));
    await _settle(tester);
    await tester.tap(find.text('Allow once'));
    await _settle(tester);
    expect(find.byType(ApprovalCard), findsNothing);
    expect(find.textContaining('cron script failed'), findsOneWidget);

    // The drawer lists chats.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('deploy the fix'),
      ),
    );
    await _settle(tester);
    expect(find.text('New chat'), findsWidgets);
    expect(find.text('Weekend plans'), findsOneWidget);
    await tester.tap(find.text('Weekend plans'));
    await _settle(tester);
    expect(find.text('This weekend'), findsOneWidget);
  });
}
