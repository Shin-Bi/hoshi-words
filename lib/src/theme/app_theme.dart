import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The starlit, warm-paper palette shared by the application.
abstract final class AppColors {
  static const ink = Color(0xFF17223B);
  static const paper = Color(0xFFF7F4ED);
  static const moon = Color(0xFFF2CB72);
  static const mutedBlue = Color(0xFF5E7294);

  static const deepBlue = Color(0xFF243657);
  static const searchField = Color(0xFF25314B);
  static const onDarkMuted = Color(0xFFAFBAD0);
  static const body = Color(0xFF5B6474);
  static const subtleText = Color(0xFF7A8290);
  static const reading = Color(0xFF96723A);
  static const bookmark = Color(0xFFB17A24);

  static const outline = Color(0xFFD8D4CA);
  static const cardOutline = Color(0xFFE4E0D7);
  static const divider = Color(0xFFE8E3D8);
  static const warmSurface = Color(0xFFF5F2EA);
  static const softSurface = Color(0xFFFBFAF7);
  static const toggleSurface = Color(0xFFE9E6DE);

  static const success = Color(0xFF3E765D);
  static const successText = Color(0xFF315F4B);
  static const successContainer = Color(0xFFE8F3EC);
  static const error = Color(0xFFB4554B);
  static const errorText = Color(0xFF8E4038);
  static const errorContainer = Color(0xFFF9E9E6);
}

/// Spacing values used by screens and reusable components.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double xxxl = 22;
  static const double section = 24;
  static const double screenBottom = 32;

  static const double screenHorizontal = 16;
  static const double heroHorizontal = 22;
  static const double listGap = 10;
}

/// Corner-radius values that preserve the rounded visual language.
abstract final class AppRadii {
  static const double small = 8;
  static const double inner = 10;
  static const double control = 13;
  static const double field = 14;
  static const double option = 15;
  static const double panel = 16;
  static const double card = 18;
  static const double largeCard = 22;
  static const double pill = 999;
}

/// Standard motion timings for small, non-disruptive transitions.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 180);
  static const standard = Duration(milliseconds: 200);
  static const emphasized = Duration(milliseconds: 220);
  static const expand = Duration(milliseconds: 240);
}

/// Bundled type families used to keep Korean and Japanese glyphs visually
/// consistent across devices.
abstract final class AppFonts {
  static const primary = 'sans-serif';
  static const japanese = 'sans-serif';
}

/// Material 3 theme for the word-study application.
abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.ink,
          brightness: Brightness.light,
          surface: AppColors.paper,
        ).copyWith(
          primary: AppColors.ink,
          onPrimary: Colors.white,
          primaryContainer: AppColors.deepBlue,
          onPrimaryContainer: Colors.white,
          secondary: AppColors.moon,
          onSecondary: AppColors.ink,
          secondaryContainer: const Color(0xFFFFF4D2),
          onSecondaryContainer: AppColors.ink,
          error: AppColors.error,
          onError: Colors.white,
          errorContainer: AppColors.errorContainer,
          onErrorContainer: AppColors.errorText,
          surface: AppColors.paper,
          onSurface: AppColors.ink,
          outline: AppColors.outline,
          outlineVariant: AppColors.cardOutline,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: AppColors.softSurface,
          surfaceContainer: AppColors.warmSurface,
          surfaceContainerHigh: AppColors.toggleSurface,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.paper,
      fontFamily: AppFonts.primary,
      fontFamilyFallback: const [
        AppFonts.japanese,
        'Noto Sans CJK KR',
        'Noto Sans CJK JP',
        'sans-serif',
      ],
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 32,
          height: 1.18,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          color: AppColors.ink,
          fontSize: 27,
          height: 1.25,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        headlineSmall: TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          height: 1.35,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 18,
          height: 1.35,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: AppColors.ink, fontSize: 16, height: 1.55),
        bodyMedium: TextStyle(color: AppColors.body, fontSize: 14, height: 1.5),
        bodySmall: TextStyle(
          color: AppColors.subtleText,
          fontSize: 12,
          height: 1.45,
        ),
        labelLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        labelMedium: TextStyle(
          color: AppColors.body,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.moon.withValues(alpha: 0.35),
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: AppColors.ink,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.ink
                : AppColors.mutedBlue,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        hintStyle: const TextStyle(color: AppColors.subtleText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.ink,
        disabledColor: AppColors.toggleSurface,
        side: const BorderSide(color: AppColors.outline),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: AppColors.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.paper,
        modalBackgroundColor: AppColors.paper,
        showDragHandle: true,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
