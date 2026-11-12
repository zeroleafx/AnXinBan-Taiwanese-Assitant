import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// Palette: https://colorhunt.co/palette/2a7c1376c457fff8cffbe6c2
abstract final class AppColors {
  static const green = Color(0xFF2A7C13);
  static const leaf = Color(0xFF4E9F2E);
  static const freshGreen = Color(0xFF76C457);
  static const cream = Color(0xFFFBE6C2);
  static const paleYellow = Color(0xFFFFF8CF);
  static const sand = Color(0xFFFBEBCB);
  static const card = Color(0xFFFFFCF3);
  // Darker companion shade for readable text on the palette's light surfaces.
  static const ink = Color(0xFF293526);
  // Warm accent for recording and problems.
  static const coral = Color(0xFFE0583C);
  static const coralLight = Color(0xFFF28A5E);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.green).copyWith(
    primary: AppColors.green,
    onPrimary: Colors.white,
    secondary: AppColors.freshGreen,
    onSecondary: AppColors.ink,
    surface: AppColors.paleYellow,
    onSurface: AppColors.ink,
    outline: AppColors.green,
    error: AppColors.coral,
  );
  return ThemeData(
    useMaterial3: true,
    // Bundle the Chinese font to avoid platform font substitution.
    fontFamily:
        !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS)
        ? 'NotoSansTC'
        : null,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paleYellow,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: const StadiumBorder(),
      ),
    ),
  );
}
