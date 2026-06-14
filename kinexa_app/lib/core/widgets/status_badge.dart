import 'package:flutter/material.dart';
import '../../core/constants/enums.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case SyncStatus.synced:
        color = AppColors.textMuted;
      case SyncStatus.localOnly:
      case SyncStatus.syncFailed:
        color = AppColors.redPrimary;
      case SyncStatus.syncing:
        color = AppColors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Text(
        status.label,
        style: AppTextStyles.mono(
          size: 12,
          weight: FontWeight.w700,
          color: color,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
