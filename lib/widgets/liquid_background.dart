import 'package:flutter/material.dart';

class LiquidBackground extends StatefulWidget {
  final Widget child;

  const LiquidBackground({required this.child, super.key});

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with TickerProviderStateMixin {
  late final AnimationController _c1, _c2, _c3, _c4;
  late final Animation<double> _a1, _a2, _a3, _a4;

  @override
  void initState() {
    super.initState();
    _c1 = AnimationController(vsync: this, duration: const Duration(seconds: 14))
      ..repeat(reverse: true);
    _c2 = AnimationController(vsync: this, duration: const Duration(seconds: 18))
      ..forward(from: 0.4)
      ..repeat(reverse: true);
    _c3 = AnimationController(vsync: this, duration: const Duration(seconds: 11))
      ..forward(from: 0.7)
      ..repeat(reverse: true);
    _c4 = AnimationController(vsync: this, duration: const Duration(seconds: 16))
      ..forward(from: 0.2)
      ..repeat(reverse: true);

    _a1 = CurvedAnimation(parent: _c1, curve: Curves.easeInOut);
    _a2 = CurvedAnimation(parent: _c2, curve: Curves.easeInOut);
    _a3 = CurvedAnimation(parent: _c3, curve: Curves.easeInOut);
    _a4 = CurvedAnimation(parent: _c4, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _c3.dispose();
    _c4.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_c1, _c2, _c3, _c4]),
      builder: (context, child) => CustomPaint(
        painter: _LiquidPainter(
          t1: _a1.value,
          t2: _a2.value,
          t3: _a3.value,
          t4: _a4.value,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final double t1, t2, t3, t4;

  // Accent green — vary opacity across blobs for depth
  static const _blobs = [
    Color(0x5586EFAC), // 33% — brightest, largest
    Color(0x4086EFAC), // 25%
    Color(0x3086EFAC), // 19%
    Color(0x2586EFAC), // 15% — subtlest
  ];

  const _LiquidPainter({
    required this.t1,
    required this.t2,
    required this.t3,
    required this.t4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1C1C1E),
    );

    _blob(canvas, size,
        center: Offset.lerp(
          Offset(size.width * 0.05, size.height * 0.08),
          Offset(size.width * 0.42, size.height * 0.32),
          t1,
        )!,
        radius: size.width * 0.72,
        color: _blobs[0]);

    _blob(canvas, size,
        center: Offset.lerp(
          Offset(size.width * 0.9, size.height * 0.08),
          Offset(size.width * 0.52, size.height * 0.48),
          t2,
        )!,
        radius: size.width * 0.68,
        color: _blobs[1]);

    _blob(canvas, size,
        center: Offset.lerp(
          Offset(size.width * 0.08, size.height * 0.88),
          Offset(size.width * 0.5, size.height * 0.62),
          t3,
        )!,
        radius: size.width * 0.62,
        color: _blobs[2]);

    _blob(canvas, size,
        center: Offset.lerp(
          Offset(size.width * 0.92, size.height * 0.9),
          Offset(size.width * 0.3, size.height * 0.68),
          t4,
        )!,
        radius: size.width * 0.58,
        color: _blobs[3]);
  }

  void _blob(Canvas canvas, Size size,
      {required Offset center, required double radius, required Color color}) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withAlpha(0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_LiquidPainter old) =>
      old.t1 != t1 || old.t2 != t2 || old.t3 != t3 || old.t4 != t4;
}
