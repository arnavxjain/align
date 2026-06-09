import 'dart:math';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_typography.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

class UserCard extends StatefulWidget {
  final String firstName;
  final String memberSince; // e.g. "Jun 2026"
  final int analysisCount;
  final int streak;
  final bool isDark;

  const UserCard({
    super.key,
    required this.firstName,
    required this.memberSince,
    required this.analysisCount,
    required this.streak,
    required this.isDark,
  });

  @override
  State<UserCard> createState() => _UserCardState();
}

// ── Gradient palette ──────────────────────────────────────────────────────────

const kMilestoneGradients = <String, (Color, Color)>{
  'Newcomer':        (Color(0xFF3B82F6), Color(0xFF7C3AED)),
  'The Curious':     (Color(0xFF06B6D4), Color(0xFF3B82F6)),
  'Pattern Spotter': (Color(0xFF14B8A6), Color(0xFF059669)),
  'Signal Chaser':   (Color(0xFFF97316), Color(0xFFF59E0B)),
  'Noise Canceller': (Color(0xFFEF4444), Color(0xFFEC4899)),
  'The Aligned':     (Color(0xFF9333EA), Color(0xFF6366F1)),
  'Distortion Free': (Color(0xFFEAB308), Color(0xFFF97316)),
  'The Oracle':      (Color(0xFF7C3AED), Color(0xFFD946EF)),
};

// ── State ─────────────────────────────────────────────────────────────────────

class _UserCardState extends State<UserCard> with TickerProviderStateMixin {
  late final AnimationController _snapCtrl;
  late final AnimationController _hintCtrl;
  late Animation<Offset> _snapAnim;
  late Animation<double> _hintAnim;

  double _tiltX = 0; // degrees, X = forward/back tilt
  double _tiltY = 0; // degrees, Y = left/right tilt
  Offset _fingerNorm = const Offset(0.5, 0.5);
  bool _isDragging = false;

  static const _kMaxTilt = 15.0;
  static const _kMaxParallax = 8.0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _hintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _snapAnim = AlwaysStoppedAnimation<Offset>(Offset.zero);

