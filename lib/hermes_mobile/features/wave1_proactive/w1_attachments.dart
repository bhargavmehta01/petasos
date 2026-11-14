import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Uploads bytes to the host and returns the host path, or null when uploads
/// are unavailable (no Petasos server plugin).
typedef W1Uploader = Future<String?> Function(String name, Uint8List bytes);

const _textExt = {
  'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'yaml', 'yml', 'toml', 'xml',
  'html', 'htm', 'css', 'js', 'ts', 'tsx', 'jsx', 'dart', 'py', 'rb', 'go',
  'rs', 'java', 'kt', 'kts', 'swift', 'c', 'h', 'cpp', 'hpp', 'cs', 'sh',
  'bash', 'zsh', 'sql', 'log', 'ini', 'conf', 'cfg', 'env', 'gradle', 'properties',
  'ics', 'vcf', 'srt',
};
const _imageExt = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'};

/// Max bytes inlined as text in the message.
const kInlineTextLimit = 256 * 1024;

/// Max bytes for any attachment.
const kAttachmentLimit = 20 * 1024 * 1024;

enum W1AttachmentKind { text, image, file }

/// A non-image (or picked-as-file) attachment in the composer.
class W1Attachment {
  W1Attachment({
    required this.name,
    required this.kind,
    required this.size,
    this.text,
    this.dataUrl,
    this.hostPath,
  });

  final String name;
  final W1AttachmentKind kind;
  final int size;

  /// Decoded contents for text files (inlined).
  final String? text;

  /// For images picked through the file picker.
  final String? dataUrl;

  /// Where the Petasos plugin saved a binary file on the host.
  final String? hostPath;

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String extOf(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  static W1AttachmentKind classify(String name, Uint8List bytes) {
    final ext = extOf(name);
    if (_imageExt.contains(ext)) return W1AttachmentKind.image;
    if (_textExt.contains(ext) && bytes.length <= kInlineTextLimit) {
      return W1AttachmentKind.text;
    }
    if (ext.isEmpty && bytes.length <= kInlineTextLimit && _looksText(bytes)) {
      return W1AttachmentKind.text;
    }
    return W1AttachmentKind.file;
  }

  static bool _looksText(Uint8List b) {
    final n = b.length < 2048 ? b.length : 2048;
    for (var i = 0; i < n; i++) {
      if (b[i] == 0) return false;
    }
    return true;
  }

  /// Builds an attachment; uploads binary files through [upload].
  /// Throws [W1AttachmentError] with a user-facing message.
  static Future<W1Attachment> fromBytes(
    String name,
    Uint8List bytes, {
    W1Uploader? upload,
  }) async {
    if (bytes.isEmpty) throw const W1AttachmentError('That file is empty.');
    if (bytes.length > kAttachmentLimit) {
      throw const W1AttachmentError('That file is too large (max 20 MB).');
    }
    final kind = classify(name, bytes);
    switch (kind) {
      case W1AttachmentKind.text:
        return W1Attachment(
          name: name,
          kind: kind,
          size: bytes.length,
          text: utf8.decode(bytes, allowMalformed: true),
        );
      case W1AttachmentKind.image:
        final ext = extOf(name);
        final mime = ext == 'png'
            ? 'image/png'
            : ext == 'webp'
            ? 'image/webp'
            : ext == 'gif'
            ? 'image/gif'
            : 'image/jpeg';
        if (bytes.length > 8 * 1024 * 1024) {
          throw const W1AttachmentError('That image is too large (max 8 MB).');
        }
        return W1Attachment(
          name: name,
          kind: kind,
          size: bytes.length,
          dataUrl: 'data:$mime;base64,${base64Encode(bytes)}',
        );
      case W1AttachmentKind.file:
        final path = upload == null ? null : await upload(name, bytes);
        if (path == null) {
          throw const W1AttachmentError(
            'This file type needs the Petasos server plugin on your Hermes host. '
            'Text files and images work without it.',
          );
        }
        return W1Attachment(
          name: name,
          kind: kind,
          size: bytes.length,
          hostPath: path,
        );
    }
  }

  /// Text added to the outgoing message for this attachment.
  String toMessagePart() => switch (kind) {
    W1AttachmentKind.text =>
      'Attached file `$name`:\n```${_fence(extOf(name))}\n${text!.trimRight()}\n```',
    W1AttachmentKind.file =>
      'Attached file `$name` ($sizeLabel), saved on the host at `$hostPath`. '
          'Read it from there.',
    W1AttachmentKind.image => '',
  };

  static String _fence(String ext) => switch (ext) {
    'md' || 'markdown' => 'markdown',
    'yml' => 'yaml',
    'py' => 'python',
    'js' => 'javascript',
    'ts' => 'typescript',
    'kt' || 'kts' => 'kotlin',
    'sh' || 'bash' || 'zsh' => 'bash',
    _ => ext,
  };

  /// The message text with every attachment appended.
  static String compose(String text, List<W1Attachment> files) {
    final parts = [
      if (text.trim().isNotEmpty) text.trim(),
      for (final f in files)
        if (f.kind != W1AttachmentKind.image) f.toMessagePart(),
    ];
    return parts.join('\n\n');
  }
}

class W1AttachmentError implements Exception {
  const W1AttachmentError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Opens the system file picker. Returns null when cancelled.
Future<({String name, Uint8List bytes})?> pickAnyFile() async {
  final result = await FilePicker.platform.pickFiles(withData: true);
  final f = result?.files.firstOrNull;
  if (f == null || f.bytes == null) return null;
  return (name: f.name, bytes: f.bytes!);
}
