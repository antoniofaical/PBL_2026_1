import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/boot/app_boot.dart';
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
import '../../router.dart';

enum SyncUiState { syncing, failed, authRequired, success }

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key, this.startFailed = false});

  /// Servidor indisponível na splash — exibe falha sem tentar sync.
  final bool startFailed;

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  static Future<void>? _uiSyncFuture;

  late SyncUiState _state;
  bool _bootstrapped = false;
  String? _failureDetail;

  @override
  void initState() {
    super.initState();
    _state = widget.startFailed ? SyncUiState.failed : SyncUiState.syncing;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped || !mounted) return;
    _bootstrapped = true;

    if (widget.startFailed) {
      ref.read(serverOnlineProvider.notifier).state = false;
      setState(() {
        _failureDetail =
            'Boot offline: health check falhou na splash (sem requests de sync).';
      });
      return;
    }

    if (!authGate.value || bootPhase.value != BootPhase.syncing) {
      context.go('/auth');
      return;
    }

    await _sync();
  }

  Future<void> _sync() async {
    if (!authGate.value || bootPhase.value != BootPhase.syncing) {
      if (mounted) context.go('/auth');
      return;
    }

    _uiSyncFuture ??= _runSync().whenComplete(() => _uiSyncFuture = null);
    await _uiSyncFuture;
  }

  Future<void> _runSync() async {
    if (!mounted) return;
    setState(() {
      _state = SyncUiState.syncing;
      _failureDetail = null;
    });

    final syncRepo = ref.read(syncRepositoryProvider);
    try {
      // Splash já validou health; não repetir aqui (evita falso offline).
      final result = await syncRepo.syncAll(skipHealthCheck: true);
      if (!mounted) return;

      ref.read(serverOnlineProvider.notifier).state = true;
      if (result.success) {
        ref.read(offlineModeProvider.notifier).state = false;
        bootPhase.value = BootPhase.ready;
        setState(() => _state = SyncUiState.success);
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        context.go('/home');
      } else if (result.authRequired) {
        authGate.value = false;
        bootPhase.value = BootPhase.auth;
        ref.read(authUserProvider.notifier).state = null;
        setState(() => _state = SyncUiState.authRequired);
      } else {
        setState(() {
          _state = SyncUiState.failed;
          _failureDetail = result.message ??
              result.error?.toString() ??
              'Erro desconhecido (online=${result.online})';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = SyncUiState.failed;
        _failureDetail = e.toString();
      });
    }
  }

  Future<void> _offline() async {
    ref.read(offlineModeProvider.notifier).state = true;
    ref.read(serverOnlineProvider.notifier).state = false;
    bootPhase.value = BootPhase.ready;
    await seedDemoRunsIfEmpty(
      ref.read(runRepositoryProvider),
      ref.read(settingsDaoProvider),
    );
    if (!mounted) return;
    context.go('/home');
  }

  void _retry() {
    if (widget.startFailed) {
      context.go('/splash');
      return;
    }
    _sync();
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
      SyncUiState.authRequired => _authRequiredBody(),
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

  Widget _authRequiredBody() {
    return KinexaScrollReveal(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Icon(
            Symbols.lock_reset,
            size: 88,
            color: AppColors.redPrimary,
          ),
          const SizedBox(height: 40),
          Text(
            'SESSÃO EXPIRADA',
            style: AppTextStyles.mono(
              size: 22,
              weight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            'Entre novamente para sincronizar com o servidor.',
            style: AppTextStyles.mono(
              size: 16,
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          KinexaButton.round(
            label: 'Ir para login',
            onPressed: () {
              authGate.value = false;
              bootPhase.value = BootPhase.auth;
              context.go('/auth');
            },
            expanded: true,
          ),
        ],
      ),
    );
  }

  Widget _failedBody() {
    final offlineBoot = widget.startFailed;
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
            offlineBoot ? 'SERVIDOR INDISPONÍVEL' : 'FALHA NA SINCRONIZAÇÃO!',
            style: AppTextStyles.mono(
              size: offlineBoot ? 22 : 25,
              weight: FontWeight.w700,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            offlineBoot
                ? 'Não foi possível validar o servidor na inicialização. Verifique a conexão ou o endereço em Servidor.'
                : 'Não foi possível concluir a sincronização local. Os dados podem ter sido baixados do servidor.',
            style: AppTextStyles.mono(
              size: 18,
              color: AppColors.textMuted,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          if (_failureDetail != null) ...[
            const SizedBox(height: 20),
            Text(
              'DETALHE TÉCNICO',
              style: AppTextStyles.mono(
                size: 11,
                weight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _failureDetail!,
              style: AppTextStyles.mono(
                size: 12,
                color: AppColors.redLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 49),
          KinexaButton.round(
            label: offlineBoot ? 'Tentar inicialização' : 'Tentar novamente',
            onPressed: _retry,
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
