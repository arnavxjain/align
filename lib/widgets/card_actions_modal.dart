import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/theme_notifier.dart';

enum CardAction { star, info, delete }

Future<CardAction?> showCardActionsModal(
  BuildContext context,
  String alignmentId,
  String title,
  String contentType,
) async {
  HapticFeedback.heavyImpact();
  return showGeneralDialog<CardAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Actions',
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
    pageBuilder: (ctx, _, __) => _CardActionsSheet(
      alignmentId: alignmentId,
      title: title,
      contentType: contentType,
    ),
  );
}

class _CardActionsSheet extends StatelessWidget {
  final String alignmentId;
  final String title;
  final String contentType;
  const _CardActionsSheet({
    required this.alignmentId,
    required this.title,
    required this.contentType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final cardRadius = SmoothBorderRadius(cornerRadius: 26, cornerSmoothing: 0.6);

    final (IconData typeIcon, Color typeColor, String typeLabel) = switch (contentType) {
      'youtube' => (CupertinoIcons.play_rectangle_fill, const Color(0xFFFF3B30), 'YouTube'),
      'reel'    => (CupertinoIcons.film_fill, const Color(0xFFBF5AF2), 'Reel'),
      _         => (CupertinoIcons.doc_text_fill, scheme.primary, 'Article'),
    };

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
              padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon + title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(typeIcon, color: typeColor, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                            height: 1.3,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ValueListenableBuilder<Set<String>>(
                        valueListenable: starredNotifier,
                        builder: (_, starred, __) {
                          final isStarred = starred.contains(alignmentId);
                          return _CircleButton(
                            icon: isStarred ? CupertinoIcons.star_fill : CupertinoIcons.star,
                            bgColor: isDark
                                ? const Color(0xFFFF9F0A).withValues(alpha: 0.10)
                                : const Color(0xFFFF9F0A).withValues(alpha: 0.15),
                            iconColor: const Color(0xFFFF9F0A).withValues(alpha: isDark ? 0.75 : 1.0),
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              Navigator.of(context).pop(CardAction.star);
                            },
                          );
                        },
                      ),
                      _CircleButton(
                        icon: CupertinoIcons.info_circle,
                        bgColor: scheme.primary.withValues(alpha: isDark ? 0.10 : 0.15),
                        iconColor: scheme.primary.withValues(alpha: isDark ? 0.75 : 1.0),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(CardAction.info);
                        },
                      ),
                      _CircleButton(
                        icon: CupertinoIcons.trash,
                        bgColor: const Color(0xFFFF453A).withValues(alpha: isDark ? 0.12 : 0.15),
                        iconColor: const Color(0xFFFF453A).withValues(alpha: isDark ? 0.75 : 1.0),
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          Navigator.of(context).pop(CardAction.delete);
                        },
                      ),
                      _CircleButton(
                        icon: CupertinoIcons.xmark,
                        bgColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                        iconColor: isDark
                            ? Colors.white.withValues(alpha: 0.55)
                            : Colors.black.withValues(alpha: 0.45),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(null);
                        },
                      ),
                    ],
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

class _CircleButton extends StatefulWidget {
  final IconData icon;
  final Color bgColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    required this.bgColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: widget.bgColor, shape: BoxShape.circle),
          child: Icon(widget.icon, color: widget.iconColor, size: 22),
        ),
      ),
    );
  }
}
