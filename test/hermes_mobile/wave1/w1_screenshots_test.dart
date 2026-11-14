// Wave 1 demo screenshots to docs/screenshots/hermes_mobile/w1-*.png.
//
//   HERMES_MOBILE_SCREENSHOTS=1 flutter test test/hermes_mobile/wave1/w1_screenshots_test.dart
//
// Skipped in normal test runs.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/hermes_mobile/data/demo_backend.dart';
import 'package:hermes_android/hermes_mobile/features/wave1_proactive/w1_launch.dart';
import 'package:hermes_android/hermes_mobile/hermes_mobile_app.dart';
import 'package:hermes_android/core/services/android_share_intent_service.dart';
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
  testWidgets('wave1 screenshots', (tester) async {
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
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: HermesMobileBootstrap(controller: root)),
      );
      await _settle(tester);
      final suffix = dark ? '-dark' : '';

      await tester.tap(find.byKey(const ValueKey('w1-brief-button')));
      await _settle(tester);
      await _shot(tester, key, 'w1-01-brief-today$suffix');
      await tester.tap(find.text('For you'));
      await _settle(tester);
      await _shot(tester, key, 'w1-02-for-you$suffix');
      if (dark) break;

      await tester.tap(find.byTooltip('Notification settings'));
      await _settle(tester);
      await _shot(tester, key, 'w1-07-notification-settings');
      await tester.pageBack();
      await _settle(tester);
      await tester.pageBack();
      await _settle(tester);

      // Schedule preview from the composer.
      await tester.enterText(
        find.byType(TextField).last,
        'Every weekday at 9 summarise my inbox and calendar',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester);
      await _shot(tester, key, 'w1-03-schedule-preview');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      // Sudo and clarify cards.
      await tester.enterText(find.byType(TextField).last, 'sudo restart the gateway');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester, 3);
      await _shot(tester, key, 'w1-04-sudo-card');
      await root.state!.current!.stop();
      await _settle(tester);
      root.state!.newChat();
      await _settle(tester, 4);
      await tester.enterText(find.byType(TextField).last, 'which calendar for the garden trip?');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester, 3);
      await _shot(tester, key, 'w1-05-clarify-card');
      await root.state!.current!.stop();
      await _settle(tester);

      // Home with the brief row.
      await tester.tap(find.byTooltip('Home'));
      await _settle(tester);
      await _shot(tester, key, 'w1-08-home-brief-row');

      // Share-sheet capture with the prompt picker.
      final ctx = tester.element(find.byType(Scaffold).first);
      showQuickCapture(
        ctx,
        const HermesMobileLaunchRequest(
          QuickCaptureMode.share,
          share: AndroidSharePayload(
            text: 'https://www.costco.com/sony-wh-1000xm6.product.html',
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.text('Summarize'), warnIfMissed: false);
      await _settle(tester);
      await _shot(tester, key, 'w1-06-share-capture');
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: !_enabled);
}
