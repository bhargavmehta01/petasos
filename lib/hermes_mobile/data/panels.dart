import 'dart:convert';

import 'package:http/http.dart' as http;

/// Hermes Home Panels: small JSON status cards that agents, skills and cron
/// jobs publish at `$HERMES_HOME/panels/<id>.json`. The phone cannot read the
/// gateway host's files, so panels reach it over HTTP. See docs/hermes-mobile-panels.md.
enum PanelKind { stat, list, table, text, progress }

class PanelItem {
  const PanelItem({required this.label, this.value, this.url});
  final String label;
  final String? value;
  final String? url;
}

class HermesMobilePanel {
  const HermesMobilePanel({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle,
    this.updatedAt,
    this.value,
    this.unit,
    this.trend,
    this.items = const [],
    this.columns = const [],
    this.rows = const [],
    this.text,
    this.url,
    this.source,
    this.profile,
    this.progress,
    this.staleAfterMinutes,
  });

  final String id;
  final String title;
  final PanelKind kind;
  final String? subtitle;
  final DateTime? updatedAt;
  final String? value;
  final String? unit;

  /// Signed change, e.g. "+1.37 today". A leading +/- colours it.
  final String? trend;
  final List<PanelItem> items;
  final List<String> columns;
  final List<List<String>> rows;
  final String? text;
  final String? url;
  final String? source;
  final String? profile;

  /// 0..1 for `progress` panels.
  final double? progress;
  final num? staleAfterMinutes;

  bool isStale(DateTime now) {
    final at = updatedAt;
    final limit = staleAfterMinutes;
    if (at == null || limit == null) return false;
    return now.difference(at).inSeconds > limit * 60;
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = v is num ? _num(v) : v.toString();
    return s.trim().isEmpty ? null : s;
  }

  static String _num(num v) {
    if (v is int || v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static String? _httpUrl(Object? v) {
    final s = _str(v);
    if (s == null) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return s;
  }

  /// Parses both the dashboard plugin's schema v1 (`delta`, `link`,
  /// `columns`/`rows`, `text`) and the Petasos additions (`trend`, `url`,
  /// `progress` kind). Returns null for anything that is not a valid panel.
  static HermesMobilePanel? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final id = _str(j['id']);
    final title = _str(j['title']);
    final kindName = _str(j['kind']);
    if (id == null || title == null || kindName == null) return null;
    final kind = PanelKind.values.where((k) => k.name == kindName).firstOrNull;
    if (kind == null) return null;

    final items = <PanelItem>[];
    if (j['items'] is List) {
      for (final it in (j['items'] as List).take(50)) {
        if (it is Map && _str(it['label']) != null) {
          items.add(
            PanelItem(
              label: _str(it['label'])!,
              value: _str(it['value']),
              url: _httpUrl(it['url']),
            ),
          );
        }
      }
    }
    final columns = j['columns'] is List
        ? (j['columns'] as List).map((c) => _str(c) ?? '').take(8).toList()
        : <String>[];
    final rows = j['rows'] is List
        ? (j['rows'] as List)
              .whereType<List>()
              .take(50)
              .map((r) => r.map((c) => _str(c) ?? '').take(8).toList())
              .toList()
        : <List<String>>[];

    double? progress;
    final p = j['progress'] ?? (kind == PanelKind.progress ? j['value'] : null);
    if (p is num) {
      progress = (p > 1 ? p / 100 : p).toDouble().clamp(0, 1);
    } else if (p is String) {
      final n = double.tryParse(p.replaceAll('%', ''));
      if (n != null) progress = (n > 1 ? n / 100 : n).clamp(0, 1);
    }

    return HermesMobilePanel(
      id: id,
      title: title.length > 80 ? title.substring(0, 80) : title,
      kind: kind,
      subtitle: _str(j['subtitle']),
      updatedAt: _parseTime(j['updated_at']),
      value: _str(j['value']),
      unit: _str(j['unit']),
      trend: _str(j['trend'] ?? j['delta']),
      items: items,
      columns: columns,
      rows: rows,
      text: _str(j['text']),
      url: _httpUrl(j['url'] ?? j['link']),
      source: _str(j['source']),
      profile: _str(j['profile']),
      progress: progress,
      staleAfterMinutes: j['stale_after_minutes'] is num
          ? j['stale_after_minutes'] as num
          : null,
    );
  }

  static DateTime? _parseTime(Object? v) {
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (v > 1e12 ? v : v * 1000).toInt(),
      );
    }
    final s = _str(v);
    if (s == null) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  /// Accepts `{panels:[...]}`, `{data:[...]}` or a bare list.
  static List<HermesMobilePanel> parseList(Object? body) {
    final list = body is Map
        ? (body['panels'] ?? body['data'] ?? const [])
        : body;
    if (list is! List) return const [];
    return list.map(tryParse).whereType<HermesMobilePanel>().take(100).toList();
  }
}

class PanelsResult {
  const PanelsResult({
    required this.panels,
    this.configured = true,
    this.error,
    this.sourceLabel,
  });
  final List<HermesMobilePanel> panels;

  /// False when no source is set up; Home explains how to expose panels.
  final bool configured;
  final String? error;
  final String? sourceLabel;
}

/// Where Home panels come from. Never a hidden chat prompt.
abstract class PanelsSource {
  Future<PanelsResult> load();
}

/// No source configured: Home shows the "how to expose panels" empty state.
class UnconfiguredPanelsSource implements PanelsSource {
  const UnconfiguredPanelsSource();
  @override
  Future<PanelsResult> load() async =>
      const PanelsResult(panels: [], configured: false);
}

/// Fetches panels with an injected JSON getter, e.g. the engine's
/// authenticated DashboardClient reading
/// `api/plugins/home-dashboard/panels`.
class DashboardPanelsSource implements PanelsSource {
  DashboardPanelsSource(this._get, {this.label = 'Dashboard'});
  final Future<Object?> Function() _get;
  final String label;

  @override
  Future<PanelsResult> load() async {
    try {
      final body = await _get();
      return PanelsResult(
        panels: HermesMobilePanel.parseList(body),
        sourceLabel: label,
      );
    } catch (e) {
      return PanelsResult(panels: const [], error: '$e', sourceLabel: label);
    }
  }
}

/// A user-set URL returning a list of panel JSON. Optional bearer token.
class UrlPanelsSource implements PanelsSource {
  UrlPanelsSource(this.url, {this.bearer, http.Client? client})
    : _client = client ?? http.Client();
  final String url;
  final String? bearer;
  final http.Client _client;

  @override
  Future<PanelsResult> load() async {
    try {
      final res = await _client
          .get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
              if (bearer != null && bearer!.isNotEmpty)
                'Authorization': 'Bearer $bearer',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        return PanelsResult(
          panels: const [],
          error: 'HTTP ${res.statusCode}',
          sourceLabel: Uri.tryParse(url)?.host,
        );
      }
      return PanelsResult(
        panels: HermesMobilePanel.parseList(jsonDecode(res.body)),
        sourceLabel: Uri.tryParse(url)?.host,
      );
    } catch (e) {
      return PanelsResult(
        panels: const [],
        error: '$e',
        sourceLabel: Uri.tryParse(url)?.host,
      );
    }
  }
}

/// Fixed panels, used by demo mode and tests.
class StaticPanelsSource implements PanelsSource {
  const StaticPanelsSource(this.panels);
  final List<HermesMobilePanel> panels;
  @override
  Future<PanelsResult> load() async =>
      PanelsResult(panels: panels, sourceLabel: 'Demo');
}
