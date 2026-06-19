import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_button.dart';
import '../../core/widgets/kinexa_calibration_tips_card.dart';
import '../../core/widgets/kinexa_logo.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/kinexa_scroll_reveal.dart';
import '../../overlays/calibration_positioning_overlay.dart';
import '../../providers.dart';
import '../../services/ble/ble_exception.dart';

enum CalibUiState { ready, calibrating, success, failed }

class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  CalibUiState _state = CalibUiState.ready;
  bool _openingOverlay = false;
  String? _lastError;

  Future<void> _startCalibration() async {
    if (_state == CalibUiState.calibrating || _openingOverlay) return;

    _openingOverlay = true;
    try {
      final ok = await showSensorPositioningOverlay(context);
      if (!ok || !mounted) return;

      setState(() {
        _state = CalibUiState.calibrating;
        _lastError = null;
      });
      try {
        await ref.read(bleServiceProvider).calibrate();
        ref.read(collectionSessionProvider.notifier).markCalibrated();
        setState(() => _state = CalibUiState.success);

        final mode = ref.read(sensorFlowModeProvider);
        if (mode == SensorFlowMode.newCollection) {
          await Future.delayed(const Duration(milliseconds: 1200));
          if (mounted) context.push('/metadata');
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _state = CalibUiState.failed;
            _lastError = e is BleException
                ? e.message
                : 'Falha na calibração: $e';
          });
        }
      }
    } finally {
      _openingOverlay = false;
    }
  }

  void _finishSetupFlow() {
    ref.read(sensorFlowModeProvider.notifier).state =
        SensorFlowMode.newCollection;
    ref.read(collectionSessionProvider.notifier).reset();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(serverOnlineProvider);
    final offlineMode = ref.watch(offlineModeProvider);
    final isOnline = online && !offlineMode;
    final flowMode = ref.watch(sensorFlowModeProvider);
    final setupOnly = flowMode != SensorFlowMode.newCollection;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        if (ref.read(sensorFlowModeProvider) != SensorFlowMode.newCollection) {
          ref.read(sensorFlowModeProvider.notifier).state =
              SensorFlowMode.newCollection;
          ref.read(collectionSessionProvider.notifier).reset();
        }
      },
      child: KinexaScaffold(
      body: Column(
        children: [
          _CalibrationHeader(isOnline: isOnline),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.popupBackground,
                  borderRadius: BorderRadius.circular(AppRadii.calibrationPanel),
                ),
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return KinexaScrollReveal(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'CALIBRAÇÃO',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.title
                                  .copyWith(letterSpacing: 0),
                            ),
                            const KinexaCalibrationTipsCard(),
                            const KinexaCalibrationImportantNote(),
                            _CalibrationActionArea(
                              state: _state,
                              errorMessage: _lastError,
                              setupOnly: setupOnly,
                              onStart: _startCalibration,
                              onContinue: _finishSetupFlow,
                            ),
                            const KinexaCalibrationRecalibrateNote(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _CalibrationHeader extends StatelessWidget {
  const _CalibrationHeader({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.baseBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Row(
          children: [
            const KinexaLogo(size: 40, variant: KinexaLogoVariant.darkInv),
            const Spacer(),
            _OnlineStatus(isOnline: isOnline),
          ],
        ),
      ),
    );
  }
}

class _OnlineStatus extends StatelessWidget {
  const _OnlineStatus({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final dotColor = isOnline ? AppColors.success : AppColors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            boxShadow: isOnline
                ? [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          isOnline ? 'Online' : 'Offline',
          style: AppTextStyles.mono(
            size: 10,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _CalibrationActionArea extends StatelessWidget {
  const _CalibrationActionArea({
    required this.state,
    required this.onStart,
    required this.setupOnly,
    this.errorMessage,
    this.onContinue,
  });

  final CalibUiState state;
  final String? errorMessage;
  final VoidCallback onStart;
  final bool setupOnly;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (state == CalibUiState.success || state == CalibUiState.failed) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                state == CalibUiState.success ? Symbols.check : Symbols.close,
                size: 20,
                color: state == CalibUiState.success
                    ? AppColors.success
                    : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  state == CalibUiState.success
                      ? 'CALIBRAÇÃO CONCLUÍDA'
                      : 'CALIBRAÇÃO FALHOU',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.mono(
                    size: 15,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (state == CalibUiState.failed &&
            errorMessage != null &&
            errorMessage!.isNotEmpty) ...[
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: AppTextStyles.mono(
              size: 11,
              color: AppColors.textMuted,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
        ],
        switch (state) {
          CalibUiState.ready => KinexaButton.primary(
              label: 'INICIAR CALIBRAÇÃO',
              large: true,
              onPressed: onStart,
            ),
          CalibUiState.calibrating => _CalibrationPillButton(
              label: 'CALIBRANDO...',
              backgroundColor: const Color(0x5CB5000B),
              textColor: const Color(0xFFAAAAAA),
            ),
          CalibUiState.success => setupOnly
              ? _CalibrationPillButton(
                  label: 'CONTINUAR',
                  backgroundColor: const Color(0x8027C840),
                  textColor: Colors.white,
                  onPressed: onContinue,
                )
              : const _CalibrationPillButton(
                  label: 'CONTINUANDO...',
                  backgroundColor: Color(0x8027C840),
                  textColor: Colors.white,
                ),
          CalibUiState.failed => _CalibrationPillButton(
              label: 'TENTAR NOVAMENTE',
              onPressed: onStart,
            ),
        },
      ],
    );
  }
}

class _CalibrationPillButton extends StatelessWidget {
  const _CalibrationPillButton({
    required this.label,
    this.onPressed,
    this.backgroundColor = const Color(0xB3AAAAAA),
    this.textColor = AppColors.text,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(97),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(97),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.mono(
                  size: 20,
                  weight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
