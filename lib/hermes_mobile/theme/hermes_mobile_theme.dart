import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Petasos design tokens: calm, light-first, one accent, hairline borders.
@immutable
class HermesMobileColors extends ThemeExtension<HermesMobileColors> {
  const HermesMobileColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.hairline,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.userBubble,
    required this.onUserBubble,
    required this.agentBubble,
    required this.success,
    required this.warning,
    required this.danger,
    required this.codeBackground,
    required this.shadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color hairline;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color userBubble;
  final Color onUserBubble;
  final Color agentBubble;
  final Color success;
  final Color warning;
  final Color danger;
  final Color codeBackground;
  final Color shadow;

  static const Color accentBase = Color(0xFF3E63DD);

  static const light = HermesMobileColors(
    background: Color(0xFFF7F7F5),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF1F1EF),
    hairline: Color(0xFFE6E5E2),
    text: Color(0xFF1B1B1A),
    textSecondary: Color(0xFF6B6A67),
    textTertiary: Color(0xFF9C9A96),
    accent: accentBase,
    accentSoft: Color(0xFFE8EDFC),
    onAccent: Color(0xFFFFFFFF),
    userBubble: accentBase,
    onUserBubble: Color(0xFFFFFFFF),
    agentBubble: Color(0xFFFFFFFF),
    success: Color(0xFF2F9E6E),
    warning: Color(0xFFB7791F),
    danger: Color(0xFFD64545),
    codeBackground: Color(0xFFF4F4F2),
    shadow: Color(0x0F000000),
  );

  static const dark = HermesMobileColors(
    background: Color(0xFF111112),
    surface: Color(0xFF1A1A1C),
    surfaceMuted: Color(0xFF232326),
    hairline: Color(0xFF2C2C30),
    text: Color(0xFFF2F2F0),
    textSecondary: Color(0xFFA3A29E),
    textTertiary: Color(0xFF75746F),
    accent: Color(0xFF6E8CF0),
    accentSoft: Color(0xFF1E2747),
    onAccent: Color(0xFFFFFFFF),
    userBubble: Color(0xFF4A6BE0),
    onUserBubble: Color(0xFFFFFFFF),
    agentBubble: Color(0xFF1F1F22),
    success: Color(0xFF4CC38A),
    warning: Color(0xFFE2A93B),
    danger: Color(0xFFF06A6A),
    codeBackground: Color(0xFF161618),
    shadow: Color(0x33000000),
  );

  @override
  HermesMobileColors copyWith() => this;

  @override
  HermesMobileColors lerp(ThemeExtension<HermesMobileColors>? other, double t) {
    if (other is! HermesMobileColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return HermesMobileColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      hairline: l(hairline, other.hairline),
      text: l(text, other.text),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccent: l(onAccent, other.onAccent),
      userBubble: l(userBubble, other.userBubble),
      onUserBubble: l(onUserBubble, other.onUserBubble),
      agentBubble: l(agentBubble, other.agentBubble),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      codeBackground: l(codeBackground, other.codeBackground),
      shadow: l(shadow, other.shadow),
    );
  }
}

/// Radii and spacing used everywhere so screens stay consistent.
abstract final class HermesMobileRadius {
  static const double card = 18;
  static const double bubble = 20;
  static const double chip = 12;
  static const double field = 24;
}

const String kHermesMobileFont = 'Inter';

extension HermesMobileThemeX on BuildContext {
  HermesMobileColors get hermesMobile =>
      Theme.of(this).extension<HermesMobileColors>() ?? HermesMobileColors.light;
}

ThemeData hermesMobileTheme(
  Brightness brightness, {
  // --- wave2 ---
  HermesMobileColors? colors,
  // --- end wave2 ---
}) {
  final c =
      colors ??
      (brightness == Brightness.dark ? HermesMobileColors.dark : HermesMobileColors.light);
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
  ).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    surface: c.surface,
    onSurface: c.text,
    error: c.danger,
    outline: c.hairline,
    outlineVariant: c.hairline,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kHermesMobileFont,
    scaffoldBackgroundColor: c.background,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
  );
  final text = base.textTheme.apply(
    bodyColor: c.text,
    displayColor: c.text,
    fontFamily: kHermesMobileFont,
  );
  return base.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
      bodySmall: text.bodySmall?.copyWith(color: c.textSecondary),
      labelSmall: text.labelSmall?.copyWith(
        color: c.textSecondary,
        letterSpacing: 0.2,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: kHermesMobileFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.text,
        letterSpacing: -0.2,
      ),
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HermesMobileRadius.card),
        side: BorderSide(color: c.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.textSecondary,
      textColor: c.text,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: TextStyle(color: c.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: kHermesMobileFont,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: kHermesMobileFont,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: const TextStyle(
          fontFamily: kHermesMobileFont,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.text,
      contentTextStyle: TextStyle(color: c.background, fontFamily: kHermesMobileFont),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : null,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
  );
}

/// Soft shadow used under cards.
List<BoxShadow> hermesMobileShadow(BuildContext context) => [
  BoxShadow(
    color: context.hermesMobile.shadow,
    blurRadius: 12,
    offset: const Offset(0, 2),
  ),
];
