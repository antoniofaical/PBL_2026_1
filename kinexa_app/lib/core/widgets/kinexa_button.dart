import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_gradients.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

enum _KinexaButtonVariant { primary, secondary, square, round }

class KinexaButton extends StatelessWidget {
  const KinexaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outline = false,
    this.danger = false,
    this.expanded = true,
    this.enabled = true,
    this.icon,
    this.large = false,
  }) : _variant = null;

  const KinexaButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.expanded = true,
    this.enabled = true,
    this.icon,
    this.large = false,
  })  : outline = false,
        danger = false,
        _variant = _KinexaButtonVariant.primary;

  const KinexaButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.expanded = true,
    this.enabled = true,
    this.icon,
    this.large = false,
  })  : outline = true,
        danger = false,
        _variant = _KinexaButtonVariant.secondary;

  const KinexaButton.square({
    super.key,
    required this.label,
    required this.onPressed,
    this.expanded = false,
    this.enabled = true,
    this.icon,
    this.large = false,
  })  : outline = false,
        danger = false,
        _variant = _KinexaButtonVariant.square;

  const KinexaButton.round({
    super.key,
    required this.label,
    required this.onPressed,
    this.expanded = false,
    this.enabled = true,
    this.icon,
    this.large = false,
  })  : outline = false,
        danger = false,
        _variant = _KinexaButtonVariant.round;

  final String label;
  final VoidCallback? onPressed;
  final bool outline;
  final bool danger;
  final bool expanded;
  final bool enabled;
  final Widget? icon;
  final bool large;
  final _KinexaButtonVariant? _variant;

  @override
  Widget build(BuildContext context) {
    final variant = _variant ??
        (outline ? _KinexaButtonVariant.secondary : _KinexaButtonVariant.primary);
    final textStyle = large ? AppTextStyles.buttonLarge : AppTextStyles.button;
    final radius = switch (variant) {
      _KinexaButtonVariant.square => AppRadii.squareButton,
      _KinexaButtonVariant.round => AppRadii.roundButton,
      _ => AppRadii.squareButton,
    };

    Widget child;
    if (danger) {
      child = _solidButton(
        background: const Color(0xFF8B1A1A),
        foreground: Colors.white,
        border: null,
        radius: radius,
        textStyle: textStyle,
      );
    } else if (variant == _KinexaButtonVariant.secondary) {
      child = _solidButton(
        background: Colors.transparent,
        foreground: AppColors.redPrimary,
        border: Border.all(color: AppColors.redPrimary),
        radius: radius,
        textStyle: textStyle,
      );
    } else {
      child = _gradientButton(radius: radius, textStyle: textStyle);
    }

    return expanded ? SizedBox(width: double.infinity, child: child) : child;
  }

  Widget _gradientButton({
    required double radius,
    required TextStyle textStyle,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled ? AppGradients.primaryButton : null,
            color: enabled ? null : AppColors.disabled,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: _buttonContent(
            foreground: Colors.white,
            textStyle: textStyle,
          ),
        ),
      ),
    );
  }

  Widget _solidButton({
    required Color background,
    required Color foreground,
    required Border? border,
    required double radius,
    required TextStyle textStyle,
  }) {
    return Material(
      color: enabled ? background : AppColors.disabled,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: _buttonContent(foreground: foreground, textStyle: textStyle),
        ),
      ),
    );
  }

  Widget _buttonContent({
    required Color foreground,
    required TextStyle textStyle,
  }) {
    final horizontalPadding =
        large ? 12.0 : AppSpacing.buttonHorizontalMin;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.buttonVertical,
        horizontal: horizontalPadding,
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 8),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                style: textStyle.copyWith(color: foreground),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
