import 'package:flutter/material.dart';

/// Wraps any widget with iOS-style press feedback — fades to [opacity] on
/// tap-down and snaps back on release. Pass [scaleOnPress] to also shrink
/// to 0.95 (useful for card-like elements).
class Tappable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double opacity;
  final bool scaleOnPress;

  const Tappable({
    required this.child,
    this.onTap,
    this.opacity = 0.4,
    this.scaleOnPress = false,
    super.key,
  });

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _pressed = false;

  void _down(_) => setState(() => _pressed = true);
  void _up(_)   => setState(() => _pressed = false);
  void _cancel() => setState(() => _pressed = false);

  @override
  Widget build(BuildContext context) {
    Widget inner = AnimatedOpacity(
      opacity: _pressed ? widget.opacity : 1.0,
      duration: const Duration(milliseconds: 80),
      child: widget.child,
    );

    if (widget.scaleOnPress) {
      inner = AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: inner,
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      behavior: HitTestBehavior.opaque,
      child: inner,
    );
  }
}
