import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Fundo hex-grid com círculos discretos conforme tokens do design system.
class KinexaPatternBackground extends StatelessWidget {
  const KinexaPatternBackground({
    super.key,
    required this.child,
    this.color = AppColors.baseBackground,
  });

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: CustomPaint(
        painter: const _KinexaCirclePatternPainter(),
        child: child,
      ),
    );
  }
}

class _KinexaCirclePatternPainter extends CustomPainter {
  const _KinexaCirclePatternPainter();

  static const double baseCircleSize = 15.0;
  static const double scale = 0.17;
  static const double spacingFactor = 2.38;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (baseCircleSize * scale) / 2;
    final spacingX = baseCircleSize * spacingFactor;
    final spacingY = baseCircleSize * spacingFactor;

    final paint = Paint()
      ..color = AppColors.patternCircle.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;

    for (double y = 0; y < size.height + spacingY; y += spacingY) {
      final row = (y / spacingY).floor();
      final offsetX = row.isEven ? 0.0 : spacingX / 2;

      for (double x = -spacingX; x < size.width + spacingX; x += spacingX) {
        canvas.drawCircle(Offset(x + offsetX, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
