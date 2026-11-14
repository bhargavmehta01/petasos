import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/hermes_mobile_theme.dart';
import 'blocks.dart';

/// Lets cards ask the chat to do something (e.g. "Approve order").
class HermesMobileCardScope extends InheritedWidget {
  const HermesMobileCardScope({
    super.key,
    required this.onAction,
    required super.child,
  });
  final void Function(String message) onAction;

  static HermesMobileCardScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HermesMobileCardScope>();

  @override
  bool updateShouldNotify(HermesMobileCardScope oldWidget) => false;
}

Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

/// Renders one block. Prose is handled by the bubble; everything else is a card.
class HermesMobileBlockView extends StatelessWidget {
  const HermesMobileBlockView(this.block, {super.key});
  final HermesMobileBlock block;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      ProseBlock(:final markdown) => HermesMobileMarkdown(markdown),
      CodeBlock() => CodeCard(block as CodeBlock),
      TableBlock() => TableCard(block as TableBlock),
      LinksBlock() => LinkCards(block as LinksBlock),
      FileBlock() => FileCard(block as FileBlock),
      StructuredCardBlock() => StructuredCard(block as StructuredCardBlock),
    };
  }
}

/// Makes [child]'s text selectable (long-press, then drag the handles)
/// unless an ancestor SelectionArea already does. Taps on links and buttons
/// still go through.
class HermesMobileSelectable extends StatelessWidget {
  const HermesMobileSelectable({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (SelectionContainer.maybeOf(context) != null) return child;
    return SelectionArea(child: child);
  }
}

class HermesMobileMarkdown extends StatelessWidget {
  const HermesMobileMarkdown(this.data, {super.key, this.color});
  final String data;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!.copyWith(color: color ?? c.text);
    // Selection comes from the nearest SelectionArea (HermesMobileSelectable adds
    // one when there is none) rather than per-paragraph SelectableText, so a
    // drag can select across paragraphs and links stay tappable.
    return HermesMobileSelectable(
      child: MarkdownBody(
        data: data,
        selectable: false,
        softLineBreak: true,
        onTapLink: (text, href, title) {
          if (href != null) openExternal(context, href);
        },
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: base,
          listBullet: base,
          a: base.copyWith(
            color: color ?? c.accent,
            decoration: TextDecoration.underline,
            decorationColor: (color ?? c.accent).withValues(alpha: 0.4),
          ),
          strong: base.copyWith(fontWeight: FontWeight.w600),
          h1: base.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
          h2: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
          h3: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          code: base.copyWith(
            fontFamily: 'monospace',
            fontSize: 14,
            backgroundColor: c.codeBackground,
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.hairline, width: 3)),
          ),
          blockquotePadding: const EdgeInsets.only(left: 12),
          pPadding: EdgeInsets.zero,
          blockSpacing: 8,
        ),
      ),
    );
  }
}

/// Common card chrome: soft rounded surface, hairline border, optional header.
class HermesMobileCardFrame extends StatelessWidget {
  const HermesMobileCardFrame({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });
  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: c.textSecondary),
                    const SizedBox(width: 8),
                  ],
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          child,
        ],
      ),
    );
    // Shadow on an outer box, surface on a Material so ListTiles and ink
    // splashes inside the card paint correctly.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HermesMobileRadius.card),
        boxShadow: hermesMobileShadow(context),
      ),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HermesMobileRadius.card),
          side: BorderSide(color: c.hairline),
        ),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

// ── Code ─────────────────────────────────────────────────────────────────

class CodeCard extends StatelessWidget {
  const CodeCard(this.block, {super.key});
  final CodeBlock block;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Container(
      decoration: BoxDecoration(
        color: c.codeBackground,
        borderRadius: BorderRadius.circular(HermesMobileRadius.card - 4),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 0),
            child: Row(
              children: [
                Text(
                  block.language.isEmpty ? 'code' : block.language,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: c.textSecondary,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: block.code));
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: SelectableText(
              block.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
                color: c.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ────────────────────────────────────────────────────────────────

class TableCard extends StatefulWidget {
  const TableCard(this.block, {super.key});
  final TableBlock block;

  @override
  State<TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<TableCard> {
  static const _preview = 6;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final b = widget.block;
    final rows = _expanded ? b.rows : b.rows.take(_preview).toList();
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: c.textSecondary,
      fontWeight: FontWeight.w600,
    );
    final cellStyle = Theme.of(context).textTheme.bodyMedium;
    return HermesMobileCardFrame(
      title: b.title ?? 'Table',
      icon: Icons.table_chart_outlined,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      trailing: Text(
        '${b.rows.length} rows',
        style: Theme.of(context).textTheme.labelSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.hairline)),
                  ),
                  children: [
                    for (final col in b.columns)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 20, 8),
                        child: Text(col, style: headerStyle),
                      ),
                  ],
                ),
                for (final row in rows)
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: c.hairline.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    children: [
                      for (final cell in row)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 9, 20, 9),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(cell, style: cellStyle),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (b.rows.length > _preview)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'Show less' : 'Show all ${b.rows.length} rows',
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Links ────────────────────────────────────────────────────────────────

class LinkCards extends StatelessWidget {
  const LinkCards(this.block, {super.key});
  final LinksBlock block;

