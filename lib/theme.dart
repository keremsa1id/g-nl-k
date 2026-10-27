import 'package:flutter/material.dart';

/// Siyah zemin + kırmızı vurgulu modern koyu tema.
class AppTheme {
  static const red = Color(0xFFE53935);
  static const redBright = Color(0xFFFF4D4D);
  static const redDeep = Color(0xFF7F0D12);
  static const black = Color(0xFF000000);
  static const surface1 = Color(0xFF0D0D0F);
  static const surface2 = Color(0xFF151518);
  static const surface3 = Color(0xFF1D1D21);
  static const border = Color(0xFF26262B);

  static const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: red,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF3B0A0E),
    onPrimaryContainer: Color(0xFFFFDAD6),
    secondary: redBright,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF2A0F12),
    onSecondaryContainer: Color(0xFFFFB4AB),
    tertiary: Color(0xFFFF8A65),
    onTertiary: black,
    error: Color(0xFFFF5449),
    onError: black,
    surface: black,
    onSurface: Color(0xFFF2F2F3),
    onSurfaceVariant: Color(0xFF9D9DA6),
    surfaceContainerLowest: black,
    surfaceContainerLow: surface1,
    surfaceContainer: surface1,
    surfaceContainerHigh: surface2,
    surfaceContainerHighest: surface3,
    outline: Color(0xFF3A3A40),
    outlineVariant: border,
    shadow: black,
    scrim: black,
    inverseSurface: Color(0xFFF2F2F3),
    onInverseSurface: black,
    inversePrimary: redDeep,
    surfaceTint: Colors.transparent,
  );

  static ThemeData get dark {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final rounded14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return base.copyWith(
      scaffoldBackgroundColor: black,
      canvasColor: black,
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: black,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        indicatorColor: red.withValues(alpha: 0.18),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? redBright : scheme.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? redBright : scheme.onSurfaceVariant,
            )),
      ),
      cardTheme: CardThemeData(
        color: surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: red,
        foregroundColor: Colors.white,
        elevation: 6,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: rounded14,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: redBright,
          side: BorderSide(color: red.withValues(alpha: 0.6)),
          shape: rounded14,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: redBright, shape: rounded14),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: red, width: 1.6),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: Color(0xFF4A4A52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: border),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface3,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        actionTextColor: redBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: redBright,
        linearTrackColor: Colors.white.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? red : surface3),
        trackOutlineColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? red : scheme.outline),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        selectedColor: red.withValues(alpha: 0.25),
        checkmarkColor: redBright,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? red : surface2),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? Colors.white : scheme.onSurfaceVariant),
          side: const WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: surface2,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: redDeep,
        headerForegroundColor: Colors.white,
      ),
      timePickerTheme: const TimePickerThemeData(backgroundColor: surface2),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(surface2),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: border),
          )),
        ),
      ),
    );
  }
}
