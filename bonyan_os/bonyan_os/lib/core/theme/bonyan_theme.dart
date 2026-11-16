// lib/core/theme/bonyan_theme.dart
//
// ╔══════════════════════════════════════════════════════════════╗
// ║         بنيان OS — نظام التصميم (Namaa 2.0)                 ║
// ║  Arabic-first · Cairo Font · OLED Dark · Emerald Neo-brut    ║
// ╚══════════════════════════════════════════════════════════════╝

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 1 — COLOR PALETTE
// ─────────────────────────────────────────────────────────────────────────────

class BonyanColors {
  BonyanColors._();

  // ── Primary: Emerald ─────────────────────────────────────────────────────
  static const emerald50  = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981); // Brand primary
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald900 = Color(0xFF064E3B);

  // ── OLED Dark Scale ───────────────────────────────────────────────────────
  static const black      = Color(0xFF000000); // True OLED black
  static const surface900 = Color(0xFF0A0A0A); // Cards on OLED
  static const surface800 = Color(0xFF111111); // Elevated surfaces
  static const surface700 = Color(0xFF1A1A1A); // Dialogs
  static const surface600 = Color(0xFF242424); // Input fields
  static const surface500 = Color(0xFF2E2E2E); // Dividers / borders

  // ── Light Scale ───────────────────────────────────────────────────────────
  static const white      = Color(0xFFFFFFFF);
  static const grey50     = Color(0xFFFAFAFA);
  static const grey100    = Color(0xFFF5F5F5);
  static const grey200    = Color(0xFFE5E5E5);
  static const grey400    = Color(0xFFA3A3A3);
  static const grey600    = Color(0xFF525252);
  static const grey800    = Color(0xFF262626);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const success    = Color(0xFF10B981);
  static const warning    = Color(0xFFF59E0B);
  static const error      = Color(0xFFEF4444);
  static const info       = Color(0xFF3B82F6);

  // ── Neo-brutalism accents ────────────────────────────────────────────────
  static const neonEmerald = Color(0xFF00FF94); // Glow accent
  static const goldAccent  = Color(0xFFFFD700); // Achievement gold
  static const purpleAcc   = Color(0xFF8B5CF6); // Rank/badge special

  // ── Gradient presets ─────────────────────────────────────────────────────
  static const List<Color> emeraldGradient = [emerald500, emerald700];
  static const List<Color> darkGradient    = [surface800, black];
  static const List<Color> goldGradient    = [Color(0xFFFFD700), Color(0xFFFFA500)];
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 2 — TYPOGRAPHY (Cairo, Arabic-first)
// ─────────────────────────────────────────────────────────────────────────────

class BonyanTypography {
  BonyanTypography._();

  static TextTheme _buildTextTheme(Color onSurface) {
    final cairo = GoogleFonts.cairo;

    return TextTheme(
      // ── Display ───────────────────────────────────────────────────────────
      displayLarge: cairo(
        fontSize: 57, fontWeight: FontWeight.w800,
        letterSpacing: -0.25, color: onSurface,
        height: 1.12,
      ),
      displayMedium: cairo(
        fontSize: 45, fontWeight: FontWeight.w700,
        letterSpacing: 0, color: onSurface, height: 1.16,
      ),
      displaySmall: cairo(
        fontSize: 36, fontWeight: FontWeight.w700,
        letterSpacing: 0, color: onSurface, height: 1.22,
      ),

      // ── Headline ──────────────────────────────────────────────────────────
      headlineLarge: cairo(
        fontSize: 32, fontWeight: FontWeight.w700,
        letterSpacing: 0, color: onSurface, height: 1.25,
      ),
      headlineMedium: cairo(
        fontSize: 28, fontWeight: FontWeight.w600,
        letterSpacing: 0, color: onSurface, height: 1.29,
      ),
      headlineSmall: cairo(
        fontSize: 24, fontWeight: FontWeight.w600,
        letterSpacing: 0, color: onSurface, height: 1.33,
      ),

      // ── Title ─────────────────────────────────────────────────────────────
      titleLarge: cairo(
        fontSize: 22, fontWeight: FontWeight.w600,
        letterSpacing: 0, color: onSurface, height: 1.27,
      ),
      titleMedium: cairo(
        fontSize: 16, fontWeight: FontWeight.w600,
        letterSpacing: 0.15, color: onSurface, height: 1.50,
      ),
      titleSmall: cairo(
        fontSize: 14, fontWeight: FontWeight.w600,
        letterSpacing: 0.1, color: onSurface, height: 1.43,
      ),

      // ── Body ──────────────────────────────────────────────────────────────
      bodyLarge: cairo(
        fontSize: 16, fontWeight: FontWeight.w400,
        letterSpacing: 0.5, color: onSurface, height: 1.75,
      ),
      bodyMedium: cairo(
        fontSize: 14, fontWeight: FontWeight.w400,
        letterSpacing: 0.25, color: onSurface, height: 1.71,
      ),
      bodySmall: cairo(
        fontSize: 12, fontWeight: FontWeight.w400,
        letterSpacing: 0.4, color: onSurface, height: 1.67,
      ),

      // ── Label ─────────────────────────────────────────────────────────────
      labelLarge: cairo(
        fontSize: 14, fontWeight: FontWeight.w600,
        letterSpacing: 0.1, color: onSurface, height: 1.43,
      ),
      labelMedium: cairo(
        fontSize: 12, fontWeight: FontWeight.w600,
        letterSpacing: 0.5, color: onSurface, height: 1.33,
      ),
      labelSmall: cairo(
        fontSize: 11, fontWeight: FontWeight.w500,
        letterSpacing: 0.5, color: onSurface, height: 1.45,
      ),
    );
  }

