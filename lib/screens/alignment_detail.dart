import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/theme_notifier.dart';
import '../services/analysis_service.dart';
import '../services/reel_service.dart';
import '../widgets/tappable.dart';

class AlignmentDetailScreen extends StatefulWidget {
  final String alignmentId;
  const AlignmentDetailScreen({super.key, required this.alignmentId});

  @override
  State<AlignmentDetailScreen> createState() => _AlignmentDetailScreenState();
}

class _AlignmentDetailScreenState extends State<AlignmentDetailScreen> {
  String _statusMessage = 'Analysing…';
  double _progress = 0.0;
  bool _isAnalysing = false;
  // True when analysis is running in the background (started by a prior screen
  // instance) — we can't get live progress, so show indeterminate bar.
  bool _watchingBackground = false;

  @override
  void initState() {
    super.initState();
    final alignment = alignmentsNotifier.value
        .firstWhere((e) => e['id'] == widget.alignmentId, orElse: () => {});
    if (alignment['is_analyzing'] == true) {
      _isAnalysing = true;
      if (!AnalysisService.isRunning(widget.alignmentId)) {
        _doAnalysis(alignment);
      } else {
        _watchingBackground = true;
        alignmentsNotifier.addListener(_onNotifierUpdate);
      }
    }
  }

  void _onNotifierUpdate() {
    final alignment = alignmentsNotifier.value
        .firstWhere((e) => e['id'] == widget.alignmentId, orElse: () => {});
    if (alignment.isEmpty || alignment['is_analyzing'] != true) {
      alignmentsNotifier.removeListener(_onNotifierUpdate);
      if (mounted) setState(() { _isAnalysing = false; _watchingBackground = false; });
    }
  }

  @override
  void dispose() {
    if (_watchingBackground) alignmentsNotifier.removeListener(_onNotifierUpdate);
    super.dispose();
  }

  Future<void> _doAnalysis(Map<String, dynamic> entry) async {
    try {
      await AnalysisService.runAnalysis(
        pendingEntry: entry,
        onStatus: (msg) {
          if (mounted) setState(() => _statusMessage = msg);
        },
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _isAnalysing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAnalysing = false);
      final msg = e is ReelDownloadException
          ? e.message
          : 'Something went wrong. Please try again.';
      await showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Error'),
          content: Text(msg),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.maybePop(context);
    }
  }

