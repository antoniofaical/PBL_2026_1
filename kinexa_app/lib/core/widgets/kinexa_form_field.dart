import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

const _fieldRadius = 6.0;
const _borderWidth = 2.0;

class KinexaLabeledFieldShell extends StatelessWidget {
  const KinexaLabeledFieldShell({
    super.key,
    required this.label,
    required this.child,
    this.height = 71,
    this.labelBackgroundColor = AppColors.popupBackground,
  });

  final String label;
  final Widget child;
  final double height;
  final Color labelBackgroundColor;

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
                border: Border.all(
                  color: AppColors.redPrimary,
                  width: _borderWidth,
                ),
                borderRadius: BorderRadius.circular(_fieldRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_fieldRadius - _borderWidth),
                child: child,
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: -12,
            child: ColoredBox(
              color: labelBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  style: AppTextStyles.mono(
                    size: 15,
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

class KinexaMetadataTextField extends StatelessWidget {
  const KinexaMetadataTextField({
    super.key,
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.height = 71,
    this.labelBackgroundColor = AppColors.popupBackground,
    this.obscureText = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final double height;
  final Color labelBackgroundColor;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  static const _noBorder = InputDecoration(
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    isCollapsed: true,
  );

  @override
  Widget build(BuildContext context) {
    final isSingleLine = maxLines == 1;

    return KinexaLabeledFieldShell(
      label: label,
      height: height,
      labelBackgroundColor: labelBackgroundColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          isSingleLine ? 0 : 10,
          18,
          isSingleLine ? 0 : 10,
        ),
        child: TextField(
          controller: controller,
          expands: true,
          maxLines: null,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: AppTextStyles.mono(size: 24, letterSpacing: 0),
          cursorColor: AppColors.redPrimary,
          cursorWidth: 2,
          textAlignVertical: isSingleLine
              ? TextAlignVertical.center
              : TextAlignVertical.top,
          decoration: _noBorder,
        ),
      ),
    );
  }
}

class KinexaMetadataSelectField<T> extends StatefulWidget {
  const KinexaMetadataSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.itemLabel,
    required this.onChanged,
    this.labelBackgroundColor = AppColors.popupBackground,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T item) itemLabel;
  final ValueChanged<T> onChanged;
  final Color labelBackgroundColor;

  @override
  State<KinexaMetadataSelectField<T>> createState() =>
      _KinexaMetadataSelectFieldState<T>();
}

class _KinexaMetadataSelectFieldState<T>
    extends State<KinexaMetadataSelectField<T>> {
  final _anchorKey = GlobalKey();

  Future<void> _openMenu() async {
    final overlay = Overlay.of(context);
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;

    final fieldOffset = box.localToGlobal(Offset.zero);
    final fieldSize = box.size;
    late OverlayEntry entry;

    void close() {
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: fieldOffset.dx,
            top: fieldOffset.dy + fieldSize.height,
            width: fieldSize.width,
            child: Material(
              color: Colors.transparent,
              child: _KinexaDropdownMenu<T>(
                value: widget.value,
                options: widget.options,
                itemLabel: widget.itemLabel,
                onSelected: (item) {
                  widget.onChanged(item);
                  close();
                },
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openMenu,
      child: Container(
        key: _anchorKey,
        child: KinexaLabeledFieldShell(
          label: widget.label,
          labelBackgroundColor: widget.labelBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.itemLabel(widget.value),
                    style: AppTextStyles.mono(size: 24, letterSpacing: 0),
                  ),
                ),
                const Icon(
                  Symbols.arrow_drop_down,
                  color: AppColors.redPrimary,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KinexaDropdownMenu<T> extends StatelessWidget {
  const _KinexaDropdownMenu({
    required this.value,
    required this.options,
    required this.itemLabel,
    required this.onSelected,
  });

  final T value;
  final List<T> options;
  final String Function(T item) itemLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(_fieldRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _DropdownMenuItem(
                label: itemLabel(options[i]),
                selected: options[i] == value,
                onTap: () => onSelected(options[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DropdownMenuItem extends StatelessWidget {
  const _DropdownMenuItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_fieldRadius),
          child: Ink(
            decoration: BoxDecoration(
              border: selected
                  ? Border.all(color: AppColors.redDark)
                  : null,
              borderRadius: BorderRadius.circular(_fieldRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.mono(
                        size: 15,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (selected)
                    Text(
                      '✓',
                      style: AppTextStyles.mono(
                        size: 15,
                        letterSpacing: 0,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
