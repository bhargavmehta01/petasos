import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../chat/chat_controller.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'w4_api.dart';
import 'w4_extract.dart';
import 'w4_models.dart';

/// One local action waiting out its undo window.
class UndoTicket {
  UndoTicket({required this.id, required this.label, required this.deadline});
  final String id;
  final String label;
  final DateTime deadline;
  final Completer<bool> _done = Completer<bool>();
  Timer? _timer;
  bool cancelled = false;

  /// Completes true when the action ran, false when it was undone.
  Future<bool> get result => _done.future;

  Duration remaining(DateTime now) {
    final d = deadline.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// All Wave 4 state for one backend: watchers, commitments, the overnight
/// recap, held outbound actions, the proactivity dial, context triggers, the
/// offline queue and local undo windows.
///
/// Reach it with `HermesMobileScope.of(context).wave4` (see [Wave4StateX]); it lives
/// as long as the [HermesMobileAppState] it hangs off.
class Wave4Controller extends ChangeNotifier {
  Wave4Controller(this.app, {Wave4Api? api, SharedPreferences? preferences})
    : api = api ?? wave4ApiFor(app.backend),
      _prefs = preferences;

  final HermesMobileAppState app;
  final Wave4Api api;
  SharedPreferences? _prefs;
  bool _disposed = false;
  bool _started = false;

  static const _kPrefix = 'hermes_mobile.w4.';
  static const kRecapSeen = '${_kPrefix}recap_seen';
  static const kLevel = '${_kPrefix}proactivity';
  static const kLevelSynced = '${_kPrefix}proactivity_synced';
  static const kTriggers = '${_kPrefix}triggers';
  static const kQueue = '${_kPrefix}queue';
  static const kCommitDone = '${_kPrefix}commitments_done';
  static const kLocalCommitments = '${_kPrefix}commitments_local';
  static const kDismissedProposals = '${_kPrefix}dismissed_proposals';
  static const kUndoSeconds = '${_kPrefix}undo_seconds';

  /// Undo window for outbound actions started on this phone.
  static const defaultUndo = Duration(seconds: 10);

  /// Same trigger at most once per this long.
  static const triggerCooldown = Duration(minutes: 30);

  // ── public state ───────────────────────────────────────────────────
  bool pluginChecked = false;
  bool get pluginAvailable => api.pluginAvailable;

  List<HermesMobileWatcher> watchers = [];
  bool watchersLoading = false;
  String? watchersError;
  WatcherProposal? proposal;

  List<HermesMobileCommitment> commitments = [];
  bool commitmentsLoading = false;

  List<AutonomousAction> recap = [];
  DateTime recapSince = DateTime.now().subtract(const Duration(hours: 12));
  bool recapLoading = false;
  bool recapDismissed = false;

  List<HeldOutbound> held = [];
  final List<UndoTicket> tickets = [];

  ProactivityLevel level = ProactivityLevel.balanced;

  /// True when the dial is saved on the server as a standing rule.
  bool levelSynced = false;

  List<ContextTrigger> triggers = [
    for (final k in ContextTriggerKind.values) ContextTrigger(kind: k),
  ];

  bool online = true;
  List<QueuedMessage> queue = [];
  bool flushing = false;

  Duration undoWindow = defaultUndo;

  Timer? _healthTimer;
  Timer? _heldTimer;
  int _seq = 0;
  final Set<String> _doneIds = {};
  final List<HermesMobileCommitment> _localCommitments = [];
  final Set<String> _dismissedProposals = {};

  static const contextChannel = MethodChannel(
    'com.hermesagent.hermes_android/hermes_mobile_context',
  );

  // ── lifecycle ──────────────────────────────────────────────────────

  /// Loads local state, probes the plugin, then fetches everything once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _loadLocal();
    _listenContext();
    await refreshAll();
    if (queue.isNotEmpty) _startHealthPolling();
  }

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> _loadLocal() async {
    try {
      final p = await _p;
      final seen = p.getInt(kRecapSeen);
      if (seen != null) {
        final t = DateTime.fromMillisecondsSinceEpoch(seen);
        // Never look back further than 24h; never newer than 12h ago on start
        // so the morning recap covers the night.
        final floor = DateTime.now().subtract(const Duration(hours: 24));
        recapSince = t.isBefore(floor) ? floor : t;
      }
      level = ProactivityLevelX.parse(p.getString(kLevel));
      levelSynced = p.getBool(kLevelSynced) ?? false;
      undoWindow = Duration(seconds: p.getInt(kUndoSeconds) ?? 10);
      final trig = p.getString(kTriggers);
      if (trig != null) {
        final list = (jsonDecode(trig) as List)
            .whereType<Map>()
            .map((m) => ContextTrigger.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        triggers = [
          for (final k in ContextTriggerKind.values)
            list.where((t) => t.kind == k).firstOrNull ??
                ContextTrigger(kind: k),
        ];
      }
      final q = p.getString(kQueue);
      if (q != null) {
        queue = (jsonDecode(q) as List)
            .whereType<Map>()
            .map((m) => QueuedMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      _doneIds.addAll(p.getStringList(kCommitDone) ?? const []);
      _dismissedProposals.addAll(
        p.getStringList(kDismissedProposals) ?? const [],
      );
      final local = p.getString(kLocalCommitments);
      if (local != null) {
        _localCommitments.addAll(
          (jsonDecode(local) as List).whereType<Map>().map(
            (m) => HermesMobileCommitment.fromJson(Map<String, dynamic>.from(m)),
          ),
        );
      }
    } catch (_) {
      // Corrupt local state is not worth crashing over; start fresh.
    }
  }

  Future<void> refreshAll() async {
    try {
      await api.probe();
    } catch (_) {}
    pluginChecked = true;
    _notify();
    await Future.wait([
      refreshWatchers(),
      refreshCommitments(),
      refreshRecap(),
      refreshHeld(),
      _syncLevelFromServer(),
    ]);
  }

  // ── watchers ───────────────────────────────────────────────────────

  Future<void> refreshWatchers() async {
    watchersLoading = true;
    _notify();
    try {
      watchers = [
        for (final w in await api.watchers())
          if (!_stoppingWatchers.contains(w.id)) w,
      ];
      watchersError = null;
    } catch (e) {
      watchersError = '$e';
    }
    watchersLoading = false;
    _computeProposal();
    _notify();
  }

  Future<void> createWatcher({
    required String title,
    required String target,
    String every = 'Every 6 hours',
    String? condition,
  }) async {
    await api.createWatcher(
      title: title,
      target: target,
      every: every,
      condition: condition,
    );
    proposal = null;
    await refreshWatchers();
  }

  Future<void> togglePaused(HermesMobileWatcher w) async {
    await api.setWatcherPaused(w, !w.paused);
    await refreshWatchers();
  }

  Future<void> checkNow(HermesMobileWatcher w) async {
    await api.checkWatcherNow(w);
    await refreshWatchers();
  }

  Future<void> deleteWatcher(HermesMobileWatcher w) async {
    await api.deleteWatcher(w);
    await refreshWatchers();
  }

  /// Watchers hidden while their "Stopped watching" Undo is open.
  final Set<String> _stoppingWatchers = {};

  /// Hides [w] now; returns its old index. [commitDeleteWatcher] deletes it
  /// on the host, [undoDeleteWatcher] puts it back.
  int stageDeleteWatcher(HermesMobileWatcher w) {
    final i = watchers.indexWhere((x) => x.id == w.id);
    _stoppingWatchers.add(w.id);
    if (i >= 0) {
      watchers = [...watchers]..removeAt(i);
      _notify();
    }
    return i;
  }

  void undoDeleteWatcher(HermesMobileWatcher w, int index) {
    _stoppingWatchers.remove(w.id);
    if (watchers.any((x) => x.id == w.id)) return;
    watchers = [...watchers]
      ..insert(index < 0 ? 0 : index.clamp(0, watchers.length), w);
    _notify();
  }

  Future<void> commitDeleteWatcher(HermesMobileWatcher w) async {
    try {
      await api.deleteWatcher(w);
    } catch (e) {
      watchersError = 'Could not stop watching: $e';
    }
    _stoppingWatchers.remove(w.id);
    await refreshWatchers();
  }

  int get watchersNeedingYou => watchers
      .where(
        (w) =>
            w.status == WatcherStatus.changed ||
            w.status == WatcherStatus.error,
      )
      .length;

  /// The questions the user asked recently, from chat titles and the chats
  /// open on this phone.
  List<MapEntry<String, String>> _recentAsks() {
    final asks = <MapEntry<String, String>>[];
    for (final c in app.chats.take(40)) {
      asks.add(MapEntry(c.id, c.displayTitle));
      final ctl = app.controllerById(c.id);
      if (ctl != null) {
        for (final m in ctl.messages.where((m) => m.isUser).skip(1)) {
          asks.add(MapEntry(c.id, m.text));
        }
      }
    }
    if (app.backend.isDemo) {
      asks.addAll(const [
        MapEntry('demo-a', 'What is the Braves Fest ticket price now?'),
        MapEntry('demo-b', 'Braves Fest ticket price again?'),
        MapEntry('demo-c', 'Did the Braves Fest ticket price drop?'),
      ]);
    }
    return asks;
  }

  void _computeProposal() {
    if (level == ProactivityLevel.quiet) {
      proposal = null;
      return;
    }
    final p = proposeWatcher(
      _recentAsks(),
      minCount: level == ProactivityLevel.chatty ? 2 : 3,
      dismissed: _dismissedProposals,
    );
    if (p == null) {
      proposal = null;
      return;
    }
    final already = watchers.any(
      (w) => w.title.toLowerCase().contains(p.topic.toLowerCase()),
    );
    proposal = already ? null : p;
  }

  Future<void> dismissProposal() async {
    final p = proposal;
    if (p == null) return;
    _dismissedProposals.add(p.topic.toLowerCase());
    proposal = null;
    _notify();
    try {
      (await _p).setStringList(
        kDismissedProposals,
        _dismissedProposals.toList(),
      );
    } catch (_) {}
  }

  // ── commitments ────────────────────────────────────────────────────

  Future<void> refreshCommitments({bool scanChats = false}) async {
    commitmentsLoading = true;
    _notify();
    final byId = <String, HermesMobileCommitment>{};
    try {
      for (final c in await api.commitments()) {
        byId[c.id] = c;
      }
    } catch (_) {}
    // Extract from chats open on this phone (and recent ones on request).
    final local = <HermesMobileCommitment>[..._localCommitments];
    for (final chat in app.chats.take(scanChats ? 8 : 40)) {
      ChatController? ctl = app.controllerById(chat.id);
      List<HermesMobileMessage>? msgs = ctl?.messages;
      if ((msgs == null || msgs.isEmpty) && scanChats && !chat.isDraft) {
        try {
          msgs = await app.backend.loadMessages(chat.id);
        } catch (_) {}
      }
      if (msgs == null || msgs.isEmpty) continue;
      local.addAll(
        extractCommitments(msgs, chatId: chat.id, chatTitle: chat.displayTitle),
      );
    }
    for (final c in local) {
      byId.putIfAbsent(c.id, () => c);
    }
    // Remember phone-extracted ones so they outlive the open chat.
    _localCommitments
      ..clear()
      ..addAll(byId.values.where((c) => c.source == 'chat'));
    commitments = [
      for (final c in byId.values)
        _doneIds.contains(c.id) ? c.copyWith(done: true) : c,
    ]..sort(_byDue);
    commitmentsLoading = false;
    _notify();
    try {
      (await _p).setString(
        kLocalCommitments,
        jsonEncode(_localCommitments.take(100).map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  static int _byDue(HermesMobileCommitment a, HermesMobileCommitment b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    final ad = a.due, bd = b.due;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }

  Future<void> setCommitmentDone(HermesMobileCommitment c, bool done) async {
    if (done) {
      _doneIds.add(c.id);
    } else {
      _doneIds.remove(c.id);
    }
    commitments = [
      for (final x in commitments) x.id == c.id ? x.copyWith(done: done) : x,
    ]..sort(_byDue);
    _notify();
    try {
      (await _p).setStringList(kCommitDone, _doneIds.toList());
      if (c.source != 'chat') await api.saveCommitment(c.copyWith(done: done));
    } catch (_) {}
  }

  int dueCount(DateTime now) => commitments
      .where(
        (c) =>
            !c.done &&
            c.due != null &&
            c.due!.isBefore(now.add(const Duration(hours: 24))),
      )
      .length;

  // ── recap ──────────────────────────────────────────────────────────

  Future<void> refreshRecap() async {
    recapLoading = true;
    _notify();
    try {
      recap = await api.recap(recapSince);
    } catch (_) {
      recap = [];
    }
    recapLoading = false;
    _notify();
  }

  /// "While you slept" shows in the morning (5–12) or whenever there are
  /// autonomous actions the user has not seen yet.
  bool showRecap(DateTime now) {
    if (recapDismissed || recap.isEmpty) return false;
    if (recap.any((a) => !a.ok)) return true;
    return level != ProactivityLevel.quiet;
  }

  Future<void> markRecapSeen() async {
    recapDismissed = true;
    _notify();
    try {
      (await _p).setInt(kRecapSeen, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<bool> revert(AutonomousAction a) async {
    final ok = await api.revert(a);
    if (ok) {
      recap = [
        for (final x in recap) x.id == a.id ? x.copyWith(reverted: true) : x,
      ];
      _notify();
    }
    return ok;
  }

  // ── held outbound (server undo window) ─────────────────────────────

  Future<void> refreshHeld() async {
    try {
      held = await api.heldOutbound();
    } catch (_) {
      held = [];
    }
    _heldTimer?.cancel();
    if (held.isNotEmpty && !_disposed) {
      _heldTimer = Timer(const Duration(seconds: 1), refreshHeld);
    }
    _notify();
  }

  Future<bool> undoHeld(HeldOutbound h) async {
    final ok = await api.undoOutbound(h);
    held = [
      for (final x in held)
        if (x.id != h.id) x,
    ];
    _notify();
    return ok;
  }

  // ── local undo window ──────────────────────────────────────────────

  /// Runs [commit] after the undo window unless [undo] is called first.
  /// With the window set to zero it runs right away.
  UndoTicket hold(String label, Future<void> Function() commit) {
    final ticket = UndoTicket(
      id: 'u${_seq++}',
      label: label,
      deadline: DateTime.now().add(undoWindow),
    );
    Future<void> run() async {
      tickets.remove(ticket);
      _notify();
      if (ticket.cancelled) return;
      try {
        await commit();
      } finally {
        if (!ticket._done.isCompleted) ticket._done.complete(true);
      }
    }

    if (undoWindow == Duration.zero) {
      unawaited(run());
    } else {
      tickets.add(ticket);
      ticket._timer = Timer(undoWindow, run);
      _notify();
    }
    return ticket;
  }

  void undo(UndoTicket ticket) {
    if (ticket._done.isCompleted) return;
    ticket.cancelled = true;
    ticket._timer?.cancel();
    tickets.remove(ticket);
    ticket._done.complete(false);
    _notify();
  }

  Future<void> setUndoWindow(Duration d) async {
    undoWindow = d;
    _notify();
    try {
      (await _p).setInt(kUndoSeconds, d.inSeconds);
    } catch (_) {}
  }

  // ── proactivity dial ───────────────────────────────────────────────

  Future<void> _syncLevelFromServer() async {
    try {
      final server = await api.proactivity();
      if (server != null) {
        level = server;
        levelSynced = true;
        (await _p).setString(kLevel, level.name);
      }
    } catch (_) {}
    _notify();
  }

  /// Saves the dial locally and as a standing rule on the server. Returns
  /// true when the server stored it.
  Future<bool> setLevel(ProactivityLevel l) async {
    level = l;
    _computeProposal();
    _notify();
    var synced = false;
    try {
      synced = await api.setProactivity(l);
    } catch (_) {}
    levelSynced = synced;
    _notify();
    try {
      final p = await _p;
      await p.setString(kLevel, l.name);
      await p.setBool(kLevelSynced, synced);
    } catch (_) {}
    return synced;
  }

  /// Fallback when the plugin is missing: ask the agent to remember the rule.
  Future<void> saveLevelViaChat() async {
    final ctl = app.controllerFor(
      HermesMobileChat(
        id: app.backend.newChatId(),
        title: 'Proactivity: ${level.label}',
        isDraft: true,
      ),
    );
    await ctl.send(
      'Save this as a standing rule in your memory, replacing any older '
      'proactivity rule: "${level.rule}"',
    );
    levelSynced = ctl.error == null;
    _notify();
  }

  // ── context triggers ───────────────────────────────────────────────

  void _listenContext() {
    try {
      contextChannel.setMethodCallHandler((call) async {
        if (call.method != 'signal') return null;
        final args = call.arguments is Map
            ? Map<String, dynamic>.from(call.arguments as Map)
            : const <String, dynamic>{};
        final kind = ContextTriggerKindX.parse(args['kind']?.toString());
        if (kind != null) {
          await onSignal(kind, param: args['param']?.toString());
        }
        return null;
      });
      unawaited(_pushTriggerConfig());
    } catch (_) {}
  }

  /// Tells the native side which signals to listen for. Missing native code
  /// (tests, older builds) is fine: triggers then only fire from the UI.
  Future<void> _pushTriggerConfig() async {
    try {
      await contextChannel.invokeMethod('configure', {
        'triggers': [for (final t in triggers) t.toJson()],
      });
    } catch (_) {}
  }

  /// Asks Android for the permissions a trigger needs. Returns false when
  /// the user declined or the native side is missing.
  Future<bool> requestPermission(ContextTriggerKind kind) async {
    try {
      return await contextChannel.invokeMethod<bool>('requestPermission', {
            'kind': kind.wire,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateTrigger(ContextTrigger t) async {
    triggers = [for (final x in triggers) x.kind == t.kind ? t : x];
    _notify();
    try {
      (await _p).setString(
        kTriggers,
        jsonEncode([for (final x in triggers) x.toJson()]),
      );
    } catch (_) {}
    await _pushTriggerConfig();
  }

  /// A native signal arrived. Runs the trigger's prompt in a new chat when
  /// the trigger is on and out of its cooldown. Returns the chat id or null.
  Future<String?> onSignal(
    ContextTriggerKind kind, {
    String? param,
    DateTime? now,
    bool force = false,
  }) async {
    final t = triggers.firstWhere((x) => x.kind == kind);
    final at = now ?? DateTime.now();
    if (!force) {
      if (!t.enabled) return null;
      if (t.lastFired != null &&
          at.difference(t.lastFired!) < triggerCooldown) {
        return null;
      }
      if (kind == ContextTriggerKind.chargingAtNight &&
          !(at.hour >= 21 || at.hour < 2)) {
        return null;
      }
      if (kind == ContextTriggerKind.carBluetooth &&
          (t.param?.isNotEmpty ?? false) &&
          param != null &&
          !param.toLowerCase().contains(t.param!.toLowerCase())) {
        return null;
      }
    }
    await updateTrigger(t.copyWith(lastFired: at));
    final id = app.backend.newChatId();
    final ctl = app.controllerFor(
      HermesMobileChat(id: id, title: kind.label, isDraft: true),
    );
    unawaited(api.logTrigger(t));
    unawaited(ctl.send(t.effectivePrompt));
    return id;
  }

  // ── offline queue ──────────────────────────────────────────────────

  /// Queues a message for later. Used when Hermes is unreachable.
  Future<QueuedMessage> enqueue(
    ChatController ctl,
    String text,
    String? image,
  ) async {
    final q = QueuedMessage(
      id: 'q${DateTime.now().microsecondsSinceEpoch}',
      chatId: ctl.chatId,
      chatTitle: ctl.title,
      text: text,
      imageDataUrl: image,
      queuedAt: DateTime.now(),
    );
    queue = [...queue, q];
    online = false;
    _notify();
    await _saveQueue();
    _startHealthPolling();
    return q;
  }

  List<QueuedMessage> queuedFor(String chatId) => [
    for (final q in queue)
      if (q.chatId == chatId) q,
  ];

  Future<void> removeQueued(QueuedMessage q) async {
    queue = [
      for (final x in queue)
        if (x.id != q.id) x,
    ];
    _notify();
    await _saveQueue();
  }

  Future<void> _saveQueue() async {
    try {
      (await _p).setString(
        kQueue,
        jsonEncode([for (final q in queue) q.toJson()]),
      );
    } catch (_) {}
  }

  /// A send just failed. When it failed because Hermes was unreachable, the
  /// exchange moves into the queue instead of showing an error.
  Future<bool> captureFailedSend(
    ChatController ctl,
    String text,
    String? image,
  ) async {
    if (!isOfflineError(ctl.error)) return false;
    final msgs = ctl.messages;
    if (msgs.length >= 2 &&
        msgs[msgs.length - 2].isUser &&
        msgs[msgs.length - 2].text == text.trim()) {
      msgs.removeRange(msgs.length - 2, msgs.length);
    }
    ctl.error = null;
    ctl.wave4Refresh();
    await enqueue(ctl, text, image);
    return true;
  }

  void _startHealthPolling() {
    _healthTimer?.cancel();
    if (_disposed) return;
    _healthTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => checkOnline(),
    );
  }

  /// Checks Hermes once; on success flushes the queue.
  Future<bool> checkOnline() async {
    bool ok;
    try {
      ok = await app.backend.checkHealth();
    } catch (_) {
      ok = false;
    }
    online = ok;
    _notify();
    if (ok) {
      if (queue.isEmpty) _healthTimer?.cancel();
      await flush();
    }
    return ok;
  }

  /// Sends every queued message in order. Stops at the first one that fails
  /// for lack of a connection, which goes back to the front of the queue.
  Future<int> flush() async {
    if (flushing || queue.isEmpty) return 0;
    flushing = true;
    _notify();
    var sent = 0;
    try {
      while (queue.isNotEmpty && !_disposed) {
        final q = queue.first;
        final title = q.chatTitle ?? app.titleFor(q.chatId);
        final ctl = app.controllerFor(HermesMobileChat(id: q.chatId, title: title));
        while (ctl.running) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        queue = queue.sublist(1);
        await _saveQueue();
        await ctl.send(q.text, imageDataUrl: q.imageDataUrl);
        if (isOfflineError(ctl.error)) {
          final msgs = ctl.messages;
          if (msgs.length >= 2) msgs.removeRange(msgs.length - 2, msgs.length);
          ctl.error = null;
          ctl.wave4Refresh();
          queue = [q, ...queue];
          await _saveQueue();
          online = false;
          _startHealthPolling();
          break;
        }
        sent++;
      }
    } finally {
      flushing = false;
      if (queue.isEmpty) _healthTimer?.cancel();
      _notify();
    }
    return sent;
  }

  // ── glance (widgets, Wear tile) ────────────────────────────────────

  Wave4Glance glance(DateTime now) {
    final due = dueCount(now);
    final changed = watchersNeedingYou;
    String? headline;
    if (changed > 0) {
      headline = watchers
          .where((w) => w.status == WatcherStatus.changed)
          .map((w) => '${w.title}: ${w.lastValue ?? 'changed'}')
          .firstOrNull;
    }
    headline ??= due > 0 ? '$due due today' : null;
    return Wave4Glance(
      watchersChanged: changed,
      commitmentsDue: due,
      overnightActions: recap.length,
      queued: queue.length,
      headline: headline,
    );
  }

  // ── plumbing ───────────────────────────────────────────────────────

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _healthTimer?.cancel();
    _heldTimer?.cancel();
    for (final t in List.of(tickets)) {
      t._timer?.cancel();
    }
    try {
      contextChannel.setMethodCallHandler(null);
    } catch (_) {}
    api.dispose();
    super.dispose();
  }
}

final Expando<Wave4Controller> _wave4 = Expando<Wave4Controller>('wave4');

/// `state.wave4` gives the Wave 4 controller for this app state, created on
/// first use and started in the background.
extension Wave4StateX on HermesMobileAppState {
  Wave4Controller get wave4 {
    var c = _wave4[this];
    if (c == null) {
      c = Wave4Controller(this);
      _wave4[this] = c;
      unawaited(c.start());
    }
    return c;
  }

  /// Tests install a controller with a custom API or preferences.
  set wave4(Wave4Controller c) => _wave4[this] = c;

  /// Disposes the controller if one was created. Called from
  /// [HermesMobileAppState.dispose].
  void disposeWave4() {
    final c = _wave4[this];
    if (c != null) {
      c.dispose();
      _wave4[this] = null;
    }
  }
}

@visibleForTesting
void debugResetWave4(HermesMobileAppState s) => _wave4[s] = null;
