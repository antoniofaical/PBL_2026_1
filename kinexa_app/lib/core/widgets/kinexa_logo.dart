import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/asset_paths.dart';

class KinexaLogo extends StatelessWidget {
  const KinexaLogo({
    super.key,
    double? size,
    double? height,
    this.variant = KinexaLogoVariant.dark,
  }) : height = height ?? size ?? 32;

  final double height;
  final KinexaLogoVariant variant;

  @override
  Widget build(BuildContext context) {
    final asset = switch (variant) {
      KinexaLogoVariant.dark => AssetPaths.logos.kinexaDark,
      KinexaLogoVariant.darkInv => AssetPaths.logos.kinexaDarkInv,
      KinexaLogoVariant.white => AssetPaths.logos.kinexaWhite,
    };

    return SvgPicture.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
    );
  }
}

enum KinexaLogoVariant { dark, darkInv, white }
