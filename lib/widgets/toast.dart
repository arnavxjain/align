import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ToastService {
  static OverlayEntry? _active;

  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    Color? iconColor,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 3),
  }) {
    _active?.remove();
    _active = null;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _ToastEntry(
        message: message,
        icon: icon,
        iconColor: iconColor,
        onTap: onTap,
        duration: duration,
        onDone: () {
          entry.remove();
          if (_active == entry) _active = null;
        },
      ),
    );
    _active = entry;
    overlay.insert(entry);
  }
}

class _ToastEntry extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Duration duration;
  final VoidCallback onDone;

  const _ToastEntry({
    required this.message,
    required this.duration,
    required this.onDone,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  @override
  State<_ToastEntry> createState() => _ToastEntryState();
}

class _ToastEntryState extends State<_ToastEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted || _ctrl.status != AnimationStatus.completed) return;
    await _ctrl.reverse();
    widget.onDone();
  }

  void _handleTap() {
    _ctrl.stop();
    widget.onDone();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final topPad = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPad + 12,
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: GestureDetector(
              onTap: widget.onTap != null ? _handleTap : null,
              behavior: HitTestBehavior.translucent,
              child: ClipSmoothRect(
                radius:
                    SmoothBorderRadius(cornerRadius: 18, cornerSmoothing: 0.6),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: ShapeDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.13)
                          : Colors.white.withValues(alpha: 0.88),
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                            cornerRadius: 18, cornerSmoothing: 0.6),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.09),
                          width: 0.6,
                        ),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Colors.black.withValues(
                              alpha: isDark ? 0.35 : 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: 16,
                            color: widget.iconColor ?? scheme.primary,
                          ),
                          const SizedBox(width: 9),
                        ],
                        Expanded(
                          child: Text(
                            widget.message,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurface,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        if (widget.onTap != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ],
                      ],
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