  static TextTheme get dark  => _buildTextTheme(BonyanColors.white);
  static TextTheme get light => _buildTextTheme(BonyanColors.grey800);
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 3 — DARK THEME (OLED Black + Glowing Emerald)
// ─────────────────────────────────────────────────────────────────────────────

ThemeData bonyanDarkTheme() {
  const primary   = BonyanColors.emerald500;
  const onPrimary = BonyanColors.white;
  const bg        = BonyanColors.black;
  const surface   = BonyanColors.surface900;

  final colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary:            primary,
    onPrimary:          onPrimary,
    primaryContainer:   BonyanColors.emerald900,
    onPrimaryContainer: BonyanColors.emerald100,
    secondary:          BonyanColors.neonEmerald,
    onSecondary:        BonyanColors.black,
    secondaryContainer: BonyanColors.surface700,
    onSecondaryContainer: BonyanColors.emerald200,
    tertiary:           BonyanColors.goldAccent,
    onTertiary:         BonyanColors.black,
    error:              BonyanColors.error,
    onError:            BonyanColors.white,
    surface:            surface,
    onSurface:          BonyanColors.white,
    surfaceContainerHighest: BonyanColors.surface700,
    outline:            BonyanColors.surface500,
    outlineVariant:     BonyanColors.surface600,
    shadow:             BonyanColors.black,
    scrim:              BonyanColors.black,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: bg,
    textTheme: BonyanTypography.dark,

    // ── AppBar ───────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: BonyanColors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: primary.withOpacity(0.3),
      centerTitle: true,
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: BonyanColors.white,
      ),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: BonyanColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      iconTheme: const IconThemeData(color: BonyanColors.white),
    ),

    // ── Card ─────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: BonyanColors.surface500, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── ElevatedButton ───────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    // ── OutlinedButton ───────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: BonyanColors.emerald500, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    // ── TextButton ───────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),

    // ── InputDecoration ──────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BonyanColors.surface600,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BonyanColors.surface500),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BonyanColors.surface500),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BonyanColors.emerald500, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BonyanColors.error, width: 2),
      ),
      hintStyle: GoogleFonts.cairo(
        color: BonyanColors.grey400, fontSize: 14,
      ),
      labelStyle: GoogleFonts.cairo(
        color: BonyanColors.grey400, fontSize: 14,
      ),
      floatingLabelStyle: GoogleFonts.cairo(
        color: BonyanColors.emerald500, fontSize: 12,
      ),
    ),

    // ── BottomNavigationBar ──────────────────────────────────────────────────
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: BonyanColors.surface900,
      selectedItemColor: primary,
      unselectedItemColor: BonyanColors.grey400,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w400),
    ),

    // ── Chip ─────────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: BonyanColors.surface700,
      selectedColor: BonyanColors.emerald900,
      labelStyle: GoogleFonts.cairo(fontSize: 13, color: BonyanColors.white),
      side: const BorderSide(color: BonyanColors.surface500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: BonyanColors.surface500,
      thickness: 1,
      space: 1,
    ),

    // ── Dialog ───────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: BonyanColors.surface700,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: BonyanColors.white,
      ),
      contentTextStyle: GoogleFonts.cairo(
        fontSize: 15, color: BonyanColors.grey200,
      ),
    ),

    // ── SnackBar ─────────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BonyanColors.surface700,
      contentTextStyle: GoogleFonts.cairo(color: BonyanColors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
      actionTextColor: primary,
    ),

    // ── Switch ───────────────────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return BonyanColors.grey400;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primary.withOpacity(0.4);
        }
        return BonyanColors.surface600;
      }),
    ),

    // ── FloatingActionButton ─────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: BonyanColors.emerald500,
      foregroundColor: BonyanColors.white,
      elevation: 4,
      shape: CircleBorder(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 4 — LIGHT THEME (Clean Emerald on White)
// ─────────────────────────────────────────────────────────────────────────────

ThemeData bonyanLightTheme() {
  const primary   = BonyanColors.emerald600;
  const onPrimary = BonyanColors.white;
  const bg        = BonyanColors.grey50;
  const surface   = BonyanColors.white;

  final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary:            primary,
    onPrimary:          onPrimary,
    primaryContainer:   BonyanColors.emerald100,
    onPrimaryContainer: BonyanColors.emerald900,
    secondary:          BonyanColors.emerald400,
    onSecondary:        BonyanColors.white,
    secondaryContainer: BonyanColors.emerald50,
    onSecondaryContainer: BonyanColors.emerald900,
    tertiary:           BonyanColors.goldAccent,
    onTertiary:         BonyanColors.black,
    error:              BonyanColors.error,
    onError:            BonyanColors.white,
    surface:            surface,
    onSurface:          BonyanColors.grey800,
    surfaceContainerHighest: BonyanColors.grey100,
    outline:            BonyanColors.grey200,
    outlineVariant:     BonyanColors.grey100,
    shadow:             BonyanColors.grey400,
    scrim:              BonyanColors.black,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: bg,
    textTheme: BonyanTypography.light,

    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: BonyanColors.grey800,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: true,
      titleTextStyle: GoogleFonts.cairo(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: BonyanColors.grey800,
      ),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: BonyanColors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),

    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: BonyanColors.grey200),
      ),
      shadowColor: BonyanColors.grey400.withOpacity(0.3),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BonyanColors.grey100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BonyanColors.grey200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BonyanColors.grey200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BonyanColors.emerald600, width: 2),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 5 — DESIGN TOKENS (Spacing, Radius, Shadows, Haptics)
