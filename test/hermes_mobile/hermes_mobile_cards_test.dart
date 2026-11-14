import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/cards/blocks.dart';
import 'package:hermes_android/hermes_mobile/cards/card_widgets.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/models.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:hermes_android/hermes_mobile/widgets/message_views.dart';

Widget _wrap(Widget child, {void Function(String)? onAction}) => MaterialApp(
  theme: hermesMobileTheme(Brightness.light),
  home: Scaffold(
    body: HermesMobileCardScope(
      onAction: onAction ?? (_) {},
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ),
);

void main() {
  group('parseHermesMobileBlocks', () {
    test('splits prose, table with title, links and a calendar card', () {
      final blocks = parseHermesMobileBlocks(DemoBackend.sampleReply);
      expect(blocks.first, isA<ProseBlock>());
      final table = blocks.whereType<TableBlock>().single;
      expect(table.title, 'This weekend');
      expect(table.columns, ['Event', 'Day', 'Price']);
      expect(table.rows, hasLength(3));
      final links = blocks.whereType<LinksBlock>().single;
      expect(links.links, hasLength(3));
      expect(links.title, 'Sources', reason: '"Sources:" line titles the links');
      expect(
        blocks.whereType<ProseBlock>().any((p) => p.markdown == 'Sources:'),
        isFalse,
      );
      expect(links.links.first.domain, 'example.org');
      expect(links.links.first.displayTitle, 'City Botanical Garden');
      final card = blocks.whereType<StructuredCardBlock>().single;
      expect(card.type, 'calendar');
      expect(card.data['location'], contains('Garden Way'));
      // The closing question stays prose after the card.
      expect((blocks.last as ProseBlock).markdown, contains('book'));
    });

    test('code fences become code cards and keep the language', () {
      final blocks = parseHermesMobileBlocks('Run this:\n\n```bash\necho hi\n```\n');
      final code = blocks.whereType<CodeBlock>().single;
      expect(code.language, 'bash');
      expect(code.code, 'echo hi');
      expect(code.closed, isTrue);
    });

    test('an unclosed fence while streaming stays an open code block', () {
      final blocks = parseHermesMobileBlocks('```python\nprint(1)', isFinal: false);
      final code = blocks.whereType<CodeBlock>().single;
      expect(code.closed, isFalse);
    });

    test('a streaming hermes-mobile-card shows a loading placeholder', () {
      final blocks = parseHermesMobileBlocks('```hermes-mobile-card\n{"type":"ta', isFinal: false);
      expect(
        blocks.whereType<StructuredCardBlock>().single.type,
        'loading',
      );
    });

    test('invalid hermes-mobile-card JSON falls back to a code card', () {
      final blocks = parseHermesMobileBlocks('```hermes-mobile-card\n{nope}\n```');
      expect(blocks.single, isA<CodeBlock>());
    });

    test('unknown hermes-mobile-card type falls back to a code card', () {
      final blocks = parseHermesMobileBlocks('```hermes-mobile-card\n{"type":"rocket"}\n```');
      expect(blocks.single, isA<CodeBlock>());
    });

    test('bare URL lines become link cards, inline links stay prose', () {
      final blocks = parseHermesMobileBlocks(
        'See [the docs](https://example.com/docs) for more.\n\n'
        'https://www.chargepoint.com/drivers/home\n'
        'Emporia: https://www.emporiaenergy.com/ev-charger',
      );
      expect(blocks.first, isA<ProseBlock>());
      expect((blocks.first as ProseBlock).markdown, contains('[the docs]'));
      final links = blocks.whereType<LinksBlock>().single.links;
      expect(links.map((l) => l.domain), [
        'chargepoint.com',
        'emporiaenergy.com',
      ]);
      expect(links.last.title, 'Emporia');
    });

    test('a sentence ending in a URL is not turned into a link card', () {
      final blocks = parseHermesMobileBlocks('Read more at https://example.com');
      expect(blocks.whereType<LinksBlock>(), isEmpty);
    });

    test('MEDIA: tags become file cards', () {
      final blocks = parseHermesMobileBlocks(
        'Here is the log.\nMEDIA:/home/me/.hermes/logs/run.log',
      );
      final file = blocks.whereType<FileBlock>().single;
      expect(file.name, 'run.log');
      expect(file.isRemote, isFalse);
    });

    test('replyPlainText drops hermes-mobile-card JSON', () {
      expect(
        replyPlainText('Hi\n```hermes-mobile-card\n{"type":"text"}\n```'),
        'Hi',
      );
    });
  });

  group('card widgets', () {
    testWidgets('table card shows title, headers and expands rows', (
      tester,
    ) async {
      final rows = [
        for (var i = 0; i < 9; i++) ['Row $i', '$i'],
      ];
      await tester.pumpWidget(
        _wrap(TableCard(TableBlock(title: 'Prices', columns: const ['Item', 'N'], rows: rows))),
      );
      expect(find.text('Prices'), findsOneWidget);
      expect(find.text('Item'), findsOneWidget);
      expect(find.text('Row 5'), findsOneWidget);
      expect(find.text('Row 8'), findsNothing);
      await tester.tap(find.text('Show all 9 rows'));
      await tester.pumpAndSettle();
      expect(find.text('Row 8'), findsOneWidget);
    });

    testWidgets('code card renders code and a copy button', (tester) async {
      await tester.pumpWidget(_wrap(const CodeCard(CodeBlock('ls -la', language: 'bash'))));
      expect(find.text('bash'), findsOneWidget);
      expect(find.text('ls -la'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);
    });

    testWidgets('link cards show title and domain', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const LinkCards(
            LinksBlock([
              LinkRef(url: 'https://example.org/garden/', title: 'Garden'),
              LinkRef(url: 'https://www.poncecitymarket.com/', title: 'PCM'),
            ]),
          ),
        ),
      );
      expect(find.text('Garden'), findsOneWidget);
      expect(find.text('example.org'), findsOneWidget);
      expect(find.text('poncecitymarket.com'), findsOneWidget);
    });

    testWidgets('order summary approve button sends the approve prompt', (
      tester,
    ) async {
      String? sent;
      final block = parseHermesMobileBlocks(DemoBackend.orderReply)
          .whereType<StructuredCardBlock>()
          .single;
      await tester.pumpWidget(
        _wrap(StructuredCard(block), onAction: (m) => sent = m),
      );
      expect(find.text('Costco Same-Day'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('\$26.95'), findsOneWidget);
      await tester.tap(find.text('Approve and order'));
      expect(sent, contains('Costco Same-Day'));
    });

    testWidgets('summary card collapses and expands', (tester) async {
      await tester.pumpWidget(
        _wrap(const SummaryCard(title: 'Log', markdown: 'First line\n\n**Second** part')),
      );
      expect(find.text('Log'), findsOneWidget);
      await tester.tap(find.text('Log'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Second'), findsWidgets);
    });

    testWidgets('calendar card offers Add to calendar', (tester) async {
      final block = parseHermesMobileBlocks(DemoBackend.sampleReply)
          .whereType<StructuredCardBlock>()
          .single;
      await tester.pumpWidget(_wrap(StructuredCard(block)));
      expect(find.text('Garden lights with Maya'), findsOneWidget);
      expect(find.text('Add to calendar'), findsOneWidget);
      final uri = calendarInsertUri(block.data);
      expect(uri.queryParameters['action'], 'TEMPLATE');
      expect(uri.queryParameters['dates'], '20261107T233000Z/20261108T013000Z');
    });

    testWidgets('agent reply renders prose bubbles plus cards and a done task', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          AgentReply(
            message: HermesMobileMessage(
              role: HermesMobileRole.assistant,
              text: DemoBackend.codeReply,
              toolNames: const ['terminal', 'patch'],
            ),
          ),
        ),
      );
      expect(find.text('Done · 2 steps'), findsOneWidget);
      expect(find.byType(CodeCard), findsOneWidget);
      expect(find.byType(SummaryCard), findsOneWidget);
      expect(find.byType(FileCard), findsOneWidget);
      expect(find.textContaining('jq'), findsWidgets);
    });
  });
}
