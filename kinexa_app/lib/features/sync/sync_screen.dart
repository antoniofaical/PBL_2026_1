import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_button.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/kinexa_scroll_reveal.dart';
import '../../core/widgets/sync_brand_header.dart';
import '../../core/widgets/sync_version_footer.dart';
import '../../debug/demo_runs_seed.dart';
import '../../providers.dart';

enum SyncUiState { syncing, failed, success }

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  SyncUiState _state = SyncUiState.syncing;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  Future<void> _sync() async {
    setState(() => _state = SyncUiState.syncing);
    final syncRepo = ref.read(syncRepositoryProvider);
    try {
      final result = await syncRepo.syncAll();
      ref.read(serverOnlineProvider.notifier).state = result.online;
      if (result.success) {
        ref.read(offlineModeProvider.notifier).state = false;
        setState(() => _state = SyncUiState.success);
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) context.go('/home');
      } else {
        setState(() => _state = SyncUiState.failed);
      }
    } catch (_) {
      setState(() => _state = SyncUiState.failed);
    }
  }

  Future<void> _offline() async {
    ref.read(offlineModeProvider.notifier).state = true;
    ref.read(serverOnlineProvider.notifier).state = false;
    await seedDemoRunsIfEmpty(
      ref.read(runRepositoryProvider),
      ref.read(settingsDaoProvider),
    );
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            const SyncBrandHeader(),
            const SizedBox(height: 24),
            Expanded(child: _buildBody()),
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: SyncVersionFooter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_state) {
      SyncUiState.syncing => _syncingBody(),
      SyncUiState.success => _successBody(),
      SyncUiState.failed => _failedBody(),
    };
  }

  Widget _syncingBody() => _scrollableStateBody(
        icon: const SizedBox(
          width: 88,
          height: 88,
          child: CircularProgressIndicator(
            strokeWidth: 6,
            color: AppColors.redPrimary,
          ),
        ),
        title: 'Sincronizando banco de dados de performance...',
        titleSize: 21,
        titleSpacing: 2.1,
        subtitle: 'Aguarde enquanto carregamos seus dados de campo',
      );

  Widget _successBody() => _scrollableStateBody(
        icon: Icon(
          Symbols.check_circle,
          size: 88,
          color: AppColors.success,
        ),
        title: 'SINCRONIZAÇÃO CONCLUÍDA!',
        titleSize: 22,
        titleWeight: FontWeight.w700,
        subtitle: 'Seus dados foram atualizados com sucesso.',
      );

  Widget _scrollableStateBody({
    required Widget icon,
    required String title,
    required String subtitle,
    double titleSize = 18,
    double titleSpacing = 0,
    FontWeight titleWeight = FontWeight.w400,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 420;
        final gap = compact ? 20.0 : 40.0;

        return KinexaScrollReveal(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                SizedBox(height: gap),
                Text(
                  title,
                  style: AppTextStyles.mono(
                    size: titleSize,
                    weight: titleWeight,
                    letterSpacing: titleSpacing,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: gap * 0.6),
                Text(
                  subtitle,
                  style: AppTextStyles.mono(
                    size: compact ? 14 : 16,
                    color: AppColors.textMuted,
                    letterSpacing: compact ? 0.8 : 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _failedBody() {
    return KinexaScrollReveal(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Icon(
            Symbols.warning,
            size: 102,
            color: AppColors.redPrimary,
          ),
          const SizedBox(height: 49),
          Text(
            'FALHA NA SINCRONIZAÇÃO!',
            style: AppTextStyles.mono(
              size: 25,
              weight: FontWeight.w700,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            'Não foi possível conectar ao servidor. Verifique sua conexão à internet ou tente novamente.',
            style: AppTextStyles.mono(
              size: 18,
              color: AppColors.textMuted,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 49),
          KinexaButton.round(
            label: 'Tentar novamente',
            onPressed: _sync,
            expanded: true,
          ),
          const SizedBox(height: 20),
          _offlineButton(),
        ],
      ),
    );
  }

  Widget _offlineButton() {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: const Color(0xFF444444),
        borderRadius: BorderRadius.circular(AppRadii.roundButton),
        child: InkWell(
          onTap: _offline,
          borderRadius: BorderRadius.circular(AppRadii.roundButton),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              'ENTRAR NO MODO OFFLINE',
              style: AppTextStyles.mono(
                size: 16,
                weight: FontWeight.w700,
                letterSpacing: 0,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
