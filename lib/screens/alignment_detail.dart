import 'dart:math';
import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/theme_notifier.dart';
import '../services/analysis_service.dart';
import '../services/gemini_service.dart';
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
            bottom: false,
            top: false,
            child: Stack(
              children: [
                CustomScrollView(
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
                          filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                          child: Container(
                            color: scaffoldBg.withAlpha(isDark ? 110 : 150),
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
                      builder: (_, starred, _a) {
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
                                      builder: (_, value, _b) =>
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

                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48 + 16 + 16 + MediaQuery.of(context).padding.bottom,
                  ),
                ),
              ],
            ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _ChatBar(alignmentId: widget.alignmentId),
                ),
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

// ── Chat input bar ────────────────────────────────────────────────────────────

class _ChatBar extends StatefulWidget {
  final String alignmentId;
  const _ChatBar({required this.alignmentId});

  @override
  State<_ChatBar> createState() => _ChatBarState();
}

class _ChatBarState extends State<_ChatBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openSheet(BuildContext context, {String? initialMessage}) {
    final alignment = alignmentsNotifier.value.firstWhere(
      (e) => e['id'] == widget.alignmentId,
      orElse: () => <String, dynamic>{},
    );
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (ctx, _, __) => Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: _ChatSheet(
                alignmentId: widget.alignmentId,
                alignment: alignment,
                initialMessage: initialMessage,
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInQuart,
        );
        return Stack(
          children: [
            // Full-screen blurred + tinted scrim
            AnimatedBuilder(
              animation: curved,
              builder: (_, __) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(ctx).pop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: curved.value * 22,
                    sigmaY: curved.value * 22,
                  ),
                  child: Container(
                    color: Colors.black
                        .withAlpha((curved.value * 110).round()),
                  ),
                ),
              ),
            ),
            // Sheet slides up
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ],
        );
      },
    );
  }

  void _submit(BuildContext context) {
    final text = _ctrl.text.trim();
    _ctrl.clear();
    _openSheet(context, initialMessage: text.isNotEmpty ? text : null);
  }

  BoxDecoration _pillDecoration(bool isDark) => BoxDecoration(
        color: isDark ? Colors.white.withAlpha(22) : Colors.black.withAlpha(12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(45) : Colors.black.withAlpha(30),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 70 : 30),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final alignment = alignmentsNotifier.value.firstWhere(
      (e) => e['id'] == widget.alignmentId,
      orElse: () => <String, dynamic>{},
    );
    final hasChatHistory =
        (alignment['chat_history'] as List?)?.isNotEmpty ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.only(left: 16, right: 6),
                  decoration: _pillDecoration(isDark),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submit(context),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: scheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ask anything about this alignment…',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _ctrl,
                        builder: (ctx, val, _) {
                          final hasText = val.text.trim().isNotEmpty;
                          return Tappable(
                            onTap: hasText ? () => _submit(context) : null,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasText
                                    ? scheme.primary
                                    : (isDark
                                        ? Colors.white.withAlpha(18)
                                        : Colors.black.withAlpha(12)),
                              ),
                              child: Icon(
                                CupertinoIcons.arrow_up,
                                size: 15,
                                color: hasText
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasChatHistory) ...[
            const SizedBox(width: 8),
            Tappable(
              onTap: () => _openSheet(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: _pillDecoration(isDark),
                    child: Icon(
                      CupertinoIcons.bubble_left_fill,
                      size: 17,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chat sheet ────────────────────────────────────────────────────────────────

class _ChatSheet extends StatefulWidget {
  final String alignmentId;
  final Map<String, dynamic> alignment;
  final String? initialMessage;

  const _ChatSheet({
    required this.alignmentId,
    required this.alignment,
    this.initialMessage,
  });

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.alignment['chat_history'];
    if (raw is List) {
      _messages = raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
        _send(widget.initialMessage!);
      } else {
        _scrollToBottom(animated: false);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _buildSystemContext() {
    final a = widget.alignment;
    final title = a['title'] as String? ?? 'Unknown';
    final type = a['content_type'] as String? ?? 'article';
    final url = a['url'] as String? ?? '';
    final raw = a['analyses'];
    final analyses =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    final sb = StringBuffer()
      ..writeln(
          'You are a helpful assistant. The user is asking about content they analysed:')
      ..writeln('Title: $title')
      ..writeln('Type: $type')
      ..writeln('URL: $url')
      ..writeln();

    final realismCheck = analyses['realism_check'];
    if (realismCheck is List && realismCheck.isNotEmpty) {
      sb.writeln('Realism Check (${realismCheck.length} claims):');
      for (final c in realismCheck.take(6)) {
        if (c is Map) sb.writeln('  ${c['claim']} → ${c['verdict']}');
      }
    }

    final products = analyses['products'];
    if (products is List && products.isNotEmpty) {
      sb.writeln(
          'Products: ${products.whereType<Map>().map((p) => p['product']).join(', ')}');
    }

    final timeline = analyses['timeline'];
    if (timeline is List && timeline.isNotEmpty) {
      sb.writeln('Timeline: ${timeline.length} events extracted.');
    }

    final similar = analyses['similar_content'];
    if (similar is List && similar.isNotEmpty) {
      sb.writeln('Similar content: ${similar.length} items found.');
    }

    sb.writeln('\nAnswer questions about this content concisely and helpfully.');
    return sb.toString();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loading) return;

    final userMsg = <String, dynamic>{
      'role': 'user',
      'content': trimmed,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    setState(() {
      _messages = [..._messages, userMsg];
      _loading = true;
    });
    _scrollToBottom();

    AnalysisService.saveChatHistory(
            widget.alignmentId, List.from(_messages))
        .ignore();

    final response = await GeminiService.chat(
      systemContext: _buildSystemContext(),
      history: _messages
          .map((m) => {
                'role': m['role'] as String,
                'content': m['content'] as String,
              })
          .toList(),
    );

    if (!mounted) return;

    final assistantMsg = <String, dynamic>{
      'role': 'assistant',
      'content': response ?? "Sorry, I couldn't get a response. Please try again.",
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    setState(() {
      _messages = [..._messages, assistantMsg];
      _loading = false;
    });
    _scrollToBottom();

    AnalysisService.saveChatHistory(
            widget.alignmentId, List.from(_messages))
        .ignore();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (animated) {
        _scrollCtrl.animateTo(max,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      } else {
        _scrollCtrl.jumpTo(max);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: Container(
          color: isDark
              ? const Color(0xFF1C1C1E).withAlpha(200)
              : Colors.white.withAlpha(200),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3A3C)
                      : const Color(0xFFD1D1D6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ask about this Alignment',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    Tappable(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                        ),
                        child: Icon(CupertinoIcons.xmark,
                            size: 13, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: scheme.outline.withAlpha(60)),
              // Messages
              Expanded(
                child: _messages.isEmpty && !_loading
                    ? _ChatEmptyState(scheme: scheme)
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        itemCount: _messages.length + (_loading ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _messages.length) {
                            return const _TypingIndicator();
                          }
                          return _MessageBubble(
                            message: _messages[i],
                            isDark: isDark,
                            scheme: scheme,
                          );
                        },
                      ),
              ),
              // Input
              Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: scheme.outline.withAlpha(60)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (t) {
                          _send(t);
                          _ctrl.clear();
                        },
                        style: GoogleFonts.inter(
                            fontSize: 14, color: scheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Message…',
                          hintStyle: GoogleFonts.inter(
                              fontSize: 14, color: scheme.onSurfaceVariant),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFF2F2F7),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tappable(
                      onTap: () {
                        final t = _ctrl.text.trim();
                        if (t.isNotEmpty) {
                          _send(t);
                          _ctrl.clear();
                        }
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary,
                        ),
                        child: Icon(CupertinoIcons.arrow_up,
                            size: 16, color: scheme.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chat message bubble ───────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isDark;
  final ColorScheme scheme;

  const _MessageBubble({
    required this.message,
    required this.isDark,
    required this.scheme,
  });

  @override
  Widget build(BuildContext _) {
    final isUser = message['role'] == 'user';
    final content = message['content'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withAlpha(18),
              ),
              child: Icon(CupertinoIcons.sparkles,
                  size: 12, color: scheme.primary),
            ),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? scheme.primary
                    : (isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFF2F2F7)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                content,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isUser ? scheme.onPrimary : scheme.onSurface,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withAlpha(18),
            ),
            child: Icon(CupertinoIcons.sparkles,
                size: 12, color: scheme.primary),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color:
                  isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, _c) {
                    final phase = (_ctrl.value * 3.0 - i).remainder(3.0);
                    final t = (phase >= 0 && phase < 1.0) ? phase : 0.0;
                    final opacity = 0.3 + 0.7 * sin(t * pi);
                    return Container(
                      width: 6,
                      height: 6,
                      margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.onSurfaceVariant.withValues(alpha: opacity),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat empty state ──────────────────────────────────────────────────────────

class _ChatEmptyState extends StatelessWidget {
  final ColorScheme scheme;
  const _ChatEmptyState({required this.scheme});

  @override
  Widget build(BuildContext _) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withAlpha(18),
            ),
            child: Icon(CupertinoIcons.sparkles,
                color: scheme.primary, size: 24),
          ),
          const SizedBox(height: 14),
          Text(
            'Ask anything',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Questions about claims, products,\ntimeline, or anything else.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
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
