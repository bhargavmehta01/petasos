import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/services/hands_free_speech.dart';
import '../../cards/blocks.dart';
import '../../chat/chat_controller.dart';
import '../../theme/hermes_mobile_theme.dart';
import 'w2_settings.dart';

/// Speech in and out. The device implementation uses the engine's TTS speaker
/// (chunked, interruptible) and the platform recognizer; tests inject a fake.
abstract class W2VoiceIO {
  Future<bool> init();
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    void Function(double level)? onLevel,
  });
  Future<void> stopListening();
  bool get listening;

  /// Completes when the text has been spoken or [stopSpeaking] was called.
  Future<void> speak(String text);
  Future<void> stopSpeaking();
  bool get speaking;

  static W2VoiceIO Function() factory = DeviceVoiceIO.new;
}

class DeviceVoiceIO implements W2VoiceIO {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  late final FlutterVoiceReplySpeaker _speaker = FlutterVoiceReplySpeaker(_tts);
  bool _ready = false;
  bool _speaking = false;
  int _generation = 0;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  @override
  bool get listening => _stt.isListening;

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
    void Function(double level)? onLevel,
  }) async {
    if (!await init()) return;
    await _stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Future<void> stopListening() => _stt.stop();

  @override
  bool get speaking => _speaking;

  @override
  Future<void> speak(String text) async {
    final gen = ++_generation;
    _speaking = true;
    try {
      await _tts.setSpeechRate(W2Settings.current.speechRate);
      await _speaker.speak(text, isCurrent: () => gen == _generation);
    } catch (_) {
    } finally {
      if (gen == _generation) _speaking = false;
    }
  }

  @override
  Future<void> stopSpeaking() async {
    _generation++;
    _speaking = false;
    try {
      await _speaker.stop();
    } catch (_) {}
  }
}

/// Text for speech: drop code, tables and cards; keep the prose.
String w2SpeakableText(String markdown) {
  final noCode = markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'^\|.*\|\s*$', multiLine: true), ' ')
      .replaceAll(RegExp(r'https?://\S+'), ' ')
      .replaceAll(RegExp(r'^MEDIA:.*$', multiLine: true), ' ');
  return replyPlainText(noCode).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// App-wide read-aloud for message actions and auto-read.
class W2ReadAloud extends ChangeNotifier {
  W2ReadAloud._();
  static final W2ReadAloud instance = W2ReadAloud._();

  W2VoiceIO? _io;
  W2VoiceIO get io => _io ??= W2VoiceIO.factory();
  String? speakingText;

  bool isSpeaking(String text) => speakingText == text;

  Future<void> speak(String markdown) async {
    if (speakingText == markdown) return stop();
    await stop();
    final text = w2SpeakableText(markdown);
    if (text.isEmpty) return;
    speakingText = markdown;
    notifyListeners();
    await io.speak(text);
    if (speakingText == markdown) {
      speakingText = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (speakingText == null) return;
    speakingText = null;
    notifyListeners();
    await io.stopSpeaking();
  }

  @visibleForTesting
  void reset() {
    _io = null;
    speakingText = null;
  }
}

enum W2VoicePhase { idle, listening, thinking, speaking }

/// Drives a live voice conversation over one chat. Separate from the widget so
/// tests can run the loop with a fake [W2VoiceIO].
class W2VoiceSession extends ChangeNotifier {
  W2VoiceSession(this.chat, {W2VoiceIO? io}) : io = io ?? W2VoiceIO.factory();

  final ChatController chat;
  final W2VoiceIO io;
  W2VoicePhase phase = W2VoicePhase.idle;
  String heard = '';
  String lastReply = '';
  double level = 0;
  bool holdToTalk = false;
  bool available = true;
  bool _closed = false;
  int _turn = 0;

  Future<void> start() async {
    available = await io.init();
    if (!available) {
      notifyListeners();
      return;
    }
    if (!holdToTalk) await _listen();
  }

  Future<void> _listen({bool bargeIn = false}) async {
    if (_closed) return;
    if (!bargeIn) {
      phase = W2VoicePhase.listening;
      heard = '';
    }
    notifyListeners();
    final turn = _turn;
    await io.listen(
      onLevel: (l) {
        level = l;
        notifyListeners();
      },
      onResult: (words, isFinal) {
        if (_closed || turn != _turn) return;
        if (phase == W2VoicePhase.speaking) {
          // Barge-in: the user started talking over the reply.
          if (words.trim().length < 3) return;
          unawaited(io.stopSpeaking());
          phase = W2VoicePhase.listening;
          W2Haptics.selection();
        }
        heard = words;
        notifyListeners();
        if (isFinal && !holdToTalk) unawaited(_submit());
      },
    );
  }

  Future<void> _submit() async {
    final text = heard.trim();
    if (text.isEmpty || chat.running) {
      if (!holdToTalk) await _listen();
      return;
    }
    _turn++;
    await io.stopListening();
    phase = W2VoicePhase.thinking;
    W2Haptics.light();
    notifyListeners();
    await chat.send(text);
    if (_closed) return;
    final reply = chat.messages.isEmpty ? '' : chat.messages.last.text;
    lastReply = reply;
    final speakable = w2SpeakableText(reply);
    if (speakable.isEmpty) {
      if (!holdToTalk) await _listen();
      return;
    }
    phase = W2VoicePhase.speaking;
    heard = '';
    notifyListeners();
    final turn = _turn;
    if (W2Settings.current.bargeIn && !holdToTalk) {
      unawaited(_listen(bargeIn: true));
    }
    await io.speak(speakable);
    if (_closed || turn != _turn) return;
    if (phase == W2VoicePhase.speaking) {
      phase = W2VoicePhase.idle;
      notifyListeners();
      if (!holdToTalk) {
        await io.stopListening();
        await _listen();
      }
    }
  }

