import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/hermes_mobile/chat/chat_controller.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/panels.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_attachments.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_controller.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_models.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_notifications.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_services.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_widgets_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('models', () {
    test('ProactiveCard.fromJson reads the plugin shape', () {
      final c = ProactiveCard.fromJson({
        'id': 'brief:j1:x.md',
        'kind': 'brief',
        'period': 'evening',
        'title': 'Evening recap',
        'body': 'All good',
        'created_at': 1762180000.5,
        'read': true,
        'action': {'kind': 'run', 'label': 'Run again', 'payload': {'cron_id': 'j2'}},
      });
      expect(c.isBrief, isTrue);
      expect(c.period, 'evening');
      expect(c.read, isTrue);
      expect(c.action!.kind, ProactiveActionKind.run);
      expect(c.action!.payload['cron_id'], 'j2');
      expect(ProactiveAction.fromJson({'kind': 'explode'}), isNull);
    });

    test('HermesMobilePrompt.fromControl parses batch clarify, sudo and secret', () {
      final q = HermesMobilePrompt.fromControl('c', {
        'hermes_mobile_control': 'clarify.request',
        'request_id': 'r1',
        'run_id': 'run1',
        'execution_generation': 3,
        'questions': [
          {'qid': 'q1', 'question': 'Which one?', 'choices': ['A', {'label': 'B'}]},
        ],
      })!;
      expect(q.kind, HermesMobilePromptKind.clarify);
      expect(q.questionId, 'q1');
      expect(q.choices, ['A', 'B']);
      expect(q.executionGeneration, 3);
      expect(q.isSensitive, isFalse);
      final s = HermesMobilePrompt.fromControl('c', {'hermes_mobile_control': 'sudo.request', 'request_id': 'r2'})!;
      expect(s.kind, HermesMobilePromptKind.sudo);
      expect(s.isSensitive, isTrue);
      final k = HermesMobilePrompt.fromControl('c', {
        'hermes_mobile_control': 'secret.request',
        'request_id': 'r3',
        'env_var': 'GITHUB_TOKEN',
      })!;
      expect(k.title, 'GITHUB_TOKEN');
      expect(HermesMobilePrompt.fromControl('c', {'hermes_mobile_control': 'clarify.request'}), isNull);
      expect(HermesMobilePrompt.fromControl('c', {'text': 'Thinking'}), isNull);
    });
  });

  group('notify policy', () {
    const p = NotifyPolicy(quietStart: 22, quietEnd: 7, muted: {'price watch'});
    test('quiet hours wrap past midnight', () {
      expect(p.isQuiet(DateTime(2026, 11, 3, 23)), isTrue);
      expect(p.isQuiet(DateTime(2026, 11, 3, 6, 59)), isTrue);
      expect(p.isQuiet(DateTime(2026, 11, 3, 7)), isFalse);
      expect(p.isQuiet(DateTime(2026, 11, 3, 15)), isFalse);
    });
    test('mute and blocking approvals', () {
      final night = DateTime(2026, 11, 3, 23);
      final day = DateTime(2026, 11, 3, 12);
      expect(p.shouldNotify('Price Watch', day), isFalse);
      expect(p.shouldNotify('cron', day), isTrue);
      expect(p.shouldNotify('cron', night), isFalse);
      expect(p.shouldNotify('approvals', night, blocking: true), isTrue);
      expect(p.copyWith(enabled: false).shouldNotify('cron', day), isFalse);
    });
  });

  test('notification intents: approval actions, inline reply, turn taps', () {
    final a = Wave1NotificationIntent.parse(
      jsonEncode({'hermes_mobile': 'w1', 'type': 'approval', 'chatId': 'c1'}),
      actionId: 'hermes_mobile_allow',
    )!;
    expect(a.type, 'approval');
    expect(a.action, 'allow');
    final r = Wave1NotificationIntent.parse(
      jsonEncode({'hermes_mobile': 'w1', 'type': 'card', 'cardId': 'x'}),
      actionId: 'hermes_mobile_reply',
      input: 'yes please',
    )!;
    expect(r.action, 'reply');
    expect(r.input, 'yes please');
    final t = Wave1NotificationIntent.parse(jsonEncode({'sessionId': 's9'}))!;
    expect(t.type, 'turn');
    expect(t.chatId, 's9');
    expect(Wave1NotificationIntent.parse('plain-turn-id'), isNull);
    expect(Wave1Notifier.idFor('a'), Wave1Notifier.idFor('a'));
    expect(Wave1Notifier.idFor('a'), isNot(Wave1Notifier.idFor('b')));
  });

  group('attachments', () {
    test('text files inline, binaries upload, missing plugin explains', () async {
      final t = await W1Attachment.fromBytes(
        'notes.md',
        Uint8List.fromList(utf8.encode('# Hi\n')),
      );
      expect(t.kind, W1AttachmentKind.text);
      expect(W1Attachment.compose('Read this', [t]), contains('```markdown\n# Hi\n```'));
      final pdf = await W1Attachment.fromBytes(
        'lab.pdf',
        Uint8List.fromList([37, 80, 68, 70, 0, 1]),
        upload: (n, b) async => '/home/h/.hermes/hermes_mobile/uploads/$n',
      );
      expect(pdf.kind, W1AttachmentKind.file);
      expect(pdf.toMessagePart(), contains('/home/h/.hermes/hermes_mobile/uploads/lab.pdf'));
      expect(
        () => W1Attachment.fromBytes('a.zip', Uint8List.fromList([0, 1, 2])),
        throwsA(isA<W1AttachmentError>()),
      );
      final img = await W1Attachment.fromBytes('p.png', Uint8List.fromList([1, 2]));
      expect(img.dataUrl, startsWith('data:image/png;base64,'));
    });
  });

  test('widget snapshot picks latest brief, top card and pinned panel', () {
    final now = DateTime(2026, 11, 3, 8, 5);
    final snap = HermesMobileWidgetBridge.snapshot(
      briefs: [
        ProactiveCard(id: 'a', title: 'Old', body: 'x', kind: 'brief', createdAt: DateTime(2026, 11, 2)),
        ProactiveCard(id: 'b', title: 'Good morning', body: '**Calendar**: 2 things', kind: 'brief', createdAt: now),
      ],
      feed: [ProactiveCard(id: 'c', title: 'Approve cart', createdAt: now)],
      needsYou: 2,
      panels: PanelsResult(panels: [
        HermesMobilePanel.tryParse({'id': 'p1', 'title': 'Spend', 'kind': 'stat', 'value': 12}),
        HermesMobilePanel.tryParse({'id': 'p2', 'title': 'Weather', 'kind': 'stat', 'value': '64', 'unit': '°F'}),
      ].whereType<HermesMobilePanel>().toList()),
      pinnedPanelId: 'p2',
      now: now,
    );
    expect(snap[HermesMobileWidgetBridge.kBriefTitle], 'Good morning');
    expect(snap[HermesMobileWidgetBridge.kBriefBody], 'Calendar: 2 things');
    expect(snap[HermesMobileWidgetBridge.kNeedsYou], 2);
    expect(snap[HermesMobileWidgetBridge.kNeedsTop], 'Approve cart');
    expect(snap[HermesMobileWidgetBridge.kPanelTitle], 'Weather');
    expect(snap[HermesMobileWidgetBridge.kPanelValue], '64 °F');
    expect(snap[HermesMobileWidgetBridge.kUpdated], '08:05');
  });

  group('live plumbing', () {
    test('answerPromptLive posts to the run control endpoint', () async {
      final calls = <String, Map<String, dynamic>>{};
      final p = HermesMobilePrompt.fromControl('c', {
        'hermes_mobile_control': 'clarify.request',
        'request_id': 'r1',
        'run_id': 'run 1',
      })!;
      await answerPromptLive(
        (e) async => {'execution_generation': 4},
        (e, b) async {
          calls[e] = b;
          return {};
        },
        p,
        'Family',
      );
      expect(calls.keys.single, 'v1/runs/run%201/clarify');
      expect(calls.values.single, {'request_id': 'r1', 'execution_generation': 4, 'answer': 'Family'});
    });

    test('without the plugin, briefs come from cron runs', () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime(2026, 11, 3, 9);
      final at = DateTime(2026, 11, 3, 7).millisecondsSinceEpoch / 1000;
      final src = PluginProactiveSource(
        (e) async => throw const DashboardHttpException(404),
        (e, b) async => {},
        fallback: () => cronFallbackCards(
          () async => [
            {'id': 'j1', 'name': 'Morning brief', 'last_status': 'ok'},
            {'id': 'j2', 'name': 'Backups', 'last_status': 'error', 'last_error': 'jq missing'},
            {'id': 'j3', 'name': 'Price watch', 'last_status': 'ok'},
          ],
          (id) async => [(id: 'cron_${id}_1', at: at)],
          (sid) async => [
            {'role': 'user', 'content': 'go'},
            {'role': 'assistant', 'content': 'Two meetings today.'},
          ],
          now: now,
        ),
      );
      final feed = await src.load();
      expect(feed.available, isTrue);
      expect(feed.pluginMissing, isTrue);
      final brief = feed.cards.singleWhere((c) => c.isBrief);
      expect(brief.body, 'Two meetings today.');
      expect(brief.period, 'morning');
      final alert = feed.cards.singleWhere((c) => c.kind == 'alert');
      expect(alert.body, 'jq missing');
      // Dismiss is kept on the phone.
      await src.dismiss(brief.id);
      expect((await src.load()).cards.where((c) => c.isBrief), isEmpty);
      expect(() => src.feedback(alert, true), throwsStateError);
    });

    test('plugin source reports a missing plugin as unavailable', () async {
      final src = PluginProactiveSource(
        (e) async => throw const DashboardHttpException(404),
        (e, b) async => {},
      );
      final feed = await src.load();
      expect(feed.available, isFalse);
      final ok = PluginProactiveSource(
        (e) async => {
          'cards': [
            {'id': '1', 'title': 'Hi', 'created_at': 1},
          ],
        },
        (e, b) async => {},
      );
      expect((await ok.load()).cards.single.title, 'Hi');
    });
  });

  group('prompts through ChatController (demo)', () {
    test('sudo prompt blocks the run until answered', () async {
      final backend = DemoBackend(fast: true);
      final ctl = ChatController(backend: backend, chatId: 'p1', isNew: true);
      final done = ctl.send('sudo restart nginx');
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(ctl.prompt, isNotNull);
      expect(ctl.prompt!.kind, HermesMobilePromptKind.sudo);
      expect(ctl.running, isTrue);
      await ctl.answerPrompt('hunter2');
      await done;
      expect(ctl.prompt, isNull);
      expect(ctl.running, isFalse);
      expect(ctl.messages.last.text, contains('did not store'));
      expect(ctl.messages.last.text, isNot(contains('hunter2')));
    });

    test('clarify answer reaches the agent', () async {
      final ctl = ChatController(backend: DemoBackend(fast: true), chatId: 'p2', isNew: true);
      final done = ctl.send('which calendar for the party?');
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(ctl.prompt!.choices, ['Family', 'Work', 'Both']);
      await ctl.answerPrompt('Family');
      await done;
      expect(ctl.messages.last.text, contains('Got it: **Family**'));
    });
  });
}
