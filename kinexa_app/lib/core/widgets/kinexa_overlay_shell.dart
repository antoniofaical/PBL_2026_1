import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';

import 'kinexa_overlay_scroll_hint.dart';

class KinexaOverlayShell extends StatelessWidget {
  const KinexaOverlayShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 40, 20, 20),
    this.backgroundColor = AppColors.popupBackground,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.overlayPopup),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2EFFFFFF),
            blurRadius: 10.4,
          ),
        ],
      ),
      child: child,
    );
  }
}

Future<T?> showKinexaOverlay<T>(
  BuildContext context,
  Widget child, {
  Color? backgroundColor,
  EdgeInsetsGeometry? padding,
  bool showScrollHint = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (dialogContext) {
      final maxHeight = MediaQuery.sizeOf(dialogContext).height * 0.88;
      final shellColor = backgroundColor ?? AppColors.popupBackground;

      final scrollChild = showScrollHint
          ? KinexaOverlayScrollArea(
              fadeColor: shellColor,
              child: child,
            )
          : SingleChildScrollView(child: child);

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: KinexaOverlayShell(
            backgroundColor: shellColor,
            padding: padding ?? const EdgeInsets.fromLTRB(20, 40, 20, 20),
            child: scrollChild,
          ),
        ),
      );
    },
  );
}
