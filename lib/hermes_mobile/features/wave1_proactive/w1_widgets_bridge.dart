import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/panels.dart';
import 'w1_models.dart';

/// Feeds the native home-screen widgets (HermesMobileWidgetProviders.kt). Values go
/// to the app's SharedPreferences, which the widgets read directly (Flutter
/// stores them as `flutter.<key>` in `FlutterSharedPreferences`); then the
/// providers are asked to redraw.
class HermesMobileWidgetBridge {
  HermesMobileWidgetBridge._();
  static final HermesMobileWidgetBridge shared = HermesMobileWidgetBridge._();

  static const channel = MethodChannel('com.hermesagent.hermesMobile/widgets');
  static const pinnedPanelKey = 'hermes_mobile.widget.pinned_panel_id';

  static const kBriefTitle = 'hermes_mobile.widget.brief_title';
  static const kBriefBody = 'hermes_mobile.widget.brief_body';
  static const kNeedsYou = 'hermes_mobile.widget.needs_you';
  static const kNeedsTop = 'hermes_mobile.widget.needs_top';
  static const kPanelTitle = 'hermes_mobile.widget.panel_title';
  static const kPanelValue = 'hermes_mobile.widget.panel_value';
  static const kPanelSub = 'hermes_mobile.widget.panel_sub';
  static const kUpdated = 'hermes_mobile.widget.updated';

  String? _last;

  /// The values the widgets show, as plain strings (testable).
  static Map<String, Object> snapshot({
    required List<ProactiveCard> briefs,
    required List<ProactiveCard> feed,
    required int needsYou,
    PanelsResult? panels,
    String? pinnedPanelId,
    DateTime? now,
  }) {
    final brief = briefs.isEmpty
        ? null
        : (briefs.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
              .first;
    final plain = (brief?.body ?? '')
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final top = feed.where((c) => !c.read).firstOrNull ?? feed.firstOrNull;
    final list = panels?.panels ?? const <HermesMobilePanel>[];
    final panel =
        list.where((p) => p.id == pinnedPanelId).firstOrNull ?? list.firstOrNull;
    String panelValue() {
      if (panel == null) return '';
      if (panel.value != null) {
        return '${panel.value}${panel.unit == null ? '' : ' ${panel.unit}'}';
      }
      if (panel.items.isNotEmpty) {
        final i = panel.items.first;
        return i.value == null ? i.label : '${i.label}: ${i.value}';
      }
      return panel.text ?? '';
    }

    final t = now ?? DateTime.now();
    return {
      kBriefTitle: brief?.title ?? 'No brief yet',
      kBriefBody: plain.length > 220 ? '${plain.substring(0, 219)}…' : plain,
      kNeedsYou: needsYou,
      kNeedsTop: top?.title ?? 'All caught up',
      kPanelTitle: panel?.title ?? 'No panel pinned',
      kPanelValue: panelValue(),
      kPanelSub: panel?.subtitle ?? panel?.source ?? '',
      kUpdated:
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    };
  }

  Future<void> push(Map<String, Object> values) async {
    final key = values.entries
        .where((e) => e.key != kUpdated)
        .map((e) => '${e.key}=${e.value}')
        .join('|');
    if (key == _last) return;
    _last = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in values.entries) {
        final v = e.value;
        if (v is int) {
          await prefs.setInt(e.key, v);
        } else {
          await prefs.setString(e.key, '$v');
        }
      }
      await channel.invokeMethod<void>('update');
    } on MissingPluginException {
      // Tests and non-Android hosts have no widgets.
    } catch (_) {}
  }
}
