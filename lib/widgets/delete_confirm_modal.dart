import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

Future<bool> showDeleteConfirmModal(BuildContext context) async {
  HapticFeedback.heavyImpact();
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Delete',
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
    pageBuilder: (ctx, _, __) => const _DeleteConfirmSheet(),
  );
  return result ?? false;
}

class _DeleteConfirmSheet extends StatelessWidget {
  const _DeleteConfirmSheet();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    const deleteRed = Color(0xFFFF453A);

    final cardRadius = SmoothBorderRadius(cornerRadius: 26, cornerSmoothing: 0.6);

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
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Are you sure you would like to delete this alignment?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                      letterSpacing: -0.2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Button(
                    label: 'Cancel',
                    bgColor: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.06),
                    textColor: scheme.onSurface,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop(false);
                    },
                  ),
                  const SizedBox(height: 8),
                  _Button(
                    label: 'Delete',
                    bgColor: deleteRed.withValues(alpha: isDark ? 0.30 : 0.18),
                    textColor: deleteRed,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop(true);
                    },
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

class _Button extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color textColor;
  final VoidCallback onTap;

  const _Button({
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: bgColor,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 0.6),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
