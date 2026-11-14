// Renders Wave 4 demo screens to docs/screenshots/hermes_mobile/w4-*.png.
//
//   HERMES_MOBILE_SCREENSHOTS=1 flutter test test/hermes_mobile/wave4/w4_screenshots_test.dart
//
// Skipped in normal test runs.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/hermes_mobile_app.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_controller.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/w4_api.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_watchers.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_commitments.dart';
import 'package:hermes_android/hermes_mobile/features/wave4_novel/ui/w4_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _enabled = Platform.environment['HERMES_MOBILE_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.view(
          File('assets/fonts/Inter-Variable.ttf').readAsBytesSync().buffer,
        ),
      ),
    );
  await inter.load();
  final monoFile = File('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf');
  if (monoFile.existsSync()) {
    final mono = FontLoader('monospace')
      ..addFont(Future.value(ByteData.view(monoFile.readAsBytesSync().buffer)));
    await mono.load();
  }
  // flutter test copies the icon font into the unit-test asset bundle.
  var iconFile = File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (!iconFile.existsSync() && flutterRoot != null) {
    iconFile = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
  if (iconFile.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconFile.readAsBytesSync().buffer)));
    await icons.load();
  }
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/screenshots/hermes_mobile/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('wave4 screenshots', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(412 * 2.5, 892 * 2.5);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    for (final dark in [false, true]) {
      SharedPreferences.setMockInitialValues({
        'hermes_mobile.demo': true,
        'hermes_mobile.theme_mode': dark ? 'dark' : 'light',
      });
      final prefs = await SharedPreferences.getInstance();
      final root = HermesMobileRootController(
        prefs: prefs,
        demoFactory: () => DemoBackend(fast: true),
      );
      await root.rebuild();
      final state = root.state!;
      final w4 = Wave4Controller(state, api: DemoWave4Api(), preferences: prefs)
        ..recapSince = DateTime.now().subtract(const Duration(days: 1));
      state.wave4 = w4;
      await tester.runAsync(w4.start);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: HermesMobileBootstrap(controller: root)),
      );
      await _settle(tester);
      final suffix = dark ? '-dark' : '';

      if (!dark) {
        state.open(state.chats.firstWhere((c) => c.id == 'demo-weekend'));
        await _settle(tester);
        await _shot(tester, key, 'w4-07-chat-chips');
      }

      await tester.tap(find.byTooltip('Home'));
      await _settle(tester);
      await tester.drag(find.byType(ListView).first, const Offset(0, -520));
      await _settle(tester);
      await _shot(tester, key, 'w4-01-home-autopilot$suffix');
      if (dark) {
        state.dispose();
        break;
      }
      await tester.drag(find.byType(ListView).first, const Offset(0, -560));
      await _settle(tester);
      await _shot(tester, key, 'w4-02-home-watching');

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute(builder: (_) => const WatchersScreen()));
      await _settle(tester);
      await _shot(tester, key, 'w4-03-watchers');
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => const CommitmentsScreen()));
      await _settle(tester);
      await _shot(tester, key, 'w4-04-commitments');
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => const AutopilotSettingsScreen()));
      await _settle(tester);
      await _shot(tester, key, 'w4-05-proactivity');
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => const ContextTriggersScreen()));
      await _settle(tester);
      await _shot(tester, key, 'w4-06-triggers');
      nav.pop();
      await _settle(tester);
      state.dispose();
    }
  }, skip: !_enabled);
}
