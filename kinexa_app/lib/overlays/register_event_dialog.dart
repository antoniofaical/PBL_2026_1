import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/digital_display.dart';
import '../core/widgets/kinexa_overlay_shell.dart';
import '../data/models/event_model.dart';

Future<EventModel?> showRegisterEventDialog(BuildContext context, int timestampMs) {
  return showKinexaOverlay<EventModel>(
    context,
    _RegisterEventOverlay(timestampMs: timestampMs),
  );
}

class _RegisterEventOverlay extends StatefulWidget {
  const _RegisterEventOverlay({required this.timestampMs});

  final int timestampMs;

  @override
  State<_RegisterEventOverlay> createState() => _RegisterEventOverlayState();
}

class _RegisterEventOverlayState extends State<_RegisterEventOverlay> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      EventModel(
        timestampMs: widget.timestampMs,
        description: _controller.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'REGISTRAR EVENTO',
          style: AppTextStyles.title.copyWith(letterSpacing: 0),
        ),
        const SizedBox(height: 30),
        _OverlayReadOnlyField(
          label: 'Tempo',
          value: formatDurationMs(widget.timestampMs),
          trailing: const Icon(
            Symbols.lock,
            size: 16,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 30),
        _OverlayDescriptionField(controller: _controller),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: _OverlaySecondaryButton(
                label: 'Cancelar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OverlayPrimaryButton(
                label: 'Salvar',
                onPressed: _save,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverlayReadOnlyField extends StatelessWidget {
  const _OverlayReadOnlyField({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _OverlayFieldShell(
      label: label,
      borderColor: AppColors.cardBackground,
      height: 41,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: AppTextStyles.mono(
                  size: 15,
                  color: const Color(0xFFAAAAAA),
                  letterSpacing: 0,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _OverlayDescriptionField extends StatelessWidget {
  const _OverlayDescriptionField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _OverlayFieldShell(
      label: 'Descrição',
      borderColor: AppColors.redPrimary,
      height: 105,
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLines: null,
        expands: true,
        style: AppTextStyles.mono(
          size: 15,
          letterSpacing: 0,
        ),
        cursorColor: AppColors.redDark,
        cursorWidth: 2,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(18, 10, 18, 10),
          isCollapsed: true,
        ),
      ),
    );
  }
}

class _OverlayFieldShell extends StatelessWidget {
  const _OverlayFieldShell({
    required this.label,
    required this.borderColor,
    required this.height,
    required this.child,
  });

  final String label;
  final Color borderColor;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: child,
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: -12,
            child: ColoredBox(
              color: AppColors.popupBackground,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  style: AppTextStyles.mono(
                    size: 11,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverlaySecondaryButton extends StatelessWidget {
  const _OverlaySecondaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(97),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(97),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.mono(
                size: 14,
                weight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayPrimaryButton extends StatelessWidget {
  const _OverlayPrimaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.redPrimary,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: AppTextStyles.mono(
                size: 14,
                weight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showFinishCollectionDialog(
  BuildContext context, {
  required int durationMs,
  required int eventCount,
  Future<void> Function()? onConfirm,
}) {
  return showKinexaOverlay<bool>(
    context,
    _FinishCollectionOverlay(
      durationMs: durationMs,
      eventCount: eventCount,
      onConfirm: onConfirm,
    ),
  ).then((value) => value ?? false);
}

class _FinishCollectionOverlay extends StatefulWidget {
  const _FinishCollectionOverlay({
    required this.durationMs,
    required this.eventCount,
    this.onConfirm,
  });

  final int durationMs;
  final int eventCount;
  final Future<void> Function()? onConfirm;

  @override
  State<_FinishCollectionOverlay> createState() =>
      _FinishCollectionOverlayState();
}

class _FinishCollectionOverlayState extends State<_FinishCollectionOverlay> {
  bool _closing = false;

  Future<void> _confirm() async {
    setState(() => _closing = true);
    await widget.onConfirm?.call();
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ENCERRAR COLETA',
          textAlign: TextAlign.center,
          style: AppTextStyles.title.copyWith(letterSpacing: 0),
        ),
        const SizedBox(height: 30),
        _OverlayReadOnlyField(
          label: 'Duração',
          value: formatDurationMs(widget.durationMs),
        ),
        const SizedBox(height: 30),
        _OverlayReadOnlyField(
          label: 'Eventos Registrados',
          value: '${widget.eventCount}',
        ),
        const SizedBox(height: 30),
        if (_closing)
          Material(
            color: AppColors.redDark.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(97),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  'ENCERRANDO COLETA...',
                  style: AppTextStyles.mono(
                    size: 14,
                    weight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OverlaySecondaryButton(
                label: 'Cancelar',
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(height: 10),
              Material(
                color: AppColors.redPrimary,
                borderRadius: BorderRadius.circular(97),
                child: InkWell(
                  onTap: _confirm,
                  borderRadius: BorderRadius.circular(97),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Text(
                        'ENCERRAR',
                        style: AppTextStyles.mono(
                          size: 14,
                          weight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
