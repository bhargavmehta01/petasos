import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/client_certificate_service.dart';
import '../core/services/connection_manager.dart';
import '../core/services/mobile_push_service.dart';
import '../core/services/turn_notification_service.dart';
import 'cards/blocks.dart';
import '../l10n/app_localizations.dart';
import 'data/app_state.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/keep_alive_binder.dart';
import 'data/live_backend.dart';
import 'screens/connect_screen.dart';
import 'screens/shell.dart';
import 'theme/hermes_mobile_theme.dart';
// --- wave2 ---
import 'features/wave2_parity/w2_settings.dart';
import 'features/wave2_parity/w2_theme.dart';
// --- end wave2 ---

/// Demo mode at build time: `flutter run --dart-define=HERMES_MOBILE_DEMO=true`.
const bool kHermesMobileDemo = bool.fromEnvironment('HERMES_MOBILE_DEMO');

void hermesMobileMain() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(ClientCertificateService().cleanupStaging());
  runApp(const HermesMobileBootstrap());
}

/// Root controller: preferences, theme, and which backend is active.
class HermesMobileRootController extends ChangeNotifier {
  HermesMobileRootController({
    required this.prefs,
    this.connections,
    this.demoFactory,
  });

  final SharedPreferences prefs;

  /// Tests inject a fast demo backend.
  final HermesMobileBackend Function()? demoFactory;

  /// Null in demo-only runs (tests, web screenshots).
  final ConnectionManager? connections;

  static const _themeKey = 'hermes_mobile.theme_mode';
  static const _demoKey = 'hermes_mobile.demo';
  static const _activeKey = 'hermes_mobile.active_connection';

  HermesMobileAppState? _state;
  HermesMobileAppState? get state => _state;

  ThemeMode get themeMode => switch (prefs.getString(_themeKey)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) async {
    await prefs.setString(_themeKey, mode.name);
    notifyListeners();
  }

  bool get demo => kHermesMobileDemo || (prefs.getBool(_demoKey) ?? false);

  List<SavedConnection> get savedConnections =>
      connections?.getConnections() ?? const [];

  SavedConnection? get activeConnection {
    final list = savedConnections;
    if (list.isEmpty) return null;
    final id = prefs.getString(_activeKey);
    return list.where((c) => c.id == id).firstOrNull ?? list.first;
  }

  /// Builds the backend for the current settings, or null when the user still
  /// has to connect.
  Future<void> rebuild() async {
    _state?.dispose();
    _state = null;
    HermesMobileBackend? backend;
    if (demo) {
      backend = demoFactory?.call() ?? DemoBackend();
    } else {
      final cm = connections;
      final active = activeConnection;
      if (cm != null && active != null) {
        final full = (await cm.loadConnectionsWithSecrets())
            .where((c) => c.id == active.id)
            .firstOrNull;
        if (full != null) backend = LiveBackend(full, prefs);
      }
    }
    if (backend != null) {
      final state = HermesMobileAppState(backend);
      if (!backend.isDemo) {
        final connectionId = activeConnection?.id;
        state.onTurnSettled = (chatId, title, reply, failed) =>
            _notifyTurn(connectionId, chatId, title, reply, failed);
      }
      _state = state;
    }
    notifyListeners();
  }

