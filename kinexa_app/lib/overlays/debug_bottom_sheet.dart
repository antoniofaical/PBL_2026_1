import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/kinexa_device_card.dart';
import '../providers.dart';

void showDebugBottomSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final logService = ref.watch(debugLogProvider);
        final logs = logService.logs;
        final device = ref.read(bleServiceProvider).connectedDevice;

        Future<void> copyLogs() async {
          if (logs.isEmpty) return;
          await Clipboard.setData(ClipboardData(text: logService.exportText()));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Log copiado (${logs.length} linhas)',
                style: AppTextStyles.mono(size: 12),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.fromLTRB(10, 20, 10, 20),
            decoration: BoxDecoration(
              color: AppColors.popupBackground,
              borderRadius: BorderRadius.circular(AppRadii.overlayPopup),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2EFFFFFF),
                  blurRadius: 10.4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Symbols.terminal,
                      size: 16,
                      color: AppColors.redPrimary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'DETALHES TÉCNICOS',
                      style: AppTextStyles.mono(
                        size: 12,
                        weight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: logs.isEmpty ? null : copyLogs,
                      child: Text(
                        'COPIAR',
                        style: AppTextStyles.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: logs.isEmpty
                              ? AppColors.textMuted
                              : AppColors.redPrimary,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(
                        'FECHAR',
                        style: AppTextStyles.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: AppColors.redDark,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                if (device != null)
                  KinexaDeviceCard(device: device, detailed: true)
                else
                  Text(
                    'Nenhum dispositivo conectado',
                    style: AppTextStyles.mono(size: 12, letterSpacing: 0),
                  ),
                const SizedBox(height: 30),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.baseBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: logs.isEmpty
                      ? Text(
                          'Sem logs',
                          style: AppTextStyles.mono(
                            size: 12,
                            color: AppColors.textMuted,
                            letterSpacing: 0,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: logs.length,
                          itemBuilder: (_, i) {
                            final line = logs[logs.length - 1 - i];
                            return _LogLine(text: line);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(text);
    final time = match?.group(1) ?? '--:--:--';
    final message = match?.group(2) ?? text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: AppTextStyles.mono(
              size: 12,
              color: const Color(0xFFAAAAAA),
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 10),
          const Text('•', style: TextStyle(color: AppColors.text)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.mono(size: 12, letterSpacing: 0),
            ),
          ),
        ],
      ),
    );
  }
}
