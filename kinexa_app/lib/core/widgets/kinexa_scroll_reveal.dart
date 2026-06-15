import 'dart:async';

import 'package:flutter/material.dart';

/// Wraps scrollable screen content and, after [delay], gently scrolls down
/// when there is hidden content below the fold. Users can scroll freely before
/// or after the hint animation.
class KinexaScrollReveal extends StatefulWidget {
  const KinexaScrollReveal({
    super.key,
    required this.child,
    this.padding,
    this.physics,
    this.delay = const Duration(seconds: 5),
  }) : children = null;

  const KinexaScrollReveal.list({
    super.key,
    required this.children,
    this.padding,
    this.physics,
    this.delay = const Duration(seconds: 5),
  }) : child = null;

  final Widget? child;
  final List<Widget>? children;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final Duration delay;

  @override
  State<KinexaScrollReveal> createState() => _KinexaScrollRevealState();
}

class _KinexaScrollRevealState extends State<KinexaScrollReveal> {
  static const _minScrollExtent = 48.0;
  static const _revealFraction = 0.35;
  static const _minRevealOffset = 80.0;

  final _controller = ScrollController();
  Timer? _timer;
  bool _hintPlayed = false;
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onUserScroll);
    _timer = Timer(widget.delay, _playReveal);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller
      ..removeListener(_onUserScroll)
      ..dispose();
    super.dispose();
  }

  void _onUserScroll() {
    if (_userScrolled || !_controller.hasClients) return;
    if (_controller.offset > 4) {
      _userScrolled = true;
      _timer?.cancel();
    }
  }

  Future<void> _playReveal() async {
    if (!mounted || _userScrolled || _hintPlayed) return;

    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted || _userScrolled) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (_controller.hasClients &&
          _controller.position.maxScrollExtent >= _minScrollExtent) {
        break;
      }
    }

    if (!mounted || _userScrolled || !_controller.hasClients) return;

    final maxExtent = _controller.position.maxScrollExtent;
    if (maxExtent < _minScrollExtent) return;

    _hintPlayed = true;
    final target = (maxExtent * _revealFraction).clamp(_minRevealOffset, maxExtent);

    if (_controller.offset >= target - 8) return;

    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    if (children != null) {
      return ListView(
        controller: _controller,
        padding: widget.padding,
        physics: widget.physics,
        children: children,
      );
    }

    return SingleChildScrollView(
      controller: _controller,
      padding: widget.padding,
      physics: widget.physics,
      child: widget.child,
    );
  }
}

/// Mixin for widgets that own their own [ScrollController] but still want the
/// delayed downward reveal (e.g. overlay scroll areas).
mixin KinexaScrollRevealBehavior<T extends StatefulWidget> on State<T> {
  static const _minScrollExtent = 48.0;
  static const _revealFraction = 0.35;
  static const _minRevealOffset = 80.0;

  ScrollController get scrollRevealController;
  Duration get scrollRevealDelay => const Duration(seconds: 5);

  Timer? _scrollRevealTimer;
  bool _scrollRevealPlayed = false;
  bool _scrollRevealUserScrolled = false;

  void initScrollReveal() {
    scrollRevealController.addListener(_onScrollRevealUserInput);
    _scrollRevealTimer = Timer(scrollRevealDelay, _playScrollReveal);
  }

  void disposeScrollReveal() {
    _scrollRevealTimer?.cancel();
    scrollRevealController.removeListener(_onScrollRevealUserInput);
  }

  void _onScrollRevealUserInput() {
    if (_scrollRevealUserScrolled || !scrollRevealController.hasClients) {
      return;
    }
    if (scrollRevealController.offset > 4) {
      _scrollRevealUserScrolled = true;
      _scrollRevealTimer?.cancel();
    }
  }

  Future<void> _playScrollReveal() async {
    if (!mounted || _scrollRevealUserScrolled || _scrollRevealPlayed) return;

    for (var attempt = 0; attempt < 12; attempt++) {
      if (!mounted || _scrollRevealUserScrolled) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (scrollRevealController.hasClients &&
          scrollRevealController.position.maxScrollExtent >= _minScrollExtent) {
        break;
      }
    }

    if (!mounted ||
        _scrollRevealUserScrolled ||
        !scrollRevealController.hasClients) {
      return;
    }

    final maxExtent = scrollRevealController.position.maxScrollExtent;
    if (maxExtent < _minScrollExtent) return;

    _scrollRevealPlayed = true;
    final target =
        (maxExtent * _revealFraction).clamp(_minRevealOffset, maxExtent);

    if (scrollRevealController.offset >= target - 8) return;

    await scrollRevealController.animateTo(
      target,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
    );
  }
}
