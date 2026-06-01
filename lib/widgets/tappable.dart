import 'package:flutter/material.dart';

/// Wraps any widget with iOS-style press opacity — fades to [opacity] on
/// tap-down and snaps back on release, exactly like CupertinoButton.
class Tappable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double opacity;

  const Tappable({
    required this.child,
    this.onTap,
    this.opacity = 0.4,
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
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _pressed ? widget.opacity : 1.0,
        duration: const Duration(milliseconds: 80),
        child: widget.child,
      ),
    );
  }
}