  /// The big orb: interrupt speech, send what was heard, or stop the run.
  Future<void> tapOrb() async {
    W2Haptics.selection();
    switch (phase) {
      case W2VoicePhase.speaking:
        _turn++;
        await io.stopSpeaking();
        await io.stopListening();
        await _listen();
      case W2VoicePhase.listening:
        await _submit();
      case W2VoicePhase.thinking:
        await chat.stop();
      case W2VoicePhase.idle:
        await _listen();
    }
  }

  Future<void> holdStart() async {
    holdToTalk = true;
    _turn++;
    await io.stopSpeaking();
    await _listen();
  }

  Future<void> holdEnd() async {
    await io.stopListening();
    await _submit();
  }

  void setHoldToTalk(bool v) {
    holdToTalk = v;
    notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    _turn++;
    await io.stopListening();
    await io.stopSpeaking();
  }
}

/// Full-screen live voice conversation with barge-in.
class W2VoiceModeScreen extends StatefulWidget {
  const W2VoiceModeScreen({super.key, required this.chat, this.io});
  final ChatController chat;
  final W2VoiceIO? io;

  @override
  State<W2VoiceModeScreen> createState() => _W2VoiceModeScreenState();
}

class _W2VoiceModeScreenState extends State<W2VoiceModeScreen>
    with SingleTickerProviderStateMixin {
  late final W2VoiceSession session = W2VoiceSession(widget.chat, io: widget.io);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    unawaited(session.start());
  }

  @override
  void dispose() {
    unawaited(session.close());
    session.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String _label(W2VoicePhase p) => switch (p) {
    W2VoicePhase.listening => 'Listening…',
    W2VoicePhase.thinking => 'Thinking…',
    W2VoicePhase.speaking => 'Speaking. Talk or tap to interrupt',
    W2VoicePhase.idle => session.holdToTalk ? 'Hold the button and talk' : 'Tap to talk',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(widget.chat.title),
        leading: IconButton(
          tooltip: 'Close voice mode',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.available) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Speech recognition is not available on this phone.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final phase = session.phase;
          final caption = phase == W2VoicePhase.speaking ||
                  phase == W2VoicePhase.thinking
              ? w2SpeakableText(
                  widget.chat.messages.isEmpty ? '' : widget.chat.messages.last.text,
                )
              : session.heard;
          return SafeArea(
            child: Column(
              children: [
                const Spacer(),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final active = phase != W2VoicePhase.idle;
                    final lvl = (session.level.clamp(0, 10) / 10);
                    final scale = active
                        ? 1 + 0.06 * _pulse.value + 0.12 * lvl
                        : 1.0;
                    return GestureDetector(
                      onTap: session.holdToTalk ? null : session.tapOrb,
                      onLongPressStart: session.holdToTalk
                          ? (_) => session.holdStart()
                          : null,
                      onLongPressEnd: session.holdToTalk
                          ? (_) => session.holdEnd()
                          : null,
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          key: const ValueKey('w2-voice-orb'),
                          width: 168,
                          height: 168,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                c.accent,
                                Color.lerp(c.accent, c.background, 0.55)!,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: c.accent.withValues(alpha: 0.35),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            switch (phase) {
                              W2VoicePhase.listening => Icons.mic_rounded,
                              W2VoicePhase.thinking => Icons.more_horiz_rounded,
                              W2VoicePhase.speaking => Icons.graphic_eq_rounded,
                              W2VoicePhase.idle => Icons.mic_none_rounded,
                            },
                            size: 56,
                            color: c.onAccent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(_label(phase), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: SizedBox(
                    height: 120,
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FilterChip(
                        label: const Text('Hold to talk'),
                        selected: session.holdToTalk,
                        onSelected: (v) async {
                          session.setHoldToTalk(v);
                          if (v) {
                            await session.io.stopListening();
                            session.phase = W2VoicePhase.idle;
                          } else {
                            await session.tapOrb();
                          }
                        },
                      ),
                      IconButton.filledTonal(
                        tooltip: 'End voice mode',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.call_end_rounded, color: c.danger),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Composer accessory: tap for voice mode, press and hold to talk (sends on
/// release).
class W2VoiceButton extends StatefulWidget {
  const W2VoiceButton({super.key, required this.onOpenVoiceMode, required this.onHeld});
  final VoidCallback onOpenVoiceMode;
  final void Function(String text) onHeld;

  @override
  State<W2VoiceButton> createState() => _W2VoiceButtonState();
}

class _W2VoiceButtonState extends State<W2VoiceButton> {
  W2VoiceIO? _io;
  String _heard = '';
  bool _holding = false;

  Future<void> _start() async {
    final io = _io ??= W2VoiceIO.factory();
    if (!await io.init()) return;
    W2Haptics.medium();
    setState(() {
      _holding = true;
      _heard = '';
    });
    await io.listen(onResult: (w, _) => _heard = w);
  }

  Future<void> _end() async {
    if (!_holding) return;
    await _io?.stopListening();
    setState(() => _holding = false);
    // Let the recognizer flush the last words.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final text = _heard.trim();
    if (text.isNotEmpty) widget.onHeld(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Tooltip(
      message: 'Voice mode (hold to talk)',
      child: GestureDetector(
        onLongPressStart: (_) => _start(),
        onLongPressEnd: (_) => _end(),
        child: IconButton(
          key: const ValueKey('w2-voice-button'),
          onPressed: widget.onOpenVoiceMode,
          icon: Transform.rotate(
            angle: _holding ? math.pi / 32 : 0,
            child: Icon(
              Icons.graphic_eq_rounded,
              color: _holding ? c.danger : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
