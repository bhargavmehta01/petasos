import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/chat/chat_controller.dart';
import 'package:hermes_android/hermes_mobile/data/app_state.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_api.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_branches.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_canvas.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_composer_assist.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_message_actions.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_search.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_settings.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_theme.dart';
import 'package:hermes_android/hermes_mobile/features/wave2_parity/w2_voice.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scripted speech for voice-loop tests.
class FakeVoiceIO implements W2VoiceIO {
  void Function(String, bool)? _onResult;
  final spoken = <String>[];
  bool _listening = false;
  bool _speaking = false;
  int listens = 0;
  int stops = 0;
  bool holdSpeech = false;
  Completer<void>? _speech;

  void say(String words, {bool isFinal = true}) => _onResult?.call(words, isFinal);

  @override
  Future<bool> init() async => true;
  @override
  bool get listening => _listening;
  @override
  bool get speaking => _speaking;
  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    void Function(double level)? onLevel,
  }) async {
    listens++;
    _listening = true;
    _onResult = onResult;
  }

  @override
  Future<void> stopListening() async => _listening = false;
  @override
  Future<void> speak(String text) async {
    _speaking = true;
    spoken.add(text);
    if (holdSpeech) {
      _speech = Completer<void>();
      await _speech!.future;
    } else {
      await Future<void>.delayed(Duration.zero);
    }
    _speaking = false;
  }

  @override
  Future<void> stopSpeaking() async {
    stops++;
    _speaking = false;
    if (_speech?.isCompleted == false) _speech!.complete();
  }
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue);
}

