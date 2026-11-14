import 'dart:convert';

import '../../core/utils/media_tags.dart';

/// A renderable piece of an assistant reply. Replies are split into prose and
/// cards (links, tables, code, files, structured `hermes-mobile-card` blocks).
sealed class HermesMobileBlock {
  const HermesMobileBlock();
}

class ProseBlock extends HermesMobileBlock {
  const ProseBlock(this.markdown);
  final String markdown;
}

class CodeBlock extends HermesMobileBlock {
  const CodeBlock(this.code, {this.language = '', this.closed = true});
  final String code;
  final String language;

  /// False while the closing fence has not streamed in yet.
  final bool closed;
}

class TableBlock extends HermesMobileBlock {
  const TableBlock({this.title, required this.columns, required this.rows});
  final String? title;
  final List<String> columns;
  final List<List<String>> rows;
}

class LinkRef {
  const LinkRef({required this.url, this.title, this.description});
  final String url;
  final String? title;
  final String? description;

  String get domain {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  String get displayTitle {
    final t = title?.trim() ?? '';
    if (t.isNotEmpty && t != url) return t;
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return last != null
        ? Uri.decodeComponent(last).replaceAll(RegExp(r'[-_]'), ' ')
        : domain;
  }
}

class LinksBlock extends HermesMobileBlock {
  const LinksBlock(this.links, {this.title});
  final List<LinkRef> links;
  final String? title;
}

class FileBlock extends HermesMobileBlock {
  const FileBlock({required this.path, required this.name, this.isImage = false});
  final String path;
  final String name;
  final bool isImage;

