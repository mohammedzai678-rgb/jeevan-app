import 'package:flutter/material.dart';

/// Jeevan design tokens.
///
/// Colour theory: a single warm brand hue (crimson) carries every primary action
/// and the SOS identity; teal — its complement — is reserved for "healthy / ok"
/// states; deep navy ink gives text authority; everything else is a quiet cool
/// neutral so the brand colour can actually stand out.
class Palette {
  // Neutrals
  static const bg = Color(0xFFF6F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHi = Color(0xFFF1F3F8);
  static const outline = Color(0xFFE6E9F0);

  // Ink
  static const text = Color(0xFF111827);
  static const textDim = Color(0xFF5B6475);
  static const textMuted = Color(0xFF9AA3B2);

  // Brand
  static const red = Color(0xFFE63946);
  static const redDark = Color(0xFFC1121F);
  static const redLight = Color(0xFFFDECEE);

  // Supporting accents (always used as tint + saturated glyph pairs)
  static const teal = Color(0xFF0E9F8E);
  static const blue = Color(0xFF3B6FF0);
  static const purple = Color(0xFF7C4DDB);
  static const amber = Color(0xFFE59A0B);
  static const orange = Color(0xFFF2711C);
  static const green = Color(0xFF16A34A);
  static const pink = Color(0xFFE5508F);

  /// Tinted background for an accent colour (icon chips, pills).
  static Color tint(Color c, [double a = 0.12]) => c.withValues(alpha: a);

  static Color forStatus(String status) {
    switch (status.toLowerCase()) {
      case 'critical':
      case 'high':
        return red;
      case 'warning':
      case 'moderate':
        return orange;
      case 'attention':
        return amber;
      default:
        return green;
    }
  }
}

/// Spacing scale (8-pt grid).
class Gap {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

const kFontFamily = 'PlusJakartaSans';

TextTheme _textTheme() {
  const ink = Palette.text;
  TextStyle s(double size, FontWeight w, {double h = 1.35, double ls = 0, Color c = ink}) =>
      TextStyle(
        fontFamily: kFontFamily,
        fontSize: size,
        fontWeight: w,
        height: h,
        letterSpacing: ls,
        color: c,
      );
  return TextTheme(
    displayLarge: s(34, FontWeight.w800, h: 1.15, ls: -0.8),
    displayMedium: s(30, FontWeight.w800, h: 1.15, ls: -0.6),
    displaySmall: s(26, FontWeight.w800, h: 1.2, ls: -0.5),
    headlineLarge: s(24, FontWeight.w800, h: 1.2, ls: -0.4),
    headlineMedium: s(22, FontWeight.w800, h: 1.25, ls: -0.3),
    headlineSmall: s(20, FontWeight.w700, h: 1.25, ls: -0.2),
    titleLarge: s(18, FontWeight.w700, ls: -0.2),
    titleMedium: s(16, FontWeight.w700, ls: -0.1),
    titleSmall: s(14, FontWeight.w700),
    bodyLarge: s(16, FontWeight.w500, h: 1.5),
    bodyMedium: s(14, FontWeight.w500, h: 1.45),
    bodySmall: s(12.5, FontWeight.w500, h: 1.4, c: Palette.textDim),
    labelLarge: s(14, FontWeight.w700),
    labelMedium: s(12, FontWeight.w600, ls: 0.2),
    labelSmall: s(11, FontWeight.w600, ls: 0.3, c: Palette.textDim),
  );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: Palette.red,
    onPrimary: Colors.white,
    primaryContainer: Palette.redLight,
    onPrimaryContainer: Palette.red,
    secondary: Palette.teal,
    onSecondary: Colors.white,
    secondaryContainer: Palette.redLight,
    onSecondaryContainer: Palette.red,
    tertiary: Palette.blue,
    error: Palette.red,
    surface: Palette.surface,
    onSurface: Palette.text,
    outline: Palette.outline,
  );

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: kFontFamily,
    colorScheme: scheme,
    textTheme: _textTheme(),
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.surface,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.surface,
      foregroundColor: Palette.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: IconThemeData(color: Palette.text),
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        color: Palette.text,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    dividerTheme: const DividerThemeData(color: Palette.outline, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(Palette.outline),
      enabledBorder: border(Palette.outline),
      focusedBorder: border(Palette.red, 1.6),
      labelStyle: const TextStyle(color: Palette.textDim, fontWeight: FontWeight.w500),
      hintStyle: const TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.red,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        minimumSize: const Size(0, 46),
        side: const BorderSide(color: Palette.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.red,
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Palette.surface,
      selectedColor: Palette.redLight,
      secondarySelectedColor: Palette.redLight,
      checkmarkColor: Palette.red,
      side: const BorderSide(color: Palette.outline),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Palette.text,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: kFontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Palette.red,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.red,
      thumbColor: Palette.red,
      inactiveTrackColor: Palette.outline,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.red : Palette.outline,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Palette.red,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.text,
      contentTextStyle: const TextStyle(
        fontFamily: kFontFamily,
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}
