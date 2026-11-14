import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../features/wave1_proactive/w1_attachments.dart'; // wave1
import '../theme/hermes_mobile_theme.dart';

/// Rounded composer: + for a photo, mic for dictation, send / stop.
class HermesMobileComposer extends StatefulWidget {
  const HermesMobileComposer({
    super.key,
    required this.running,
    required this.onSend,
    required this.onStop,
    this.enabled = true,
    this.hint = 'Message Hermes',
    this.onUploadFile, // wave1
    // --- wave2 ---
    this.controller,
    this.w2Above,
    this.w2Accessory,
    // --- end wave2 ---
  });

  /// --- wave1 --- Uploads a non-text file to the host (Petasos plugin);
  /// null hides binary uploads (text files and images still attach).
  final W1Uploader? onUploadFile;

  // --- wave2 ---
  /// Optional external text controller (slash commands, @mentions).
  final TextEditingController? controller;

  /// Shown above the field (suggestion strip, model chip).
  final Widget Function(TextEditingController text)? w2Above;

  /// Shown beside the mic while the field is empty (voice mode button).
  final Widget? w2Accessory;
  // --- end wave2 ---

  final bool running;
  final bool enabled;
  final String hint;
  final void Function(String text, String? imageDataUrl) onSend;
  final VoidCallback onStop;

  @override
  State<HermesMobileComposer> createState() => _HermesMobileComposerState();
}

class _HermesMobileComposerState extends State<HermesMobileComposer> {
  // --- wave2 --- external controller support
  late final TextEditingController _text =
      widget.controller ?? TextEditingController();
  // --- end wave2 ---
  final _focus = FocusNode();
  final _speech = SpeechToText();
  bool _listening = false;
  String _beforeDictation = '';
  String? _image;
  String? _imageName;
  final List<W1Attachment> _files = []; // wave1
  bool _attaching = false; // wave1

  bool get _canSend =>
      widget.enabled &&
      !_attaching &&
      (_text.text.trim().isNotEmpty || _image != null || _files.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _speech.cancel();
    if (widget.controller == null) _text.dispose(); // --- wave2 ---
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    if (!_canSend) return;
    HapticFeedback.lightImpact();
    if (_listening) _stopDictation();
    widget.onSend(W1Attachment.compose(_text.text, _files), _image); // wave1
    _text.clear();
    setState(() {
      _image = null;
      _imageName = null;
      _files.clear(); // wave1
    });
  }

  Future<void> _pick(ImageSource source) async {
    Navigator.of(context).pop();
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        _snack('That image is too large (max 8 MB).');
        return;
      }
      final mime = file.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      setState(() {
        _image = 'data:$mime;base64,${base64Encode(bytes)}';
        _imageName = file.name;
      });
    } catch (e) {
      _snack('Could not attach the image.');
    }
  }

  // --- wave1 ---
  Future<void> _pickFile() async {
    Navigator.of(context).pop();
    try {
      final picked = await pickAnyFile();
      if (picked == null) return;
      setState(() => _attaching = true);
      final a = await W1Attachment.fromBytes(
        picked.name,
        picked.bytes,
        upload: widget.onUploadFile,
      );
      if (!mounted) return;
      setState(() {
        if (a.kind == W1AttachmentKind.image && _image == null) {
          _image = a.dataUrl;
          _imageName = a.name;
        } else if (a.kind != W1AttachmentKind.image) {
          _files.add(a);
        }
      });
    } on W1AttachmentError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not attach the file.');
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }
  // --- end wave1 ---

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _attachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo library'),
              onTap: () => _pick(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => _pick(ImageSource.camera),
            ),
            ListTile( // wave1
              leading: const Icon(Icons.attach_file_rounded),
              title: const Text('File'),
              subtitle: const Text('Text, code, PDF, documents'),
              onTap: _pickFile,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleDictation() async {
    if (_listening) {
      _stopDictation();
      return;
    }
    HapticFeedback.selectionClick();
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
    if (!ok) {
      _snack('Speech recognition is not available on this phone.');
      return;
    }
    _beforeDictation = _text.text.isEmpty ? '' : '${_text.text.trimRight()} ';
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        _text.text = _beforeDictation + r.recognizedWords;
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
      },
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  void _stopDictation() {
    _speech.stop();
    setState(() => _listening = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.w2Above != null) widget.w2Above!(_text), // --- wave2 ---
            if (_image != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InputChip(
                    avatar: const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                      _imageName ?? 'Image',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: () => setState(() {
                      _image = null;
                      _imageName = null;
                    }),
                  ),
                ),
              ),
            // --- wave1 ---
            if (_files.isNotEmpty || _attaching)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final f in _files)
                        InputChip(
                          avatar: Icon(
                            f.kind == W1AttachmentKind.text
                                ? Icons.description_outlined
                                : Icons.insert_drive_file_outlined,
                            size: 18,
                          ),
                          label: Text(
                            '${f.name} · ${f.sizeLabel}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => setState(() => _files.remove(f)),
                        ),
                      if (_attaching)
                        const Chip(
                          avatar: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          label: Text('Attaching…'),
                        ),
                    ],
                  ),
                ),
              ),
            // --- end wave1 ---
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(HermesMobileRadius.field),
                border: Border.all(
                  color: _focus.hasFocus ? c.accent.withValues(alpha: 0.5) : c.hairline,
                ),
                boxShadow: hermesMobileShadow(context),
              ),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    onPressed: widget.enabled ? _attachSheet : null,
                    icon: Icon(Icons.add_rounded, color: c.textSecondary),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: _listening ? 'Listening…' : widget.hint,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  // --- wave2 ---
                  if (widget.w2Accessory != null &&
                      !widget.running &&
                      _text.text.trim().isEmpty &&
                      _image == null &&
                      _files.isEmpty)
                    widget.w2Accessory!,
                  // --- end wave2 ---
                  if (!widget.running && _text.text.trim().isEmpty && _image == null && _files.isEmpty)
                    IconButton(
                      tooltip: _listening ? 'Stop dictation' : 'Dictate',
                      onPressed: widget.enabled ? _toggleDictation : null,
                      icon: Icon(
                        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _listening ? c.danger : c.textSecondary,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: widget.running
                          ? _RoundButton(
                              key: const ValueKey('stop'),
                              icon: Icons.stop_rounded,
                              color: c.text,
                              iconColor: c.background,
                              tooltip: 'Stop',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                widget.onStop();
                              },
                            )
                          : _RoundButton(
                              key: const ValueKey('send'),
                              icon: Icons.arrow_upward_rounded,
                              color: _canSend ? c.accent : c.surfaceMuted,
                              iconColor: _canSend ? c.onAccent : c.textTertiary,
                              tooltip: 'Send',
                              onTap: _canSend ? _send : null,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.tooltip,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
      ),
    );
  }
}
