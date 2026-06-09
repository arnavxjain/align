import 'dart:async';
import 'dart:math';
import 'dart:ui';


import 'package:figma_squircle/figma_squircle.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_typography.dart';
import '../providers/theme_notifier.dart';
import '../services/analysis_service.dart';
import '../widgets/page_header.dart';
import '../widgets/tappable.dart';

Future<void> showInsightsModal(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Insights',
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
    pageBuilder: (_, __, ___) => const _InsightsSheet(),
  );
}

// Keep the old class name usable as an alias
typedef InsightsScreen = _InsightsSheet;

class _InsightsSheet extends StatefulWidget {
  const _InsightsSheet({super.key});

  @override
  State<_InsightsSheet> createState() => _InsightsSheetState();
}

class _InsightsSheetState extends State<_InsightsSheet>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  double _dragX = 0;
  late AnimationController _snapBackCtrl;
  late Animation<double> _snapBackAnim;
  double _snapBackFrom = 0;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    if (alignmentsNotifier.value.isEmpty) {
      await AnalysisService.loadAlignments();
    }
    if (mounted) setState(() => _isLoading = false);
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
    final scheme = Theme.of(context).colorScheme;
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
                      child: Stack(
                        children: [
                          // ── Scrollable content with gradient-blur top edge ──
                          ValueListenableBuilder<List<Map<String, dynamic>>>(
                            valueListenable: alignmentsNotifier,
                            builder: (context, alignments, _) {
                              final completed = alignments
                                  .where((e) => e['is_analyzing'] != true)
                                  .toList();
                              final data = _isLoading
                                  ? null
                                  : _InsightsData.compute(completed);

                              return CustomScrollView(
                                slivers: [
                                  // Space for the pinned header
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 120),
                                  ),
                                  if (_isLoading)
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: _SkeletonBody(isDark: isDark),
                                    )
                                  else if (completed.isEmpty)
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: _EmptyState(scheme: scheme),
                                    )
                                  else ...[
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                                        child: _InsightsHeatmap(
                                          alignments: alignments,
                                          isDark: isDark,
                                          scheme: scheme,
                                        ),
                                      ),
                                    ),
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                                        child: _Content(
                                          data: data!,
                                          scheme: scheme,
                                          isDark: isDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),

                          // ── Colour-gradient pinned header overlay ────────
                          Positioned(
                            top: 0, left: 0, right: 0,
                            child: _GradientBlurHeader(isDark: isDark, scheme: scheme),
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

// ── Gradient-blur pinned header ───────────────────────────────────────────────

class _GradientBlurHeader extends StatelessWidget {
  final bool isDark;
  final ColorScheme scheme;
  const _GradientBlurHeader({required this.isDark, required this.scheme});

  @override
  Widget build(BuildContext context) {
    const topPad = 8.0;
    const titleH = 52.0;
    const totalH = 72.0;
    final fadeColor = isDark ? Colors.black : Colors.white;
    final a = isDark ? 0.92 : 0.98;

    return SizedBox(
      height: totalH,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    fadeColor.withValues(alpha: a),
                    fadeColor.withValues(alpha: a * 0.85),
                    fadeColor.withValues(alpha: a * 0.65),
                    fadeColor.withValues(alpha: a * 0.42),
                    fadeColor.withValues(alpha: a * 0.22),
                    fadeColor.withValues(alpha: a * 0.08),
                    fadeColor.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.20, 0.40, 0.58, 0.74, 0.88, 1.0],
                ),
              ),
            ),
          ),

          // Title row
          Padding(
            padding: const EdgeInsets.only(top: topPad),
            child: SizedBox(
              height: titleH,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                      child: Icon(
                        CupertinoIcons.arrow_left,
                        size: 20,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Insights',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _InsightsData {
  final int total;
  final int articles;
  final int youtube;
  final int reels;
  final int realismChecks;
  final int productIdentifications;
  final int timelines;
  final int similarSearches;
  final int totalProducts;
  final int totalFlags;
  final String? topDomain;
  final List<int> last7Days;

  const _InsightsData({
    required this.total,
    required this.articles,
    required this.youtube,
    required this.reels,
    required this.realismChecks,
    required this.productIdentifications,
    required this.timelines,
    required this.similarSearches,
    required this.totalProducts,
    required this.totalFlags,
    required this.topDomain,
    required this.last7Days,
  });

  factory _InsightsData.compute(List<Map<String, dynamic>> alignments) {
    var articles = 0, youtube = 0, reels = 0;
    var realismChecks = 0, productIdentifications = 0, timelines = 0,
        similarSearches = 0;
    var totalProducts = 0, totalFlags = 0;
    final domainCounts = <String, int>{};
    final today = DateTime.now();
    final last7 = List<int>.filled(7, 0);

    for (final a in alignments) {
      final type = a['content_type'] as String? ?? 'article';
      switch (type) {
        case 'youtube':
          youtube++;
        case 'reel':
          reels++;
        default:
          articles++;
      }

      final raw = a['analyses'];
      final analyses = raw is Map ? raw : const <String, dynamic>{};

      if (analyses['realism_check'] != null) {
        realismChecks++;
        final flags = analyses['realism_check'];
        if (flags is List) totalFlags += flags.length;
      }
      if (analyses['products'] != null) {
        productIdentifications++;
        final products = analyses['products'];
        if (products is List) totalProducts += products.length;
      }
      if (analyses['timeline'] != null) timelines++;
      if (analyses['similar_content'] != null) similarSearches++;

      if (type == 'article') {
        final url = a['url'] as String? ?? '';
        try {
          final host = Uri.parse(url).host.replaceAll('www.', '');
          if (host.isNotEmpty) {
            domainCounts[host] = (domainCounts[host] ?? 0) + 1;
          }
        } catch (_) {}
      }

      final createdAt =
          DateTime.tryParse(a['created_at'] as String? ?? '')?.toLocal();
      if (createdAt != null) {
        final todayMidnight = DateTime(today.year, today.month, today.day);
        final entryMidnight =
            DateTime(createdAt.year, createdAt.month, createdAt.day);
        final diff = todayMidnight.difference(entryMidnight).inDays;
        if (diff >= 0 && diff < 7) last7[6 - diff]++;
      }
    }

    String? topDomain;
    if (domainCounts.isNotEmpty) {
      topDomain = domainCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    }

    return _InsightsData(
      total: alignments.length,
      articles: articles,
      youtube: youtube,
      reels: reels,
      realismChecks: realismChecks,
      productIdentifications: productIdentifications,
      timelines: timelines,
      similarSearches: similarSearches,
      totalProducts: totalProducts,
      totalFlags: totalFlags,
      topDomain: topDomain,
      last7Days: last7,
    );
  }

  List<String> get insights {
    final list = <String>[];

    if (articles >= youtube && articles >= reels && articles > 0) {
      final pct = (articles / total * 100).round();
      list.add(
          '$pct% of your content is articles — you prefer reading over watching.');
    } else if (youtube >= reels && youtube > 0) {
      list.add('You lean towards YouTube videos for your analyses.');
    } else if (reels > 0) {
      list.add('Most of your analyses are short-form reels.');
    }

    if (realismChecks > 0) {
      if (totalFlags == 0) {
        list.add(
            'All $realismChecks fact-checked ${realismChecks == 1 ? 'piece' : 'pieces'} came back clean — no flagged claims.');
      } else {
        final avg = (totalFlags / realismChecks * 10).round() / 10;
        list.add(
            'On average, $avg ${avg == 1.0 ? 'claim was' : 'claims were'} flagged per fact-check.');
      }
    }

    if (topDomain != null) list.add('Your most analysed source is $topDomain.');

    if (list.length < 3) {
      final weekTotal = last7Days.reduce((a, b) => a + b);
      if (weekTotal > 0) {
        list.add(
            "You've run $weekTotal ${weekTotal == 1 ? 'analysis' : 'analyses'} in the past 7 days.");
      }
    }

    return list.take(3).toList();
  }
}

// ── Main content ──────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  final _InsightsData data;
  final ColorScheme scheme;
  final bool isDark;

  const _Content(
      {required this.data, required this.scheme, required this.isDark});

  Color get _cardBg => isDark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get _cardBorder =>
      isDark ? const Color(0xFF2A2A2C) : const Color(0xFFE5E5EA);

  @override
  Widget build(BuildContext context) {
    final insightsList = data.insights;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryRow(),
        const SizedBox(height: 16),
        _section('Content Type Breakdown', _donut()),
        const SizedBox(height: 16),
        _section('Analysis Types Used', _analysisTypes()),
        const SizedBox(height: 16),
        _section('Activity — Last 7 Days', _activity()),
        if (insightsList.isNotEmpty) ...[
          const SizedBox(height: 16),
          _insightCards(insightsList),
        ],
      ],
    );
  }

  // ── Summary cards ────────────────────────────────────────────────────────────

  Widget _summaryRow() {
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statCard('Alignments', '${data.total}', scheme.primary),
        const SizedBox(width: 10),
        _statCard(
            'Products Found', '${data.totalProducts}', const Color(0xFF34C759)),
        const SizedBox(width: 10),
        _statCard(
            'Flags Raised', '${data.totalFlags}', const Color(0xFFFF3B30)),
      ],
    ),
    );
  }

  Widget _statCard(String label, String value, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6),
          border: Border.all(color: _cardBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: AppTypography.statValue(color: accent),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section card wrapper ─────────────────────────────────────────────────────

  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6),
        border: Border.all(color: _cardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.sectionTitle(color: scheme.onSurface),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ── Donut chart ──────────────────────────────────────────────────────────────

  Widget _donut() {
    final total = data.total.toDouble();
    final sections = <PieChartSectionData>[];

    if (data.articles > 0) {
      sections.add(PieChartSectionData(
          value: data.articles.toDouble(),
          color: scheme.primary,
          radius: 28,
          title: ''));
    }
    if (data.youtube > 0) {
      sections.add(PieChartSectionData(
          value: data.youtube.toDouble(),
          color: const Color(0xFFFF3B30),
          radius: 28,
          title: ''));
    }
    if (data.reels > 0) {
      sections.add(PieChartSectionData(
          value: data.reels.toDouble(),
          color: const Color(0xFFBF5AF2),
          radius: 28,
          title: ''));
    }

    return Row(
      children: [
        SizedBox(
          width: 110,
          height: 110,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 32,
              sectionsSpace: sections.length > 1 ? 2 : 0,
              startDegreeOffset: -90,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data.articles > 0)
                _legendRow(scheme.primary, 'Article', data.articles, total),
              if (data.youtube > 0) ...[
                const SizedBox(height: 10),
                _legendRow(
                    const Color(0xFFFF3B30), 'YouTube', data.youtube, total),
              ],
              if (data.reels > 0) ...[
                const SizedBox(height: 10),
                _legendRow(
                    const Color(0xFFBF5AF2), 'Reel', data.reels, total),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label, int count, double total) {
    final pct = total > 0 ? (count / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: AppTypography.chipLabel(color: scheme.onSurface)),
        ),
        Text(
          '$pct%',
          style: AppTypography.dataLabel(color: scheme.onSurface),
        ),
        const SizedBox(width: 4),
        Text(
          '($count)',
          style: AppTypography.dataSmall(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ── Analysis type horizontal bars ────────────────────────────────────────────

  Widget _analysisTypes() {
    final items = [
      ('Realism Check', data.realismChecks),
      ('Identify Products', data.productIdentifications),
      ('Create Timeline', data.timelines),
      ('Find Similar', data.similarSearches),
    ];
    final maxVal = items.map((e) => e.$2).reduce(max);
    final trackColor =
        isDark ? const Color(0xFF2A2A2C) : const Color(0xFFE5E5EA);

    return Column(
      children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        final fraction = maxVal > 0 ? item.$2 / maxVal : 0.0;

        return Padding(
          padding: EdgeInsets.only(bottom: i < items.length - 1 ? 14 : 0),
          child: Row(
            children: [
              SizedBox(
                width: 118,
                child: Text(item.$1,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) => Stack(
                    children: [
                      Container(
                        height: 7,
                        width: constraints.maxWidth,
                        decoration: BoxDecoration(
                          color: trackColor,
                          borderRadius: SmoothBorderRadius(cornerRadius: 4, cornerSmoothing: 0.6),
                        ),
                      ),
                      if (fraction > 0)
                        Container(
                          height: 7,
                          width: constraints.maxWidth * fraction,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: SmoothBorderRadius(cornerRadius: 4, cornerSmoothing: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 20,
                child: Text(
                  '${item.$2}',
                  textAlign: TextAlign.right,
                  style: AppTypography.dataLabel(color: scheme.onSurface),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── 7-day bar chart ──────────────────────────────────────────────────────────

  Widget _activity() {
    final maxVal = data.last7Days.reduce(max);
    final maxY = max(1, maxVal + 1).toDouble();
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return SizedBox(
      height: 130,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: List.generate(7, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data.last7Days[i].toDouble(),
                  color: scheme.primary,
                  width: 26,
                  borderRadius: SmoothBorderRadius.only(
                    topLeft: SmoothRadius(cornerRadius: 6, cornerSmoothing: 0.6),
                    topRight: SmoothRadius(cornerRadius: 6, cornerSmoothing: 0.6),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: isDark
                        ? const Color(0xFF3A3A3C)
                        : const Color(0xFFEEEEF0),
                  ),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i > 6) return const SizedBox.shrink();
                  final date =
                      DateTime.now().subtract(Duration(days: 6 - i));
                  final label = i == 6 ? 'Today' : dayNames[date.weekday - 1];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: AppTypography.chartAxisLabel(
                        color: i == 6 ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
        ),
      ),
    );
  }


  Widget _insightCards(List<String> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Insights',
          style: AppTypography.sectionHeader(color: scheme.onSurface)
              .copyWith(fontSize: 15),
        ),
        const SizedBox(height: 10),
        ...list.map(
          (insight) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(isDark ? 28 : 18),
                borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
                border: Border.all(
                  color: scheme.primary.withAlpha(isDark ? 55 : 38),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(CupertinoIcons.lightbulb_fill,
                        size: 14, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      insight,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: scheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Skeleton loader ───────────────────────────────────────────────────────────

class _SkeletonBody extends StatelessWidget {
  final bool isDark;
  const _SkeletonBody({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA);

    Widget block(double height) => Container(
          width: double.infinity,
          height: height,
          decoration:
              BoxDecoration(color: c, borderRadius: SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6)),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: block(84)),
              const SizedBox(width: 10),
              Expanded(child: block(84)),
              const SizedBox(width: 10),
              Expanded(child: block(84)),
            ],
          ),
          const SizedBox(height: 16),
          block(176),
          const SizedBox(height: 16),
          block(158),
          const SizedBox(height: 16),
          block(178),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ColorScheme scheme;
  const _EmptyState({required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.chart_bar_fill,
                  color: scheme.primary, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              'No insights yet',
              style: AppTypography.navTitle(color: scheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              'Run your first alignment to start seeing personalised insights about your content.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 14, color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Activity heatmap ──────────────────────────────────────────────────────────

class _InsightsHeatmap extends StatefulWidget {
  final List<Map<String, dynamic>> alignments;
  final bool isDark;
  final ColorScheme scheme;

  const _InsightsHeatmap({
    required this.alignments,
    required this.isDark,
    required this.scheme,
  });

  @override
  State<_InsightsHeatmap> createState() => _InsightsHeatmapState();
}

class _InsightsHeatmapState extends State<_InsightsHeatmap> {
  static const _weeks = 16;
  static const _gap   = 3.0;

  int?      _tipCol;
  DateTime? _tipDate;
  int       _tipCount = 0;
  Timer?    _tipTimer;

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  Map<DateTime, int> _buildDayMap() {
    final map = <DateTime, int>{};
    for (final a in widget.alignments) {
      if (a['is_analyzing'] == true || a['status'] == 'failed') continue;
      final raw = a['created_at'] as String?;
      if (raw == null) continue;
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      map[day] = (map[day] ?? 0) + 1;
    }
    return map;
  }

  Color _cellColor(int count) {
    if (widget.isDark) {
      if (count == 0) return Colors.white.withValues(alpha: 0.06);
      if (count == 1) return const Color(0xFF1a3a5c);
      if (count <= 3) return const Color(0xFF1e6bb8);
      if (count <= 5) return const Color(0xFF2188ff);
      return const Color(0xFF79c0ff);
    } else {
      if (count == 0) return Colors.black.withValues(alpha: 0.07);
      if (count == 1) return const Color(0xFFBBDEFB);
      if (count <= 3) return const Color(0xFF64B5F6);
      if (count <= 5) return const Color(0xFF1E88E5);
      return const Color(0xFF0D47A1);
    }
  }

  void _showTip(int col, DateTime date, int count) {
    _tipTimer?.cancel();
    setState(() { _tipCol = col; _tipDate = date; _tipCount = count; });
    _tipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _tipCol = null);
    });
  }

  static String _mon(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];

  @override
  Widget build(BuildContext context) {
    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final todayRow = today.weekday - 1;
    final dayMap   = _buildDayMap();

    final legendColors = widget.isDark
        ? const [Color(0x0FFFFFFF), Color(0xFF1a3a5c), Color(0xFF1e6bb8), Color(0xFF2188ff), Color(0xFF79c0ff)]
        : const [Color(0x12000000), Color(0xFFBBDEFB), Color(0xFF64B5F6), Color(0xFF1E88E5), Color(0xFF0D47A1)];
    final mutedText = widget.scheme.onSurfaceVariant.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(builder: (_, constraints) {
        final step     = (constraints.maxWidth + _gap) / _weeks;
        final cellSize = step - _gap;
        final gridW    = constraints.maxWidth;
        final gridH    = 7 * step - _gap;

        // Month labels
        final monthLabels = <Widget>[];
        String? lastLbl;
        for (int col = 0; col < _weeks; col++) {
          final daysBack = ((_weeks - 1) - col) * 7 + todayRow;
          final monday   = today.subtract(Duration(days: daysBack));
          final lbl      = _mon(monday.month);
          if (lbl != lastLbl) {
            lastLbl = lbl;
            monthLabels.add(Positioned(
              left: col * step, top: 0,
              child: Text(lbl, style: GoogleFonts.inter(
                fontSize: 9,
                color: widget.scheme.onSurfaceVariant.withValues(alpha: 0.45),
              )),
            ));
          }
        }

        // Grid cells
        final cells = <Widget>[];
        for (int col = 0; col < _weeks; col++) {
          for (int row = 0; row < 7; row++) {
            final daysBack = ((_weeks - 1) - col) * 7 + (todayRow - row);
            final isFuture = daysBack < 0;
            final date     = today.subtract(Duration(days: daysBack));
            final count    = isFuture ? 0 : (dayMap[date] ?? 0);

            cells.add(Positioned(
              left: col * step, top: row * step,
              child: GestureDetector(
                onTap: isFuture ? null : () => _showTip(col, date, count),
                child: Container(
                  width: cellSize, height: cellSize,
                  decoration: BoxDecoration(
                    color: isFuture ? Colors.transparent : _cellColor(count),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ));
          }
        }

        // Tooltip
        Widget? tooltip;
        if (_tipCol != null && _tipDate != null) {
          final d   = _tipDate!;
          final lbl = _tipCount == 0
              ? 'No analyses · ${_mon(d.month)} ${d.day}'
              : '$_tipCount ${_tipCount == 1 ? 'analysis' : 'analyses'} · ${_mon(d.month)} ${d.day}';
          const tipW    = 150.0;
          final rawLeft = _tipCol! * step + cellSize / 2 - tipW / 2;
          final tipLeft = rawLeft.clamp(0.0, gridW - tipW);

          tooltip = Positioned(
            left: tipLeft, bottom: gridH + 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  width: tipW,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.13)
                        : Colors.black.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.09),
                      width: 0.5,
                    ),
                  ),
                  child: Text(lbl,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: widget.isDark ? Colors.white : const Color(0xFF1C1C1E),
                    )),
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: gridW, height: 14, child: Stack(children: monthLabels)),
            const SizedBox(height: 3),
            SizedBox(
              width: gridW, height: gridH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [...cells, if (tooltip != null) tooltip],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Less', style: GoogleFonts.inter(fontSize: 9, color: mutedText)),
                const SizedBox(width: 4),
                ...legendColors.map((c) => Container(
                  width: cellSize, height: cellSize,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(width: 4),
                Text('More', style: GoogleFonts.inter(fontSize: 9, color: mutedText)),
              ],
            ),
          ],
        );
      }),
    );
  }
}
