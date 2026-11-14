import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/data/panels.dart';
import 'package:hermes_android/hermes_mobile/screens/home_screen.dart';
import 'package:hermes_android/hermes_mobile/theme/hermes_mobile_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: hermesMobileTheme(Brightness.light),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

void main() {
  group('HermesMobilePanel.tryParse', () {
    test('reads the home-dashboard schema v1 (delta, link, rows)', () {
      final p = HermesMobilePanel.tryParse({
        'id': 'daily-cost',
        'title': 'API spend',
        'kind': 'stat',
        'value': 18.42,
        'unit': 'USD',
        'delta': '+1.37 today',
        'link': 'https://example.com/costs',
        'updated_at': '2026-11-01T13:15:00Z',
        'stale_after_minutes': 60,
      })!;
      expect(p.kind, PanelKind.stat);
      expect(p.value, '18.42');
      expect(p.trend, '+1.37 today');
      expect(p.url, 'https://example.com/costs');
      expect(p.updatedAt, isNotNull);
      expect(p.isStale(DateTime.utc(2026, 11, 1, 15)), isTrue);
      expect(p.isStale(DateTime.utc(2026, 11, 1, 13, 30)), isFalse);
    });

    test('reads Petasos additions: progress kind, trend, url, items', () {
      final p = HermesMobilePanel.tryParse({
        'id': 'backup',
        'title': 'Backup',
        'kind': 'progress',
        'value': 75,
        'url': 'https://example.com',
        'items': [
          {'label': 'B2', 'value': 'ok', 'url': 'javascript:alert(1)'},
        ],
      })!;
      expect(p.progress, 0.75);
      expect(p.items.single.url, isNull, reason: 'only http(s) links kept');
    });

    test('rejects invalid panels and parses lists of every shape', () {
      expect(HermesMobilePanel.tryParse({'id': 'x', 'title': 'X'}), isNull);
      expect(HermesMobilePanel.tryParse({'id': 'x', 'title': 'X', 'kind': 'pie'}), isNull);
      final doc = {'id': 'a', 'title': 'A', 'kind': 'text', 'text': 'hi'};
      expect(HermesMobilePanel.parseList({'version': 1, 'panels': [doc]}), hasLength(1));
      expect(HermesMobilePanel.parseList({'data': [doc, 'junk']}), hasLength(1));
      expect(HermesMobilePanel.parseList([doc, doc]), hasLength(2));
      expect(HermesMobilePanel.parseList('nope'), isEmpty);
    });
  });

  group('panel sources', () {
    test('UrlPanelsSource sends the bearer token and parses panels', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'panels': [
              {'id': 'a', 'title': 'A', 'kind': 'text', 'text': 'hi'},
            ],
          }),
          200,
        );
      });
      final r = await UrlPanelsSource(
        'https://host/panels.json',
        bearer: 'tok',
        client: client,
      ).load();
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(r.panels.single.id, 'a');
      expect(r.error, isNull);
    });

    test('UrlPanelsSource reports HTTP errors instead of throwing', () async {
      final client = MockClient((_) async => http.Response('no', 401));
      final r = await UrlPanelsSource('https://host/p', client: client).load();
      expect(r.panels, isEmpty);
      expect(r.error, 'HTTP 401');
    });

    test('DashboardPanelsSource wraps getter failures', () async {
      final r = await DashboardPanelsSource(() async => throw 'down').load();
      expect(r.error, 'down');
    });

    test('unconfigured source asks Home for the setup empty state', () async {
      final r = await const UnconfiguredPanelsSource().load();
      expect(r.configured, isFalse);
    });
  });

  group('PanelsGrid', () {
    testWidgets('renders every demo panel kind', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PanelsGrid(
            result: PanelsResult(panels: DemoBackend.demoPanels),
            loading: false,
            onSetup: () {},
          ),
        ),
      );
      expect(find.text('API spend · month'), findsOneWidget);
      expect(find.text('+1.37 today'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('OpenRouter flex'), findsOneWidget);
      expect(find.text('Stroller'), findsOneWidget);
      expect(find.textContaining('2 PRs waiting'), findsOneWidget);
    });

    testWidgets('unconfigured shows how to expose panels', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          PanelsGrid(
            result: const PanelsResult(panels: [], configured: false),
            loading: false,
            onSetup: () => tapped = true,
          ),
        ),
      );
      expect(find.text('Show your Hermes panels here'), findsOneWidget);
      await tester.tap(find.text('Set up panels'));
      expect(tapped, isTrue);
    });
  });
}
