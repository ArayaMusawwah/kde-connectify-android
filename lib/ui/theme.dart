import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Signal palette (`brand/README.md` in linksy-desktop).
abstract final class Signal {
  static const blue = Color(0xFF2563FF);
  static const cyan = Color(0xFF22C3E6);
  static const deep = Color(0xFF1438B8);
}

/// Corner radii, from small pieces to whole surfaces.
abstract final class Radii {
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Material You: the wallpaper's colors when the system offers them, else
/// Signal blue as the seed.
ThemeData buildTheme(ColorScheme? dynamic, Brightness brightness) {
  final scheme =
      dynamic?.harmonized() ??
      ColorScheme.fromSeed(seedColor: Signal.blue, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  const stadium = StadiumBorder();
  const buttonText = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displayMedium: text.displayMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineLarge: text.headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      // Edge-to-edge: transparent bars, icons that contrast with the theme
      // rather than with an app bar color that may be see-through.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: brightness,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: stadium,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: stadium,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: stadium, textStyle: buttonText),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md + 4),
      ),
      extendedTextStyle: buttonText,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      titleTextStyle: text.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      iconColor: scheme.onSurfaceVariant,
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Icon(Icons.check)
            : null,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearTrackColor: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      linearMinHeight: 6,
    ),
  );
}

/// Status colors: green incoming and nearby, red failed or declined.
extension StatusColors on ColorScheme {
  bool get _light => brightness == Brightness.light;

  Color get incoming =>
      _light ? const Color(0xFF16803C) : const Color(0xFF7DDB95);

  Color get incomingContainer =>
      _light ? const Color(0xFFD7F5DE) : const Color(0xFF103D20);

  Color get nearby =>
      _light ? const Color(0xFF1F9D4F) : const Color(0xFF6ED68D);
}

/// Fill of grouped items: a step up from the page in either brightness.
Color groupFill(ColorScheme scheme) => scheme.brightness == Brightness.light
    ? scheme.surfaceContainerLow
    : scheme.surfaceContainerHigh;

/// A tonal scheme per device, seeded by its id, so each device keeps one
/// color across renames and on every screen.
ColorScheme deviceScheme(String id, Brightness brightness) =>
    _deviceSchemes.putIfAbsent((id, brightness), () {
      final hue = (int.tryParse(id.substring(0, 4), radix: 16) ?? 0) % 360;
      return ColorScheme.fromSeed(
        seedColor: HSLColor.fromAHSL(1, hue.toDouble(), 0.65, 0.5).toColor(),
        brightness: brightness,
      );
    });

final _deviceSchemes = <(String, Brightness), ColorScheme>{};
