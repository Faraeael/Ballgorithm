import 'package:flutter/material.dart';

/// Immutable 1:1 design tokens for the Hardwood Command visual system.
@immutable
class HardwoodCommandTokens extends ThemeExtension<HardwoodCommandTokens> {
  const HardwoodCommandTokens({
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgGlassHeader,
    required this.borderSubtle,
    required this.borderActive,
    required this.accentPrimary,
    required this.accentPrimaryFg,
    required this.accentPrimaryTint,
    required this.accentSecondary,
    required this.accentSecondaryFg,
    required this.accentSecondaryBg,
    required this.teamPrimary,
    required this.teamSecondary,
    required this.statusSuccess,
    required this.statusSuccessFg,
    required this.statusSuccessBg,
    required this.statusWarning,
    required this.statusWarningFg,
    required this.statusWarningBg,
    required this.statusDanger,
    required this.statusDangerFg,
    required this.statusDangerBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.space100,
    required this.space200,
    required this.space300,
    required this.space400,
    required this.space600,
    required this.touchMin,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusPill,
  });

  static const HardwoodCommandTokens dark = HardwoodCommandTokens(
    bgCanvas: Color(0xFF0B0F17),
    bgSurface: Color(0xFF131A26),
    bgElevated: Color(0xFF1C2636),
    bgGlassHeader: Color(0xFF172030),
    borderSubtle: Color(0xFF263347),
    borderActive: Color(0xFFF59E0B),
    accentPrimary: Color(0xFFF59E0B),
    accentPrimaryFg: Color(0xFF0B0F17),
    accentPrimaryTint: Color(0x24F59E0B),
    accentSecondary: Color(0xFF0EA5E9),
    accentSecondaryFg: Color(0xFFE0F2FE),
    accentSecondaryBg: Color(0xFF0C2D48),
    teamPrimary: Color(0xFF1D4ED8),
    teamSecondary: Color(0xFF38BDF8),
    statusSuccess: Color(0xFF10B981),
    statusSuccessFg: Color(0xFF34D399),
    statusSuccessBg: Color(0xFF064E3B),
    statusWarning: Color(0xFFF97316),
    statusWarningFg: Color(0xFFFDBA74),
    statusWarningBg: Color(0xFF431407),
    statusDanger: Color(0xFFEF4444),
    statusDangerFg: Color(0xFFFCA5A5),
    statusDangerBg: Color(0xFF450A0A),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF7C8EA6),
    space100: 4.0,
    space200: 8.0,
    space300: 12.0,
    space400: 16.0,
    space600: 24.0,
    touchMin: 48.0,
    radiusSm: 6.0,
    radiusMd: 10.0,
    radiusLg: 14.0,
    radiusPill: 999.0,
  );

  final Color bgCanvas;
  final Color bgSurface;
  final Color bgElevated;
  final Color bgGlassHeader;
  final Color borderSubtle;
  final Color borderActive;

  final Color accentPrimary;
  final Color accentPrimaryFg;
  final Color accentPrimaryTint;
  final Color accentSecondary;
  final Color accentSecondaryFg;
  final Color accentSecondaryBg;
  final Color teamPrimary;
  final Color teamSecondary;

  final Color statusSuccess;
  final Color statusSuccessFg;
  final Color statusSuccessBg;
  final Color statusWarning;
  final Color statusWarningFg;
  final Color statusWarningBg;
  final Color statusDanger;
  final Color statusDangerFg;
  final Color statusDangerBg;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final double space100;
  final double space200;
  final double space300;
  final double space400;
  final double space600;
  final double touchMin;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusPill;

  static HardwoodCommandTokens of(BuildContext context) {
    final ext = Theme.of(context).extension<HardwoodCommandTokens>();
    return ext ?? dark;
  }

  @override
  HardwoodCommandTokens copyWith({
    Color? bgCanvas,
    Color? bgSurface,
    Color? bgElevated,
    Color? bgGlassHeader,
    Color? borderSubtle,
    Color? borderActive,
    Color? accentPrimary,
    Color? accentPrimaryFg,
    Color? accentPrimaryTint,
    Color? accentSecondary,
    Color? accentSecondaryFg,
    Color? accentSecondaryBg,
    Color? teamPrimary,
    Color? teamSecondary,
    Color? statusSuccess,
    Color? statusSuccessFg,
    Color? statusSuccessBg,
    Color? statusWarning,
    Color? statusWarningFg,
    Color? statusWarningBg,
    Color? statusDanger,
    Color? statusDangerFg,
    Color? statusDangerBg,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    double? space100,
    double? space200,
    double? space300,
    double? space400,
    double? space600,
    double? touchMin,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusPill,
  }) {
    return HardwoodCommandTokens(
      bgCanvas: bgCanvas ?? this.bgCanvas,
      bgSurface: bgSurface ?? this.bgSurface,
      bgElevated: bgElevated ?? this.bgElevated,
      bgGlassHeader: bgGlassHeader ?? this.bgGlassHeader,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderActive: borderActive ?? this.borderActive,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentPrimaryFg: accentPrimaryFg ?? this.accentPrimaryFg,
      accentPrimaryTint: accentPrimaryTint ?? this.accentPrimaryTint,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      accentSecondaryFg: accentSecondaryFg ?? this.accentSecondaryFg,
      accentSecondaryBg: accentSecondaryBg ?? this.accentSecondaryBg,
      teamPrimary: teamPrimary ?? this.teamPrimary,
      teamSecondary: teamSecondary ?? this.teamSecondary,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusSuccessFg: statusSuccessFg ?? this.statusSuccessFg,
      statusSuccessBg: statusSuccessBg ?? this.statusSuccessBg,
      statusWarning: statusWarning ?? this.statusWarning,
      statusWarningFg: statusWarningFg ?? this.statusWarningFg,
      statusWarningBg: statusWarningBg ?? this.statusWarningBg,
      statusDanger: statusDanger ?? this.statusDanger,
      statusDangerFg: statusDangerFg ?? this.statusDangerFg,
      statusDangerBg: statusDangerBg ?? this.statusDangerBg,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      space100: space100 ?? this.space100,
      space200: space200 ?? this.space200,
      space300: space300 ?? this.space300,
      space400: space400 ?? this.space400,
      space600: space600 ?? this.space600,
      touchMin: touchMin ?? this.touchMin,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusPill: radiusPill ?? this.radiusPill,
    );
  }

  @override
  HardwoodCommandTokens lerp(
    ThemeExtension<HardwoodCommandTokens>? other,
    double t,
  ) {
    if (other is! HardwoodCommandTokens) return this;
    return HardwoodCommandTokens(
      bgCanvas: Color.lerp(bgCanvas, other.bgCanvas, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      bgGlassHeader: Color.lerp(bgGlassHeader, other.bgGlassHeader, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderActive: Color.lerp(borderActive, other.borderActive, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentPrimaryFg: Color.lerp(accentPrimaryFg, other.accentPrimaryFg, t)!,
      accentPrimaryTint: Color.lerp(
        accentPrimaryTint,
        other.accentPrimaryTint,
        t,
      )!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      accentSecondaryFg: Color.lerp(
        accentSecondaryFg,
        other.accentSecondaryFg,
        t,
      )!,
      accentSecondaryBg: Color.lerp(
        accentSecondaryBg,
        other.accentSecondaryBg,
        t,
      )!,
      teamPrimary: Color.lerp(teamPrimary, other.teamPrimary, t)!,
      teamSecondary: Color.lerp(teamSecondary, other.teamSecondary, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusSuccessFg: Color.lerp(statusSuccessFg, other.statusSuccessFg, t)!,
      statusSuccessBg: Color.lerp(statusSuccessBg, other.statusSuccessBg, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusWarningFg: Color.lerp(statusWarningFg, other.statusWarningFg, t)!,
      statusWarningBg: Color.lerp(statusWarningBg, other.statusWarningBg, t)!,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t)!,
      statusDangerFg: Color.lerp(statusDangerFg, other.statusDangerFg, t)!,
      statusDangerBg: Color.lerp(statusDangerBg, other.statusDangerBg, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      space100: space100,
      space200: space200,
      space300: space300,
      space400: space400,
      space600: space600,
      touchMin: touchMin,
      radiusSm: radiusSm,
      radiusMd: radiusMd,
      radiusLg: radiusLg,
      radiusPill: radiusPill,
    );
  }
}

extension HardwoodTokensX on BuildContext {
  HardwoodCommandTokens get tokens => HardwoodCommandTokens.of(this);
}

ThemeData buildHardwoodCommandTheme() {
  const t = HardwoodCommandTokens.dark;
  final scheme = ColorScheme.dark(
    primary: t.accentPrimary,
    onPrimary: t.accentPrimaryFg,
    secondary: t.accentSecondary,
    onSecondary: t.accentSecondaryFg,
    surface: t.bgSurface,
    onSurface: t.textPrimary,
    onSurfaceVariant: t.textSecondary,
    surfaceContainerHighest: t.bgElevated,
    outline: t.borderSubtle,
    error: t.statusDanger,
    onError: Colors.white,
    primaryContainer: t.accentSecondaryBg,
    onPrimaryContainer: t.accentSecondaryFg,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bgCanvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: t.bgGlassHeader,
      foregroundColor: t.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: t.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: t.bgSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusLg),
        side: BorderSide(color: t.borderSubtle),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.borderSubtle, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: t.bgElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusLg),
        side: BorderSide(color: t.borderSubtle),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(t.touchMin, t.touchMin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusMd),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(t.touchMin, t.touchMin),
        foregroundColor: t.accentSecondaryFg,
        side: BorderSide(color: t.borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusMd),
        ),
      ),
    ),
    extensions: const <ThemeExtension<dynamic>>[HardwoodCommandTokens.dark],
  );
}
