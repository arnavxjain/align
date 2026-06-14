import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_typography.dart';
import '../providers/theme_notifier.dart';
import '../screens/alignment_detail.dart';
import '../services/analysis_service.dart';
import '../utils/transitions.dart';
import '../widgets/tappable.dart';
import '../widgets/toast.dart';

Future<void> showNewAlignmentModal(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'New Alignment',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeOutCubic,
      );
      return Stack(
        children: [
          AnimatedBuilder(
            animation: curved,
            builder: (_, __) => BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 12 * curved.value,
                sigmaY: 12 * curved.value,
              ),
              child: Container(
                color: Colors.black.withValues(alpha: 0.45 * curved.value),
              ),
            ),
          ),
          SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        ],
      );
    },
    pageBuilder: (_, __, ___) => const _NewAlignmentSheet(),
  );
}

class _NewAlignmentSheet extends StatefulWidget {
  const _NewAlignmentSheet({super.key});

  @override
  State<_NewAlignmentSheet> createState() => _NewAlignmentSheetState();
}

class _NewAlignmentSheetState extends State<_NewAlignmentSheet>
    with SingleTickerProviderStateMixin {
  double _dragX = 0;
  late AnimationController _snapBackCtrl;
  late Animation<double> _snapBackAnim;
  double _snapBackFrom = 0;

  @override
  void initState() {
    super.initState();
    _snapBackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _snapBackAnim = CurvedAnimation(parent: _snapBackCtrl, curve: Curves.easeOutCubic);
    _snapBackCtrl.addListener(() {
      setState(() => _dragX = _snapBackFrom * (1 - _snapBackAnim.value));
    });
  }

  @override
  void dispose() {
    _snapBackCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_snapBackCtrl.isAnimating) _snapBackCtrl.stop();
    final sw = MediaQuery.of(context).size.width;
    setState(() => _dragX = (_dragX + d.delta.dx).clamp(0.0, sw.toDouble()));
  }

  void _onDragEnd(DragEndDetails d) {
    final sw = MediaQuery.of(context).size.width;
    if (_dragX > sw * 0.35 || d.velocity.pixelsPerSecond.dx > 600) {
      Navigator.of(context).pop();
    } else {
      _snapBackFrom = _dragX;
      _snapBackCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final sh = MediaQuery.of(context).size.height;
    final cardRadius = SmoothBorderRadius(cornerRadius: 38, cornerSmoothing: 0.6);

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Transform.translate(
          offset: Offset(_dragX, 0),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 4),
              child: ClipSmoothRect(
                radius: cardRadius,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                  child: Container(
                    height: sh - topPad - bottomPad - 20,
                    decoration: ShapeDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.45)
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
                    child: ClipSmoothRect(
                      radius: cardRadius,
                      child: NewAlignmentScreen(onStarted: () => Navigator.of(context).pop()),
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

class NewAlignmentScreen extends StatefulWidget {
  final VoidCallback? onStarted;
  const NewAlignmentScreen({super.key, this.onStarted});

  @override
  State<NewAlignmentScreen> createState() => _NewAlignmentScreenState();
}

// Max URL length accepted; anything longer is almost certainly not a real URL.
const _kMaxUrlLength = 2048;
// Daily analysis cap per user.
const _kDailyLimit = 20;
// Max total saved analyses per user.
const _kMaxAnalyses = 500;

class _NewAlignmentScreenState extends State<NewAlignmentScreen> {
  String? _url;
  bool _realismCheck = true;
  bool _identifyProducts = false;
  bool _createTimeline = false;
  bool _findSimilarContent = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
  }

  /// Returns true if [url] looks like a valid HTTP/HTTPS URL.
  static bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    // Strip all leading/trailing whitespace and limit length before accepting.
    var text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    if (text.length > _kMaxUrlLength) text = text.substring(0, _kMaxUrlLength);
    if (!_isValidUrl(text)) {
      if (mounted) {
        ToastService.show(
          context,
          message: 'That doesn\'t look like a valid URL.',
          icon: CupertinoIcons.exclamationmark_circle,
        );
      }
      return;
    }
    setState(() => _url = text);
  }

  void _clear() => setState(() => _url = null);

  /// Counts how many analyses were created today (UTC).
  int _todayCount() {
    final today = DateTime.now().toUtc();
    return alignmentsNotifier.value.where((e) {
      final raw = e['created_at'] as String?;
      if (raw == null) return false;
      final d = DateTime.tryParse(raw)?.toUtc();
      if (d == null) return false;
      return d.year == today.year &&
          d.month == today.month &&
          d.day == today.day;
    }).length;
  }

  Future<void> _startAnalysis() async {
    if (_url == null || _submitting) return;

    // Auth guard — must be signed in.
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ToastService.show(context,
            message: 'Please sign in to run an analysis.',
            icon: CupertinoIcons.lock);
      }
      return;
    }

    // Daily limit check.
    if (_todayCount() >= _kDailyLimit) {
      if (mounted) {
        ToastService.show(
          context,
          message: 'Daily limit reached (${_kDailyLimit} analyses). Come back tomorrow.',
          icon: CupertinoIcons.clock,
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }

    // Total analysis cap.
    if (alignmentsNotifier.value.length >= _kMaxAnalyses) {
      if (mounted) {
        ToastService.show(
          context,
          message: 'You\'ve reached $_kMaxAnalyses saved analyses. Delete some to continue.',
          icon: CupertinoIcons.archivebox,
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      final entry = AnalysisService.createPendingEntry(
        url: _url!,
        detectedType: _detectType(_url!),
        realismCheck: _realismCheck,
        identifyProducts: _identifyProducts,
        createTimeline: _createTimeline,
        findSimilar: _findSimilarContent,
      );
      widget.onStarted?.call();
      if (mounted) {
        Navigator.push(
          context,
          AppRoute.push(AlignmentDetailScreen(alignmentId: entry['id'] as String)),
        );
      }
    } finally {
      // Reset after a short delay so rapid re-opens don't re-trigger instantly.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _submitting = false);
      });
    }
  }

  static String _detectType(String url) {
    final u = url.toLowerCase();
    if (u.contains('youtube.com') || u.contains('youtu.be')) return 'Video';
    if (u.contains('instagram.com/reel')) return 'Reel';
    if (u.contains('instagram.com')) return 'Post';
    if (u.contains('tiktok.com')) return 'Short';
    if (u.contains('twitter.com') || u.contains('x.com')) return 'Post';
    if (u.contains('reddit.com')) return 'Thread';
    return 'Article';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: _UrlDropZone(
                  url: _url,
                  onTap: _paste,
                  onClear: _clear,
                  isDark: isDark,
                  scheme: scheme,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: _url == null
                    ? const SizedBox.shrink()
                    : _OptionsSection(
                        linkType: _detectType(_url!),
                        realismCheck: _realismCheck,
                        onRealismChanged: (v) => setState(() => _realismCheck = v),
                        identifyProducts: _identifyProducts,
                        onIdentifyChanged: (v) => setState(() => _identifyProducts = v),
                        createTimeline: _createTimeline,
                        onTimelineChanged: (v) => setState(() => _createTimeline = v),
                        findSimilarContent: _findSimilarContent,
                        onFindSimilarChanged: (v) => setState(() => _findSimilarContent = v),
                        scheme: scheme,
                        isDark: isDark,
                      ),
              ),
            ),
            // Bottom padding so content doesn't hide behind floating button
            SliverToBoxAdapter(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: SizedBox(height: _url == null ? 0 : 96),
              ),
            ),
          ],
        ),
        // Floating frosted swipe button
        AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          bottom: _url == null ? -100 : 16,
          left: 20,
          right: 20,
          child: _SwipeToGoButton(
            onComplete: () => _startAnalysis(),
            disabled: _submitting,
            scheme: scheme,
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Tappable(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
              ),
              child: Icon(CupertinoIcons.multiply,
                  color: scheme.onSurface, size: 16),
            ),
          ),
          Expanded(
            child: Text(
              'New Alignment',
              textAlign: TextAlign.center,
              style: AppTypography.navTitle(color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }
}

// ── URL drop zone ─────────────────────────────────────────────────────────────

class _UrlDropZone extends StatelessWidget {
  final String? url;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final bool isDark;
  final ColorScheme scheme;

  const _UrlDropZone({
    required this.url,
    required this.onTap,
    required this.onClear,
    required this.isDark,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null;
    final borderColor = hasUrl
        ? scheme.primary.withAlpha(120)
        : isDark
            ? const Color(0xFF48484A)
            : const Color(0xFFC7C7CC);
    final iconColor = hasUrl
        ? scheme.primary
        : isDark
            ? const Color(0xFF636366)
            : const Color(0xFFAEAEB2);

    return Tappable(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: borderColor, radius: 18),
        child: SizedBox(
          width: double.infinity,
          height: 180,
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.link, color: iconColor, size: 28),
                      const SizedBox(height: 12),
                      if (hasUrl)
                        Text(
                          url!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: scheme.onSurface,
                            height: 1.5,
                          ),
                        )
                      else
                        Text(
                          'Tap to paste a YouTube, Reel,\narticle or any web URL',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (hasUrl)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Tappable(
                    onTap: onClear,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? const Color(0xFF48484A)
                            : const Color(0xFFD1D1D6),
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 13, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Options section (appears after paste) ────────────────────────────────────

class _OptionsSection extends StatelessWidget {
  final String linkType;
  final bool realismCheck;
  final ValueChanged<bool> onRealismChanged;
  final bool identifyProducts;
  final ValueChanged<bool> onIdentifyChanged;
  final bool createTimeline;
  final ValueChanged<bool> onTimelineChanged;
  final bool findSimilarContent;
  final ValueChanged<bool> onFindSimilarChanged;
  final ColorScheme scheme;
  final bool isDark;

  const _OptionsSection({
    required this.linkType,
    required this.realismCheck,
    required this.onRealismChanged,
    required this.identifyProducts,
    required this.onIdentifyChanged,
    required this.createTimeline,
    required this.onTimelineChanged,
    required this.findSimilarContent,
    required this.onFindSimilarChanged,
    required this.scheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Link type badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: ShapeDecoration(
                color: scheme.primary.withAlpha(isDark ? 40 : 25),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(cornerRadius: 10, cornerSmoothing: 0.6),
                  side: BorderSide(
                    color: scheme.primary.withAlpha(isDark ? 80 : 60),
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                linkType,
                style: AppTypography.chipLabel(color: scheme.primary),
              ),
            ),
          ),

          const SizedBox(height: 20),

          _ToggleRow(
            label: 'Realism Check',
            subtitle: 'Flag misleading or biased claims',
            value: realismCheck,
            onChanged: onRealismChanged,
            scheme: scheme,
          ),
          const SizedBox(height: 20),
          _ToggleRow(
            label: 'Identify Products',
            subtitle: 'Detect and list mentioned products',
            value: identifyProducts,
            onChanged: onIdentifyChanged,
            scheme: scheme,
          ),
          const SizedBox(height: 20),
          _ToggleRow(
            label: 'Create Timeline',
            subtitle: 'Extract key events in order',
            value: createTimeline,
            onChanged: onTimelineChanged,
            scheme: scheme,
          ),
          const SizedBox(height: 20),
          _ToggleRow(
            label: 'Find Similar Content',
            subtitle: 'Discover related articles or videos',
            value: findSimilarContent,
            onChanged: onFindSimilarChanged,
            scheme: scheme,
          ),
        ],
      ),
    );
  }
}

// ── Swipe-to-go button ────────────────────────────────────────────────────────

class _SwipeToGoButton extends StatefulWidget {
  final VoidCallback onComplete;
  final ColorScheme scheme;
  final bool isDark;
  final bool disabled;

  const _SwipeToGoButton({
    required this.onComplete,
    required this.scheme,
    required this.isDark,
    this.disabled = false,
  });

  @override
  State<_SwipeToGoButton> createState() => _SwipeToGoButtonState();
}

class _SwipeToGoButtonState extends State<_SwipeToGoButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  double _drag = 0;
  bool _completed = false;

  static const double _height   = 64;
  static const double _thumbW   = 68;
  static const double _thumbH   = 54;
  static const double _pad      = 5;

  double _maxDrag(double w) => w - _thumbW - _pad * 2;
  double _progress(double w) =>
      w > 0 ? (_drag / _maxDrag(w)).clamp(0.0, 1.0) : 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 420));
    _controller.addListener(() => setState(() => _drag = _animation.value));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d, double w) {
    if (_completed || widget.disabled) return;
    _controller.stop();
    setState(() => _drag = (_drag + d.delta.dx).clamp(0, _maxDrag(w)));
  }

  void _onEnd(DragEndDetails d, double w) {
    if (_completed || widget.disabled) return;
    if (_progress(w) >= 0.85) {
      _animation = Tween<double>(begin: _drag, end: _maxDrag(w))
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0).then((_) {
        if (mounted) {
          setState(() => _completed = true);
          widget.onComplete();
        }
      });
    } else {
      _animation = Tween<double>(begin: _drag, end: 0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final trackRadius = SmoothBorderRadius(cornerRadius: _height / 2, cornerSmoothing: 0.6);

    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.78,
        child: LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final progress = _progress(w);

      return GestureDetector(
        onHorizontalDragUpdate: (d) => _onUpdate(d, w),
        onHorizontalDragEnd:   (d) => _onEnd(d, w),
        child: ClipSmoothRect(
          radius: trackRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
          height: _height,
          decoration: ShapeDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
            shape: SmoothRectangleBorder(
              borderRadius: trackRadius,
              side: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.10),
                width: 0.8,
              ),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Opacity(
                  opacity: (1.0 - progress * 2).clamp(0.0, 1.0),
                  child: Text(
                    'Swipe to Go',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withAlpha(160),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              // Draggable thumb
              Positioned(
                left: _pad + _drag,
                top: (_height - _thumbH) / 2,
                child: Container(
                  width: _thumbW,
                  height: _thumbH,
                  decoration: BoxDecoration(
                    borderRadius: SmoothBorderRadius(cornerRadius: _thumbH / 2, cornerSmoothing: 0.6),
                    color: Colors.black,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x30000000),
                        blurRadius: 10,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      PhosphorIcons.caretDoubleRightFill,
                      size: 22,
                      color: widget.scheme.primary,
                    )
                  ),
                ),
              ),
            ],
          ),
        ),
          ),
        ),
      );
    }),
      ),
    );
  }
}


// ── Reusable toggle row ───────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme scheme;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? scheme.primary : Colors.transparent,
              border: Border.all(
                color: value
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withAlpha(80),
                width: 2,
              ),
            ),
            child: value
                ? Icon(CupertinoIcons.checkmark, size: 14, color: scheme.onPrimary)
                : null,
          ),
        ],
      ),
    );
  }
}


class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  static const _strokeWidth = 1.5;
  static const _dashLength  = 7.0;
  static const _gapLength   = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(_strokeWidth / 2, _strokeWidth / 2,
        size.width - _strokeWidth, size.height - _strokeWidth);
    final path = SmoothRectangleBorder(
      borderRadius: SmoothBorderRadius(cornerRadius: radius, cornerSmoothing: 0.6),
    ).getOuterPath(rect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      bool drawing = true;
      while (distance < metric.length) {
        final len = drawing ? _dashLength : _gapLength;
        if (drawing) {
          canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        }
        distance += len;
        drawing = !drawing;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
