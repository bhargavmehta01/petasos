import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/services/android_share_intent_service.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'w1_attachments.dart';
import 'w1_schedule.dart';
import 'w1_schedule_card.dart';
import 'w1_services.dart';

/// What launched or re-entered the app: a launcher shortcut, the Quick
/// Settings tile, a home-screen widget, or a share.
enum QuickCaptureMode { ask, remind, watch, voice, brief, needsYou, share }

class HermesMobileLaunchRequest {
  const HermesMobileLaunchRequest(this.mode, {this.share});
  final QuickCaptureMode mode;
  final AndroidSharePayload? share;

  /// Maps the native launch action string (MainActivity.launchActionFor).
  static QuickCaptureMode? modeFor(String? action) => switch (action) {
    'quickChat' || 'hermes_mobile:ask' => QuickCaptureMode.ask,
    'hermes_mobile:remind' => QuickCaptureMode.remind,
    'hermes_mobile:watch' => QuickCaptureMode.watch,
    'hermes_mobile:voice' => QuickCaptureMode.voice,
    'hermes_mobile:brief' => QuickCaptureMode.brief,
    'hermes_mobile:needs' => QuickCaptureMode.needsYou,
    _ => null,
  };
}

/// Listens on the engine's launch and share channels (the Petasos root owns
/// them; the classic app's services are not running).
class HermesMobileLaunchBridge {
  HermesMobileLaunchBridge._();
  static final HermesMobileLaunchBridge shared = HermesMobileLaunchBridge._();

  static const _launch = MethodChannel('com.hermesagent.hermes_android/launch');
  final AndroidShareIntentService _share = AndroidShareIntentService();
  final StreamController<HermesMobileLaunchRequest> _out =
      StreamController<HermesMobileLaunchRequest>.broadcast();
  final List<HermesMobileLaunchRequest> _pending = [];
  bool _started = false;
  int _listeners = 0;

  Stream<HermesMobileLaunchRequest> get requests => _out.stream;

  /// Requests that arrived before anyone listened (cold start).
  List<HermesMobileLaunchRequest> takePending() {
    final list = List.of(_pending);
    _pending.clear();
    return list;
  }

  void _emit(HermesMobileLaunchRequest r) {
    if (_listeners == 0) {
      _pending.add(r);
    } else {
      _out.add(r);
    }
  }

  StreamSubscription<HermesMobileLaunchRequest> listen(
    void Function(HermesMobileLaunchRequest) onRequest,
  ) {
    _listeners++;
    final sub = _out.stream.listen(onRequest);
    for (final r in takePending()) {
      onRequest(r);
    }
    return sub;
  }

  void unlisten() => _listeners = (_listeners - 1).clamp(0, 1 << 20);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _launch.setMethodCallHandler((call) async {
      if (call.method != 'launchAction') return;
      final mode = HermesMobileLaunchRequest.modeFor(call.arguments as String?);
      if (mode != null) _emit(HermesMobileLaunchRequest(mode));
    });
    try {
      final mode = HermesMobileLaunchRequest.modeFor(
        await _launch.invokeMethod<String>('getInitialLaunchAction'),
      );
      if (mode != null) _emit(HermesMobileLaunchRequest(mode));
    } on MissingPluginException {
      // Not Android.
    } on PlatformException {
      // A launcher failure must never block startup.
    }
    _share.pendingShare.addListener(() {
      final payload = _share.takePendingShare();
      if (payload != null) {
        _emit(HermesMobileLaunchRequest(QuickCaptureMode.share, share: payload));
      }
    });
    await _share.initialize();
  }
}

/// Prompt templates for shared content.
class SharePrompt {
  const SharePrompt(this.label, this.icon, this.build);
  final String label;
  final IconData icon;
  final String Function(String shared) build;

  static final all = <SharePrompt>[
    SharePrompt('Ask about this', Icons.chat_bubble_outline_rounded, (s) => s),
    SharePrompt('Summarize', Icons.short_text_rounded, (s) => 'Summarize this:\n\n$s'),
    SharePrompt(
      'Remind me',
      Icons.alarm_rounded,
      (s) => 'Remind me tomorrow at 9am about this: $s',
    ),
    SharePrompt(
      'Watch this',
      Icons.visibility_outlined,
      (s) => 'Every 6 hours check this and tell me if it changes: $s',
    ),
    SharePrompt('Remember', Icons.bookmark_add_outlined, (s) => 'Remember this for later: $s'),
  ];
}

String _presetFor(QuickCaptureMode mode) => switch (mode) {
  QuickCaptureMode.remind => 'Remind me to ',
  QuickCaptureMode.watch => 'Every 6 hours check ',
  _ => '',
};

String _titleFor(QuickCaptureMode mode) => switch (mode) {
  QuickCaptureMode.remind => 'Remind me…',
  QuickCaptureMode.watch => 'Watch this…',
  QuickCaptureMode.share => 'Send to Hermes',
  QuickCaptureMode.voice => 'Ask Hermes',
  _ => 'Ask Hermes',
};

