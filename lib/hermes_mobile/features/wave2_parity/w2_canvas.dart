import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cards/blocks.dart';
import '../../cards/card_widgets.dart';
import '../../theme/hermes_mobile_theme.dart';
import 'w2_settings.dart';

enum W2CanvasKind { code, doc, table }

/// What the canvas edits: a code block, a markdown document, or a table.
class W2CanvasDoc {
  W2CanvasDoc.code(this.text, {this.language = ''})
    : kind = W2CanvasKind.code,
      columns = [],
      rows = [];
  W2CanvasDoc.doc(this.text)
    : kind = W2CanvasKind.doc,
      language = '',
      columns = [],
      rows = [];
  W2CanvasDoc.table(this.columns, this.rows)
    : kind = W2CanvasKind.table,
      text = '',
      language = '';

  final W2CanvasKind kind;
  String text;
  final String language;
  final List<String> columns;
  final List<List<String>> rows;

  /// Picks the most editable part of a reply: its first code block, else its
  /// first table, else the whole text as a document.
  factory W2CanvasDoc.fromMessage(String markdown) {
    final blocks = parseHermesMobileBlocks(markdown, isFinal: true);
    for (final b in blocks) {
      if (b is CodeBlock) return W2CanvasDoc.code(b.code, language: b.language);
    }
    for (final b in blocks) {
      if (b is TableBlock) {
        return W2CanvasDoc.table(
          List.of(b.columns),
          [for (final r in b.rows) List.of(r)],
        );
      }
    }
    return W2CanvasDoc.doc(markdown.trim());
  }

  String get title => switch (kind) {
    W2CanvasKind.code => language.isEmpty ? 'Code' : language,
    W2CanvasKind.doc => 'Document',
    W2CanvasKind.table => 'Table',
  };

  /// The message sent back to Hermes.
  String toMessage() => switch (kind) {
    W2CanvasKind.code =>
      'Here is my edited version:\n\n```$language\n${text.trimRight()}\n```',
    W2CanvasKind.doc => 'Here is my edited version:\n\n${text.trim()}',
    W2CanvasKind.table => 'Here is my edited table:\n\n${tableMarkdown()}',
  };

  String tableMarkdown() {
    String cell(String s) => s.replaceAll('|', r'\|').replaceAll('\n', ' ');
    final b = StringBuffer()
      ..writeln('| ${columns.map(cell).join(' | ')} |')
      ..writeln('|${List.filled(columns.length, '---').join('|')}|');
    for (final r in rows) {
      final padded = [
        for (var i = 0; i < columns.length; i++) i < r.length ? r[i] : '',
      ];
      b.writeln('| ${padded.map(cell).join(' | ')} |');
    }
    return b.toString().trimRight();
  }
}

/// Opens the full-screen canvas. Returns the message to send back, or null.
Future<String?> openW2Canvas(BuildContext context, W2CanvasDoc doc) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => W2CanvasScreen(doc: doc),
      ),
    );

class W2CanvasScreen extends StatefulWidget {
  const W2CanvasScreen({super.key, required this.doc});
  final W2CanvasDoc doc;

  @override
  State<W2CanvasScreen> createState() => _W2CanvasScreenState();
}

class _W2CanvasScreenState extends State<W2CanvasScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.doc.text,
  );
  bool _preview = false;
  bool _dirty = false;

  W2CanvasDoc get doc => widget.doc;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      doc.text = _text.text;
      if (!_dirty) setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _copy() {
    final s = doc.kind == W2CanvasKind.table ? doc.tableMarkdown() : doc.text;
    Clipboard.setData(ClipboardData(text: s));
    W2Haptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  void _send() {
    W2Haptics.light();
    Navigator.of(context).pop(doc.toMessage());
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard your edits?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Canvas · ${doc.title}'),
          actions: [
            if (doc.kind == W2CanvasKind.doc)
              IconButton(
                tooltip: _preview ? 'Edit' : 'Preview',
                icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _preview = !_preview),
              ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded),
              onPressed: _copy,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                key: const ValueKey('w2-canvas-send'),
                onPressed: _send,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                label: const Text('Send back'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: switch (doc.kind) {
            W2CanvasKind.table => _TableEditor(
              doc: doc,
              onChanged: () => setState(() => _dirty = true),
            ),
            W2CanvasKind.doc when _preview => SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: HermesMobileMarkdown(doc.text),
            ),
            _ => Container(
              color: doc.kind == W2CanvasKind.code ? c.codeBackground : null,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: TextField(
                key: const ValueKey('w2-canvas-field'),
                controller: _text,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                style: doc.kind == W2CanvasKind.code
                    ? const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.45)
                    : Theme.of(context).textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          },
        ),
      ),
    );
  }
}

class _TableEditor extends StatefulWidget {
  const _TableEditor({required this.doc, required this.onChanged});
  final W2CanvasDoc doc;
  final VoidCallback onChanged;

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  W2CanvasDoc get doc => widget.doc;

  Widget _cell(String value, void Function(String) onChanged, {bool header = false}) {
    return SizedBox(
      width: 150,
      child: TextFormField(
        initialValue: value,
        onChanged: (v) {
          onChanged(v);
          widget.onChanged();
        },
        style: header ? const TextStyle(fontWeight: FontWeight.w600) : null,
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < doc.columns.length; i++)
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: _cell(doc.columns[i], (v) => doc.columns[i] = v, header: true),
                    ),
                ],
              ),
              for (var r = 0; r < doc.rows.length; r++)
                Row(
                  children: [
                    for (var i = 0; i < doc.columns.length; i++)
                      Padding(
                        padding: const EdgeInsets.all(3),
                        child: _cell(
                          i < doc.rows[r].length ? doc.rows[r][i] : '',
                          (v) {
                            while (doc.rows[r].length <= i) {
                              doc.rows[r].add('');
                            }
                            doc.rows[r][i] = v;
                          },
                        ),
                      ),
                    IconButton(
                      tooltip: 'Delete row',
                      icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                      onPressed: () => setState(() {
                        doc.rows.removeAt(r);
                        widget.onChanged();
                      }),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                doc.rows.add(List.filled(doc.columns.length, '', growable: true));
                widget.onChanged();
              }),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Row'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                doc.columns.add('Column ${doc.columns.length + 1}');
                for (final r in doc.rows) {
                  r.add('');
                }
                widget.onChanged();
              }),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Column'),
            ),
          ],
        ),
      ],
    );
  }
}
