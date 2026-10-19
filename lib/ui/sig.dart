import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// "Signal", Linksy's own look. Blue is the sender, cyan the receiver
/// (`brand/README.md` in linksy-desktop): outgoing things are blue, incoming
/// things cyan, everywhere.
@immutable
class Sig extends ThemeExtension<Sig> {
  const Sig({
    required this.bg,
    required this.card,
    required this.raised,
    required this.line,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.mint,
    required this.red,
    required this.heroTop,
    required this.heroBottom,
  });

  static const blue = Color(0xFF2563FF);
  static const cyan = Color(0xFF22C3E6);
  static const deep = Color(0xFF1438B8);

  /// Outgoing and incoming, by the brand's sender/receiver roles.
  static const outgoing = blue;
  static const incoming = cyan;

  static const display = 'Sora';
  static const body = 'Inter';

  final Color bg;
  final Color card;
  final Color raised;
  final Color line;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color mint;
  final Color red;

  /// The ink panel behind the orbit and device headers.
  final Color heroTop;
  final Color heroBottom;

  static const light = Sig(
    bg: Color(0xFFF2F4F9),
    card: Color(0xFFFFFFFF),
    raised: Color(0xFFE9EDF5),
    line: Color(0xFFE1E6EF),
    ink: Color(0xFF0A1024),
    muted: Color(0xFF5A6378),
    faint: Color(0xFF98A1B3),
    mint: Color(0xFF0FB37F),
    red: Color(0xFFE5384F),
    heroTop: Color(0xFF0B1230),
    heroBottom: Color(0xFF14257A),
  );

  static const dark = Sig(
    bg: Color(0xFF060A14),
    card: Color(0xFF0E1424),
    raised: Color(0xFF161D31),
    line: Color(0xFF1E2741),
    ink: Color(0xFFEEF2FA),
    muted: Color(0xFF8C95AB),
    faint: Color(0xFF545D74),
    mint: Color(0xFF2FD99E),
    red: Color(0xFFFF5C72),
    heroTop: Color(0xFF070C1F),
    heroBottom: Color(0xFF0F1D5C),
  );

  static Sig of(BuildContext context) => Theme.of(context).extension<Sig>()!;

  LinearGradient get hero => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [heroTop, heroBottom],
  );

  static const sendGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B74FF), deep],
  );

  @override
  Sig copyWith() => this;

  @override
  Sig lerp(Sig? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Sig(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      raised: l(raised, other.raised),
      line: l(line, other.line),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      mint: l(mint, other.mint),
      red: l(red, other.red),
      heroTop: l(heroTop, other.heroTop),
      heroBottom: l(heroBottom, other.heroBottom),
    );
  }
}

abstract final class Radii {
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 30.0;
}

/// Display text in Sora: titles, names, numbers.
TextStyle sora(
  double size, {
  FontWeight weight = FontWeight.w600,
  Color? color,
  double? spacing,
  double? height,
}) => TextStyle(
  fontFamily: Sig.display,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: spacing ?? -size * 0.025,
  height: height,
);

ThemeData buildTheme(Brightness brightness) {
  final s = brightness == Brightness.light ? Sig.light : Sig.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Sig.blue,
        brightness: brightness,
      ).copyWith(
        primary: Sig.blue,
        onPrimary: Colors.white,
        secondary: Sig.cyan,
        surface: s.bg,
        onSurface: s.ink,
        onSurfaceVariant: s.muted,
        surfaceContainerLowest: s.card,
        surfaceContainerLow: s.card,
        surfaceContainer: s.card,
        surfaceContainerHigh: s.card,
        surfaceContainerHighest: s.raised,
        outline: s.faint,
        outlineVariant: s.line,
        error: s.red,
      );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: Sig.body,
    brightness: brightness,
  );
  final t = base.textTheme;
  TextStyle? d(TextStyle? x, FontWeight w) => x?.copyWith(
    fontFamily: Sig.display,
    fontWeight: w,
    letterSpacing: -(x.fontSize ?? 16) * 0.025,
  );

  return base.copyWith(
    scaffoldBackgroundColor: s.bg,
    canvasColor: s.bg,
    extensions: [s],
    // No ink ripples: pressables scale instead (see Pressable).
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textTheme: t.copyWith(
      displayLarge: d(t.displayLarge, FontWeight.w700),
      displayMedium: d(t.displayMedium, FontWeight.w700),
      displaySmall: d(t.displaySmall, FontWeight.w700),
      headlineLarge: d(t.headlineLarge, FontWeight.w700),
      headlineMedium: d(t.headlineMedium, FontWeight.w700),
      headlineSmall: d(t.headlineSmall, FontWeight.w600),
      titleLarge: d(t.titleLarge, FontWeight.w600),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      foregroundColor: s.ink,
      systemOverlayStyle: overlayFor(brightness),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.card,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(alpha: 0.45),
      showDragHandle: true,
      dragHandleColor: s.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.light ? s.ink : s.raised,
      contentTextStyle: TextStyle(
        fontFamily: Sig.body,
        color: brightness == Brightness.light ? Colors.white : s.ink,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: s.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: s.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.raised,
      hintStyle: TextStyle(color: s.faint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: Sig.blue, width: 1.5),
      ),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Sig.blue),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? Colors.white : s.card,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? Sig.blue : s.raised,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? Sig.blue : s.line,
      ),
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Sig.blue,
      linearTrackColor: s.raised,
      borderRadius: BorderRadius.circular(4),
      linearMinHeight: 5,
    ),
  );
}

SystemUiOverlayStyle overlayFor(Brightness brightness) => SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.transparent,
  statusBarIconBrightness: brightness == Brightness.light
      ? Brightness.dark
      : Brightness.light,
  statusBarBrightness: brightness,
);

/// Each device's own hue, from its id, so it keeps one color across renames.
Color deviceHue(String id) {
  final h = (int.tryParse(id.substring(0, 4), radix: 16) ?? 0) % 360;
  return HSLColor.fromAHSL(1, h.toDouble(), 0.75, 0.58).toColor();
}
