import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import 'w1_dismissed.dart';
import 'w1_models.dart';
import 'w1_services.dart';

/// Notification preferences: quiet hours and per-source mute.
class NotifyPolicy {
  const NotifyPolicy({
    this.enabled = true,
    this.quietStart = 22,
    this.quietEnd = 7,
    this.quietEnabled = true,
    this.muted = const {},
  });

  final bool enabled;

  /// Hours (0-23). Quiet when start > end wraps past midnight.
  final int quietStart;
  final int quietEnd;
  final bool quietEnabled;
  final Set<String> muted;

  bool isQuiet(DateTime t) {
    if (!quietEnabled || quietStart == quietEnd) return false;
    final h = t.hour;
    return quietStart < quietEnd
        ? h >= quietStart && h < quietEnd
        : h >= quietStart || h < quietEnd;
  }

  /// Approvals still alert in quiet hours (silently) because a run is blocked.
  bool shouldNotify(String source, DateTime at, {bool blocking = false}) {
    if (!enabled) return false;
    if (muted.contains(source.toLowerCase())) return false;
    if (isQuiet(at) && !blocking) return false;
    return true;
  }

  NotifyPolicy copyWith({
    bool? enabled,
    int? quietStart,
    int? quietEnd,
    bool? quietEnabled,
    Set<String>? muted,
  }) => NotifyPolicy(
    enabled: enabled ?? this.enabled,
    quietStart: quietStart ?? this.quietStart,
    quietEnd: quietEnd ?? this.quietEnd,
    quietEnabled: quietEnabled ?? this.quietEnabled,
    muted: muted ?? this.muted,
  );

  static const _k = 'hermes_mobile.w1.notify';

  static NotifyPolicy load(SharedPreferences p) => NotifyPolicy(
    enabled: p.getBool('$_k.enabled') ?? true,
    quietStart: p.getInt('$_k.quiet_start') ?? 22,
    quietEnd: p.getInt('$_k.quiet_end') ?? 7,
    quietEnabled: p.getBool('$_k.quiet') ?? true,
    muted: (p.getStringList('$_k.muted') ?? const []).toSet(),
  );

  Future<void> save(SharedPreferences p) async {
    await p.setBool('$_k.enabled', enabled);
    await p.setInt('$_k.quiet_start', quietStart);
    await p.setInt('$_k.quiet_end', quietEnd);
    await p.setBool('$_k.quiet', quietEnabled);
    await p.setStringList('$_k.muted', muted.toList()..sort());
  }
}

/// The proactive feed for one app state: server cards, plus pending approvals
/// as local cards, with dismiss / snooze / act / feedback.
class ProactiveController extends ChangeNotifier {
  ProactiveController(
    this.state, {
    ProactiveSource? source,
    DismissedStore? dismissedStore,
  }) : source = source ?? Wave1Services.of(state.backend).source,
       // ignore: prefer_initializing_formals
       _dismissedStore = dismissedStore {
    state.addListener(_onState);
  }

  final HermesMobileAppState state;
  final ProactiveSource source;

  static final Expando<ProactiveController> _byState = Expando('w1.feed');

  /// One controller per app state (created on first use).
  static ProactiveController of(HermesMobileAppState state) =>
      _byState[state] ??= ProactiveController(state);

  List<ProactiveCard> _server = [];
  bool loading = false;
  bool loaded = false;
  bool available = true;

  /// Live without the Petasos plugin: briefs come from cron runs only.
  bool pluginMissing = false;
  String? error;
  String? lastFeedback;
  NotifyPolicy policy = const NotifyPolicy();
  SharedPreferences? _prefs;
  int _approvalCount = 0;
  bool _disposed = false;

  /// Cards for the feed: pending approvals first, then server cards.
  List<ProactiveCard> get cards => [..._approvalCards(), ..._feed()];

  List<ProactiveCard> get briefs => _server.where((c) => c.isBrief).toList();

  List<ProactiveCard> _feed() => _server.where((c) => !c.isBrief).toList();

  int get unread =>
      state.pendingApprovals.length + _server.where((c) => !c.read).length;

  /// Approvals plus unread approval/alert cards: the "Needs you" counter.
  int get needsYou =>
      state.pendingApprovals.length +
      _server
          .where((c) => !c.read && (c.kind == 'approval' || c.kind == 'alert'))
          .length;

