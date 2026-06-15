import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/kinexa_logo.dart';
import '../../core/widgets/kinexa_scaffold.dart';
import '../../core/widgets/kinexa_scroll_reveal.dart';
import '../../providers.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(offlineModeProvider)) {
        ref.read(syncRepositoryProvider).syncPendingUploads();
      }
    });
  }

  static const _credits = [
    'Antonio Elias Faiçal Junior',
    'Beatriz Pena de Antonio',
    'Isabelle Yadoya Chakur',
    'José Guilherme Teixeira Salama',
    'Otávio Nunes Ferreira Messer',
    'Pedro Condão Machado Milhomem',
    'Tiago Bandeira de Mello',
  ];

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(serverOnlineProvider);
    final offlineMode = ref.watch(offlineModeProvider);
    final isOnline = online && !offlineMode;

    return KinexaScaffold(
      backgroundColor: AppColors.popupBackground,
      body: Column(
        children: [
          _AboutHeader(
            isOnline: isOnline,
            onBack: () => context.pop(),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return KinexaScrollReveal(
                  padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SOBRE',
                          style: AppTextStyles.mono(
                            size: 24,
                            weight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _AboutIntroSection(),
                        const SizedBox(height: 24),
                        _AboutSection(
                          title: 'APLICATIVO',
                          children: const [
                            _AboutField(
                              label: 'Versão',
                              value: AppConstants.appVersion,
                            ),
                            _AboutField(
                              label: 'Build',
                              value: AppConstants.buildLabel,
                            ),
                            _AboutField(
                              label: 'Compatibilidade de Firmware',
                              value: AppConstants.firmwareCompat,
                            ),
                            _AboutField(
                              label: 'Última atualização',
                              value: AppConstants.lastUpdateLabel,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _AboutSection(
                          title: 'PROJETO',
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Instituições Associadas',
                                  style: AppTextStyles.mono(
                                    size: 12,
                                    color: const Color(0xFFAAAAAA),
                                    letterSpacing: 0,
                                  ),
                                ),
                                Text(
                                  'SESI',
                                  style: AppTextStyles.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                                Text(
                                  'Faculdade Israelita de Ciências da Saúde Albert Einstein',
                                  style: AppTextStyles.mono(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                            const _AboutField(
                              label: 'Curso',
                              value: 'Engenharia Biomédica',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _AboutSection(
                          title: 'HARDWARE',
                          children: const [
                            _AboutField(
                              label: 'Microcontrolador',
                              value: 'ESP32-C3 Super Mini',
                            ),
                            _AboutField(
                              label: 'Sensor Inercial',
                              value: 'MPU6050',
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _AboutSection(
                          title: 'CRÉDITOS',
                          children: [
                            Text(
                              'Grupo 7 - 2026-1',
                              style: AppTextStyles.mono(
                                size: 12,
                                color: const Color(0xFFAAAAAA),
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.aboutSubsection),
                            for (final name in _credits)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  name,
                                  style: AppTextStyles.mono(
                                    size: 12,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutHeader extends StatelessWidget {
  const _AboutHeader({
    required this.isOnline,
    required this.onBack,
  });

  final bool isOnline;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.baseBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: 16,
        ),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(
                Symbols.arrow_back_ios_new,
                size: 18,
                color: Colors.white,
              ),
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const KinexaLogo(
                    size: 36,
                    variant: KinexaLogoVariant.darkInv,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? AppColors.success : AppColors.textMuted,
                        shape: BoxShape.circle,
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutIntroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KINEXA',
          style: AppTextStyles.mono(
            size: 15,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: AppSpacing.aboutSubsection),
        Text(
          'MOVIMENTO. DADOS. DESEMPENHO.',
          style: AppTextStyles.mono(
            size: 12,
            color: const Color(0xFFAAAAAA),
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: AppSpacing.aboutSubsection),
        Text(
          'Sistema de aquisição e análise de dados biomecânicos '
          'desenvolvido para pesquisas e avaliações esportivas '
          'utilizando sensores inerciais.',
          textAlign: TextAlign.justify,
          style: AppTextStyles.mono(
            size: 10,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.mono(
            size: 15,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: AppSpacing.aboutSubsection),
        ..._spaced(children),
      ],
    );
  }

  List<Widget> _spaced(List<Widget> items) {
    if (items.isEmpty) return items;
    final result = <Widget>[items.first];
    for (var i = 1; i < items.length; i++) {
      result
        ..add(const SizedBox(height: AppSpacing.aboutSubsection))
        ..add(items[i]);
    }
    return result;
  }
}

class _AboutField extends StatelessWidget {
  const _AboutField({
    this.label,
    required this.value,
  });

  final String? label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTextStyles.mono(
              size: 12,
              color: const Color(0xFFAAAAAA),
              letterSpacing: 0,
            ),
          ),
        ],
        Text(
          value,
          style: AppTextStyles.mono(
            size: label == null ? 11 : 12,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}
