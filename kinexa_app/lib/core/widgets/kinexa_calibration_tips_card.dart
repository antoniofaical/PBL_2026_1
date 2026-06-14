import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/asset_paths.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_text_styles.dart';

class KinexaCalibrationTipsCard extends StatelessWidget {
  const KinexaCalibrationTipsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            AssetPaths.icons.phone,
            height: 92,
            width: 57,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Posicione o dispositivo corretamente',
                  style: AppTextStyles.mono(
                    size: 15,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 20),
                _tipRow(
                  icon: Symbols.accessibility_new,
                  text:
                      'Garanta que o atleta esteja na\nposição anatômica de referência',
                ),
                const SizedBox(height: 20),
                _tipRow(
                  icon: Symbols.pause_circle,
                  text:
                      'Mantenha o dispositivo na\nposição de repouso',
                ),
                const SizedBox(height: 20),
                _tipRow(
                  icon: Symbols.vibration,
                  text: 'Evite vibrações e movimentos',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppColors.redPrimary),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.mono(
                size: 8,
                color: const Color(0xFFAAAAAA),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KinexaCalibrationImportantNote extends StatelessWidget {
  const KinexaCalibrationImportantNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Symbols.error,
            size: 20,
            color: AppColors.redPrimary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'IMPORTANTE',
                  style: AppTextStyles.mono(
                    size: 15,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Durante a calibração, não mova o atleta\n'
                  'nem o dispositivo. Aguarde até o fim do processo.',
                  style: AppTextStyles.mono(
                    size: 9,
                    color: const Color(0xFFAAAAAA),
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KinexaCalibrationRecalibrateNote extends StatelessWidget {
  const KinexaCalibrationRecalibrateNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Symbols.verified_user,
            size: 20,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Você poderá recalibrar quando necessário\n'
              'nas configurações do aplicativo.',
              style: AppTextStyles.mono(
                size: 9,
                color: const Color(0xFFAAAAAA),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30.9,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x33191919),
                  borderRadius: BorderRadius.circular(AppRadii.card - 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 40,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
