import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/services/background_work_prefs.dart';
import '../../core/services/connection_keepalive_service.dart';
import 'app_state.dart';

/// Keeps a running turn alive while Hermes is in the background, using the
/// engine's foreground keep-alive service. Without it Android may drop the
/// SSE stream, and the API server treats a dropped client as an interrupt.
class KeepAliveBinder extends StatefulWidget {
  const KeepAliveBinder({super.key, required this.state, required this.child});
  final HermesMobileAppState? state;
  final Widget child;

  @override
  State<KeepAliveBinder> createState() => _KeepAliveBinderState();
}

class _KeepAliveBinderState extends State<KeepAliveBinder>
    with WidgetsBindingObserver {
  final _keepAlive = ConnectionKeepAliveService();
  HermesMobileAppState? _listening;

  bool get _active =>
      widget.state != null &&
      !widget.state!.backend.isDemo &&
      widget.state!.runningChats.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keepAlive.onPolicyChanged(false);
    _attach();
    unawaited(
      BackgroundWorkPrefsStore.load()
          .then((_) {
            if (mounted) {
              _keepAlive.onPolicyChanged(BackgroundWorkPrefsStore.confirmedEnabled);
            }
          })
          .catchError((Object _) {}),
    );
    BackgroundWorkPrefsStore.confirmedChanges.addListener(_onPolicy);
  }

  void _onPolicy() =>
      _keepAlive.onPolicyChanged(BackgroundWorkPrefsStore.confirmedEnabled);

  void _attach() {
    if (identical(_listening, widget.state)) return;
    _listening?.removeListener(_onState);
    _listening = widget.state;
    _listening?.addListener(_onState);
    _onState();
  }

  void _onState() => _keepAlive.onTurnActivityChanged(_active);

  @override
  void didUpdateWidget(KeepAliveBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _keepAlive.onAppLifecycleState(state, hasActiveTurn: _active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BackgroundWorkPrefsStore.confirmedChanges.removeListener(_onPolicy);
    _listening?.removeListener(_onState);
    unawaited(_keepAlive.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
