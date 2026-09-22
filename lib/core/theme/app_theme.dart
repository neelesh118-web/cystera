import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cystera's palette is a crimson→rose ramp rather than OneKit's monochrome.
///
/// The accent is deliberately a *deeper* crimson in both themes, because white
/// text on a bright rose (#E23A5E) only reaches about 4.2:1 contrast, which
/// fails AA for body-sized text on the app's primary button. #C81E48 puts white
/// at 5.6:1 and still reads as rose rather than burgundy.
///
/// Severity colours climb the same ramp instead of switching to a traffic light:
/// a symptom is never painted red-as-error and a good day is never green-as-good,
/// because both readings are wrong for a record-keeping app.
class Rose {
  Rose._();

  // Dark: warm near-black rather than pure black, so the crimson reads as lit.
  static const ink = Color(0xFF0B0709);
  static const inkSurface = Color(0xFF150E11);
  static const inkRaised = Color(0xFF1E1519);
  static const inkBorder = Color(0xFF2E2126);

  // Light: a warm off-white; a pure #FFFFFF background makes the rose look pink.
  static const paper = Color(0xFFFFF8F9);
  static const paperSurface = Color(0xFFFFFFFF);
  static const paperRaised = Color(0xFFFFF1F4);
  static const paperBorder = Color(0xFFF2D9E0);

  // The ramp itself.
  static const crimson = Color(0xFFC81E48);
  static const rose = Color(0xFFFF7A94);
  static const blush = Color(0xFFFFB3C1);
  static const ember = Color(0xFF8E1030);

  static const white = Color(0xFFFFFFFF);
  static const chalk = Color(0xFFFFF7F9);
  static const silver = Color(0xFFC9AEB6);
  static const ash = Color(0xFF8A737B);
  static const charcoal = Color(0xFF1A1114);
  static const smoke = Color(0xFF6B4A54);
}

/// Semantic tokens resolved per brightness. Widgets read these instead of
/// branching on `Theme.of(context).brightness` in every screen.
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.gradientStart,
    required this.gradientEnd,
    required this.severity,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;

  /// The primary button fill and the app's brand mark.
  final Color accent;

  /// Text and icons drawn on top of [accent].
  final Color onAccent;

  /// The lighter end of the ramp: highlights, secondary emphasis, charts.
  final Color accentSoft;

  final Color gradientStart;
  final Color gradientEnd;

  /// Index 0 is "none logged", 1–3 climb the ramp. Fixed length so widgets can
  /// index without a fallback that would silently render the wrong intensity.
  final List<Color> severity;

  final bool isDark;

  static const dark = AppTokens(
    background: Rose.ink,
    surface: Rose.inkSurface,
    surfaceRaised: Rose.inkRaised,
    border: Rose.inkBorder,
    textPrimary: Rose.chalk,
    textSecondary: Rose.silver,
    textFaint: Rose.ash,
    accent: Rose.crimson,
    onAccent: Rose.white,
    accentSoft: Rose.rose,
    gradientStart: Rose.crimson,
    gradientEnd: Rose.rose,
    severity: [Rose.inkBorder, Rose.blush, Rose.rose, Rose.crimson],
    isDark: true,
  );

  static const light = AppTokens(
    background: Rose.paper,
    surface: Rose.paperSurface,
    surfaceRaised: Rose.paperRaised,
    border: Rose.paperBorder,
    textPrimary: Rose.charcoal,
    textSecondary: Rose.smoke,
    textFaint: Rose.ash,
    accent: Rose.crimson,
    onAccent: Rose.white,
    accentSoft: Rose.rose,
    gradientStart: Rose.crimson,
    gradientEnd: Rose.rose,
    severity: [Rose.paperBorder, Rose.blush, Rose.rose, Rose.crimson],
    isDark: false,
  );

  @override
  ThemeExtension<AppTokens> copyWith() => this;

  @override
  ThemeExtension<AppTokens> lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return t < 0.5 ? this : other;
  }
}

extension TokenLookup on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}

class AppTheme {
  AppTheme._();

  static const double radius = 18;
  static const double radiusSmall = 12;
  static const double gutter = 20;

  /// Built once: a new ThemeData identity invalidates every `Theme.of` dependent
  /// in the tree, so rebuilding these on a settings change would rebuild
  /// everything on screen.
  static final ThemeData darkTheme = _build(AppTokens.dark);
  static final ThemeData lightTheme = _build(AppTokens.light);

  static ThemeData dark() => darkTheme;
  static ThemeData light() => lightTheme;

  static ThemeData _build(AppTokens t) {
    final scheme = ColorScheme(
      brightness: t.isDark ? Brightness.dark : Brightness.light,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accentSoft,
      onSecondary: t.textPrimary,
      surface: t.surface,
      onSurface: t.textPrimary,
      error: t.accent,
      onError: t.onAccent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: [t],
      textTheme: _text(base.textTheme, t),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: t.textPrimary,
        titleTextStyle: TextStyle(
          color: t.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: t.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
      ),
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: t.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          disabledBackgroundColor: t.border,
          disabledForegroundColor: t.textFaint,
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall + 2)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          minimumSize: const Size(0, 54),
          side: BorderSide(color: t.border, width: 1.4),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall + 2)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: t.textPrimary, minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        selectedColor: t.accent,
        side: BorderSide(color: t.border),
        labelStyle: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: t.onAccent, fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.isDark ? Rose.inkRaised : Rose.paperRaised,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: t.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? t.accent : t.textFaint,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: t.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surfaceRaised,
        contentTextStyle: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.border,
        circularTrackColor: t.border,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.textSecondary,
        textColor: t.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.surface,
        ),
        trackOutlineColor: WidgetStatePropertyAll(t.border),
      ),
    );
  }

  static TextTheme _text(TextTheme base, AppTokens t) {
    return base
        .apply(bodyColor: t.textPrimary, displayColor: t.textPrimary)
        .copyWith(
          displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.0, color: t.textPrimary),
          headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: t.textPrimary),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: t.textPrimary),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary),
          bodyLarge: TextStyle(fontSize: 15.5, height: 1.45, color: t.textPrimary),
          bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: t.textSecondary),
          bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: t.textFaint),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary),
        );
  }
}
