import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    surface: AppColors.baseBackground,
    primary: AppColors.redPrimary,
    onPrimary: Colors.white,
    secondary: AppColors.popupBackground,
    onSurface: AppColors.text,
    error: AppColors.redPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppTextStyles.primaryFont,
    scaffoldBackgroundColor: AppColors.baseBackground,
    cardColor: AppColors.cardBackground,
    dividerColor: AppColors.patternCircle,
    textTheme: TextTheme(
      headlineMedium: AppTextStyles.title,
      bodyMedium: AppTextStyles.body,
      labelLarge: AppTextStyles.button,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.baseBackground,
      foregroundColor: AppColors.text,
      elevation: 0,
      titleTextStyle: AppTextStyles.title,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.popupBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        borderSide: const BorderSide(color: AppColors.patternCircle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        borderSide: const BorderSide(color: AppColors.patternCircle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        borderSide: const BorderSide(color: AppColors.redPrimary),
      ),
      labelStyle: AppTextStyles.label,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: AppSpacing.buttonVertical,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.popupBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.popupBackground,
    ),
  );
}
