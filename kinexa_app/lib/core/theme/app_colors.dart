import 'package:flutter/material.dart';

class AppColors {
  // Canonical tokens
  static const baseBackground = Color(0xFF121212);
  static const patternCircle = Color(0xFF2C2C2C);
  static const cardBackground = Color(0xFF2C2C2C);
  static const popupBackground = Color(0xFF191919);

  static const redLight = Color(0xFFFF434E);
  static const redPrimary = Color(0xFFE30613);
  static const redDark = Color(0xFFB5000B);
  static const redHighlight = Color(0xFFFF7676);
  static const digitalAccent = Color(0xFFFF2431);

  static const text = Color(0xFFE8E8E8);
  static const textMuted = Color(0xFF9A9A9A);
  static const success = Color(0xFF2ECC71);
  static const warning = Color(0xFFF1C40F);
  static const disabled = Color(0xFF555555);

  static const overlayScrim = Colors.black;

  // Legacy aliases (used by existing screens until migrated)
  static const carbon = baseBackground;
  static const card = cardBackground;
  static const elevated = popupBackground;
  static const border = patternCircle;
  static const primary = redPrimary;
  static const primaryHover = redLight;
}
