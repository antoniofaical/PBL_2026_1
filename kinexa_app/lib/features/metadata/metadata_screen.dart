import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/enums.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_button.dart';
import '../../core/widgets/kinexa_form_field.dart';
import '../../core/widgets/kinexa_logo.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/kinexa_scroll_reveal.dart';
import '../../providers.dart';

class MetadataScreen extends ConsumerStatefulWidget {
  const MetadataScreen({super.key});

  @override
  ConsumerState<MetadataScreen> createState() => _MetadataScreenState();
}

class _MetadataScreenState extends ConsumerState<MetadataScreen> {
  final _athleteCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Activity _activity = Activity.saltoVertical;
  Environment _environment = Environment.pistaExterna;

  @override
  void dispose() {
    _athleteCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _start() {
    if (_athleteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Informe o nome do atleta',
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
          ),
          backgroundColor: AppColors.cardBackground,
        ),
      );
      return;
    }

    if (!ref.read(collectionSessionProvider).isCalibrated) {
      context.push('/calibration');
      return;
    }

    ref.read(collectionSessionProvider.notifier).setMetadata(
          athlete: _athleteCtrl.text.trim(),
          activity: _activity.value,
          environment: _environment.value,
          notes: _notesCtrl.text.trim(),
        );
    context.push('/collection');
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(serverOnlineProvider);
    final offlineMode = ref.watch(offlineModeProvider);
    final isOnline = online && !offlineMode;

    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: Column(
        children: [
          _MetadataHeader(isOnline: isOnline),
          Expanded(
            child: ColoredBox(
              color: AppColors.popupBackground,
              child: KinexaScrollReveal(
                padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'NOVA COLETA',
                      style: AppTextStyles.mono(
                        size: 32,
                        weight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.metadataSection),
                    KinexaMetadataTextField(
                      label: 'Nome do atleta',
                      controller: _athleteCtrl,
                    ),
                    const SizedBox(height: AppSpacing.metadataSection),
                    KinexaMetadataSelectField<Activity>(
                      label: 'Atividade',
                      value: _activity,
                      options: Activity.values,
                      itemLabel: (item) => item.label,
                      onChanged: (value) => setState(() => _activity = value),
                    ),
                    const SizedBox(height: AppSpacing.metadataSection),
                    KinexaMetadataSelectField<Environment>(
                      label: 'Ambiente',
                      value: _environment,
                      options: Environment.values,
                      itemLabel: (item) => item.label,
                      onChanged: (value) =>
                          setState(() => _environment = value),
                    ),
                    const SizedBox(height: AppSpacing.metadataSection),
                    KinexaMetadataTextField(
                      label: 'Observações',
                      controller: _notesCtrl,
                      maxLines: 5,
                      height: 183,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: KinexaButton.primary(
              label: 'INICIAR COLETA',
              large: true,
              onPressed: _start,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataHeader extends StatelessWidget {
  const _MetadataHeader({required this.isOnline});

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
