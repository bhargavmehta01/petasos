import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import 'w1_brief_screen.dart';
import 'w1_controller.dart';
import 'w1_launch.dart';
import 'w1_notifications.dart';
import 'w1_widgets_bridge.dart';

/// Wires Wave 1 into the shell: feed refresh, background approval and card
/// notifications, launcher/QS-tile/share entry points, home-screen widgets.
class Wave1Binder extends StatefulWidget {
  const Wave1Binder({
    super.key,
    required this.onOpenChat,
    required this.child,
    this.enablePlatform = true,
  });

  final void Function(HermesMobileChat chat) onOpenChat;
  final Widget child;

  /// Tests turn off notifications, channels and timers.
  final bool enablePlatform;

  @override
  State<Wave1Binder> createState() => _Wave1BinderState();
}

class _Wave1BinderState extends State<Wave1Binder> with WidgetsBindingObserver {
  HermesMobileAppState? _state;
  ProactiveController? _feed;
  Set<String> _approvals = {};
  Timer? _poll;
  StreamSubscription<HermesMobileLaunchRequest>? _launchSub;
  static const _notifiedKey = 'hermes_mobile.w1.notified_cards';

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = HermesMobileScope.read(context);
    if (identical(state, _state)) return;
    _detach();
    _state = state;
    _feed = ProactiveController.of(state);
    _approvals = state.pendingApprovals.keys.toSet();
    state.addListener(_onState);
    _feed!.addListener(_syncWidgets);
    state.addListener(_syncWidgets);
    unawaited(_feed!.refresh());
    if (widget.enablePlatform) {
      Wave1Notifier.shared.attach(state, widget.onOpenChat);
      unawaited(HermesMobileLaunchBridge.shared.start());
      _launchSub = HermesMobileLaunchBridge.shared.listen(_onLaunch);
    }
  }

  void _detach() {
    final s = _state;
    if (s == null) return;
    s.removeListener(_onState);
    s.removeListener(_syncWidgets);
    _feed?.removeListener(_syncWidgets);
    if (widget.enablePlatform) {
      Wave1Notifier.shared.detach(s);
      _launchSub?.cancel();
      HermesMobileLaunchBridge.shared.unlisten();
    }
    _launchSub = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _detach();
    super.dispose();
  }

  // ── approvals while backgrounded ────────────────────────────────────
  void _onState() {
    final state = _state!;
    final now = state.pendingApprovals.keys.toSet();
    final added = now.difference(_approvals);
    final gone = _approvals.difference(now);
    _approvals = now;
    if (!widget.enablePlatform) return;
    for (final id in gone) {
      unawaited(Wave1Notifier.shared.cancel('approval:$id'));
    }
    if (_foreground) return;
    for (final id in added) {
      final a = state.pendingApprovals[id];
      if (a == null) continue;
      unawaited(
        Wave1Notifier.shared.showApproval(
          id,
          state.titleFor(id),
          a,
          _feed!.policy,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!widget.enablePlatform) return;
    if (s == AppLifecycleState.resumed) {
      _poll?.cancel();
      _poll = null;
      Wave1Notifier.shared.onResumed();
      unawaited(_feed?.refresh());
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      // Posted approvals that are already pending when the app goes away.
      final state = _state;
      if (state != null) {
        for (final e in state.pendingApprovals.entries) {
          unawaited(
            Wave1Notifier.shared.showApproval(
              e.key,
              state.titleFor(e.key),
              e.value,
              _feed!.policy,
            ),
          );
        }
      }
      _poll ??= Timer.periodic(const Duration(minutes: 15), (_) => _pollFeed());
    }
  }

  /// While the process lives in the background (a turn streaming, the
  /// keep-alive service), check the feed and notify new cards.
  Future<void> _pollFeed() async {
    final feed = _feed;
    if (feed == null || _foreground) return;
    await feed.refresh();
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(_notifiedKey) ?? const []).toSet();
    final fresh = [
      for (final c in [...feed.briefs, ...feed.cards])
        if (!c.local && !c.read && !seen.contains(c.id)) c,
    ];
    if (fresh.isEmpty) return;
    await Wave1Notifier.shared.showCards(fresh, feed.policy);
    final keep = [...seen, ...fresh.map((c) => c.id)];
    await prefs.setStringList(
      _notifiedKey,
      keep.length > 300 ? keep.sublist(keep.length - 300) : keep,
    );
  }

  // ── widgets ─────────────────────────────────────────────────────────
  Future<void> _syncWidgets() async {
    if (!widget.enablePlatform) return;
    final feed = _feed;
    final state = _state;
    if (feed == null || state == null) return;
    String? pinned;
    try {
      pinned = (await SharedPreferences.getInstance()).getString(
        HermesMobileWidgetBridge.pinnedPanelKey,
      );
    } catch (_) {}
    await HermesMobileWidgetBridge.shared.push(
      HermesMobileWidgetBridge.snapshot(
        briefs: feed.briefs,
        feed: feed.cards,
        needsYou: feed.needsYou,
        panels: state.panels,
        pinnedPanelId: pinned,
      ),
    );
  }

  // ── launcher shortcuts, QS tile, widgets, share sheet ───────────────
  Future<void> _onLaunch(HermesMobileLaunchRequest r) async {
    if (!mounted) return;
    // Let the first frame (and any route) settle.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    HermesMobileChat? chat;
    switch (r.mode) {
      case QuickCaptureMode.brief:
        chat = await openBrief(context);
      case QuickCaptureMode.needsYou:
        chat = await openBrief(context, tab: 1);
      default:
        chat = await showQuickCapture(context, r);
    }
    if (chat != null && mounted) widget.onOpenChat(chat);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