  @override
  Widget build(BuildContext context) {
    final links = block.links;
    final header = block.title == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              block.title!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.hermesMobile.textSecondary,
              ),
            ),
          );
    if (links.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [?header, _LinkCard(links.single, wide: true)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ?header,
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: links.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) =>
                SizedBox(width: 232, child: _LinkCard(links[i])),
          ),
        ),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard(this.link, {this.wide = false});
  final LinkRef link;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return HermesMobileCardFrame(
      padding: const EdgeInsets.all(12),
      onTap: () => openExternal(context, link.url),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Favicon(domain: link.domain),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  link.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Icon(Icons.north_east_rounded, size: 14, color: c.textTertiary),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            link.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (wide && link.description != null) ...[
            const SizedBox(height: 4),
            Text(
              link.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class Favicon extends StatelessWidget {
  const Favicon({super.key, required this.domain, this.size = 18});
  final String domain;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(5),
      ),
      alignment: Alignment.center,
      child: Text(
        domain.isEmpty ? '•' : domain[0].toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.6,
          fontWeight: FontWeight.w700,
          color: c.accent,
        ),
      ),
    );
    if (domain.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.network(
        'https://icons.duckduckgo.com/ip3/$domain.ico',
        width: size,
        height: size,
        errorBuilder: (_, _, _) => fallback,
        frameBuilder: (context, child, frame, sync) =>
            frame == null && !sync ? fallback : child,
      ),
    );
  }
}

// ── Files ────────────────────────────────────────────────────────────────

IconData fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'heic' => Icons.image_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'mp3' || 'wav' || 'm4a' || 'ogg' || 'opus' => Icons.audiotrack_outlined,
    'mp4' || 'mov' || 'webm' || 'mkv' => Icons.movie_outlined,
    'csv' || 'xlsx' || 'xls' => Icons.grid_on_outlined,
    'zip' || 'tar' || 'gz' => Icons.folder_zip_outlined,
    'md' || 'txt' || 'doc' || 'docx' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class FileCard extends StatelessWidget {
  const FileCard(this.block, {super.key});
  final FileBlock block;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    if (block.isImage && block.isRemote) {
      return HermesMobileCardFrame(
        padding: EdgeInsets.zero,
        onTap: () => openExternal(context, block.path),
        child: Image.network(
          block.path,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _row(context, c),
        ),
      );
    }
    return HermesMobileCardFrame(
      padding: EdgeInsets.zero,
      onTap: () {
        if (block.isRemote) {
          openExternal(context, block.path);
        } else {
          Clipboard.setData(ClipboardData(text: block.path));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'File path copied. Open it from Files on the host.',
              ),
            ),
          );
        }
      },
      child: _row(context, c),
    );
  }

  Widget _row(BuildContext context, HermesMobileColors c) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(fileIcon(block.name), color: c.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                block.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                block.isRemote ? Uri.parse(block.path).host : block.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Icon(
          block.isRemote ? Icons.north_east_rounded : Icons.copy_rounded,
          size: 16,
          color: c.textTertiary,
        ),
      ],
    ),
  );
}

// ── Structured hermes-mobile-card blocks ──────────────────────────────────────────

class StructuredCard extends StatelessWidget {
  const StructuredCard(this.block, {super.key});
  final StructuredCardBlock block;

  String? _s(String key) {
    final v = block.data[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  @override
  Widget build(BuildContext context) {
    final d = block.data;
    switch (block.type) {
      case 'loading':
        return const SkeletonCard();
      case 'text':
        return HermesMobileCardFrame(
          title: _s('title'),
          icon: Icons.notes_rounded,
          child: HermesMobileMarkdown(_s('body') ?? _s('text') ?? ''),
        );
      case 'links':
        final raw = d['links'] ?? d['items'];
        final links = <LinkRef>[
          if (raw is List)
            for (final l in raw)
              if (l is Map && l['url'] != null)
                LinkRef(
                  url: l['url'].toString(),
                  title: l['title']?.toString(),
                  description: l['description']?.toString(),
                ),
        ];
        return LinkCards(LinksBlock(links, title: _s('title')));
      case 'table':
        final cols = (d['columns'] as List? ?? const [])
            .map((e) => e.toString())
            .toList();
        final rows = (d['rows'] as List? ?? const [])
            .whereType<List>()
            .map((r) => r.map((e) => e?.toString() ?? '').toList())
            .toList();
        return TableCard(
          TableBlock(title: _s('title'), columns: cols, rows: rows),
        );
      case 'summary':
        return SummaryCard(
          title: _s('title') ?? 'Summary',
          markdown: _s('markdown') ?? _s('body') ?? '',
          initiallyExpanded: d['collapsed'] == false,
        );
      case 'order_summary':
        return OrderSummaryCard(data: d);
      case 'calendar':
        return CalendarCard(data: d);
      case 'images':
        return ImagesCard(data: d);
    }
    return const SizedBox.shrink();
  }
}

class SummaryCard extends StatefulWidget {
  const SummaryCard({
    super.key,
    required this.title,
    required this.markdown,
    this.initiallyExpanded = false,
  });
  final String title;
  final String markdown;
  final bool initiallyExpanded;

  @override
  State<SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<SummaryCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return HermesMobileCardFrame(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.article_outlined, size: 16, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more_rounded, color: c.textSecondary),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.markdown.replaceAll(RegExp(r'[#*_`>]'), ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: HermesMobileMarkdown(widget.markdown),
            ),
          ),
        ],
      ),
    );
  }
}