  static String _relativeTime(String isoString) {
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return [];
    return value
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: alignmentsNotifier,
      builder: (context, alignments, _) {
        final alignment = alignments.firstWhere(
          (e) => e['id'] == widget.alignmentId,
          orElse: () => <String, dynamic>{},
        );

        final url = alignment['url'] as String? ?? '';
        final title = alignment['title'] as String?;
        final contentType = alignment['content_type'] as String? ?? 'article';
        final createdAt = alignment['created_at'] as String? ?? '';
        final raw = alignment['analyses'];
        final analyses =
            raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

        final realismCheck = _asList(analyses['realism_check']);
        final products = _asList(analyses['products']);
        final timeline = _asList(analyses['timeline']);
        final similar = _asList(analyses['similar_content']);

        final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

        return Scaffold(
          body: SafeArea(
            top: false,
            child: CustomScrollView(
              slivers: [
                // ── Pinned blurred header ────────────────────────────────────
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: 66,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  automaticallyImplyLeading: false,
                  leadingWidth: 68,
                  flexibleSpace: ClipRect(
                    child: Stack(
                      children: [
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            color: scaffoldBg.withAlpha(isDark ? 155 : 195),
                          ),
                        ),
                        Positioned(
                          left: 0, right: 0, bottom: 0,
                          child: Container(
                            height: 0.5,
                            color: isDark
                                ? const Color(0xFF424242)
                                : const Color(0xFFD1D1D6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Center(
                      child: Tappable(
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
                          child: Icon(CupertinoIcons.chevron_left,
                              color: scheme.onSurface, size: 16),
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    'Alignment',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  actions: [
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: starredNotifier,
                      builder: (_, starred, __) {
                        final isStarred =
                            starred.contains(widget.alignmentId);
                        return Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: Tappable(
                            onTap: () => AnalysisService.toggleStar(
                                widget.alignmentId),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFE5E5EA),
                              ),
                              child: Icon(
                                isStarred
                                    ? CupertinoIcons.star_fill
                                    : CupertinoIcons.star,
                                size: 17,
                                color: isStarred
                                    ? const Color(0xFFFF9F0A)
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                // ── Meta card ────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      decoration: ShapeDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius(
                              cornerRadius: 16, cornerSmoothing: 0.6),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _TypeBadge(type: contentType, scheme: scheme),
                              const Spacer(),
                              Text(
                                _relativeTime(createdAt),
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          if (title != null && title.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                                height: 1.35,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            url,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Progress card (visible while analysing) ──────────────────
                if (_isAnalysing)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: ShapeDecoration(
                          color:
                              isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          shape: SmoothRectangleBorder(
                            borderRadius: SmoothBorderRadius(
                                cornerRadius: 14, cornerSmoothing: 0.6),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              child: Text(
                                _statusMessage,
                                key: ValueKey(_statusMessage),
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: _watchingBackground
                                  ? LinearProgressIndicator(
                                      minHeight: 4,
                                      backgroundColor:
                                          scheme.primary.withAlpha(30),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          scheme.primary),
                                    )
                                  : TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.0, end: _progress),
                                      duration:
                                          const Duration(milliseconds: 500),
                                      curve: Curves.easeOutCubic,
                                      builder: (_, value, __) =>
                                          LinearProgressIndicator(
                                        value: value,
                                        minHeight: 4,
                                        backgroundColor:
                                            scheme.primary.withAlpha(30),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                scheme.primary),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Analysis sections (appear as each completes) ─────────────
                if (realismCheck.isNotEmpty)
                  _Section(
                    icon: CupertinoIcons.checkmark_shield_fill,
                    title: 'Realism Check',
                    scheme: scheme,
                    isDark: isDark,
                    children: realismCheck
                        .map((m) => _RealismItem(
                              claim: m['claim'] as String? ?? '',
                              verdict: m['verdict'] as String? ?? 'unverified',
                              explanation: m['explanation'] as String? ?? '',
                              scheme: scheme,
                              isDark: isDark,
                            ))
                        .toList(),
                  ),

                if (products.isNotEmpty)
                  _Section(
                    icon: CupertinoIcons.tag_fill,
                    title: 'Products & Brands',
                    scheme: scheme,
                    isDark: isDark,
                    children: products
                        .map((m) => _ProductItem(
                              product: m['product'] as String? ?? '',
                              brand: m['brand'] as String? ?? '',
                              context: m['context'] as String? ?? '',
                              scheme: scheme,
                            ))
                        .toList(),
                  ),

                if (timeline.isNotEmpty)
                  _Section(
                    icon: CupertinoIcons.clock_fill,
                    title: 'Timeline',
                    scheme: scheme,
                    isDark: isDark,
                    children: timeline
                        .map((m) => _TimelineItem(
                              position: m['position']?.toString() ?? '',
                              event: m['event'] as String? ?? '',
                              scheme: scheme,
                            ))
                        .toList(),
                  ),

                if (similar.isNotEmpty)
                  _Section(
                    icon: CupertinoIcons.link,
                    title: 'Similar Content',
                    scheme: scheme,
                    isDark: isDark,
                    children: similar
                        .map((m) => _SimilarItem(
                              title: m['title'] as String? ?? '',
                              url: m['url'] as String? ?? '',
                              summary: m['summary'] as String? ?? '',
                              scheme: scheme,
                            ))
                        .toList(),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme scheme;
  final bool isDark;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.title,
    required this.scheme,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 15),
                const SizedBox(width: 7),
                Text(
                  title.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: ShapeDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                shape: SmoothRectangleBorder(
                  borderRadius:
                      SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6),
                ),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: scheme.outline.withAlpha(60),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Realism item ──────────────────────────────────────────────────────────────

class _RealismItem extends StatelessWidget {
  final String claim;
  final String verdict;
  final String explanation;
  final ColorScheme scheme;
  final bool isDark;

  const _RealismItem({
    required this.claim,
    required this.verdict,
    required this.explanation,
    required this.scheme,
    required this.isDark,
  });

  Color get _verdictColor => switch (verdict.toLowerCase()) {
        'true' => const Color(0xFF34C759),
        'misleading' => const Color(0xFFFF3B30),
        _ => const Color(0xFFFF9500),
      };

  String get _verdictLabel => switch (verdict.toLowerCase()) {
        'true' => 'TRUE',
        'misleading' => 'MISLEADING',
        _ => 'UNVERIFIED',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  claim,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _verdictColor.withAlpha(isDark ? 45 : 25),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: _verdictColor.withAlpha(90), width: 1),
                ),
                child: Text(
                  _verdictLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _verdictColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              explanation,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Product item ──────────────────────────────────────────────────────────────

class _ProductItem extends StatelessWidget {
  final String product;
  final String brand;
  final String context;
  final ColorScheme scheme;

  const _ProductItem({
    required this.product,
    required this.brand,
    required this.context,
    required this.scheme,
  });

  @override
  Widget build(BuildContext _) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface)),
          if (brand.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(brand,
                style: GoogleFonts.inter(
                    fontSize: 13, color: scheme.primary)),
          ],
          if (context.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(context,
                style: GoogleFonts.inter(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

// ── Timeline item ─────────────────────────────────────────────────────────────

class _TimelineItem extends StatelessWidget {
  final String position;
  final String event;
  final ColorScheme scheme;

  const _TimelineItem(
      {required this.position, required this.event, required this.scheme});

  @override
  Widget build(BuildContext _) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              position,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(event,
                style: GoogleFonts.inter(
                    fontSize: 14, color: scheme.onSurface, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ── Similar content item ──────────────────────────────────────────────────────

class _SimilarItem extends StatelessWidget {
  final String title;
  final String url;
  final String summary;
  final ColorScheme scheme;

  const _SimilarItem({
    required this.title,
    required this.url,
    required this.summary,
    required this.scheme,
  });

  static String _domain(String url) {
    try {
      return Uri.parse(url).host.replaceAll('www.', '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext _) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                  height: 1.3)),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(_domain(url),
                style:
                    GoogleFonts.inter(fontSize: 12, color: scheme.primary)),
          ],
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(summary,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    height: 1.45)),
          ],
        ],
      ),
    );
  }
}

// ── Content type badge ────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String type;
  final ColorScheme scheme;

  const _TypeBadge({required this.type, required this.scheme});

  (IconData, Color, String) get _config => switch (type) {
        'youtube' => (CupertinoIcons.play_rectangle_fill,
            const Color(0xFFFF3B30), 'YouTube'),
        'reel' => (CupertinoIcons.film_fill, const Color(0xFFBF5AF2), 'Reel'),
        _ => (CupertinoIcons.doc_text_fill, scheme.primary, 'Article'),
      };

  @override
  Widget build(BuildContext _) {
    final (icon, color, label) = _config;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}