    // Gentle rock: 0 → 7 → -5 → 0 degrees (Y axis)
    _hintAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 7.0),  weight: 1),
      TweenSequenceItem(tween: Tween(begin: 7.0, end: -5.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _hintCtrl, curve: Curves.easeInOut));

    _snapCtrl.addListener(() { if (mounted) setState(() {}); });
    _hintCtrl.addListener(() { if (mounted) setState(() {}); });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _hintCtrl.forward();
    });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    _hintCtrl.dispose();
    super.dispose();
  }

  Offset get _effectiveTilt {
    if (_isDragging) return Offset(_tiltX, _tiltY);
    if (_snapCtrl.isAnimating) return _snapAnim.value;
    if (_hintCtrl.isAnimating) {
      final v = _hintAnim.value;
      return Offset(v * 0.25, v); // slight X tilt alongside Y rock
    }
    return Offset.zero;
  }

  void _onPanStart(DragStartDetails d) {
    _snapCtrl.stop();
    _hintCtrl.stop();
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails d, Size cardSize) {
    final nx = (d.localPosition.dx / cardSize.width).clamp(0.0, 1.0);
    final ny = (d.localPosition.dy / cardSize.height).clamp(0.0, 1.0);
    setState(() {
      _fingerNorm = Offset(nx, ny);
      // Finger above centre → card tips forward (negative X rotation)
      _tiltX = ((ny - 0.5) * 2 * _kMaxTilt).clamp(-_kMaxTilt, _kMaxTilt);
      // Finger right of centre → card tips right (positive Y rotation)
      _tiltY = ((nx - 0.5) * 2 * _kMaxTilt).clamp(-_kMaxTilt, _kMaxTilt);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    _isDragging = false;
    _snapAnim = Tween<Offset>(
      begin: Offset(_tiltX, _tiltY),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut));
    _snapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final tilt = _effectiveTilt;
    const colors = (Color(0xFF3B82F6), Color(0xFF7C3AED));

    // Parallax: blob shifts opposite to the tilt direction
    final parallax = Offset(
      -tilt.dy * (_kMaxParallax / _kMaxTilt),
       tilt.dx * (_kMaxParallax / _kMaxTilt),
    );

    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = w * 4 / 3;

      return GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: (d) => _onPanUpdate(d, Size(w, h)),
        onPanEnd: _onPanEnd,
        child: SizedBox(
          width: w, height: h,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateX(tilt.dx * pi / 180)
              ..rotateY(tilt.dy * pi / 180),
            child: Container(
              decoration: ShapeDecoration(
                color: widget.isDark
                    ? const Color(0xFF0D0D0F)
                    : const Color(0xFFF7F3EE),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 24,
                    cornerSmoothing: 0.6,
                  ),
                  side: BorderSide(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.11)
                        : Colors.black.withAlpha(12),
                    width: 0.7,
                  ),
                ),
                shadows: [
                  BoxShadow(
                    color: Colors.black.withAlpha(widget.isDark ? 130 : 65),
                    blurRadius: 40,
                    spreadRadius: 0,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipSmoothRect(
                radius: SmoothBorderRadius(cornerRadius: 24, cornerSmoothing: 0.6),
                child: Stack(
                  children: [
                    // ── Gradient circle with glow ──────────────────────────
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CirclePainter(
                          color1: colors.$1,
                          color2: colors.$2,
                          parallax: parallax,
                          isDark: widget.isDark,
                        ),
                      ),
                    ),

                    // ── Specular sheen ─────────────────────────────────────
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SpecularPainter(
                          position: _fingerNorm,
                          visible: _isDragging || _snapCtrl.isAnimating,
                        ),
                      ),
                    ),

                    // ── Bottom info section ────────────────────────────────
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: _CardContent(
                        firstName: widget.firstName,
                        analysisCount: widget.analysisCount,
                        streak: widget.streak,
                        memberSince: widget.memberSince,
                        isDark: widget.isDark,
                        accent: colors.$1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ── Circle painter ────────────────────────────────────────────────────────────

class _CirclePainter extends CustomPainter {
  final Color color1;
  final Color color2;
  final Offset parallax;
  final bool isDark;

  const _CirclePainter({
    required this.color1,
    required this.color2,
    required this.parallax,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;

    // Circle lives above the card — only its glow bleeds in from the top
    final radius = w * 0.60;
    final center = Offset(
      w * 0.5 + parallax.dx,
      -radius * 0.75 + parallax.dy,
    );

    // 1 — Outermost ambient bloom
    canvas.drawCircle(
      center,
      radius * 2.5,
      Paint()
        ..color = color1.withAlpha(isDark ? 50 : 32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 62),
    );

    // 2 — Mid glow volume
    canvas.drawCircle(
      center,
      radius * 1.7,
      Paint()
        ..color = color2.withAlpha(isDark ? 95 : 65)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38),
    );

    // 3 — Tight halo ring just outside the (hidden) circle edge
    canvas.drawCircle(
      center,
      radius * 1.15,
      Paint()
        ..color = color1.withAlpha(isDark ? 110 : 80)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // 4 — Inner rim
    canvas.drawCircle(
      center,
      radius * 1.05,
      Paint()
        ..color = color2.withAlpha(isDark ? 85 : 60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  @override
  bool shouldRepaint(_CirclePainter old) =>
      old.color1 != color1 ||
      old.color2 != color2 ||
      old.parallax != parallax;
}

// ── Specular sheen painter ────────────────────────────────────────────────────

class _SpecularPainter extends CustomPainter {
  final Offset position; // normalized 0–1
  final bool visible;

  const _SpecularPainter({required this.position, required this.visible});

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    // Convert 0-1 normalised pos to -1..1 alignment
    final ax = position.dx * 2 - 1;
    final ay = position.dy * 2 - 1;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(ax, ay),
        radius: 0.75,
        colors: [
          Colors.white.withAlpha(38), // ~0.15 opacity
          Colors.white.withAlpha(0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_SpecularPainter old) =>
      old.position != position || old.visible != visible;
}

// ── Card content (bottom section) ────────────────────────────────────────────

class _CardContent extends StatelessWidget {
  final String firstName;
  final int analysisCount;
  final int streak;
  final String memberSince;
  final bool isDark;
  final Color accent;

  const _CardContent({
    required this.firstName,
    required this.analysisCount,
    required this.streak,
    required this.memberSince,
    required this.isDark,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary  = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final textSecondary = isDark
        ? Colors.white.withAlpha(100)
        : const Color(0xFF1A1A1A).withAlpha(85);
    final pillBorder = isDark
        ? Colors.white.withAlpha(20)
        : Colors.black.withAlpha(14);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Name
          Text(
            firstName.isNotEmpty ? firstName : 'You',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              letterSpacing: -0.5,
              height: 1.05,
            ),
          ),

          const SizedBox(height: 14),

          // Stamp badges
          Row(
            children: [
              _StampBadge(
                value: analysisCount.toString(),
                label: 'analyses',
                isDark: isDark,
                accent: accent,
              ),
              const SizedBox(width: 10),
              _StampBadge(
                value: streak.toString(),
                label: 'day streak',
                isDark: isDark,
                accent: accent,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Bottom row: member since + branding
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: pillBorder, width: 1),
                ),
                child: Text(
                  memberSince,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'ALIGN',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textSecondary,
                  letterSpacing: 2.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stamp badge ───────────────────────────────────────────────────────────────

class _StampBadge extends StatelessWidget {
  final String value;
  final String label;
  final bool isDark;
  final Color accent;

  const _StampBadge({
    required this.value,
    required this.label,
    required this.isDark,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? Colors.white.withAlpha(12)
        : accent.withAlpha(14);
    final border = isDark
        ? Colors.white.withAlpha(24)
        : accent.withAlpha(55);
    final valuecol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final labelCol  = isDark
        ? Colors.white.withAlpha(90)
        : const Color(0xFF1A1A1A).withAlpha(75);

    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: border, width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: AppTypography.stampValue(color: valuecol),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: labelCol,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
