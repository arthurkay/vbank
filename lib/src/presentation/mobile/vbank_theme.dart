import 'package:shadcn_flutter/shadcn_flutter.dart';

/// vBank design tokens: matte-black dark, paper light, neutral accent.
///
/// Replaces the bare `ThemeData()` / `ThemeData.dark()` defaults (slate —
/// the dark-bluish cast) with explicit neutral ramps. Primary actions are
/// monochrome (near-black on light, near-white on dark); color is reserved
/// for semantics: amber warnings, red errors. Screens read
/// these through the theme; no per-screen color literals. Motion tokens
/// live here too so pushes, sheets and refreshes share one timing
/// language.
abstract final class VBankTheme {
  /// Dark page background. Matches the app icon tile.
  static const Color darkBackground = Color(0xFF0B0B0C);

  /// Dark card surface.
  static const Color darkCard = Color(0xFF171717);

  /// Dark sunken panel (breakdown boxes inside cards).
  static const Color darkPanel = Color(0xFF101012);

  /// Dark hairline borders and inputs.
  static const Color darkBorder = Color(0xFF262626);

  /// Dark secondary text.
  static const Color darkMutedForeground = Color(0xFFA1A1AA);

  /// Light page background (paper).
  static const Color lightBackground = Color(0xFFFAFAFA);

  /// Light card surface.
  static const Color lightCard = Color(0xFFFFFFFF);

  /// The dark color scheme: neutral matte zinc, monochrome primary.
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    background: darkBackground,
    foreground: Color(0xFFFAFAFA),
    card: darkCard,
    cardForeground: Color(0xFFFAFAFA),
    popover: darkCard,
    popoverForeground: Color(0xFFFAFAFA),
    primary: Color(0xFFFAFAFA),
    primaryForeground: Color(0xFF18181B),
    secondary: Color(0xFF1F1F1F),
    secondaryForeground: Color(0xFFFAFAFA),
    muted: Color(0xFF141414),
    mutedForeground: darkMutedForeground,
    accent: Color(0xFF1F1F1F),
    accentForeground: Color(0xFFFAFAFA),
    destructive: Color(0xFFF87171),
    destructiveForeground: Color(0xFF450A0A),
    border: darkBorder,
    input: darkBorder,
    ring: Color(0xFFD4D4D8),
    chart1: Color(0xFFFAFAFA),
    chart2: Color(0xFFD4D4D8),
    chart3: Color(0xFFA1A1AA),
    chart4: Color(0xFF71717A),
    chart5: Color(0xFF52525B),
  );

  /// The light color scheme: paper background, white cards.
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    background: lightBackground,
    foreground: Color(0xFF09090B),
    card: lightCard,
    cardForeground: Color(0xFF09090B),
    popover: lightCard,
    popoverForeground: Color(0xFF09090B),
    primary: Color(0xFF18181B),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFF4F4F5),
    secondaryForeground: Color(0xFF18181B),
    muted: Color(0xFFF4F4F5),
    mutedForeground: Color(0xFF71717A),
    accent: Color(0xFFF4F4F5),
    accentForeground: Color(0xFF18181B),
    destructive: Color(0xFFEF4444),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFE4E4E7),
    input: Color(0xFFE4E4E7),
    ring: Color(0xFF09090B),
    chart1: Color(0xFF18181B),
    chart2: Color(0xFF3F3F46),
    chart3: Color(0xFF71717A),
    chart4: Color(0xFFA1A1AA),
    chart5: Color(0xFFD4D4D8),
  );

  /// The light theme for [ShadcnApp].
  static const ThemeData light = ThemeData(
    colorScheme: lightScheme,
    radius: 0.75,
  );

  /// The dark theme for [ShadcnApp].
  static const ThemeData dark = ThemeData(
    colorScheme: darkScheme,
    radius: 0.75,
  );

  /// Drill-in pushes: slide plus fade.
  static const Duration pushDuration = Duration(milliseconds: 220);

  /// Drill-in curve.
  static const Curve pushCurve = Curves.easeOutCubic;

  /// Bottom sheets and dialogs.
  static const Duration sheetDuration = Duration(milliseconds: 260);

  /// Sheet curve.
  static const Curve sheetCurve = Curves.easeOutCubic;

  /// Tab switches and post-sync refreshes.
  static const Duration fadeDuration = Duration(milliseconds: 150);

  /// Builds a drill-in route honoring reduce-motion: with animations
  /// disabled the push is instant.
  static Route<T> pageRoute<T>(BuildContext context, Widget child) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return PageRouteBuilder<T>(
      transitionDuration: reduce ? Duration.zero : pushDuration,
      reverseTransitionDuration: reduce ? Duration.zero : pushDuration,
      pageBuilder: (_, _, _) => child,
      transitionsBuilder: (_, Animation<double> animation, _, Widget inner) {
        if (reduce) {
          return inner;
        }
        final CurvedAnimation curved = CurvedAnimation(
          parent: animation,
          curve: pushCurve,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: inner),
        );
      },
    );
  }
}
