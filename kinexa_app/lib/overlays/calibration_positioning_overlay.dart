import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/constants/asset_paths.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/kinexa_overlay_shell.dart';

Future<bool> showSensorPositioningOverlay(BuildContext context) async {
  final ok = await showKinexaOverlay<bool>(
    context,
    const _PositioningOverlayContent(),
    backgroundColor: const Color(0xFF161617),
    showScrollHint: true,
  );
  return ok ?? false;
}

class _PositioningOverlayContent extends StatefulWidget {
  const _PositioningOverlayContent();

  @override
  State<_PositioningOverlayContent> createState() =>
      _PositioningOverlayContentState();
}

class _PositioningOverlayContentState extends State<_PositioningOverlayContent> {
  bool _diagramsReady = false;

  @override
  void initState() {
    super.initState();
    _preloadDiagrams();
  }

  Future<void> _preloadDiagrams() async {
    try {
      final loader = SvgAssetLoader(AssetPaths.diagrams.deviceOrientation);
      final loader2 = SvgAssetLoader(AssetPaths.diagrams.footOrientation);
      await Future.wait([
        loader.loadBytes(null),
        loader2.loadBytes(null),
      ]);
    } catch (_) {
      // Still render — SvgPicture will retry individually.
    }
    if (mounted) setState(() => _diagramsReady = true);
  }

  @override
  Widget build(BuildContext context) {
    // Dialog inset (19*2) + shell padding (20*2).
    final diagramWidth = MediaQuery.sizeOf(context).width - 78;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'POSICIONAMENTO DO SENSOR',
          textAlign: TextAlign.center,
          style: AppTextStyles.title.copyWith(letterSpacing: 0),
        ),
        const SizedBox(height: AppSpacing.calibrationPopupSection),
        if (!_diagramsReady)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else ...[
          _DiagramImage(
            asset: AssetPaths.diagrams.deviceOrientation,
            width: diagramWidth,
            aspectRatio: 1062 / 810,
          ),
          const SizedBox(height: AppSpacing.calibrationPopupSection),
          Center(
            child: _DiagramImage(
              asset: AssetPaths.diagrams.footOrientation,
              width: diagramWidth * 0.55,
              aspectRatio: 447 / 1129,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.calibrationPopupSection),
        Text(
          'Confirme a orientação antes de calibrar',
          textAlign: TextAlign.center,
          style: AppTextStyles.mono(
            size: 12,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: AppSpacing.calibrationPopupSection),
        Material(
          color: const Color(0xB3AAAAAA),
          borderRadius: BorderRadius.circular(97),
          child: InkWell(
            onTap: () => Navigator.of(context).pop(true),
            borderRadius: BorderRadius.circular(97),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Center(
                child: Text(
                  'OK, PRONTO',
                  style: AppTextStyles.mono(
                    size: 16,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiagramImage extends StatelessWidget {
  const _DiagramImage({
    required this.asset,
    required this.width,
    required this.aspectRatio,
  });

  final String asset;
  final double width;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final height = width / aspectRatio;

    return ClipRect(
      child: SizedBox(
        width: width,
        height: height,
        child: SvgPicture.asset(
          asset,
          width: width,
          height: height,
          fit: BoxFit.contain,
          clipBehavior: Clip.hardEdge,
        ),
      ),
    );
  }
}