// ─────────────────────────────────────────────────────────────────────────────

class BonyanSpacing {
  BonyanSpacing._();
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 16.0;
  static const lg  = 24.0;
  static const xl  = 32.0;
  static const xxl = 48.0;
}

class BonyanRadius {
  BonyanRadius._();
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const full = 999.0;
}

class BonyanShadow {
  BonyanShadow._();

  static List<BoxShadow> emeraldGlow = [
    BoxShadow(
      color: BonyanColors.emerald500.withOpacity(0.4),
      blurRadius: 20,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: BonyanColors.emerald500.withOpacity(0.15),
      blurRadius: 40,
      spreadRadius: 4,
    ),
  ];

  static List<BoxShadow> cardDark = [
    BoxShadow(
      color: Colors.black.withOpacity(0.5),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> goldGlow = [
    BoxShadow(
      color: BonyanColors.goldAccent.withOpacity(0.5),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];
}

/// Haptic patterns — use with HapticFeedback.*
/// Different vibration semantics for Bonyan OS.
class BonyanHaptics {
  BonyanHaptics._();

  /// Positive reward / coin earned
  static Future<void> rewardPulse() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }

  /// Achievement unlocked — triple pulse
  static Future<void> achievementUnlocked() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }

  /// Urgent alarm (Fajr missed, cascade)
  static Future<void> urgentAlarm() async {
    for (int i = 0; i < 5; i++) {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  /// Soft confirmation
  static Future<void> softConfirm() => HapticFeedback.selectionClick();

  /// Error / warning
  static Future<void> errorPulse() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    await HapticFeedback.heavyImpact();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 6 — GRADIENT & DECORATIVE PRESETS
// ─────────────────────────────────────────────────────────────────────────────

class BonyanGradients {
  BonyanGradients._();

  static const emerald = LinearGradient(
    colors: [BonyanColors.emerald500, BonyanColors.emerald700],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const darkCard = LinearGradient(
    colors: [BonyanColors.surface800, BonyanColors.surface900],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const gold = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const emeraldGlow = RadialGradient(
    colors: [
      Color(0x4010B981), // emerald with 25% opacity
      Colors.transparent,
    ],
    radius: 1.5,
  );

  static LinearGradient coinShimmer = LinearGradient(
    colors: [
      BonyanColors.goldAccent.withOpacity(0.8),
      BonyanColors.goldAccent,
      BonyanColors.goldAccent.withOpacity(0.8),
    ],
    stops: const [0.0, 0.5, 1.0],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION 7 — THEME PROVIDER HELPER
// ─────────────────────────────────────────────────────────────────────────────

/// Convenience extension for accessing Bonyan design tokens from BuildContext.
extension BonyanThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get surfaceCard => isDark
      ? BonyanColors.surface900
      : BonyanColors.white;

  Color get emerald => isDark
      ? BonyanColors.emerald500
      : BonyanColors.emerald600;
}
