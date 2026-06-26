import 'dart:async';
import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show appNavigatorKey;
import '../providers/theme_notifier.dart';
import '../screens/creative_space.dart';

class CreativeSessionPill extends StatefulWidget {
  const CreativeSessionPill({super.key});

  @override
  State<CreativeSessionPill> createState() => _CreativeSessionPillState();
}

class _CreativeSessionPillState extends State<CreativeSessionPill>
    with SingleTickerProviderStateMixin {
  final _pillKey = GlobalKey();

  late final AnimationController _animCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 1.8),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _animCtrl,
    curve: const Interval(0.0, 0.6),
  );

  Map<String, dynamic>? _session;
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    activeCreativeSessionNotifier.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    activeCreativeSessionNotifier.removeListener(_onSessionChanged);
    _timer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final next = activeCreativeSessionNotifier.value;
    if (next != null && _session == null) {
      setState(() {
        _session = next;
        _elapsed = (next['elapsedSeconds'] as int?) ?? 0;
      });
      _animCtrl.forward(from: 0);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed++);
      });
    } else if (next == null && _session != null) {
      _timer?.cancel();
      _animCtrl.reverse().then((_) {
        if (mounted) setState(() => _session = null);
      });
    } else if (next != null) {
      setState(() {
        _session = next;
        _elapsed = (next['elapsedSeconds'] as int?) ?? 0;
      });
    }
  }

  void _onTap() {
    final session = _session;
    if (session == null) return;
    HapticFeedback.lightImpact();

    // Capture pill rect before clearing the session (which hides the pill).
    Rect? pillRect;
    final box = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      pillRect = box.localToGlobal(Offset.zero) & box.size;
    }

    activeCreativeSessionNotifier.value = null;
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      openCreativeSpace(
        ctx,
        session['alignmentId'] as String,
        initialElapsed: _elapsed,
        fromRect: pillRect,
      );
    }
  }

  static String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  static (IconData, Color) _typeInfo(String type) => switch (type) {
    'youtube' => (CupertinoIcons.play_rectangle_fill, const Color(0xFFFF3B30)),
    'reel'    => (CupertinoIcons.film_fill, const Color(0xFFBF5AF2)),
    _         => (CupertinoIcons.doc_text_fill, const Color(0xFF0A84FF)),
  };

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = (_session!['title'] as String?) ?? 'Creative Space';
    final contentType = (_session!['contentType'] as String?) ?? 'article';
    final (typeIcon, iconColor) = _typeInfo(contentType);

    final baseBottom = mq.padding.bottom + 88.0;

    // Use ValueListenableBuilder + TweenAnimationBuilder so the bottom offset
    // animates the instant pillShiftedNotifier changes — no AnimationController
    // needed, which avoids the Positioned/ParentDataWidget propagation issue.
    return ValueListenableBuilder<bool>(
      valueListenable: pillShiftedNotifier,
      builder: (context, shifted, child) => TweenAnimationBuilder<double>(
        tween: Tween(end: shifted ? baseBottom - 76 : baseBottom),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOutCubic,
        builder: (context, bottom, child) => Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: child,
        ),
        child: child,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: GestureDetector(
                onTap: _onTap,
                child: ClipSmoothRect(
                  key: _pillKey,
                  radius: SmoothBorderRadius(
                    cornerRadius: 20,
                    cornerSmoothing: 0.6,
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Container(
                      decoration: ShapeDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.92),
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius(
                            cornerRadius: 20,
                            cornerSmoothing: 0.6,
                          ),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 0.8,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: iconColor.withValues(alpha: 0.15),
                              border: Border.all(
                                color: iconColor.withValues(alpha: 0.30),
                                width: 0.8,
                              ),
                            ),
                            child: Icon(typeIcon, size: 17, color: iconColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Creative session in play',
                                  style: GoogleFonts.geist(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.45)
                                        : Colors.black.withValues(alpha: 0.40),
                                    decoration: TextDecoration.none,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  title,
                                  style: GoogleFonts.geist(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.92)
                                        : Colors.black.withValues(alpha: 0.88),
                                    decoration: TextDecoration.none,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _fmt(_elapsed),
                            style: GoogleFonts.geist(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.40)
                                  : Colors.black.withValues(alpha: 0.35),
                              decoration: TextDecoration.none,
                              letterSpacing: 0.3,
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
    );
  }
}
