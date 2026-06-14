import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/asset_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../transfer_models.dart';

class TransferScreenTitle extends StatelessWidget {
  const TransferScreenTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.mono(
        size: 20,
        weight: FontWeight.w700,
        letterSpacing: 0,
      ),
      textAlign: TextAlign.center,
    );
  }
}

class TransferFlowDiagram extends StatelessWidget {
  const TransferFlowDiagram({
    super.key,
    required this.layout,
    required this.leftLabel,
    this.rightLabel = 'CELULAR',
    this.midIcon = TransferFlowMidIcon.bluetooth,
    this.tone = TransferProgressTone.active,
  });

  final TransferFlowLayout layout;
  final String leftLabel;
  final String rightLabel;
  final TransferFlowMidIcon midIcon;
  final TransferProgressTone tone;

  Color get _accent => switch (tone) {
        TransferProgressTone.success => const Color(0xFF27C840),
        TransferProgressTone.warning => const Color(0xFFFEBC2F),
        TransferProgressTone.error => AppColors.redPrimary,
        TransferProgressTone.active => AppColors.redPrimary,
      };

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      TransferFlowLayout.deviceToPhone => _row(
          left: _node(AssetPaths.icons.device, leftLabel, 27, 44),
          right: _node(AssetPaths.icons.phone, rightLabel, 24, 45),
        ),
      TransferFlowLayout.phoneToServer => _row(
          left: _node(AssetPaths.icons.phone, 'CELULAR', 24, 45),
          right: _serverNode(),
        ),
      TransferFlowLayout.deviceToPhoneComplete => _row(
          left: _node(AssetPaths.icons.device, leftLabel, 27, 44),
          right: _node(AssetPaths.icons.phone, 'CELULAR', 24, 45),
        ),
      TransferFlowLayout.deviceToServerComplete => _row(
          left: _node(AssetPaths.icons.device, leftLabel, 27, 44),
          right: _serverNode(),
        ),
    };
  }

  Widget _row({required Widget left, required Widget right}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          left,
          const SizedBox(width: 8),
          _dottedLine(48),
          const SizedBox(width: 8),
          _midIconWidget(),
          const SizedBox(width: 8),
          _dottedLine(48),
          const SizedBox(width: 8),
          right,
        ],
      ),
    );
  }

  Widget _midIconWidget() {
    return switch (midIcon) {
      TransferFlowMidIcon.bluetooth => Icon(
          Symbols.bluetooth,
          size: 20,
          color: _accent,
        ),
      TransferFlowMidIcon.check => Icon(
          Symbols.check,
          size: 20,
          color: _accent,
        ),
      TransferFlowMidIcon.error => Icon(
          Symbols.close,
          size: 20,
          color: _accent,
        ),
    };
  }

  Widget _node(String asset, String label, double width, double height) {
    return SizedBox(
      width: 65,
      child: Column(
        children: [
          SizedBox(
            width: width,
            height: height,
            child: SvgPicture.asset(
              asset,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _serverNode() {
    return SizedBox(
      width: 65,
      child: Column(
        children: [
          Icon(Symbols.dns, size: 30, color: _accent),
          const SizedBox(height: 5),
          Text(
            'SERVIDOR',
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _dottedLine(double width) {
    return SizedBox(
      width: width,
      height: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          7,
          (_) => Container(
            width: 4,
            height: 6,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

enum TransferFlowMidIcon { bluetooth, check, error }

class TransferProgressPanel extends StatelessWidget {
  const TransferProgressPanel({
    super.key,
    required this.percent,
    required this.samplesDone,
    required this.samplesTotal,
    required this.packetsDone,
    required this.packetsTotal,
    required this.tone,
  });

  final int percent;
  final int samplesDone;
  final int samplesTotal;
  final int packetsDone;
  final int packetsTotal;
  final TransferProgressTone tone;

  Color get _accent => switch (tone) {
        TransferProgressTone.success => const Color(0xFF27C840),
        TransferProgressTone.warning => const Color(0xFFFEBC2F),
        TransferProgressTone.error => AppColors.redPrimary,
        TransferProgressTone.active => AppColors.redPrimary,
      };

  String _formatCount(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0, 100);
    final barFraction = clamped / 100;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.popupBackground.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 30.9,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '${clamped.toString().padLeft(2, '0')}%',
            style: AppTextStyles.digital(
              size: 48,
              color: _accent,
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: AppColors.cardBackground,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: barFraction == 0 ? 0.02 : barFraction,
                  child: SizedBox(
                    height: 18,
                    child: ColoredBox(color: _accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${_formatCount(samplesDone)} / ${_formatCount(samplesTotal)} amostras',
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
          ),
          const SizedBox(height: 10),
          Text(
            '$packetsDone / $packetsTotal pacotes BLE',
            style: AppTextStyles.mono(size: 12, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

class TransferChecklist extends StatelessWidget {
  const TransferChecklist({super.key, required this.items});

  final List<TransferChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _TransferChecklistRow(item: items[i]),
        ],
      ],
    );
  }
}

class _TransferChecklistRow extends StatelessWidget {
  const _TransferChecklistRow({required this.item});

  final TransferChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.state) {
      TransferChecklistState.failed => const Color(0xFFFEBC2F),
      _ => Colors.white,
    };

    final prefix = switch (item.state) {
      TransferChecklistState.done => '✓',
      TransferChecklistState.active => '⟳',
      TransferChecklistState.failed => '✗',
      TransferChecklistState.pending => '☐',
    };

    return SizedBox(
      width: double.infinity,
      child: Text(
        '$prefix ${item.label}',
        style: AppTextStyles.mono(
          size: 12,
          color: color,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class TransferWarningBanner extends StatelessWidget {
  const TransferWarningBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.error,
            color: AppColors.redPrimary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NÃO FECHE O APLICATIVO',
                  style: AppTextStyles.mono(
                    size: 15,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  'Mantenha o Bluetooth ligado e o app em primeiro plano',
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

class TransferErrorBanner extends StatelessWidget {
  const TransferErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.redDark.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.redPrimary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Symbols.error,
            color: AppColors.redPrimary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.mono(
                size: 12,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransferFinishPill extends StatelessWidget {
  const TransferFinishPill({super.key, required this.tone});

  final TransferProgressTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      TransferProgressTone.success =>
        const Color(0xFF27C840).withValues(alpha: 0.5),
      TransferProgressTone.warning => const Color(0xFFFEBC2F),
      _ => AppColors.cardBackground.withValues(alpha: 0.7),
    };

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(97),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            'CONCLUINDO...',
            style: AppTextStyles.mono(
              size: 14,
              weight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