class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final merchant = data['merchant']?.toString() ?? 'Order';
    final currency = data['currency']?.toString() ?? '\$';
    String money(Object? v) {
      if (v == null) return '';
      if (v is num) return '$currency${v.toStringAsFixed(2)}';
      return v.toString();
    }

    final items = (data['items'] ?? data['line_items']) as List? ?? const [];
    final approveLabel = data['approve_label']?.toString() ?? 'Approve order';
    final approvePrompt =
        data['approve_prompt']?.toString() ??
        'Approved. Go ahead and place the $merchant order.';
    final scope = HermesMobileCardScope.of(context);
    return HermesMobileCardFrame(
      title: merchant,
      icon: Icons.shopping_bag_outlined,
      trailing: data['status'] == null
          ? null
          : _Pill(data['status'].toString()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in items.whereType<Map>())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (it['qty'] != null || it['quantity'] != null)
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${it['qty'] ?? it['quantity']}×',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      (it['name'] ?? it['title'] ?? '').toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    money(it['price'] ?? it['amount']),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          if (data['subtotal'] != null || data['fees'] != null) ...[
            const SizedBox(height: 6),
            for (final k in ['subtotal', 'fees', 'tax', 'tip', 'discount'])
              if (data[k] != null)
                Row(
                  children: [
                    Text(
                      k[0].toUpperCase() + k.substring(1),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text(
                      money(data[k]),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
          ],
          Divider(height: 20, color: c.hairline),
          Row(
            children: [
              Text(
                'Total',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                money(data['total']),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (data['note'] != null) ...[
            const SizedBox(height: 6),
            Text(
              data['note'].toString(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (scope != null && data['approvable'] != false) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                scope.onAction(approvePrompt);
              },
              child: Text(approveLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.accent,
        ),
      ),
    );
  }
}

/// Builds a Google Calendar "add event" link; Android hands it to the
/// Calendar app when installed.
Uri calendarInsertUri(Map<String, dynamic> d) {
  String fmt(DateTime t) {
    final u = t.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  final start = DateTime.tryParse(d['start']?.toString() ?? '');
  final end =
      DateTime.tryParse(d['end']?.toString() ?? '') ??
      start?.add(const Duration(hours: 1));
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': d['title']?.toString() ?? 'Event',
    if (start != null && end != null) 'dates': '${fmt(start)}/${fmt(end)}',
    if (d['location'] != null) 'location': d['location'].toString(),
    if (d['description'] != null) 'details': d['description'].toString(),
  });
}

class CalendarCard extends StatelessWidget {
  const CalendarCard({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.hermesMobile;
    final start = DateTime.tryParse(data['start']?.toString() ?? '')?.toLocal();
    final end = DateTime.tryParse(data['end']?.toString() ?? '')?.toLocal();
    final loc = MaterialLocalizations.of(context);
    String when = '';
    if (start != null) {
      when =
          '${loc.formatMediumDate(start)} · ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(start))}';
      if (end != null) {
        when += ' – ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(end))}';
      }
    }
    return HermesMobileCardFrame(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  start == null
                      ? '—'
                      : loc
                            .formatShortMonthDay(start)
                            .split(' ')
                            .first
                            .toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
                Text(
                  start == null ? '' : '${start.day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title']?.toString() ?? 'Event',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (when.isNotEmpty)
                  Text(when, style: Theme.of(context).textTheme.bodySmall),
                if (data['location'] != null)
                  Text(
                    data['location'].toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('Add to calendar'),
                  onPressed: () =>
                      openExternal(context, calendarInsertUri(data).toString()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImagesCard extends StatelessWidget {
  const ImagesCard({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final raw = (data['images'] ?? data['items']) as List? ?? const [];
    final images = [
      for (final r in raw)
        if (r is Map && r['url'] != null)
          (url: r['url'].toString(), caption: r['caption']?.toString())
        else if (r is String)
          (url: r, caption: null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data['title'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text(
              data['title'].toString(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => openExternal(context, images[i].url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(HermesMobileRadius.card),
                child: Stack(
                  children: [
                    Image.network(
                      images[i].url,
                      height: 180,
                      width: 220,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 220,
                        color: context.hermesMobile.surfaceMuted,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    if (images[i].caption != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.black45,
                          child: Text(
                            images[i].caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shimmer-free skeleton: a calm pulsing placeholder.
class SkeletonCard extends StatefulWidget {
  const SkeletonCard({super.key, this.height = 84});
  final double height;
  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hermesMobile;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: h.surfaceMuted,
          borderRadius: BorderRadius.circular(HermesMobileRadius.card),
        ),
      ),
    );
  }
}
