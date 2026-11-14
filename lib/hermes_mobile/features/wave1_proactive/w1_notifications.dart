import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/services/turn_notification_service.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'w1_controller.dart';
import 'w1_models.dart';

/// What a notification tap or action asked for, parsed from its payload.
@immutable
class Wave1NotificationIntent {
  const Wave1NotificationIntent({
    required this.type,
    this.chatId,
    this.cardId,
    this.action,
    this.input,
  });
  final String type; // approval | card | digest | test | turn
  final String? chatId;
  final String? cardId;

  /// allow | deny | reply | snooze | act, or null for a body tap.
  final String? action;
  final String? input;

  static Wave1NotificationIntent? parse(
    String? payload, {
    String? actionId,
    String? input,
  }) {
    if (payload == null || payload.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final action = switch (actionId) {
      'hermes_mobile_allow' => 'allow',
      'hermes_mobile_deny' => 'deny',
      'hermes_mobile_reply' => 'reply',
      'hermes_mobile_snooze' => 'snooze',
      'hermes_mobile_act' => 'act',
      'approve' => 'allow', // engine turn-notification action ids
      'reject' => 'deny',
      _ => null,
    };
    if (decoded['hermes_mobile'] != 'w1') {
      // An engine turn notification: open its chat.
      final session = decoded['sessionId']?.toString();
      if (session == null || session.isEmpty) return null;
      return Wave1NotificationIntent(
        type: 'turn',
        chatId: session,
        action: action,
      );
    }
    return Wave1NotificationIntent(
      type: (decoded['type'] ?? 'card').toString(),
      chatId: decoded['chatId']?.toString(),
      cardId: decoded['cardId']?.toString(),
      action: action,
      input: input,
    );
  }
}

/// Posts actionable notifications (Allow/Deny, inline Reply, Snooze, the
/// card's action) and routes the user's answer back into the app.
class Wave1Notifier {
  Wave1Notifier._();
  static final Wave1Notifier shared = Wave1Notifier._();

  static const groupKey = 'com.hermesagent.hermesMobile.proactive';
  static const _channelId = 'hermes_mobile_proactive';
  static const _channelName = 'Hermes proactive';
  static const _channelDesc =
      'Approvals, briefs and cards Hermes puts in front of you';
  static const _summaryId = 0x0ad0001;

  /// How long Snooze on an approval waits before reminding again.
  static Duration snoozeApproval = const Duration(minutes: 10);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, ProactiveCard> _posted = {};
  final List<String> _groupLines = [];
  HermesMobileAppState? _state;
  void Function(HermesMobileChat chat)? _open;
  bool _ready = false;

