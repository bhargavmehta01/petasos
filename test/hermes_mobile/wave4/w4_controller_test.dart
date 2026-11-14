import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/app_state.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_api.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_controller.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demo backend whose health and sends can be made to fail like a phone
/// that lost its connection.
class _FlakyBackend extends DemoBackend {
  _FlakyBackend() : super(fast: true);
  bool offline = false;
  final List<String> sent = [];

  @override
  Future<bool> checkHealth() async => !offline;

  @override
  Future<void> send({
    required String chatId,
    required String text,
    required List<Map<String, dynamic>> history,
    String? imageDataUrl,
    required callbacks,
  }) async {
    if (offline) {
      callbacks.onError('ClientException: SocketException: Connection refused');
      return;
    }
    sent.add(text);
    return super.send(
      chatId: chatId,
      text: text,
      history: history,
      imageDataUrl: imageDataUrl,
      callbacks: callbacks,
    );
  }
}

Future<(HermesMobileAppState, Wave4Controller, DemoWave4Api)> _make({
  DemoBackendFactory? backend,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final app = HermesMobileAppState(backend?.call() ?? DemoBackend(fast: true));
  final api = DemoWave4Api();
  final w4 = Wave4Controller(app, api: api, preferences: prefs);
  app.wave4 = w4;
  return (app, w4, api);
}

typedef DemoBackendFactory = DemoBackend Function();

void main() {
  test('start loads watchers, commitments, recap and the dial', () async {
    final (app, w4, _) = await _make();
    w4.recapSince = DateTime.now().subtract(const Duration(days: 2));
    await w4.start();
    expect(w4.pluginChecked, isTrue);
    expect(w4.watchers, hasLength(4));
    expect(w4.watchersNeedingYou, 2);
    expect(w4.commitments.length, greaterThanOrEqualTo(3));
    expect(w4.recap, isNotEmpty);
    expect(w4.level, ProactivityLevel.balanced);
    // Demo asks repeat "Braves Fest ticket price" three times.
    expect(w4.proposal, isNotNull);
    expect(w4.proposal!.topic.toLowerCase(), contains('braves'));
    app.dispose();
  });

  test('watchers: create, pause, check and delete', () async {
    final (app, w4, _) = await _make();
    await w4.refreshWatchers();
    await w4.createWatcher(title: 'Fox Theatre lottery', target: 'foxtheatre.org');
    expect(w4.watchers.first.title, 'Fox Theatre lottery');
    expect(w4.watchers.first.status, WatcherStatus.pending);
    await w4.togglePaused(w4.watchers.first);
    expect(w4.watchers.first.paused, isTrue);
    await w4.togglePaused(w4.watchers.first);
    await w4.checkNow(w4.watchers.first);
    expect(w4.watchers.first.status, WatcherStatus.ok);
    await w4.deleteWatcher(w4.watchers.first);
    expect(w4.watchers.any((w) => w.title == 'Fox Theatre lottery'), isFalse);
    app.dispose();
  });

  test('quiet dial hides watcher proposals and syncs as a rule', () async {
    final (app, w4, api) = await _make();
    await w4.refreshWatchers();
    expect(w4.proposal, isNotNull);
    final ok = await w4.setLevel(ProactivityLevel.quiet);
    expect(ok, isTrue);
    expect(w4.levelSynced, isTrue);
    expect(w4.proposal, isNull);
    expect(await api.proactivity(), ProactivityLevel.quiet);
    // Without the plugin the dial is saved on the phone only.
    api.available = false;
    expect(await w4.setLevel(ProactivityLevel.chatty), isFalse);
    expect(w4.levelSynced, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(Wave4Controller.kLevel), 'chatty');
    app.dispose();
  });

  test('commitments: done state persists and sorts last', () async {
    final (app, w4, _) = await _make();
    await w4.refreshCommitments();
    final first = w4.commitments.first;
    await w4.setCommitmentDone(first, true);
    expect(w4.commitments.last.id, first.id);
    expect(w4.commitments.last.done, isTrue);
    await w4.refreshCommitments();
    expect(w4.commitments.firstWhere((c) => c.id == first.id).done, isTrue);
    app.dispose();
  });

  test('commitments are extracted from chats open on the phone', () async {
    final (app, w4, _) = await _make();
    final ctl = app.controllerFor(const HermesMobileChat(id: 'x1', title: 'Errands', isDraft: true));
    ctl.messages.add(
      HermesMobileMessage(role: HermesMobileRole.user, text: 'Remind me to renew the car tag tomorrow.'),
    );
    app.chats = [const HermesMobileChat(id: 'x1', title: 'Errands')];
    await w4.refreshCommitments();
    final found = w4.commitments.where((c) => c.chatId == 'x1').toList();
    expect(found, hasLength(1));
    expect(found.single.text, 'Renew the car tag tomorrow');
    expect(found.single.owner, CommitmentOwner.user);
    app.dispose();
  });

  test('undo window: runs after the window, or never when undone', () async {
    final (app, w4, _) = await _make();
    await w4.setUndoWindow(const Duration(milliseconds: 60));
    var ran = 0;
    final t1 = w4.hold('Send email', () async => ran++);
    expect(w4.tickets, hasLength(1));
    expect(await t1.result, isTrue);
    expect(ran, 1);
    expect(w4.tickets, isEmpty);

    final t2 = w4.hold('Send email', () async => ran++);
    w4.undo(t2);
    expect(await t2.result, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ran, 1);

    await w4.setUndoWindow(Duration.zero);
    final t3 = w4.hold('Send', () async => ran++);
    expect(await t3.result, isTrue);
    expect(ran, 2);
    app.dispose();
  });

  test('held outbound: undo removes it', () async {
    final (app, w4, api) = await _make();
    api.simulateOutbound('Email the landlord');
    await w4.refreshHeld();
    expect(w4.held, hasLength(1));
    expect(await w4.undoHeld(w4.held.first), isTrue);
    expect(w4.held, isEmpty);
    app.dispose();
  });

  test('recap revert marks the action reverted', () async {
    final (app, w4, _) = await _make();
    w4.recapSince = DateTime.now().subtract(const Duration(days: 2));
    await w4.refreshRecap();
    final revertible = w4.recap.firstWhere((a) => a.revertible);
    expect(await w4.revert(revertible), isTrue);
    expect(w4.recap.firstWhere((a) => a.id == revertible.id).reverted, isTrue);
    final fixed = w4.recap.firstWhere((a) => !a.revertible);
    expect(await w4.revert(fixed), isFalse);
    expect(w4.showRecap(DateTime.now()), isTrue);
    await w4.markRecapSeen();
    expect(w4.showRecap(DateTime.now()), isFalse);
    app.dispose();
  });

  test('offline: a failed send moves to the queue and flushes on reconnect', () async {
    final backend = _FlakyBackend();
    final (app, w4, _) = await _make(backend: () => backend);
    final ctl = app.controllerFor(const HermesMobileChat(id: 'c1', title: 'Chat', isDraft: true));
    backend.offline = true;
    await ctl.send('Book the garden tickets');
    expect(ctl.error, isNotNull);
    expect(await w4.captureFailedSend(ctl, 'Book the garden tickets', null), isTrue);
    expect(ctl.messages, isEmpty);
    expect(ctl.error, isNull);
    expect(w4.queue, hasLength(1));
    expect(w4.online, isFalse);
    // Still offline: nothing is sent.
    expect(await w4.checkOnline(), isFalse);
    expect(w4.queue, hasLength(1));
    // Back online: the queue drains into the same chat.
    backend.offline = false;
    expect(await w4.checkOnline(), isTrue);
    expect(w4.queue, isEmpty);
    expect(backend.sent, ['Book the garden tickets']);
    expect(ctl.messages.first.text, 'Book the garden tickets');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(Wave4Controller.kQueue), '[]');
    app.dispose();
  });

  test('a non-network failure is not queued', () async {
    final (app, w4, _) = await _make();
    final ctl = app.controllerFor(const HermesMobileChat(id: 'c2', title: 'Chat', isDraft: true));
    ctl.error = 'HTTP 401';
    expect(await w4.captureFailedSend(ctl, 'hi', null), isFalse);
    expect(w4.queue, isEmpty);
    app.dispose();
  });

  test('context triggers: opt-in, cooldown and the night window', () async {
    final (app, w4, api) = await _make();
    final night = DateTime(2026, 11, 3, 22, 30);
    // Off by default.
    expect(await w4.onSignal(ContextTriggerKind.chargingAtNight, now: night), isNull);
    final t = w4.triggers.firstWhere((x) => x.kind == ContextTriggerKind.chargingAtNight);
    await w4.updateTrigger(t.copyWith(enabled: true));
    // Daytime plug-in does nothing.
    expect(
      await w4.onSignal(ContextTriggerKind.chargingAtNight, now: DateTime(2026, 11, 3, 14)),
      isNull,
    );
    final id = await w4.onSignal(ContextTriggerKind.chargingAtNight, now: night);
    expect(id, isNotNull);
    expect(api.fired, hasLength(1));
    expect(app.controllerById(id!)!.messages.first.text,
        ContextTriggerKind.chargingAtNight.defaultPrompt);
    // Cooldown.
    expect(
      await w4.onSignal(
        ContextTriggerKind.chargingAtNight,
        now: night.add(const Duration(minutes: 5)),
      ),
      isNull,
    );
    // Car Bluetooth matches the configured name.
    final car = w4.triggers.firstWhere((x) => x.kind == ContextTriggerKind.carBluetooth);
    await w4.updateTrigger(car.copyWith(enabled: true, param: 'Grand Highlander'));
    expect(await w4.onSignal(ContextTriggerKind.carBluetooth, param: 'JBL Flip'), isNull);
    expect(
      await w4.onSignal(ContextTriggerKind.carBluetooth, param: 'Toyota Grand Highlander'),
      isNotNull,
    );
    // Settings persist.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(Wave4Controller.kTriggers), contains('car_bluetooth'));
    // Let the started runs settle before tearing down.
    for (var i = 0; i < 50 && app.runningChats.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    app.dispose();
  });

  test('glance summarises for small surfaces', () async {
    final (app, w4, _) = await _make();
    await w4.refreshWatchers();
    await w4.refreshCommitments();
    final g = w4.glance(DateTime.now());
    expect(g.watchersChanged, 2);
    expect(g.headline, contains('Sony'));
    expect(g.toJson()['watchers_changed'], 2);
    app.dispose();
  });

  group('LiveWave4Api', () {
    test('uses plugin routes when the plugin answers', () async {
      final calls = <String>[];
      final api = LiveWave4Api(
        backend: DemoBackend(fast: true),
        call: (method, path, [body]) async {
          calls.add('$method $path');
          if (path == 'status') return {'ok': true, 'features': ['watchers']};
          if (path == 'watchers') {
            return {
              'watchers': [
                {'id': 'p1', 'title': 'Plugin watcher', 'status': 'changed'},
              ],
            };
          }
          if (path.startsWith('recap')) {
            return {
              'actions': [
                {'id': 'r1', 'summary': 'Sent digest', 'at': 1762180000, 'revertible': true},
              ],
            };
          }
          if (path == 'proactivity' && method == 'PUT') return {'ok': true};
          return {};
        },
      );
      expect(await api.probe(), isTrue);
      final ws = await api.watchers();
      expect(ws.single.title, 'Plugin watcher');
      final recap = await api.recap(DateTime(2020));
      expect(recap.single.revertible, isTrue);
      expect(await api.setProactivity(ProactivityLevel.quiet), isTrue);
      expect(calls, contains('PUT proactivity'));
      expect(calls.where((c) => c == 'GET status'), hasLength(1));
    });

    test('falls back to "Watch:" cron jobs without the plugin', () async {
      final backend = DemoBackend(fast: true);
      final api = LiveWave4Api(
        backend: backend,
        call: (method, path, [body]) async => throw Exception('HTTP 404'),
      );
      expect(await api.probe(), isFalse);
      expect(await api.watchers(), isEmpty);
      await api.createWatcher(
        title: 'XM6 price',
        target: 'bestbuy.com/xm6',
        condition: r'below $300',
      );
      final jobs = await backend.listCron();
      final job = jobs.firstWhere((j) => j.name == 'Watch: XM6 price');
      expect(job.prompt, contains('bestbuy.com/xm6'));
      expect(job.prompt, contains(r'below $300'));
      final ws = await api.watchers();
      expect(ws.single.title, 'XM6 price');
      expect(ws.single.target, 'bestbuy.com/xm6');
      expect(await api.commitments(), isEmpty);
      expect(await api.setProactivity(ProactivityLevel.quiet), isFalse);
    });
  });
}