  List<ProactiveCard> _approvalCards() => [
    for (final e in state.pendingApprovals.entries)
      ProactiveCard(
        id: 'approval:${e.key}',
        kind: 'approval',
        source: 'approvals',
        title: state.titleFor(e.key),
        body: e.value.description.isEmpty
            ? e.value.command
            : e.value.description,
        createdAt: DateTime.now(),
        priority: 3,
        chatId: e.key,
        local: true,
        action: const ProactiveAction(
          kind: ProactiveActionKind.approve,
          label: 'Approve',
        ),
      ),
  ];

  void _onState() {
    final n = state.pendingApprovals.length;
    if (n != _approvalCount) {
      _approvalCount = n;
      _notify();
    }
  }

  Future<void> _ensurePrefs() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      policy = NotifyPolicy.load(_prefs!);
      _dismissedStore ??= DismissedStore(_prefs!);
    } catch (_) {}
  }

  DismissedStore? _dismissedStore;

  /// Cards swiped away in the last 14 days, newest first (empty until prefs
  /// load).
  List<DismissedEntry> get dismissed => _dismissedStore?.list() ?? const [];

  /// Cards swiped away whose Undo window is still open: hidden here, not yet
  /// sent to the server. Value: the card and its index in the server list.
  final Map<String, ({ProactiveCard card, int index})> _staged = {};

  bool isStaged(String id) => _staged.containsKey(id);

  Future<void> setPolicy(NotifyPolicy p) async {
    policy = p;
    _notify();
    await _ensurePrefs();
    if (_prefs != null) await p.save(_prefs!);
  }

  Future<void> refresh() async {
    await _ensurePrefs();
    loading = true;
    _notify();
    final feed = await source.load();
    available = feed.available;
    pluginMissing = feed.pluginMissing;
    error = feed.error;
    if (feed.available && feed.error == null) {
      final ids = feed.cards.map((c) => c.id).toSet();
      _server = [
        for (final c in feed.cards)
          if (!_staged.containsKey(c.id)) c,
        // Restored on the phone while the host could not un-dismiss.
        for (final c
            in _dismissedStore?.pinnedCards() ?? const <ProactiveCard>[])
          if (!ids.contains(c.id) && !_staged.containsKey(c.id)) c,
      ];
    }
    loading = false;
    loaded = true;
    _notify();
  }

  void _drop(String id) {
    _server = _server.where((c) => c.id != id).toList();
    _notify();
  }

  /// Dismiss now, with no Undo window (used by tests and non-UI callers).
  Future<void> dismiss(ProactiveCard card) async {
    if (card.local) return;
    if (!stageDismiss(card)) return;
    await commitDismiss(card.id);
  }

  /// Hides [card] locally and remembers where it was. The server is not told
  /// until [commitDismiss]; [undoDismiss] puts it back in place. Returns false
  /// for cards that cannot be dismissed.
  bool stageDismiss(ProactiveCard card) {
    if (card.local) return false;
    final i = _server.indexWhere((c) => c.id == card.id);
    if (i < 0) return false;
    _staged[card.id] = (card: _server[i], index: i);
    _drop(card.id);
    return true;
  }

  /// Puts a staged card back where it was. Nothing reaches the server.
  void undoDismiss(String id) {
    final s = _staged.remove(id);
    if (s == null) return;
    if (_server.any((c) => c.id == id)) return;
    final list = [..._server];
    list.insert(s.index.clamp(0, list.length), s.card);
    _server = list;
    _notify();
  }

  /// Sends a staged dismiss to the server and files the card under Dismissed.
  Future<void> commitDismiss(String id) async {
    final s = _staged.remove(id);
    if (s == null) return;
    await _ensurePrefs();
    try {
      await _dismissedStore?.add(s.card);
    } catch (_) {}
    try {
      await source.dismiss(id);
    } catch (e) {
      error = '$e';
      _notify();
    }
  }

  /// Brings a dismissed card back into the feed. The server is asked to
  /// un-dismiss it; when it cannot (an older plugin) the card stays restored
  /// on this phone. Returns true when the server took it.
  Future<bool> restore(DismissedEntry entry) async {
    await _ensurePrefs();
    final card = entry.card;
    if (!_server.any((c) => c.id == card.id)) {
      final list = [..._server, card]
        ..sort((a, b) {
          final p = b.priority.compareTo(a.priority);
          return p != 0 ? p : b.createdAt.compareTo(a.createdAt);
        });
      _server = list;
    }
    var server = true;
    try {
      await source.restore(card.id);
      await _dismissedStore?.remove(card.id);
    } catch (_) {
      server = false;
      await _dismissedStore?.pin(card.id);
    }
    _notify();
    return server;
  }

  /// Removes one entry from Dismissed for good (the card stays dismissed).
  Future<void> forgetDismissed(String id) async {
    await _ensurePrefs();
    await _dismissedStore?.remove(id);
    _notify();
  }

  Future<void> markRead(ProactiveCard card) async {
    if (card.read || card.local) return;
    _server = [
      for (final c in _server) c.id == card.id ? c.copyWith(read: true) : c,
    ];
    _notify();
    unawaited(source.markRead(card.id).catchError((Object _) {}));
  }

  Future<void> snooze(ProactiveCard card, [Duration? d]) async {
    if (card.local) return;
    final minutes = (card.action?.payload['minutes'] as num?)?.toInt();
    final dur = d ?? Duration(minutes: minutes ?? 60);
    _drop(card.id);
    try {
      await source.snooze(card.id, dur);
    } catch (e) {
      error = '$e';
      _notify();
    }
  }

  /// Saves more/less feedback to Hermes memory.
  Future<void> feedback(ProactiveCard card, bool more) async {
    try {
      lastFeedback = await source.feedback(card, more);
    } catch (e) {
      error = 'Could not save feedback: $e';
    }
    _notify();
  }

  /// Runs the card's one action. [reply] is the inline reply text.
  /// Returns the chat to open, if the action leads to one.
  Future<HermesMobileChat?> act(ProactiveCard card, {String? reply}) async {
    final action = card.action;
    if (action == null) return null;
    HermesMobileChat? open;
    try {
      switch (action.kind) {
        case ProactiveActionKind.approve:
          if (card.chatId != null &&
              state.pendingApprovals.containsKey(card.chatId)) {
            await state.controllerById(card.chatId!)?.answer('once');
          } else {
            final prompt = action.payload['prompt']?.toString();
            if (prompt != null && prompt.isNotEmpty) {
              open = _sendInNewChat(prompt);
            }
          }
        case ProactiveActionKind.snooze:
          await snooze(card);
          return null;
        case ProactiveActionKind.reply:
          final text = (reply ?? '').trim();
          if (text.isEmpty) return null;
          final excerpt = card.body.length > 600
              ? '${card.body.substring(0, 600)}…'
              : card.body;
          if (card.chatId != null) {
            final ctl = state.controllerFor(
              HermesMobileChat(id: card.chatId!, title: card.title),
            );
            unawaited(ctl.send(text));
            open = HermesMobileChat(id: card.chatId!, title: card.title);
          } else {
            open = _sendInNewChat('$text\n\n(Re: "${card.title}")\n$excerpt');
          }
        case ProactiveActionKind.run:
          final cronId = action.payload['cron_id']?.toString();
          final prompt = action.payload['prompt']?.toString();
          if (cronId != null && cronId.isNotEmpty) {
            await state.backend.runCron(cronId);
          } else if (prompt != null && prompt.isNotEmpty) {
            open = _sendInNewChat(prompt);
          }
        case ProactiveActionKind.open:
          if (card.chatId != null) {
            open = HermesMobileChat(id: card.chatId!, title: card.title);
          }
      }
      if (!card.local) {
        _drop(card.id);
        await source.acted(card.id, action.kind);
      }
    } catch (e) {
      error = '$e';
      _notify();
    }
    return open;
  }

  HermesMobileChat _sendInNewChat(String text) {
    final ctl = state.newChat();
    unawaited(ctl.send(text));
    return HermesMobileChat(id: ctl.chatId, title: ctl.title);
  }

  /// Re-notifies listeners (e.g. after the pinned widget panel changed).
  void touch() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_onState);
    super.dispose();
  }
}
