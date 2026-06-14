import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/asset_paths.dart';

class KinexaRadar extends StatefulWidget {
  const KinexaRadar({super.key, this.size = 100});

  final double size;

  @override
  State<KinexaRadar> createState() => _KinexaRadarState();
}

class _KinexaRadarState extends State<KinexaRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          // 3. Base de fundo
          const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF583131),
            ),
          ),
          // 2. Radar com grade
          SvgPicture.asset(
            AssetPaths.effects.radarGrid,
            fit: BoxFit.cover,
          ),
          // 1. Sweeper por cima de tudo
          RotationTransition(
            turns: _controller,
            alignment: Alignment.center,
            child: CustomPaint(
              painter: const _RadarSweeperPainter(),
              size: Size(widget.size, widget.size),
            ),
          ),
        ],
      ),
    );
  }
}

/// Feixe do radar — desenhado em Canvas porque o SVG com máscara
/// não renderiza de forma confiável no flutter_svg.
class _RadarSweeperPainter extends CustomPainter {
  const _RadarSweeperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Alinhado ao wedge do radar_sweeper.svg (setor superior-direito).
    const startAngle = -math.pi / 2;
    const sweepAngle = math.pi / 2;

    final wedge = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(rect, startAngle, sweepAngle, false)
      ..close();

    final fill = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        const [
          Color(0xFFFFA4A4),
          Color(0xFFF96D6D),
          Color(0x00F96D6D),
        ],
        const [0.0, 0.35, 1.0],
        TileMode.clamp,
      )
      ..blendMode = BlendMode.srcOver;

    canvas.drawPath(wedge, fill);

    final edge = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx + radius * math.cos(startAngle + sweepAngle),
          center.dy + radius * math.sin(startAngle + sweepAngle));

    canvas.drawPath(
      edge,
      Paint()
        ..color = const Color(0xFFFFA4A4)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarSweeperPainter oldDelegate) => false;
}
