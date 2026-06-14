import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_text_styles.dart';

class SyncVersionFooter extends StatelessWidget {
  const SyncVersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      AppConstants.appVersionLabel,
      style: AppTextStyles.mono(
        size: 12,
        color: const Color(0xFFBBBBBB),
        letterSpacing: 1.2,
      ),
      textAlign: TextAlign.center,
    );
  }
}