  bool get isRemote => path.startsWith('http://') || path.startsWith('https://');
}

/// A structured ```hermes-mobile-card``` block. See docs/hermes-mobile-cards.md.
class StructuredCardBlock extends HermesMobileBlock {
  const StructuredCardBlock(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}

const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'};
const hermesMobileCardTypes = {
  'text',
  'links',
  'table',
  'summary',
  'order_summary',
  'calendar',
  'images',
};

final _fenceOpen = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*([A-Za-z0-9_+.\-]*)\s*$');
final _mdLinkOnly = RegExp(
  r'^\s*(?:[-*+]\s+|\d+[.)]\s+)?\[([^\]]+)\]\((https?://[^)\s]+)\)\s*(?:[-–—:]\s*(.*))?$',
);
final _bareUrlOnly = RegExp(
  r'^\s*(?:[-*+]\s+|\d+[.)]\s+)?(?:(?:\*\*)?([^:\n]{1,80}?)(?:\*\*)?\s*(?::|\s[-–—])\s*)?<?(https?://\S+?)>?\s*$',
);
final _tableSep = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

/// Splits assistant markdown into blocks. Pure and synchronous so it can run
/// on every streamed token and in widget tests.
List<HermesMobileBlock> parseHermesMobileBlocks(String input, {bool isFinal = true}) {
  final blocks = <HermesMobileBlock>[];
  final lines = input.replaceAll('\r\n', '\n').split('\n');
  final prose = <String>[];
  final links = <LinkRef>[];
  String? linksTitle;

  void flushLinks() {
    if (links.isEmpty) return;
    blocks.add(LinksBlock(List.of(links), title: linksTitle));
    links.clear();
    linksTitle = null;
  }

  /// A short "Sources:" style line right above links becomes their title.
  void takeLinksTitle() {
    if (links.isNotEmpty) return;
    while (prose.isNotEmpty && prose.last.trim().isEmpty) {
      prose.removeLast();
    }
    if (prose.isEmpty) return;
    final m = RegExp(
      r'^(?:\*\*)?([^:*#\n]{1,32}?)(?:\*\*)?:(?:\*\*)?$'
      r'|^#{1,6}\s+(.{1,32})$'
      r'|^\*\*([^*]{1,32})\*\*$',
    ).firstMatch(prose.last.trim());
    if (m != null) {
      linksTitle = (m.group(1) ?? m.group(2) ?? m.group(3))!.trim();
      prose.removeLast();
    }
  }

  void flushProse() {
    final text = prose.join('\n').trim();
    prose.clear();
    if (text.isEmpty) return;
    for (final seg in splitMediaTags(text, isFinal: isFinal)) {
      final media = seg.media;
      if (media != null) {
        if (!seg.standalone) {
          blocks.add(ProseBlock(media.filename));
        }
        blocks.add(
          FileBlock(
            path: media.path,
            name: media.filename,
            isImage: _imageExts.contains(media.extension),
          ),
        );
      } else if (seg.text.trim().isNotEmpty) {
        blocks.add(ProseBlock(seg.text.trim()));
      }
    }
  }

  void flushAll() {
    flushProse();
    flushLinks();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    // Fenced code / hermes-mobile-card.
    final fence = _fenceOpen.firstMatch(line);
    if (fence != null) {
      final marker = fence.group(1)!;
      final lang = fence.group(2)!.toLowerCase();
      final body = <String>[];
      var j = i + 1;
      var closed = false;
      while (j < lines.length) {
        final t = lines[j].trimLeft();
        if (t.startsWith(marker[0] * marker.length) &&
            t.replaceAll(marker[0], '').trim().isEmpty) {
          closed = true;
          break;
        }
        body.add(lines[j]);
        j++;
      }
      flushAll();
      final code = body.join('\n');
      if (lang == 'hermes-mobile-card' || lang == 'hermes_mobile') {
        final card = closed ? _decodeCard(code) : null;
        if (card != null) {
          blocks.add(card);
        } else if (closed) {
          blocks.add(CodeBlock(code, language: 'json'));
        } else {
          // Still streaming the JSON: keep a placeholder so text does not jump.
          blocks.add(const StructuredCardBlock('loading', {}));
        }
      } else {
        blocks.add(CodeBlock(code, language: lang, closed: closed));
      }
      i = closed ? j + 1 : j;
      continue;
    }

    // GFM table: header row, separator row, body rows.
    if (line.contains('|') &&
        i + 1 < lines.length &&
        _tableSep.hasMatch(lines[i + 1])) {
      String? title;
      // A short bold/heading line right above the table becomes its title.
      if (prose.isNotEmpty) {
        final prev = prose.last.trim();
        final heading = RegExp(r'^(#{1,6}\s+(.+)|\*\*(.+)\*\*:?)$').firstMatch(prev);
        if (heading != null) {
          title = (heading.group(2) ?? heading.group(3))?.trim();
          prose.removeLast();
        }
      }
      flushAll();
      final columns = _cells(line);
      final rows = <List<String>>[];
      var j = i + 2;
      while (j < lines.length && lines[j].contains('|') && lines[j].trim().isNotEmpty) {
        final cells = _cells(lines[j]);
        while (cells.length < columns.length) {
          cells.add('');
        }
        rows.add(cells.take(columns.length).toList());
        j++;
      }
      blocks.add(TableBlock(title: title, columns: columns, rows: rows));
      i = j;
      continue;
    }

    // A line that is only a link becomes a link card.
    final mdLink = _mdLinkOnly.firstMatch(line);
    if (mdLink != null) {
      takeLinksTitle();
      flushProse();
      links.add(
        LinkRef(
          url: mdLink.group(2)!,
          title: _stripInline(mdLink.group(1)!),
          description: mdLink.group(3)?.trim().isEmpty == true
              ? null
              : _stripInline(mdLink.group(3) ?? ''),
        ),
      );
      i++;
      continue;
    }
    final bare = _bareUrlOnly.firstMatch(line);
    if (bare != null && !line.contains('](')) {
      final url = bare.group(2)!.replaceFirst(RegExp(r'[.,;:!?)]+$'), '');
      final label = bare.group(1)?.trim();
      takeLinksTitle();
      flushProse();
      links.add(
        LinkRef(
          url: url,
          title: label == null || label.isEmpty ? null : _stripInline(label),
        ),
      );
      i++;
      continue;
    }

    if (links.isNotEmpty && line.trim().isEmpty) {
      i++;
      continue;
    }
    flushLinks();
    prose.add(line);
    i++;
  }
  flushAll();
  return blocks;
}

String _stripInline(String s) =>
    s.replaceAll(RegExp(r'[*_`]'), '').trim();

List<String> _cells(String row) {
  var r = row.trim();
  if (r.startsWith('|')) r = r.substring(1);
  if (r.endsWith('|')) r = r.substring(0, r.length - 1);
  return r.split('|').map((c) => _stripInline(c.trim())).toList();
}

StructuredCardBlock? _decodeCard(String code) {
  try {
    final decoded = jsonDecode(code);
    if (decoded is! Map) return null;
    final data = Map<String, dynamic>.from(decoded);
    final type = data['type']?.toString() ?? '';
    if (!hermesMobileCardTypes.contains(type)) return null;
    return StructuredCardBlock(type, data);
  } catch (_) {
    return null;
  }
}

/// Plain text of a reply for copy/share: drops fences' JSON for cards.
String replyPlainText(String markdown) => markdown
    .replaceAll(RegExp(r'```hermes-mobile-card[\s\S]*?```'), '')
    .trim();
