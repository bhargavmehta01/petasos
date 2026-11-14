// Renders demo-mode screens to docs/screenshots/hermes_mobile/*.png.
//
//   HERMES_MOBILE_SCREENSHOTS=1 flutter test test/hermes_mobile/screenshots_test.dart
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
  testWidgets('screenshots', (tester) async {
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

      if (!dark) await _shot(tester, key, '01-new-chat');

      // Open "Weekend plans" from the drawer.
      final state = root.state!;
      state.open(state.chats.firstWhere((c) => c.id == 'demo-weekend'));
      await _settle(tester);
      await _shot(tester, key, '02-chat-cards$suffix');

      if (dark) break;

      state.open(state.chats.firstWhere((c) => c.id == 'demo-groceries'));
      await _settle(tester);
      await _shot(tester, key, '03-order-card');

      state.open(state.chats.firstWhere((c) => c.id == 'demo-cron'));
      await _settle(tester);
      await _shot(tester, key, '04-code-summary-file');

      // A running turn with an approval.
      state.newChat();
      await _settle(tester, 4);
      await tester.enterText(find.byType(TextField).last, 'deploy the panels fix');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await _settle(tester, 3);
      await _shot(tester, key, '05-task-and-approval');

      await tester.tap(find.byTooltip('Home'));
      await _settle(tester);
      await _shot(tester, key, '06-home');

      await tester.tap(find.text('Review'));
      await _settle(tester);
      await tester.tap(find.text('Allow once'));
      await _settle(tester);

      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffold.openDrawer();
      await _settle(tester);
      await _shot(tester, key, '07-drawer');
      Navigator.of(scaffold.context).pop();
      await _settle(tester);

      await tester.tap(find.byTooltip('Profile and settings'));
      await _settle(tester);
      await _shot(tester, key, '08-profile');
      await tester.tap(find.text('Scheduled tasks'));
      await _settle(tester);
      await _shot(tester, key, '09-scheduled-tasks');
      await tester.pageBack();
      await _settle(tester);
      await tester.pageBack();
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: !_enabled);
}