/// Quick capture sheet. Sends into a new chat, or previews a schedule.
/// Resolves to the chat to open.
Future<HermesMobileChat?> showQuickCapture(
  BuildContext context,
  HermesMobileLaunchRequest request,
) async {
  final state = HermesMobileScope.read(context);
  final result = await showModalBottomSheet<_CaptureResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _QuickCaptureSheet(request: request),
  );
  if (result == null || !context.mounted) return null;
  final text = result.text.trim();
  if (text.isEmpty && result.imageDataUrl == null) return null;
  final intent = result.imageDataUrl == null ? parseScheduleIntent(text) : null;
  if (intent != null) {
    final choice = await showSchedulePreview(
      context,
      intent: intent,
      backend: state.backend,
      originalText: text,
    );
    if (choice == SchedulePreviewChoice.created) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scheduled: ${intent.human}')),
        );
      }
      return null;
    }
    if (choice != SchedulePreviewChoice.sendAsMessage) return null;
  }
  final ctl = state.newChat();
  unawaited(ctl.send(text, imageDataUrl: result.imageDataUrl));
  return HermesMobileChat(id: ctl.chatId, title: ctl.title);
}

class _CaptureResult {
  const _CaptureResult(this.text, this.imageDataUrl);
  final String text;
  final String? imageDataUrl;
}

class _QuickCaptureSheet extends StatefulWidget {
  const _QuickCaptureSheet({required this.request});
  final HermesMobileLaunchRequest request;

  @override
  State<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends State<_QuickCaptureSheet> {
  late final _text = TextEditingController(text: _presetFor(widget.request.mode));
  int _prompt = 0;
  bool _preparing = false;
  String? _image;
  final List<W1Attachment> _files = [];
  String? _error;
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  String get _shared => widget.request.share?.text ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.request.share != null) {
      _text.text = _shared;
      unawaited(_loadFiles());
    }
    if (widget.request.mode == QuickCaptureMode.voice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleVoice());
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ok || !mounted) return;
      final before = _text.text.isEmpty ? '' : '${_text.text.trimRight()} ';
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (r) {
          _text.text = before + r.recognizedWords;
          _text.selection = TextSelection.collapsed(offset: _text.text.length);
        },
        listenOptions: SpeechListenOptions(partialResults: true),
      );
    } catch (_) {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final files = widget.request.share?.files ?? const [];
    if (files.isEmpty) return;
    setState(() => _preparing = true);
    final backend = HermesMobileScope.read(context).backend;
    for (final f in files.take(5)) {
      try {
        final bytes = await File(f.path).readAsBytes();
        final a = await W1Attachment.fromBytes(
          f.name,
          bytes,
          upload: (n, b) => Wave1Services.of(backend).source.upload(n, b),
        );
        if (a.kind == W1AttachmentKind.image) {
          _image ??= a.dataUrl;
        } else {
          _files.add(a);
        }
      } on W1AttachmentError catch (e) {
        _error = e.message;
      } catch (_) {
        _error = 'Could not read ${f.name}.';
      }
    }
    if (mounted) setState(() => _preparing = false);
  }

  void _pickPrompt(int i) {
    setState(() {
      _prompt = i;
      _text.text = SharePrompt.all[i].build(_shared);
    });
  }

  void _send() {
    HapticFeedback.lightImpact();
    Navigator.pop(
      context,
      _CaptureResult(W1Attachment.compose(_text.text, _files), _image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final share = widget.request.share;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _titleFor(widget.request.mode),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (share != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: SharePrompt.all.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ChoiceChip(
                    avatar: Icon(SharePrompt.all[i].icon, size: 16),
                    label: Text(SharePrompt.all[i].label),
                    selected: _prompt == i,
                    onSelected: (_) => _pickPrompt(i),
                  ),
                ),
              ),
              if (_image != null || _files.isNotEmpty || _preparing) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    if (_image != null)
                      const Chip(
                        avatar: Icon(Icons.image_outlined, size: 16),
                        label: Text('Image'),
                      ),
                    for (final f in _files)
                      Chip(
                        avatar: const Icon(Icons.insert_drive_file_outlined, size: 16),
                        label: Text(f.name),
                      ),
                    if (_preparing) const Chip(label: Text('Preparing…')),
                  ],
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _listening
                    ? 'Listening…'
                    : widget.request.mode == QuickCaptureMode.remind
                    ? 'Remind me to … tomorrow at 9am'
                    : 'Ask anything',
                suffixIcon: IconButton(
                  tooltip: _listening ? 'Stop dictation' : 'Dictate',
                  icon: Icon(
                    _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  ),
                  onPressed: _toggleVoice,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _preparing ? null : _send,
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              label: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}
