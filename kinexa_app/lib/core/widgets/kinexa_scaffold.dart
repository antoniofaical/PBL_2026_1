import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'kinexa_pattern_background.dart';

class KinexaScaffold extends StatelessWidget {
  const KinexaScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.showBack = false,
    this.floatingAction,
    this.padding,
    this.backgroundColor = AppColors.baseBackground,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final bool showBack;
  final Widget? floatingAction;
  final EdgeInsetsGeometry? padding;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: title != null
          ? AppBar(
              leading: showBack
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              title: Text(title!, style: AppTextStyles.title),
              actions: actions,
            )
          : null,
      floatingActionButton: floatingAction,
      body: KinexaPatternBackground(
        color: backgroundColor,
        child: SafeArea(
          child: padding != null ? Padding(padding: padding!, child: body) : body,
        ),
      ),
    );
  }
}
