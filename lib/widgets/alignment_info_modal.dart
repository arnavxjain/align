import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> showAlignmentInfoModal(
  BuildContext context,
  Map<String, dynamic> alignment,
) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Info',
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
    pageBuilder: (ctx, _, __) => _AlignmentInfoSheet(alignment: alignment),
  );
}

class _AlignmentInfoSheet extends StatelessWidget {
  final Map<String, dynamic> alignment;
  const _AlignmentInfoSheet({required this.alignment});

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final cardRadius = SmoothBorderRadius(cornerRadius: 26, cornerSmoothing: 0.6);

    final contentType = alignment['content_type'] as String? ?? 'article';
    final createdAt = alignment['created_at'] as String?;
    final rawTitle = alignment['title'] as String?;
    final url = alignment['url'] as String? ?? '';
    final displayTitle = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? 'Untitled';

    final raw = alignment['analyses'];
    final analyses = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    final (IconData typeIcon, Color typeColor, String typeLabel) = switch (contentType) {
      'youtube' => (CupertinoIcons.play_rectangle_fill, const Color(0xFFFF3B30), 'YouTube'),
      'reel'    => (CupertinoIcons.film_fill, const Color(0xFFBF5AF2), 'Reel'),
      _         => (CupertinoIcons.doc_text_fill, scheme.primary, 'Article'),
    };

    // Which analysis checks were run (have non-null, non-empty data)
    final checksRun = <(String, IconData)>[];
    bool _hasData(dynamic v) => v != null && (v is! List || (v as List).isNotEmpty);
    if (_hasData(analyses['realism_check']))   checksRun.add(('Realism Check', CupertinoIcons.checkmark_shield));
    if (_hasData(analyses['products']))        checksRun.add(('Products', CupertinoIcons.bag));
    if (_hasData(analyses['timeline']))        checksRun.add(('Timeline', CupertinoIcons.calendar));
    if (_hasData(analyses['similar_content'])) checksRun.add(('Similar Content', CupertinoIcons.rectangle_stack));

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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type icon + label row
                  Row(
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
                          displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                  const SizedBox(height: 18),
                  // Date
                  _InfoRow(
                    icon: CupertinoIcons.clock,
                    label: 'Created',
                    value: _formatDate(createdAt),
                    isDark: isDark,
                    scheme: scheme,
                  ),
                  const SizedBox(height: 10),
                  // Content type
                  _InfoRow(
                    icon: CupertinoIcons.tag,
                    label: 'Type',
                    value: typeLabel,
                    isDark: isDark,
                    scheme: scheme,
                  ),
                  if (checksRun.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'CHECKS RUN',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                        letterSpacing: 0.8,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: checksRun.map((c) {
                        final (label, icon) = c;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 12,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.65)),
                              const SizedBox(width: 5),
                              Text(
                                label,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant.withValues(alpha: 0.80),
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 22),
                  // Close button
                  _CloseButton(isDark: isDark, scheme: scheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final ColorScheme scheme;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Text(
          '$label  ',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
            decoration: TextDecoration.none,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.85),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatefulWidget {
  final bool isDark;
  final ColorScheme scheme;
  const _CloseButton({required this.isDark, required this.scheme});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).pop();
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: double.infinity,
          height: 46,
          decoration: ShapeDecoration(
            color: widget.isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 0.6),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'Close',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: widget.scheme.onSurface,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