  /// Stable id for a notification key (FNV-1a, positive 28-bit).
  static int idFor(String key) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode('hermes_mobile.w1:$key')) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x0fffffff;
  }

  Future<bool> _ensure() async {
    if (_ready) return true;
    try {
      await TurnNotificationService.shared.ensureInitialized();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Routes taps and actions for [state]. Engine turn notifications open
  /// their chat too (the Petasos root did not route them before).
  void attach(HermesMobileAppState state, void Function(HermesMobileChat chat) openChat) {
    _state = state;
    _open = openChat;
    notificationResponseHandler = handleResponse;
    unawaited(_takeLaunch());
  }

  void detach(HermesMobileAppState state) {
    if (!identical(_state, state)) return;
    _state = null;
    _open = null;
    if (identical(notificationResponseHandler, handleResponse)) {
      notificationResponseHandler = null;
    }
  }

  Future<void> _takeLaunch() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final r = details?.notificationResponse;
      if (details?.didNotificationLaunchApp == true && r != null) {
        handleResponse(r);
      }
    } catch (_) {}
  }

  void handleResponse(NotificationResponse r) {
    final intent = Wave1NotificationIntent.parse(
      r.payload,
      actionId: r.actionId,
      input: r.input,
    );
    if (intent != null) unawaited(route(intent));
  }

  /// Applies a parsed intent. Public for tests.
  Future<void> route(Wave1NotificationIntent i) async {
    final state = _state;
    if (state == null) return;
    final chatId = i.chatId;
    switch (i.type) {
      case 'approval' || 'turn':
        if (chatId == null) return;
        if (i.action == 'allow' || i.action == 'deny') {
          await state
              .controllerById(chatId)
              ?.answer(i.action == 'allow' ? 'once' : 'deny');
          await cancel('approval:$chatId');
          return;
        }
        if (i.action == 'snooze' && i.type == 'approval') {
          await cancel('approval:$chatId');
          final policy = ProactiveController.of(state).policy;
          Timer(snoozeApproval, () {
            final a = _state?.pendingApprovals[chatId];
            if (a != null) {
              unawaited(showApproval(chatId, state.titleFor(chatId), a, policy));
            }
          });
          return;
        }
        if (i.action == 'reply' && (i.input ?? '').trim().isNotEmpty) {
          final ctl = state.controllerFor(
            HermesMobileChat(id: chatId, title: state.titleFor(chatId)),
          );
          // A reply to an approval declines it and sends the reply as the
          // next instruction once the run settles.
          if (ctl.approval != null) {
            await ctl.answer('deny');
            await cancel('approval:$chatId');
          }
          for (var n = 0; n < 120 && ctl.running; n++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          unawaited(ctl.send(i.input!));
        }
        _open?.call(HermesMobileChat(id: chatId, title: state.titleFor(chatId)));
      case 'card':
        final card = _posted[i.cardId];
        final feed = ProactiveController.of(state);
        if (card == null) return;
        HermesMobileChat? open;
        if (i.action == 'snooze') {
          await feed.snooze(card);
        } else if (i.action == 'reply') {
          open = await feed.act(card, reply: i.input);
        } else if (i.action == 'act') {
          open = await feed.act(card);
        } else {
          await feed.markRead(card);
          open = card.chatId == null
              ? null
              : HermesMobileChat(id: card.chatId!, title: card.title);
        }
        await cancel('card:${card.id}');
        if (open != null) _open?.call(open);
      default:
        break;
    }
  }

  AndroidNotificationDetails _details({
    required List<AndroidNotificationAction> actions,
    bool silent = false,
    bool high = true,
    StyleInformation? style,
    bool summary = false,
  }) => AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDesc,
    importance: high ? Importance.high : Importance.defaultImportance,
    priority: high ? Priority.high : Priority.defaultPriority,
    groupKey: groupKey,
    setAsGroupSummary: summary,
    silent: silent,
    playSound: !silent,
    enableVibration: !silent,
    category: AndroidNotificationCategory.recommendation,
    styleInformation: style,
    actions: actions,
  );

  static AndroidNotificationAction _btn(String id, String label) =>
      AndroidNotificationAction(id, label, showsUserInterface: true);

  static AndroidNotificationAction _reply() => const AndroidNotificationAction(
    'hermes_mobile_reply',
    'Reply',
    showsUserInterface: true,
    inputs: [AndroidNotificationActionInput(label: 'Reply to Hermes')],
  );

  /// An approval Hermes is blocked on, posted while the app is backgrounded.
  Future<void> showApproval(
    String chatId,
    String chatTitle,
    HermesMobileApproval a,
    NotifyPolicy policy, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    if (!policy.shouldNotify('approvals', at, blocking: true)) return;
    if (!await _ensure()) return;
    final body = [
      if (a.description.isNotEmpty) a.description,
      if (a.command.isNotEmpty) a.command,
    ].join('\n');
    try {
      await _plugin.show(
        idFor('approval:$chatId'),
        'Hermes needs your OK · $chatTitle',
        body.isEmpty ? 'A run is waiting for approval.' : body,
        NotificationDetails(
          android: _details(
            silent: policy.isQuiet(at),
            style: BigTextStyleInformation(body),
            actions: [
              _btn('hermes_mobile_allow', 'Allow'),
              _btn('hermes_mobile_deny', 'Deny'),
              // Android shows at most three buttons; Snooze lives on cards.
              _reply(),
            ],
          ),
        ),
        payload: jsonEncode({'hermes_mobile': 'w1', 'type': 'approval', 'chatId': chatId}),
      );
    } catch (_) {}
  }

  /// New proactive cards; more than one also posts a grouped digest summary.
  Future<int> showCards(
    List<ProactiveCard> cards,
    NotifyPolicy policy, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final allowed = cards
        .where((c) => policy.shouldNotify(c.source, at))
        .toList();
    if (allowed.isEmpty || !await _ensure()) return 0;
    for (final card in allowed) {
      _posted[card.id] = card;
      final a = card.action;
      final actions = <AndroidNotificationAction>[
        if (a != null && a.kind == ProactiveActionKind.reply) _reply(),
        if (a != null &&
            a.kind != ProactiveActionKind.reply &&
            a.kind != ProactiveActionKind.snooze)
          _btn('hermes_mobile_act', a.label),
        _btn('hermes_mobile_snooze', 'Snooze'),
      ];
      _groupLines.insert(0, card.title);
      try {
        await _plugin.show(
          idFor('card:${card.id}'),
          card.title,
          card.body.replaceAll(RegExp(r'[*_`#]'), ''),
          NotificationDetails(
            android: _details(
              high: card.kind == 'approval' || card.kind == 'alert',
              style: BigTextStyleInformation(
                card.body.replaceAll(RegExp(r'[*_`#]'), ''),
              ),
              actions: actions,
            ),
          ),
          payload: jsonEncode({
            'hermes_mobile': 'w1',
            'type': 'card',
            'cardId': card.id,
            'chatId': ?card.chatId,
          }),
        );
      } catch (_) {}
    }
    if (_groupLines.length > 1) {
      final lines = _groupLines.take(6).toList();
      try {
        await _plugin.show(
          _summaryId,
          'Hermes',
          '${_groupLines.length} updates',
          NotificationDetails(
            android: _details(
              high: false,
              summary: true,
              actions: const [],
              style: InboxStyleInformation(
                lines,
                contentTitle: '${_groupLines.length} updates from Hermes',
                summaryText: 'Brief',
              ),
            ),
          ),
          payload: jsonEncode({'hermes_mobile': 'w1', 'type': 'digest'}),
        );
      } catch (_) {}
    }
    return allowed.length;
  }

  Future<void> showTest() async {
    if (!await _ensure()) return;
    try {
      await _plugin.show(
        idFor('test'),
        'Hermes test notification',
        'Allow, Deny, Reply and Snooze appear on real approvals and cards.',
        NotificationDetails(
          android: _details(actions: [_reply(), _btn('hermes_mobile_snooze', 'Snooze')]),
        ),
        payload: jsonEncode({'hermes_mobile': 'w1', 'type': 'test'}),
      );
    } catch (_) {}
  }

  Future<void> cancel(String key) async {
    try {
      await _plugin.cancel(idFor(key));
    } catch (_) {}
    if (key.startsWith('card:')) {
      _groupLines.remove(_posted[key.substring(5)]?.title);
    }
    if (_groupLines.length <= 1) {
      try {
        await _plugin.cancel(_summaryId);
      } catch (_) {}
    }
  }

  /// Clears the digest bookkeeping when the user opens the app.
  void onResumed() => _groupLines.clear();
}
