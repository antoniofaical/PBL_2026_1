import 'package:flutter/material.dart';

import '../constants/asset_paths.dart';
import '../theme/app_text_styles.dart';
import 'kinexa_logo.dart';

/// Cabeçalho compartilhado das telas de sincronização (Figma Tela 1).
class SyncBrandHeader extends StatelessWidget {
  const SyncBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: 0.6,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          Text(
            'Powered by:',
            style: AppTextStyles.mono(
              size: 10,
              weight: FontWeight.w700,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                AssetPaths.logos.sesiPng,
                height: 15,
                width: 46,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 30),
              Image.asset(
                AssetPaths.logos.einsteinPng,
                height: 40,
                width: 50,
                fit: BoxFit.contain,
              ),
            ],
          ),
          const SizedBox(height: 40),
          const KinexaLogo(height: 73, variant: KinexaLogoVariant.darkInv),
        ],
      ),
    ),
    );
  }
}
