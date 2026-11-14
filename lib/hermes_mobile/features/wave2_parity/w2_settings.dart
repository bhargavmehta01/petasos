import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 2 device settings and small device-only stores (pins, stars, pinned
/// messages, local project instructions). Everything lives in
/// SharedPreferences under `hermes_mobile.w2.*` so it never collides with the engine.
class W2Settings extends ChangeNotifier {
  W2Settings._(this._prefs);

  final SharedPreferences? _prefs;
  final Map<String, Object?> _mem = {};

  static W2Settings? _current;
  static final Expando<W2Settings> _byPrefs = Expando('w2settings');

  /// The settings for [prefs]; one instance per preferences object.
  static W2Settings forPrefs(SharedPreferences prefs) {
    final s = _byPrefs[prefs] ??= W2Settings._(prefs);
    _current = s;
    return s;
  }

  /// The active settings, or in-memory defaults before the app attached.
  static W2Settings get current => _current ??= W2Settings._(null);

  /// Tests reset between cases.
  @visibleForTesting
  static void resetForTest() => _current = null;

  static const _p = 'hermes_mobile.w2.';

  // ── raw helpers ────────────────────────────────────────────────────
  bool _b(String k, bool d) =>
      (_prefs?.getBool('$_p$k') ?? _mem[k] as bool?) ?? d;
  double _d(String k, double d) =>
      (_prefs?.getDouble('$_p$k') ?? _mem[k] as double?) ?? d;
  int? _i(String k) => _prefs?.getInt('$_p$k') ?? _mem[k] as int?;
  String? _s(String k) => _prefs?.getString('$_p$k') ?? _mem[k] as String?;
  List<String> _l(String k) =>
      _prefs?.getStringList('$_p$k') ??
      (_mem[k] as List<String>?) ??
      const [];

  Future<void> _set(String k, Object? v) async {
    _mem[k] = v;
    final p = _prefs;
    if (p != null) {
      final key = '$_p$k';
      if (v == null) {
        await p.remove(key);
      } else if (v is bool) {
        await p.setBool(key, v);
      } else if (v is double) {
        await p.setDouble(key, v);
      } else if (v is int) {
        await p.setInt(key, v);
      } else if (v is String) {
        await p.setString(key, v);
      } else if (v is List<String>) {
        await p.setStringList(key, v);
      }
    }
    notifyListeners();
  }

  // ── appearance ────────────────────────────────────────────────────
  /// Material You: follow the wallpaper accent on Android 12+.
  bool get dynamicColor => _b('dynamic_color', false);
  Future<void> setDynamicColor(bool v) => _set('dynamic_color', v);

  /// Pure black dark theme for OLED screens.
  bool get amoled => _b('amoled', false);
  Future<void> setAmoled(bool v) => _set('amoled', v);

  /// Accent override (ARGB). Null keeps the Petasos blue.
  int? get accentArgb => _i('accent');
  Future<void> setAccent(int? argb) => _set('accent', argb);

  /// Text scale multiplier applied on top of the system setting.
  double get textScale => _d('text_scale', 1.0).clamp(0.85, 1.4);
  Future<void> setTextScale(double v) => _set('text_scale', v.clamp(0.85, 1.4));

  /// Haptic feedback on taps, sends and voice turns.
  bool get haptics => _b('haptics', true);
  Future<void> setHaptics(bool v) => _set('haptics', v);

  /// Two panes (chats list + chat) on tablets and unfolded foldables.
  bool get twoPane => _b('two_pane', true);
  Future<void> setTwoPane(bool v) => _set('two_pane', v);

  // ── voice ─────────────────────────────────────────────────────────
  /// Read every finished reply aloud.
  bool get autoReadAloud => _b('auto_read', false);
  Future<void> setAutoReadAloud(bool v) => _set('auto_read', v);

  double get speechRate => _d('speech_rate', 0.5).clamp(0.2, 1.0);
  Future<void> setSpeechRate(double v) => _set('speech_rate', v);

  /// Let speaking interrupt the reply in voice mode.
  bool get bargeIn => _b('barge_in', true);
  Future<void> setBargeIn(bool v) => _set('barge_in', v);

  // ── pinned and starred chats (device-only) ───────────────────────
  String _scope(String connection) =>
      connection.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

  List<String> pinnedChats(String connection) =>
      _l('pins.${_scope(connection)}');
  List<String> starredChats(String connection) =>
      _l('stars.${_scope(connection)}');

  bool isPinned(String connection, String chatId) =>
      pinnedChats(connection).contains(chatId);
  bool isStarred(String connection, String chatId) =>
      starredChats(connection).contains(chatId);

  Future<void> togglePinned(String connection, String chatId) {
    final list = List.of(pinnedChats(connection));
    list.contains(chatId) ? list.remove(chatId) : list.insert(0, chatId);
    return _set('pins.${_scope(connection)}', list);
  }

  Future<void> toggleStarred(String connection, String chatId) {
    final list = List.of(starredChats(connection));
    list.contains(chatId) ? list.remove(chatId) : list.insert(0, chatId);
    return _set('stars.${_scope(connection)}', list);
  }

  // ── pinned messages, per chat ────────────────────────────────────
  List<W2PinnedMessage> pinnedMessages(String chatId) => [
    for (final raw in _l('msgpins.$chatId')) ?W2PinnedMessage.tryParse(raw),
  ];

  /// All pinned messages across chats, newest first.
  List<W2PinnedMessage> allPinnedMessages() {
    final p = _prefs;
    final keys = p == null
        ? _mem.keys.where((k) => k.startsWith('msgpins.'))
        : p
              .getKeys()
              .where((k) => k.startsWith('${_p}msgpins.'))
              .map((k) => k.substring(_p.length));
    final out = <W2PinnedMessage>[];
    for (final k in keys) {
      out.addAll(pinnedMessages(k.substring('msgpins.'.length)));
    }
    out.sort((a, b) => b.pinnedAt.compareTo(a.pinnedAt));
    return out;
  }

  bool isMessagePinned(String chatId, String text) =>
      pinnedMessages(chatId).any((m) => m.text == text);

  Future<void> toggleMessagePin(W2PinnedMessage m) {
    final list = pinnedMessages(m.chatId);
    final exists = list.any((x) => x.text == m.text);
    final next = exists
        ? list.where((x) => x.text != m.text).toList()
        : [m, ...list];
    return _set('msgpins.${m.chatId}', [for (final x in next) x.encode()]);
  }

  // ── project instructions kept on the phone when the plugin is absent ─
  String projectInstructions(String projectId) =>
      _s('proj.$projectId.instructions') ?? '';
  Future<void> setProjectInstructions(String projectId, String text) =>
      _set('proj.$projectId.instructions', text);

  // ── per-chat reasoning effort (API-server connections keep it here) ─
  String? reasoningEffort(String chatId) => _s('effort.$chatId');
  Future<void> setReasoningEffort(String chatId, String? effort) =>
      _set('effort.$chatId', effort);

  // ── recent searches ──────────────────────────────────────────────
  List<String> get recentSearches => _l('recent_searches');
  Future<void> addRecentSearch(String q) {
    final t = q.trim();
    if (t.isEmpty) return Future.value();
    final list = [t, ...recentSearches.where((x) => x != t)].take(8).toList();
    return _set('recent_searches', list);
  }
}

class W2PinnedMessage {
  const W2PinnedMessage({
    required this.chatId,
    required this.chatTitle,
    required this.text,
    required this.fromUser,
    required this.pinnedAt,
  });
  final String chatId;
  final String chatTitle;
  final String text;
  final bool fromUser;
  final DateTime pinnedAt;

  String encode() => jsonEncode({
    'chat': chatId,
    'title': chatTitle,
    'text': text,
    'user': fromUser,
    'at': pinnedAt.toIso8601String(),
  });

  static W2PinnedMessage? tryParse(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return W2PinnedMessage(
        chatId: j['chat'] as String,
        chatTitle: (j['title'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        fromUser: j['user'] == true,
        pinnedAt: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Haptics that respect the user's setting.
abstract final class W2Haptics {
  static void light() {
    if (W2Settings.current.haptics) HapticFeedback.lightImpact();
  }

  static void selection() {
    if (W2Settings.current.haptics) HapticFeedback.selectionClick();
  }

  static void medium() {
    if (W2Settings.current.haptics) HapticFeedback.mediumImpact();
  }
}
