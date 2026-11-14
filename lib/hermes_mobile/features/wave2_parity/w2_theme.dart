import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/hermes_mobile_theme.dart';
import 'w2_settings.dart';

/// Wallpaper accents from Android 12+ (Material You). Null elsewhere.
class W2DynamicAccents {
  const W2DynamicAccents({
    required this.light,
    required this.dark,
    this.lightSoft,
    this.darkSoft,
  });
  final Color light;
  final Color dark;
  final Color? lightSoft;
  final Color? darkSoft;

  static const _channel = MethodChannel('hermes_mobile/w2_dynamic_color');
  static W2DynamicAccents? cached;
  static bool _loaded = false;

  static Future<W2DynamicAccents?> load() async {
    if (_loaded) return cached;
    _loaded = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final r = await _channel.invokeMapMethod<String, int>('accents');
      if (r == null || r['light'] == null || r['dark'] == null) return null;
      return cached = W2DynamicAccents(
        light: Color(r['light']!),
        dark: Color(r['dark']!),
        lightSoft: r['lightSoft'] == null ? null : Color(r['lightSoft']!),
        darkSoft: r['darkSoft'] == null ? null : Color(r['darkSoft']!),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Accent presets offered when dynamic color is off or unavailable.
const w2AccentPresets = <(String, int)>[
  ('Petasos blue', 0xFF3E63DD),
  ('Teal', 0xFF0F8B8D),
  ('Green', 0xFF2F9E6E),
  ('Amber', 0xFFC27C0E),
  ('Rose', 0xFFD6456E),
  ('Violet', 0xFF7C5CDB),
  ('Graphite', 0xFF4B5563),
];

/// Petasos colors with the Wave 2 appearance settings applied.
HermesMobileColors w2Colors(
  Brightness brightness,
  W2Settings s, {
  W2DynamicAccents? dynamicAccents,
}) {
  final dark = brightness == Brightness.dark;
  final base = dark ? HermesMobileColors.dark : HermesMobileColors.light;
  Color? accent;
  Color? soft;
  if (s.dynamicColor && dynamicAccents != null) {
    accent = dark ? dynamicAccents.dark : dynamicAccents.light;
    soft = dark ? dynamicAccents.darkSoft : dynamicAccents.lightSoft;
  } else if (s.accentArgb != null) {
    final seed = Color(s.accentArgb!);
    accent = dark ? Color.lerp(seed, Colors.white, 0.25)! : seed;
  }
  if (accent != null) {
    soft ??= dark
        ? Color.alphaBlend(accent.withValues(alpha: 0.18), base.background)
        : Color.alphaBlend(accent.withValues(alpha: 0.12), Colors.white);
  }
  final amoled = dark && s.amoled;
  return HermesMobileColors(
    background: amoled ? Colors.black : base.background,
    surface: amoled ? const Color(0xFF0B0B0C) : base.surface,
    surfaceMuted: amoled ? const Color(0xFF141416) : base.surfaceMuted,
    hairline: amoled ? const Color(0xFF1F1F22) : base.hairline,
    text: base.text,
    textSecondary: base.textSecondary,
    textTertiary: base.textTertiary,
    accent: accent ?? base.accent,
    accentSoft: soft ?? base.accentSoft,
    onAccent: base.onAccent,
    userBubble: accent ?? base.userBubble,
    onUserBubble: base.onUserBubble,
    agentBubble: amoled ? const Color(0xFF0E0E10) : base.agentBubble,
    success: base.success,
    warning: base.warning,
    danger: base.danger,
    codeBackground: amoled ? const Color(0xFF070708) : base.codeBackground,
    shadow: base.shadow,
  );
}

ThemeData w2Theme(
  Brightness brightness,
  W2Settings s, {
  W2DynamicAccents? dynamicAccents,
}) => hermesMobileTheme(
  brightness,
  colors: w2Colors(brightness, s, dynamicAccents: dynamicAccents),
);

/// Applies the user's text-size multiplier on top of the system scale.
Widget w2TextScale(BuildContext context, Widget child, W2Settings s) {
  final mq = MediaQuery.of(context);
  if ((s.textScale - 1.0).abs() < 0.01) return child;
  final system = mq.textScaler.scale(1);
  return MediaQuery(
    data: mq.copyWith(textScaler: TextScaler.linear(system * s.textScale)),
    child: child,
  );
}
