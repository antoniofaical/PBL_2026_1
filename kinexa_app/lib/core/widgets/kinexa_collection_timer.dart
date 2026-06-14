import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'digital_display.dart';

class KinexaCollectionTimer extends StatelessWidget {
  const KinexaCollectionTimer({super.key, required this.elapsedMs});

  final int elapsedMs;

  static const _cardPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);
  static const _contentHeight = 168.0;
  static const _mainFontSize = 81.8;
  static const _csFontSize = 49.8;
  static const _verticalOffset = -3.0;
  static const _gap = 13.0;

  static double _measureText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final formatted = formatDurationMs(elapsedMs);
    final parts = formatted.split('.');
    final main = parts.first;
    final centiseconds = parts.length > 1 ? parts[1] : '00';

    final mainStyle = AppTextStyles.digitalMono(
      size: _mainFontSize,
      color: AppColors.redPrimary,
    );
    final csStyle = AppTextStyles.digitalMono(
      size: _csFontSize,
      color: AppColors.redPrimary,
    );

    final mainSlotWidth = _measureText('00:00', mainStyle);
    final csSlotWidth = _measureText('00', csStyle);

    return Container(
      width: double.infinity,
      padding: _cardPadding,
      decoration: BoxDecoration(
        color: AppColors.baseBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        height: _contentHeight,
        width: double.infinity,
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, _verticalOffset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: mainSlotWidth,
                  child: Text(
                    main,
                    textAlign: TextAlign.right,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: mainStyle,
                  ),
                ),
                const SizedBox(width: _gap),
                SizedBox(
                  width: csSlotWidth,
                  child: Text(
                    centiseconds,
                    textAlign: TextAlign.left,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: csStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
