import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_text_styles.dart';

class DigitalDisplay extends StatelessWidget {
  const DigitalDisplay({
    super.key,
    required this.value,
    this.label,
    this.fontSize = 36,
  });

  final String value;
  final String? label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (label != null) ...[
          Text(label!, style: AppTextStyles.label),
          const SizedBox(height: 8),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.popupBackground,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.patternCircle),
          ),
          alignment: Alignment.center,
          child: Text(
            value,
            style: AppTextStyles.digital(size: fontSize),
          ),
        ),
      ],
    );
  }
}

String formatDurationMs(int ms) {
  final d = Duration(milliseconds: ms);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final cs = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s.$cs';
  return '$m:$s.$cs';
}
