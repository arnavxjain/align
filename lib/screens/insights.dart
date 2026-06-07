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
import '../widgets/tappable.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsState();
}

class _InsightsState extends State<InsightsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (alignmentsNotifier.value.isEmpty) {
      await AnalysisService.loadAlignments();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: alignmentsNotifier,
        builder: (context, alignments, _) {
          final completed =
              alignments.where((e) => e['is_analyzing'] != true).toList();
          final data = _isLoading ? null : _InsightsData.compute(completed);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 66,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                automaticallyImplyLeading: false,
                flexibleSpace: ClipRect(
                  child: Stack(
                    children: [
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                        child: Container(
                            color: scaffoldBg.withAlpha(isDark ? 110 : 150)),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
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
                  padding: const EdgeInsets.only(left: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Tappable(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF2C2C2E).withValues(alpha: 0.7)
                              : const Color(0xFFE5E5EA).withValues(alpha: 0.7),
                        ),
                        child: Icon(CupertinoIcons.chevron_left,
                            color: scheme.onSurface, size: 16),
                      ),
                    ),
                  ),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Your Insights',
                      style: AppTypography.navTitle(color: scheme.onSurface),
                    ),
                    if (!_isLoading)
                      Text(
                        'Based on ${completed.length} ${completed.length == 1 ? 'alignment' : 'alignments'}',
                        style: AppTypography.dataSmall(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
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
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                    child: _Content(
                      data: data!,
                      scheme: scheme,
                      isDark: isDark,
                    ),
                  ),
                ),
            ],
          );
        },
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

  Color get _cardBg => isDark ? const Color(0xFF2C2C2E) : Colors.white;
  Color get _cardBorder =>
      isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);

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
        isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);

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
    final c = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

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