ChatController _ctl([String id = 'c1']) =>
    ChatController(backend: DemoBackend(fast: true), chatId: id, isNew: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    W2Settings.forPrefs(await SharedPreferences.getInstance());
  });

  group('branches', () {
    test('edit and resend keeps both versions with arrows', () async {
      final ctl = _ctl();
      await ctl.send('Plan our Springfield weekend');
      final firstReply = ctl.messages.last.text;
      expect(ctl.branchInfo(0), isNull);

      await ctl.editAndResend(0, 'Order milk from costco');
      expect(ctl.messages, hasLength(2));
      expect(ctl.messages.first.text, 'Order milk from costco');
      expect(ctl.messages.last.text, contains('cart'));
      expect(ctl.branchInfo(0), (2, 2));

      ctl.switchBranch(0, -1);
      expect(ctl.branchInfo(0), (1, 2));
      expect(ctl.messages.first.text, 'Plan our Springfield weekend');
      expect(ctl.messages.last.text, firstReply);
      expect(ctl.runs[ctl.messages.last], isNotNull);

      ctl.switchBranch(0, 1);
      expect(ctl.messages.first.text, 'Order milk from costco');
    });

    test('regenerate branches the reply and nested branches survive', () async {
      final ctl = _ctl();
      await ctl.send('hello');
      await ctl.send('fix the cron');
      await ctl.regenerate(3);
      expect(ctl.branchInfo(2), (2, 2));
      expect(ctl.messages, hasLength(4));
      // Branch the first turn; the nested branch moves with its variant.
      await ctl.editAndResend(0, 'hi there');
      expect(ctl.messages, hasLength(2));
      expect(ctl.branchInfo(2), isNull);
      ctl.switchBranch(0, -1);
      expect(ctl.messages, hasLength(4));
      expect(ctl.branchInfo(2), (2, 2));
    });

    test('undo removes the last exchange', () async {
      final ctl = _ctl();
      await ctl.send('one');
      await ctl.send('two');
      expect(ctl.undoLast(), isTrue);
      expect(ctl.messages, hasLength(2));
      expect(ctl.messages.first.text, 'one');
    });

    test('fork copies the transcript into a new draft chat', () async {
      final state = HermesMobileAppState(DemoBackend(fast: true));
      final src = state.newChat();
      src.w2Preamble = 'Project rules';
      await src.send('first question');
      await src.send('second question');
      final fork = state.forkChat(src, 1);
      expect(fork.chatId, isNot(src.chatId));
      expect(fork.messages.map((m) => m.text).first, 'first question');
      expect(fork.messages, hasLength(2));
      expect(fork.w2Preamble, 'Project rules');
      expect(state.current, same(fork));
    });
  });

  group('settings and theme', () {
    test('pins, stars and pinned messages persist', () async {
      final s = W2Settings.current;
      await s.togglePinned('demo://hermes', 'a');
      await s.togglePinned('demo://hermes', 'b');
      expect(s.pinnedChats('demo://hermes'), ['b', 'a']);
      await s.toggleStarred('demo://hermes', 'a');
      expect(s.isStarred('demo://hermes', 'a'), isTrue);
      await s.toggleMessagePin(W2PinnedMessage(
        chatId: 'c1',
        chatTitle: 'Chat',
        text: 'Remember this',
        fromUser: false,
        pinnedAt: DateTime(2026, 11, 3),
      ));
      expect(s.isMessagePinned('c1', 'Remember this'), isTrue);
      expect(s.allPinnedMessages().single.chatTitle, 'Chat');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('hermes_mobile.w2.pins.demo___hermes'), ['b', 'a']);
    });

    test('AMOLED, accent and dynamic color shape the colors', () async {
      final s = W2Settings.current;
      await s.setAmoled(true);
      await s.setAccent(0xFF0F8B8D);
      final dark = w2Colors(Brightness.dark, s);
      expect(dark.background, Colors.black);
      final light = w2Colors(Brightness.light, s);
      expect(light.accent, const Color(0xFF0F8B8D));
      expect(light.background, HermesMobileColors.light.background);
      await s.setDynamicColor(true);
      final dyn = w2Colors(
        Brightness.light,
        s,
        dynamicAccents: const W2DynamicAccents(
          light: Color(0xFF8E4585),
          dark: Color(0xFFFFADF0),
        ),
      );
      expect(dyn.accent, const Color(0xFF8E4585));
      expect(w2Theme(Brightness.dark, s).scaffoldBackgroundColor, Colors.black);
    });

    test('text scale is clamped', () async {
      await W2Settings.current.setTextScale(3);
      expect(W2Settings.current.textScale, 1.4);
    });
  });

  group('canvas', () {
    test('picks code, then table, then the whole doc', () {
      final code = W2CanvasDoc.fromMessage(DemoBackend.codeReply);
      expect(code.kind, W2CanvasKind.code);
      expect(code.language, 'bash');
      code.text = 'echo hi';
      expect(code.toMessage(), contains('```bash\necho hi\n```'));

      final table = W2CanvasDoc.fromMessage(DemoBackend.sampleReply);
      expect(table.kind, W2CanvasKind.table);
      table.rows.first[2] = r'$40';
      expect(table.tableMarkdown(), contains(r'| $40 |'));
      expect(table.tableMarkdown().split('\n')[1], '|---|---|---|');

      final doc = W2CanvasDoc.fromMessage('Just **words** here.');
      expect(doc.kind, W2CanvasKind.doc);
    });
  });

  group('composer assist', () {
    test('token at cursor and slash suggestions', () {
      final t = w2TokenAtCursor(const TextEditingValue(
        text: 'ask @bro',
        selection: TextSelection.collapsed(offset: 8),
      ));
      expect(t!.text, '@bro');
      expect(t.start, 4);
      final s = w2SlashSuggestions('mo', const []);
      expect(s.first.insert, '/model ');
      final skills = w2SlashSuggestions('git', const [HermesMobileSkill(name: 'github')]);
      expect(skills.single.insert, '/github ');
    });

    test('mentions cover skills, projects and chats', () {
      final m = w2MentionSuggestions(
        'home',
        skills: const [HermesMobileSkill(name: 'home-panels')],
        projects: const [HermesMobileProject(id: 'p', name: 'Home lab')],
        chats: const [HermesMobileChat(id: 'c9', title: 'Home EV charger')],
      );
      expect(m.map((s) => s.insert), [
        '@skill:home-panels ',
        '@project:Home-lab ',
        '@chat:c9 ',
      ]);
      final ctl = TextEditingController(text: 'look @ho');
      ctl.selection = const TextSelection.collapsed(offset: 8);
      w2ApplySuggestion(ctl, w2TokenAtCursor(ctl.value)!, m.first.insert);
      expect(ctl.text, 'look @skill:home-panels ');
    });
  });

  group('api', () {
    test('parses the engine model catalog', () {
      final choices = LiveWave2Api.parseChoices({
        'providers': [
          {'slug': 'openrouter', 'models': ['qwen3', {'id': 'kimi-k2'}]},
          {'id': 'anthropic', 'models': [{'model': 'claude-sonnet-4.5'}]},
          {'models': ['orphan']},
        ],
      });
      expect(choices.map((c) => '${c.provider}/${c.model}'), [
        'openrouter/qwen3',
        'openrouter/kimi-k2',
        'anthropic/claude-sonnet-4.5',
      ]);
    });

    test('plugin health must list wave 2', () {
      expect(w2PluginHasWave2({'plugin': 'hermes_mobile', 'features': ['w2.projects']}), isTrue);
      expect(w2PluginHasWave2({'plugin': 'hermes_mobile', 'features': ['w1.feed']}), isFalse);
      expect(w2PluginHasWave2({}), isFalse);
    });

    test('demo api switches model, profile and keeps instructions', () async {
      final api = DemoBackend(fast: true).wave2;
      final s = await api.modelState('c1');
      expect(s.current, DemoWave2Api.demoChoices.first);
      await api.setModel('c1', DemoWave2Api.demoChoices[1], 'high');
      final s2 = await api.modelState('c1');
      expect(s2.current!.model, 'claude-sonnet-4.5');
      expect(s2.effort, 'high');
      await api.switchProfile('coder');
      expect((await api.profiles()).firstWhere((p) => p.active).id, 'coder');
      await api.saveProjectInstructions('p-home', 'Be careful with prod');
      final d = await api.projectDetails(const HermesMobileProject(id: 'p-home', name: 'Home lab'));
      expect(d.instructions, 'Be careful with prod');
      expect(d.files, isNotEmpty);
      expect(await api.createPanel(title: 't', text: 'x'), isTrue);
    });

    test('reminder choices are one-shot schedules', () {
      final c = w2ReminderChoices(DateTime(2026, 11, 3, 10));
      expect(c.first.$2, '30m');
      expect(c.last.$2, '2026-11-04T09:00:00');
      expect(c.any((x) => x.$1.startsWith('Tonight')), isTrue);
    });
  });

  group('search', () {
    test('finds chats, tasks, memory and skills; filters narrow it', () async {
      final state = HermesMobileAppState(DemoBackend(fast: true));
      await state.refreshChats();
      final all = await w2SearchAll(state, 'backup', W2SearchFilter.all);
      final kinds = all.map((h) => h.kind).toSet();
      expect(kinds, containsAll([W2SearchKind.chat, W2SearchKind.task, W2SearchKind.memory]));
      final tasks = await w2SearchAll(state, 'backup', W2SearchFilter.tasks);
      expect(tasks.every((h) => h.kind == W2SearchKind.task), isTrue);
      await W2Settings.current.toggleStarred('demo://hermes', 'demo-cron');
      final starred = await w2SearchAll(state, '', W2SearchFilter.starred);
      expect(starred.single.chatId, 'demo-cron');
    });
  });

  group('voice', () {
    test('speakable text drops code, tables and links', () {
      final t = w2SpeakableText(DemoBackend.sampleReply);
      expect(t, isNot(contains('|')));
      expect(t, isNot(contains('http')));
      expect(t, contains('Springfield weekend options'));
    });

    test('voice loop: listen, send, speak, listen again', () async {
      final io = FakeVoiceIO();
      final ctl = _ctl();
      final session = W2VoiceSession(ctl, io: io);
      await session.start();
      expect(session.phase, W2VoicePhase.listening);
      io.say('plan our springfield weekend');
      await _until(() => io.spoken.isNotEmpty && session.phase == W2VoicePhase.listening);
      expect(ctl.messages.first.text, 'plan our springfield weekend');
      expect(io.spoken.single, contains('Springfield weekend options'));
      expect(session.phase, W2VoicePhase.listening);
      expect(io.listens, greaterThanOrEqualTo(2));
      await session.close();
    });

    test('barge-in: talking over the reply stops it', () async {
      final io = FakeVoiceIO()..holdSpeech = true;
      final session = W2VoiceSession(_ctl(), io: io);
      await session.start();
      io.say('plan our springfield weekend');
      await _until(() => session.phase == W2VoicePhase.speaking);
      io.say('ok', isFinal: false); // too short to count
      expect(io.stops, 0);
      io.say('wait, what about sunday', isFinal: false);
      await _until(() => io.stops > 0);
      expect(session.phase, W2VoicePhase.listening);
      expect(session.heard, 'wait, what about sunday');
      await session.close();
    });

    test('tapping the orb interrupts speech', () async {
      final io = FakeVoiceIO();
      final session = W2VoiceSession(_ctl(), io: io)..phase = W2VoicePhase.speaking;
      await session.tapOrb();
      expect(io.stops, 1);
      expect(session.phase, W2VoicePhase.listening);
      await session.close();
    });
  });
}
