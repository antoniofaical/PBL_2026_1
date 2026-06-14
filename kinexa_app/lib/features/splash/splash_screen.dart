import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/sync_brand_header.dart';
import '../../core/widgets/sync_version_footer.dart';
import '../../data/local/local_database.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await LocalDatabase.instance.database;
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) context.go('/sync');
  }

  @override
  Widget build(BuildContext context) {
    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 50),
          const SyncBrandHeader(),
          const Spacer(),
          Text(
            'Inicializando...',
            style: AppTextStyles.mono(
              size: 24,
              weight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: SyncVersionFooter(),
          ),
        ],
      ),
    );
  }
}
