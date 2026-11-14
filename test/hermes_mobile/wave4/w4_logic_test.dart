import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_extract.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_models.dart';

HermesMobileMessage _u(String t, [DateTime? at]) =>
    HermesMobileMessage(role: HermesMobileRole.user, text: t, createdAt: at);
HermesMobileMessage _a(String t, {DateTime? at, List<String> tools = const []}) =>
    HermesMobileMessage(role: HermesMobileRole.assistant, text: t, createdAt: at, toolNames: tools);

void main() {
  // Tuesday 2026-11-03 10:00.
  final now = DateTime(2026, 11, 3, 10);

  group('parseDue', () {
    test('relative words', () {
      expect(parseDue('by tonight', now), DateTime(2026, 11, 3, 20));
      expect(parseDue('tomorrow morning', now), DateTime(2026, 11, 4, 9));
      expect(parseDue('in 2 hours', now), now.add(const Duration(hours: 2)));
      expect(parseDue('in 3 days', now), now.add(const Duration(days: 3)));
      expect(parseDue('end of day', now), DateTime(2026, 11, 3, 17));
    });
    test('weekday is the next one, never today', () {
      expect(parseDue('on Friday', now), DateTime(2026, 11, 6, 9));
      expect(parseDue('Tuesday', now), DateTime(2026, 11, 10, 9));
    });
    test('no date', () => expect(parseDue('soon-ish', now), isNull));
  });

  group('extractCommitments', () {
    test('agent promises and user reminders, with due dates', () {
      final list = extractCommitments(
        [
          _u('Remind me to call the bank tomorrow.', now),
          _a(
            "Sure. I'll check the Delta fare again on Friday. "
            'Want me to also look at United?',
            at: now,
          ),
        ],
        chatId: 'c1',
        chatTitle: 'Flights',
        now: now,
      );
      expect(list, hasLength(2));
      final user = list.firstWhere((c) => c.owner == CommitmentOwner.user);
      expect(user.text, 'Call the bank tomorrow');
      expect(user.due, DateTime(2026, 11, 4, 9));
      final agent = list.firstWhere((c) => c.owner == CommitmentOwner.agent);
      expect(agent.text, contains('check the Delta fare'));
      expect(agent.due, DateTime(2026, 11, 6, 9));
      expect(agent.chatTitle, 'Flights');
    });

    test('skips offers, questions and code', () {
      final list = extractCommitments(
        [
          _a("I'll book it if you want."),
          _a('```\n# I will delete everything\n```'),
          _a("Shall I tell you more? I can do that."),
        ],
        chatId: 'c2',
        now: now,
      );
      expect(list, isEmpty);
    });

    test('ids are stable so done-state survives a rescan', () {
      List<HermesMobileCommitment> run() => extractCommitments(
        [_a("I'll follow up on the refund by Thursday.", at: now)],
        chatId: 'c3',
        now: now,
      );
      expect(run().single.id, run().single.id);
    });
  });

  group('proposeWatcher', () {
    test('three similar checking questions make a proposal', () {
      final p = proposeWatcher(const [
        MapEntry('a', 'What is the Sony XM6 price at Best Buy?'),
        MapEntry('b', 'Sony XM6 price again'),
        MapEntry('c', 'did the sony xm6 price drop'),
        MapEntry('d', 'Plan our weekend'),
      ]);
      expect(p, isNotNull);
      expect(p!.count, 3);
      expect(p.topic.toLowerCase(), contains('sony'));
      expect(p.topic.toLowerCase(), contains('price'));
      expect(p.chatIds.toSet(), {'a', 'b', 'c'});
    });

    test('needs a checking word and enough repeats', () {
      expect(
        proposeWatcher(const [
          MapEntry('a', 'Write a poem about Springfield'),
          MapEntry('b', 'Write a poem about Springfield rain'),
          MapEntry('c', 'Another poem about Springfield'),
        ]),
        isNull,
      );
      expect(
        proposeWatcher(const [
          MapEntry('a', 'Sony XM6 price'),
          MapEntry('b', 'Sony XM6 price again'),
        ]),
        isNull,
      );
    });

    test('dismissed topics stay dismissed', () {
      final asks = const [
        MapEntry('a', 'Sony XM6 price'),
        MapEntry('b', 'Sony XM6 price again'),
        MapEntry('c', 'Sony XM6 price now'),
      ];
      final p = proposeWatcher(asks)!;
      expect(
        proposeWatcher(asks, dismissed: {p.topic.toLowerCase()}),
        isNull,
      );
    });
  });

  group('provenanceOf', () {
    test('links and web tools give sources and high confidence', () {
      final p = provenanceOf(
        _a(
          'Prices:\n\nSources:\n- [Best Buy](https://bestbuy.com/x)\n'
          '- [Amazon](https://amazon.com/y)',
          tools: const ['web_search'],
        ),
      );
      expect(p.sources, hasLength(2));
      expect(p.confidence, ConfidenceLevel.high);
      expect(p.tools, ['web_search']);
    });

    test('explicit confidence line wins; hedges mean low', () {
      expect(
        provenanceOf(_a('It opens at 9.\n\nConfidence: medium')).confidence,
        ConfidenceLevel.medium,
      );
      expect(
        provenanceOf(_a("I'm not sure, but it probably opens at 9.")).confidence,
        ConfidenceLevel.low,
      );
      expect(provenanceOf(_a('Hello!')).isEmpty, isTrue);
      expect(provenanceOf(_u('hi')).isEmpty, isTrue);
    });

    test('memory tool marks the reply as from memory', () {
      final p = provenanceOf(_a('Your usual is oat milk.', tools: const ['memory']));
      expect(p.fromMemory, isTrue);
    });
  });

  test('isOfflineError tells network failures from agent failures', () {
    expect(isOfflineError('SocketException: Connection refused'), isTrue);
    expect(isOfflineError('ClientException: Failed host lookup: box'), isTrue);
    expect(isOfflineError('TimeoutException after 0:00:30'), isTrue);
    expect(isOfflineError('HTTP 401 Unauthorized'), isFalse);
    expect(isOfflineError('Model returned an error'), isFalse);
    expect(isOfflineError(null), isFalse);
  });

  test('isOutboundAction picks sends, posts and orders, not local commands', () {
    expect(isOutboundAction('Send the email to the landlord'), isTrue);
    expect(isOutboundAction('Approve and order'), isTrue);
    expect(isOutboundAction('Run it', command: 'gws gmail send --to a@b.c'), isTrue);
    expect(
      isOutboundAction(
        'Restart the gateway so the patched cron script loads.',
        command: 'sudo systemctl restart hermes-gateway',
      ),
      isFalse,
    );
    expect(isOutboundAction('Delete old logs', command: 'rm -rf /tmp/x'), isFalse);
  });

  test('dashboardSessionUrl', () {
    expect(
      dashboardSessionUrl('http://box:9119/', 'abc 1'),
      'http://box:9119/chat?resume=abc+1',
    );
    expect(dashboardSessionUrl('', 'x'), isNull);
    expect(dashboardSessionUrl(null, 'x'), isNull);
  });

  group('models round-trip', () {
    test('watcher', () {
      final w = HermesMobileWatcher.fromJson({
        'id': 'w1',
        'title': 'Price',
        'target': 'url',
        'status': 'changed',
        'last_value': r'$279',
        'last_checked': 1762180000,
        'history': ['a', 'b'],
      });
      expect(w.status, WatcherStatus.changed);
      expect(w.lastChecked, isNotNull);
      final again = HermesMobileWatcher.fromJson(w.toJson());
      expect(again.title, 'Price');
      expect(again.history, ['a', 'b']);
      expect(again.status, WatcherStatus.changed);
    });

    test('commitment, trigger and queued message', () {
      final c = HermesMobileCommitment.fromJson({
        'id': 'k',
        'text': 'Call',
        'owner': 'user',
        'due': '2026-11-04T14:00:00Z',
        'status': 'done',
      });
      expect(c.owner, CommitmentOwner.user);
      expect(c.done, isTrue);
      expect(HermesMobileCommitment.fromJson(c.toJson()).due, c.due);

      final t = ContextTrigger(
        kind: ContextTriggerKind.carBluetooth,
        enabled: true,
        param: 'Toyota',
      );
      final t2 = ContextTrigger.fromJson(t.toJson());
      expect(t2.kind, ContextTriggerKind.carBluetooth);
      expect(t2.enabled, isTrue);
      expect(t2.param, 'Toyota');
      expect(t2.effectivePrompt, ContextTriggerKind.carBluetooth.defaultPrompt);

      final q = QueuedMessage(
        id: 'q',
        chatId: 'c',
        text: 'hi',
        queuedAt: now,
      );
      expect(QueuedMessage.fromJson(q.toJson()).text, 'hi');
    });

    test('proactivity parse and rules', () {
      expect(ProactivityLevelX.parse('quiet'), ProactivityLevel.quiet);
      expect(ProactivityLevelX.parse('nonsense'), ProactivityLevel.balanced);
      for (final l in ProactivityLevel.values) {
        expect(l.rule, startsWith('Proactivity: ${l.name}'));
      }
    });
  });
}
