import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppGradients {
  static const primaryButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.redLight,
      AppColors.redPrimary,
      AppColors.redDark,
      AppColors.redHighlight,
    ],
    stops: [0.0, 0.5, 0.94, 1.0],
  );
}
