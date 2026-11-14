import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'w1_models.dart';

/// One card the user swiped away, kept on the phone so it can be restored.
class DismissedEntry {
  const DismissedEntry({
    required this.card,
    required this.dismissedAt,
    this.pinned = false,
  });

  final ProactiveCard card;
  final DateTime dismissedAt;

  /// Restored on the phone while the server could not un-dismiss it (an older
  /// Petasos plugin): the feed keeps showing it until it is dismissed again.
  final bool pinned;

  DismissedEntry copyWith({bool? pinned}) => DismissedEntry(
    card: card,
    dismissedAt: dismissedAt,
    pinned: pinned ?? this.pinned,
  );

  Map<String, dynamic> toJson() => {
    'card': card.toJson(),
    'at': dismissedAt.millisecondsSinceEpoch,
    if (pinned) 'pinned': true,
  };

  static DismissedEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final card = raw['card'];
    final at = raw['at'];
    if (card is! Map || at is! num) return null;
    return DismissedEntry(
      card: ProactiveCard.fromJson(Map<String, dynamic>.from(card)),
      dismissedAt: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      pinned: raw['pinned'] == true,
    );
  }
}

/// Brief and feed cards the user dismissed, newest first, kept in
/// SharedPreferences for [retention] (14 days; the promise is at least 7).
class DismissedStore {
  DismissedStore(this._prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  static const key = 'hermes_mobile.w1.dismissed';
  static const retention = Duration(days: 14);
  static const maxEntries = 200;

  List<DismissedEntry> _readAll() {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    try {
      final d = jsonDecode(raw);
      if (d is! List) return [];
      return [
        for (final e in d)
          if (DismissedEntry.fromJson(e) case final DismissedEntry x) x,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<DismissedEntry> all) =>
      _prefs.setString(key, jsonEncode([for (final e in all) e.toJson()]));

  /// Dismissed (not pinned) entries inside the retention window, newest first.
  /// Expired ones are pruned from storage as a side effect.
  List<DismissedEntry> list() {
    final all = _readAll();
    final cutoff = _clock().subtract(retention);
    final kept = all.where((e) => e.dismissedAt.isAfter(cutoff)).toList();
    if (kept.length != all.length) _writeAll(kept);
    return kept.where((e) => !e.pinned).toList()
      ..sort((a, b) => b.dismissedAt.compareTo(a.dismissedAt));
  }

  /// Cards restored on the phone only (see [DismissedEntry.pinned]).
  List<ProactiveCard> pinnedCards() => [
    for (final e in _readAll())
      if (e.pinned) e.card,
  ];

  Future<void> add(ProactiveCard card) async {
    final all = _readAll()..removeWhere((e) => e.card.id == card.id);
    all.insert(0, DismissedEntry(card: card, dismissedAt: _clock()));
    while (all.length > maxEntries) {
      all.removeLast();
    }
    await _writeAll(all);
  }

  Future<void> remove(String id) async {
    final all = _readAll();
    final before = all.length;
    all.removeWhere((e) => e.card.id == id);
    if (all.length != before) await _writeAll(all);
  }

  /// Marks [id] as restored on the phone only.
  Future<void> pin(String id) async {
    final all = [
      for (final e in _readAll())
        e.card.id == id ? e.copyWith(pinned: true) : e,
    ];
    await _writeAll(all);
  }

  bool contains(String id) => _readAll().any((e) => e.card.id == id);
}