  /// Posts the engine's turn notification when a turn ends while Hermes is
  /// in the background (the app keeps the stream open until it settles).
  static void _notifyTurn(
    String? connectionId,
    String chatId,
    String title,
    String reply,
    bool failed,
  ) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) return;
    final plain = replyPlainText(reply).replaceAll(RegExp(r'\s+'), ' ').trim();
    final summary = plain.length > 140 ? '${plain.substring(0, 140)}…' : plain;
    final turnId = '$chatId-${DateTime.now().millisecondsSinceEpoch}';
    final service = TurnNotificationService.shared;
    unawaited(
      (failed
              ? service.showTurnFailed(
                  title: title,
                  turnSummary: summary.isEmpty ? 'The run stopped.' : summary,
                  turnId: turnId,
                  sessionId: chatId,
                  connectionId: connectionId,
                )
              : service.showTurnCompleted(
                  title: title,
                  turnSummary: summary.isEmpty ? 'Done.' : summary,
                  turnId: turnId,
                  sessionId: chatId,
                  connectionId: connectionId,
                ))
          .catchError((Object _) {}),
    );
  }

  Future<void> enterDemo() async {
    await prefs.setBool(_demoKey, true);
    await rebuild();
  }

  Future<void> leaveDemo() async {
    await prefs.setBool(_demoKey, false);
    await rebuild();
  }

  Future<void> useConnection(String id) async {
    await prefs.setString(_activeKey, id);
    await prefs.setBool(_demoKey, false);
    await rebuild();
  }

  void refresh() => notifyListeners();
}

class HermesMobileRoot extends InheritedNotifier<HermesMobileRootController> {
  const HermesMobileRoot({
    super.key,
    required HermesMobileRootController controller,
    required super.child,
  }) : super(notifier: controller);

  static HermesMobileRootController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HermesMobileRoot>()!.notifier!;
}

/// Loads preferences and the engine's secure connection store, then shows
/// either the connect screen or the Petasos shell.
class HermesMobileBootstrap extends StatefulWidget {
  const HermesMobileBootstrap({super.key, this.controller});

  /// Tests and screenshot builds inject a ready controller.
  final HermesMobileRootController? controller;

  @override
  State<HermesMobileBootstrap> createState() => _HermesMobileBootstrapState();
}

class _HermesMobileBootstrapState extends State<HermesMobileBootstrap> {
  HermesMobileRootController? _root;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _root = widget.controller;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    }
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      ConnectionManager? cm;
      if (!kHermesMobileDemo) cm = await ConnectionManager.create(prefs);
      final root = HermesMobileRootController(prefs: prefs, connections: cm);
      await W2DynamicAccents.load(); // --- wave2 ---
      await root.rebuild();
      if (cm != null) {
        // Engine push registration and notification channels, as upstream.
        unawaited(MobilePushService.shared.initialize(cm).catchError((Object _) {}));
        unawaited(
          TurnNotificationService.shared
              .ensureInitialized(requestPermission: true)
              .catchError((Object _) {}),
        );
      }
      if (mounted) setState(() => _root = root);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    if (root == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: hermesMobileTheme(Brightness.light),
        darkTheme: hermesMobileTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Hermes could not open its saved connections.\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
        ),
      );
    }
    return HermesMobileRoot(controller: root, child: const HermesMobileApp());
  }
}

/// Binds the keep-alive service to whichever app state is active.
class _Binder extends StatelessWidget {
  const _Binder({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return KeepAliveBinder(state: HermesMobileRoot.of(context).state, child: child);
  }
}

class HermesMobileApp extends StatelessWidget {
  const HermesMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    final root = HermesMobileRoot.of(context);
    final state = root.state;
    // --- wave2 --- appearance settings (dynamic color, AMOLED, text size)
    final w2 = W2Settings.forPrefs(root.prefs);
    return ListenableBuilder(
      listenable: w2,
      builder: (context, _) => MaterialApp(
      title: 'Hermes',
      debugShowCheckedModeBanner: false,
      themeMode: root.themeMode,
      theme: w2Theme(Brightness.light, w2, dynamicAccents: W2DynamicAccents.cached),
      darkTheme: w2Theme(Brightness.dark, w2, dynamicAccents: W2DynamicAccents.cached),
      // --- end wave2 ---
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: state == null
          ? const ConnectScreen()
          : HermesMobileShell(key: ObjectKey(state)),
      builder: (context, child) {
        // Settings and other routes push above `home`; keep the app state in
        // scope for them too.
        // --- wave2 ---
        final scaled = w2TextScale(context, child!, w2);
        if (state == null) return scaled;
        return _Binder(child: HermesMobileScope(state: state, child: scaled));
        // --- end wave2 ---
      },
    ),
    );
  }
}
