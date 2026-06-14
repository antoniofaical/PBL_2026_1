import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/asset_paths.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_text_styles.dart';
import '../../data/models/device_model.dart';

class KinexaDeviceCard extends StatelessWidget {
  const KinexaDeviceCard({
    super.key,
    required this.device,
    this.selected = false,
    this.error = false,
    this.success = false,
    this.onTap,
    this.detailed = false,
  });

  final DeviceModel device;
  final bool selected;
  final bool error;
  final bool success;
  final VoidCallback? onTap;
  final bool detailed;

  static const _radius = AppRadii.card;

  @override
  Widget build(BuildContext context) {
    final style = _resolveStyle();

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: detailed ? _buildDetailedContent() : _buildCompactContent(),
    );

    final body = Material(
      color: Colors.transparent,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(_radius - 1),
              splashColor: Colors.white.withValues(alpha: 0.06),
              highlightColor: Colors.white.withValues(alpha: 0.04),
              child: content,
            ),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: style.glow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: style.rim,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius - 1),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: style.fill,
                      borderRadius: BorderRadius.circular(_radius - 1),
                    ),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _GlassStyle _resolveStyle() {
    if (error) {
      return _GlassStyle(
        fill: AppColors.redPrimary.withValues(alpha: 0.46),
        rim: [
          AppColors.redLight.withValues(alpha: 0.55),
          AppColors.redPrimary.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.04),
        ],
        glow: [
          BoxShadow(
            color: AppColors.redPrimary.withValues(alpha: 0.85),
            blurRadius: 30.9,
          ),
        ],
      );
    }

    if (selected) {
      return _GlassStyle(
        fill: Color.alphaBlend(
          AppColors.redPrimary.withValues(alpha: 0.29),
          const Color(0x33191919),
        ),
        rim: [
          AppColors.redLight.withValues(alpha: 0.5),
          AppColors.redPrimary.withValues(alpha: 0.2),
          Colors.white.withValues(alpha: 0.03),
        ],
        glow: [
          BoxShadow(
            color: AppColors.redPrimary.withValues(alpha: 0.9),
            blurRadius: 30.9,
          ),
        ],
      );
    }

    if (success) {
      return _GlassStyle(
        fill: const Color(0x3327C840),
        rim: [
          const Color(0xFF27C840).withValues(alpha: 0.45),
          const Color(0xFF27C840).withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.04),
        ],
        glow: const [
          BoxShadow(
            color: Color(0xFF27C840),
            blurRadius: 17,
          ),
        ],
      );
    }

    return _GlassStyle(
      fill: const Color(0x33191919),
      rim: [
        Colors.white.withValues(alpha: 0.16),
        Colors.white.withValues(alpha: 0.06),
        Colors.white.withValues(alpha: 0.02),
      ],
      glow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 30.9,
        ),
      ],
    );
  }

  Widget _buildCompactContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.deviceId,
          style: AppTextStyles.mono(
            size: 15,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 20),
        _infoRow(
          icon: const Icon(Symbols.bluetooth, size: 18, color: AppColors.text),
          label: 'RSSI: ${device.rssi ?? '—'} dBm',
        ),
      ],
    );
  }

  Widget _buildDetailedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          device.deviceId,
          style: AppTextStyles.mono(
            size: 15,
            weight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 20),
        _infoRow(
          icon: SvgPicture.asset(
            AssetPaths.icons.device,
            height: 20,
            width: 13,
          ),
          label: 'MAC: ${device.mac ?? '—'}',
        ),
        const SizedBox(height: 20),
        _infoRow(
          icon: const Icon(Symbols.bluetooth, size: 18, color: AppColors.text),
          label: 'RSSI: ${device.rssi ?? '—'} dBm',
        ),
        const SizedBox(height: 20),
        _infoRow(
          icon: const Icon(
            Symbols.settings_ethernet,
            size: 16,
            color: AppColors.text,
          ),
          label: 'MTU: ${device.mtu ?? '—'}',
        ),
        const SizedBox(height: 20),
        _infoRow(
          icon: const Icon(Symbols.memory, size: 16, color: AppColors.text),
          label: 'Firmware: v${device.firmwareVersion}',
        ),
      ],
    );
  }

  Widget _infoRow({required Widget icon, required String label}) {
    return Row(
      children: [
        SizedBox(width: 20, height: 20, child: Center(child: icon)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
          ),
        ),
      ],
    );
  }
}

class _GlassStyle {
  const _GlassStyle({
    required this.fill,
    required this.rim,
    required this.glow,
  });

  final Color fill;
  final List<Color> rim;
  final List<BoxShadow> glow;
}
