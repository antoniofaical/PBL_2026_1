import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/boot/app_boot.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/sync_brand_header.dart';
import '../../core/widgets/sync_version_footer.dart';
import '../../data/local/local_database.dart';
import '../../providers.dart';
import '../../router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static int _bootGeneration = 0;
  int? _myBoot;

  @override
  void initState() {
    super.initState();
    _myBoot = ++_bootGeneration;
    _boot();
  }

  Future<void> _boot() async {
    final generation = _myBoot;
    final traceId = 'boot-$generation-${DateTime.now().millisecondsSinceEpoch}';
    resetBoot(traceId: traceId);
    authGate.value = false;
    ref.read(authUserProvider.notifier).state = null;

    await LocalDatabase.instance.database;
    if (!mounted || generation != _bootGeneration) return;

    // Apenas health check — sem sync, sem /api/runs.
    final healthFuture = ref.read(apiServiceProvider).healthCheck();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted || generation != _bootGeneration) return;

    final online = await healthFuture;
    ref.read(serverOnlineProvider.notifier).state = online;
    if (!mounted || generation != _bootGeneration) return;

    if (online) {
      bootPhase.value = BootPhase.auth;
      context.go('/auth');
    } else {
      bootPhase.value = BootPhase.offline;
      context.go('/sync?start=failed');
    }
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
