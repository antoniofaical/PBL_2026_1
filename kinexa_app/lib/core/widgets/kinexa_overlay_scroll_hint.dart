import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_text_styles.dart';
import 'kinexa_scroll_reveal.dart';

class KinexaOverlayScrollArea extends StatefulWidget {
  const KinexaOverlayScrollArea({
    super.key,
    required this.child,
    required this.fadeColor,
  });

  final Widget child;
  final Color fadeColor;

  @override
  State<KinexaOverlayScrollArea> createState() =>
      _KinexaOverlayScrollAreaState();
}

class _KinexaOverlayScrollAreaState extends State<KinexaOverlayScrollArea>
    with SingleTickerProviderStateMixin, KinexaScrollRevealBehavior {
  final _controller = ScrollController();

  @override
  ScrollController get scrollRevealController => _controller;
  late final AnimationController _bounce;
  late final Animation<double> _bounceOffset;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _bounceOffset = Tween<double>(begin: 0, end: 5).animate(
      CurvedAnimation(parent: _bounce, curve: Curves.easeInOut),
    );
    _controller.addListener(_onScroll);
    initScrollReveal();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHint());
  }

  @override
  void didUpdateWidget(covariant KinexaOverlayScrollArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHint());
  }

  @override
  void dispose() {
    disposeScrollReveal();
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    _bounce.dispose();
    super.dispose();
  }

  void _onScroll() => _updateHint();

  void _updateHint() {
    if (!_controller.hasClients) return;
    final canScroll = _controller.position.maxScrollExtent > 8;
    final atBottom =
        _controller.position.pixels >= _controller.position.maxScrollExtent - 8;
    final show = canScroll && !atBottom;
    if (show != _showHint) {
      setState(() => _showHint = show);
      if (show) {
        if (!_bounce.isAnimating) _bounce.repeat(reverse: true);
      } else {
        _bounce.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          controller: _controller,
          child: widget.child,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showHint ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: SizedBox(
                height: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.fadeColor.withValues(alpha: 0),
                        widget.fadeColor.withValues(alpha: 0.82),
                        widget.fadeColor,
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AnimatedBuilder(
                        animation: _bounceOffset,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(0, _bounceOffset.value),
                          child: child,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Symbols.keyboard_arrow_down,
                              size: 20,
                              color: Color(0xFFAAAAAA),
                            ),
                            Text(
                              'ROLE PARA VER MAIS',
                              style: AppTextStyles.mono(
                                size: 8,
                                color: const Color(0xFFAAAAAA),
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
