import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> showErrorModal(
  BuildContext context, {
  required String title,
  required String message,
  String primaryLabel = 'Try Again',
  VoidCallback? onPrimary,
  String dismissLabel = 'Dismiss',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Error',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (_, anim, __, child) {
      return SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutQuart,
            reverseCurve: Curves.easeOutCubic,
          ),
        ),
        child: child,
      );
    },
    pageBuilder: (ctx, _, __) => _ErrorSheet(
      title: title,
      message: message,
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      dismissLabel: dismissLabel,
    ),
  );
}

class _ErrorSheet extends StatelessWidget {
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String dismissLabel;

  const _ErrorSheet({
    required this.title,
    required this.message,
    required this.primaryLabel,
    this.onPrimary,
    required this.dismissLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final cardRadius = SmoothBorderRadius(cornerRadius: 26, cornerSmoothing: 0.6);
    const errorRed = Color(0xFFFF3B30);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 4),
        child: ClipSmoothRect(
          radius: cardRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: ShapeDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.92),
                shape: SmoothRectangleBorder(
                  borderRadius: cardRadius,
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: errorRed.withValues(alpha: isDark ? 0.15 : 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: errorRed.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.exclamationmark_circle,
                      size: 24,
                      color: errorRed,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      letterSpacing: -0.3,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (onPrimary != null) ...[
                    _SheetButton(
                      label: primaryLabel,
                      backgroundColor: scheme.primary,
                      textColor: Colors.white,
                      onTap: () {
                        Navigator.pop(context);
                        onPrimary!();
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  _SheetButton(
                    label: dismissLabel,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    textColor: scheme.onSurface,
                    onTap: () => Navigator.pop(context),
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

class _SheetButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: backgroundColor,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
