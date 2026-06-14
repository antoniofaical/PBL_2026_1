import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static const primaryFont = 'JetBrainsMono';
  static const displayFont = 'Digital7';
  static const displayMonoFont = 'Digital7Mono';

  static double _letterSpacingForSize(double size) {
    if (size >= 20) return 5.5;
    if (size >= 14) return 3.5;
    return 0.6;
  }

  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.text,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: primaryFont,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing ?? _letterSpacingForSize(size),
    );
  }

  static TextStyle digital({
    double size = 36,
    Color color = AppColors.text,
  }) {
    return TextStyle(
      fontFamily: displayFont,
      fontSize: size,
      color: color,
      letterSpacing: 2,
    );
  }

  static TextStyle digitalMono({
    double size = 36,
    Color color = AppColors.text,
  }) {
    return TextStyle(
      fontFamily: displayMonoFont,
      fontSize: size,
      color: color,
      letterSpacing: 2,
    );
  }

  static TextStyle get display => digital(size: 36);

  static TextStyle get title => mono(
        size: 20,
        weight: FontWeight.w700,
      );

  static TextStyle get button => mono(
        size: 14,
        weight: FontWeight.w700,
      );

  static TextStyle get buttonLarge => mono(
        size: 20,
        weight: FontWeight.w700,
      );

  static TextStyle get body => mono(size: 14);

  static TextStyle get caption => mono(
        size: 12,
        color: AppColors.textMuted,
      );

  static TextStyle get label => mono(
        size: 11,
        weight: FontWeight.w600,
        color: AppColors.textMuted,
      );
}
