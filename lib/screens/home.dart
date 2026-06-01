import 'dart:math';
import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/theme_notifier.dart';
import '../screens/alignment_detail.dart';
import '../screens/new_alignment.dart';
import '../services/analysis_service.dart';
import '../screens/insights.dart';
import '../screens/profile.dart';
import '../widgets/tappable.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

// null color → falls back to scheme.primary at runtime
const _kFilters = <(String, String, Color?, IconData?)>[
  ('youtube',  'YouTube',      Color(0xFFFF3B30), CupertinoIcons.play_rectangle_fill),
  ('reel',     'Reel',         Color(0xFFBF5AF2), CupertinoIcons.film_fill),
  ('article',  'Article',      null,              CupertinoIcons.doc_text_fill),
  ('2plus',    '2+ Analyses',  null,              null),
  ('24h',      'Last 24h',     null,              null),
];

class _HomeState extends State<Home> {
  final _user = Supabase.instance.client.auth.currentUser;
  String? _firstName;
  bool _isLoading = true;
  final Set<String> _activeFilters = {};

  String get _initial {
    final email = _user?.email ?? '';
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    final salutation = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    if (_firstName != null && _firstName!.isNotEmpty) {
      final name = _firstName![0].toUpperCase() + _firstName!.substring(1);
      return '$salutation, $name';
    }
    return salutation;
  }

  @override
  void initState() {
    super.initState();
    _loadFirstName();
    _loadAlignments();
    AnalysisService.loadStarred();
  }

  String _todayLabel() {
    final now = DateTime.now();
    final day = now.day;
    final suffix = (day >= 11 && day <= 13)
        ? 'th'
        : switch (day % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return '$day$suffix, ${weekdays[now.weekday - 1]}';
  }

  Future<void> _loadAlignments() async {
    await AnalysisService.loadAlignments();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<bool> _confirmDelete(BuildContext ctx) async {
    return await showCupertinoDialog<bool>(
          context: ctx,
          barrierDismissible: true,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Delete Alignment'),
            content: const Text(
                'This will permanently remove this alignment and all its analysis data.'),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _loadFirstName() async {
    final userId = _user?.id;
    if (userId == null) return;
    final data = await Supabase.instance.client
        .from('user_profiles')
        .select('first_name')
        .eq('id', userId)
        .maybeSingle();
    if (mounted && data != null) {
      setState(() => _firstName = data['first_name'] as String?);
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list) {
    if (_activeFilters.isEmpty) return list;
    return list.where((a) {
      final type = a['content_type'] as String? ?? 'article';
      final typeFilters = {'youtube', 'reel', 'article'}.intersection(_activeFilters);
      if (typeFilters.isNotEmpty && !typeFilters.contains(type)) return false;

      if (_activeFilters.contains('2plus')) {
        final raw = a['analyses'];
        final count = (raw is Map ? raw : {}).values.where((v) => v != null).length;
        if (count < 2) return false;
      }

      if (_activeFilters.contains('24h')) {
        final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
        if (dt == null || DateTime.now().difference(dt).inHours >= 24) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
      CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 78,
            toolbarHeight: 75,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            automaticallyImplyLeading: false,
            titleSpacing: 20,
            flexibleSpace: ClipRect(
              child: Stack(
                children: [
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      color: scaffoldBg.withAlpha(isDark ? 105 : 135),
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
            title: Row(
              children: [
                SvgPicture.asset(
                  'lib/assets/logo.svg',
                  width: 28,
                  height: 27,
                  colorFilter: ColorFilter.mode(scheme.onSurface, BlendMode.srcIn),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _greeting,
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            color: scheme.onSurface, size: 18),
                      ],
                    ),
                    Text(
                      _todayLabel(),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              Tappable(
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5EA),
                  ),
                  child: Icon(CupertinoIcons.star_fill,
                      color: scheme.onSurface, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Tappable(
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                  child: _Avatar(initial: _initial, primary: scheme.primary),
                ),
              ),
            ],
          ),

          if (!_isLoading)
            const SliverToBoxAdapter(child: SizedBox(height: 14)),

          if (!_isLoading)
            SliverPersistentHeader(
              pinned: true,
              delegate: _FilterBarDelegate(
                activeFilters: _activeFilters,
                onToggle: (key) => setState(() {
                  _activeFilters.contains(key)
                      ? _activeFilters.remove(key)
                      : _activeFilters.add(key);
                }),
                scheme: scheme,
                isDark: isDark,
                scaffoldBg: scaffoldBg,
              ),
            ),

          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: alignmentsNotifier,
                    builder: (context, alignments, _) {
                      if (alignments.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 150),
                          child: _EmptyState(scheme: scheme, isDark: isDark),
                        );
                      }
                      final filtered = _applyFilters(alignments);
                      return ValueListenableBuilder<Set<String>>(
                        valueListenable: starredNotifier,
                        builder: (context, starred, _) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 150),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Section label ─────────────────────────────
                                Padding(
                                  padding: const EdgeInsets.only(left: 24, bottom: 10),
                                  child: Text(
                                    _activeFilters.isEmpty
                                        ? 'Recent'
                                        : '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                // ── List with animated transition ─────────────
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 240),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(opacity: animation, child: child),
                                    child: filtered.isEmpty
                                        ? _NoFilterResults(
                                            key: const ValueKey('__empty__'),
                                            scheme: scheme,
                                          )
                                        : Column(
                                            key: ValueKey(_activeFilters.join(',')),
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: List.generate(filtered.length, (i) {
                                              final alignment = filtered[i];
                                              final id = alignment['id'] as String? ?? '$i';
                                              final isAnalysing = alignment['is_analyzing'] == true;
                                              return Padding(
                                                padding: EdgeInsets.only(
                                                    bottom: i < filtered.length - 1 ? 10 : 0),
                                                child: Dismissible(
                                                  key: ValueKey(id),
                                                  direction: DismissDirection.endToStart,
                                                  background: const _DeleteBackground(),
                                                  confirmDismiss: isAnalysing
                                                      ? null
                                                      : (_) => _confirmDelete(context),
                                                  onDismissed: isAnalysing
                                                      ? null
                                                      : (_) => AnalysisService.deleteAlignment(id),
                                                  child: _AlignmentTile(
                                                    alignment: alignment,
                                                    isStarred: starred.contains(id),
                                                    isAnalysing: isAnalysing,
                                                    isDark: isDark,
                                                    scheme: scheme,
                                                    onTap: () => Navigator.push(
                                                      context,
                                                      CupertinoPageRoute(
                                                        builder: (_) => AlignmentDetailScreen(
                                                            alignmentId: id),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
          // ── Floating nav bar ──────────────────────────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Center(
                  child: _NavBar(scheme: scheme, isDark: isDark),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Floating nav bar ─────────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  final ColorScheme scheme;
  final bool isDark;

  const _NavBar({required this.scheme, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final inactiveBg = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6);
    final inactiveIcon = isDark ? Colors.white70 : const Color(0xFF636366);
    final borderColor = isDark
        ? Colors.white.withAlpha(30)
        : Colors.black.withAlpha(20);
    final bgColor = isDark
        ? const Color(0xFF1C1C1E).withAlpha(200)
        : Colors.white.withAlpha(210);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 40),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: borderColor, width: 0.7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tappable(
                  onTap: () {},
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(color: inactiveBg.withValues(alpha: 0.5), shape: BoxShape.circle),
                    child: Icon(PhosphorIcons.cube, color: inactiveIcon, size: 18),
                  ),
                ),
                const SizedBox(width: 6),
                Tappable(
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const InsightsScreen()),
                  ),
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(color: inactiveBg.withValues(alpha: 0.5), shape: BoxShape.circle),
                    child: Icon(PhosphorIcons.chartBarFill, color: inactiveIcon, size: 18),
                  ),
                ),
                const SizedBox(width: 6),
                Tappable(
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const NewAlignmentScreen()),
                  ),
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.9), shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.plus, color: scheme.onPrimary, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Alignment list tile ───────────────────────────────────────────────────────

class _AlignmentTile extends StatefulWidget {
  final Map<String, dynamic> alignment;
  final bool isStarred;
  final bool isAnalysing;
  final bool isDark;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _AlignmentTile({
    required this.alignment,
    required this.isStarred,
    required this.isAnalysing,
    required this.isDark,
    required this.scheme,
    required this.onTap,
  });

  @override
  State<_AlignmentTile> createState() => _AlignmentTileState();
}

class _AlignmentTileState extends State<_AlignmentTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isAnalysing) _sweep.repeat();
  }

  @override
  void didUpdateWidget(_AlignmentTile old) {
    super.didUpdateWidget(old);
    if (widget.isAnalysing && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.isAnalysing && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  static (IconData, Color, String) _typeConfig(
          String type, ColorScheme scheme) =>
      switch (type) {
        'youtube' => (
            CupertinoIcons.play_rectangle_fill,
            const Color(0xFFFF3B30),
            'YouTube'
          ),
        'reel' => (CupertinoIcons.film_fill, const Color(0xFFBF5AF2), 'Reel'),
        _ => (CupertinoIcons.doc_text_fill, scheme.primary, 'Article'),
      };

  static String _domain(String url) {
    try {
      final h = Uri.parse(url).host.replaceAll('www.', '');
      return h.isNotEmpty ? h : url;
    } catch (_) {
      return url.length > 30 ? '${url.substring(0, 30)}…' : url;
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

  @override
  Widget build(BuildContext context) {
    final url = widget.alignment['url'] as String? ?? '';
    final title = widget.alignment['title'] as String?;
    final contentType =
        widget.alignment['content_type'] as String? ?? 'article';
    final createdAt = widget.alignment['created_at'] as String? ?? '';
    final raw = widget.alignment['analyses'];
    final analyses = raw is Map ? raw : {};
    final count = analyses.values.where((v) => v != null).length;

    final displayTitle =
        (title != null && title.isNotEmpty) ? title : _domain(url);
    final (icon, color, typeLabel) =
        _typeConfig(contentType, widget.scheme);

    Widget tile = Tappable(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: ShapeDecoration(
          color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: SmoothRectangleBorder(
            borderRadius:
                SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6),
            side: BorderSide(
              color: widget.isDark
                  ? const Color(0xFF3A3A3C)
                  : const Color(0xFFE5E5EA),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: color.withAlpha(widget.isDark ? 40 : 25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: widget.scheme.onSurface,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  widget.isAnalysing
                      ? Text(
                          '$typeLabel · Analysing…',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: widget.scheme.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : Text(
                          '$typeLabel · $count ${count == 1 ? 'Analysis' : 'Analyses'}',
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: widget.scheme.onSurfaceVariant),
                        ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isStarred) ...[
                      const Icon(CupertinoIcons.star_fill,
                          size: 11, color: Color(0xFFFF9F0A)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _relativeTime(createdAt),
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: widget.scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Icon(CupertinoIcons.chevron_right,
                    color: widget.scheme.onSurfaceVariant, size: 14),
              ],
            ),
          ],
        ),
      ),
    );

    if (!widget.isAnalysing) return tile;

    // Wrap with animated sweep border while analysing.
    return Stack(
      children: [
        tile,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (_, __) => CustomPaint(
                painter: _SweepBorderPainter(
                  progress: _sweep.value,
                  color: widget.scheme.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Rotating sweep border painter ────────────────────────────────────────────

class _SweepBorderPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _SweepBorderPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 1.5;
    final sweepAngle = 2 * pi * progress;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final shader = SweepGradient(
      center: FractionalOffset.center,
      startAngle: sweepAngle,
      endAngle: sweepAngle + 2 * pi,
      colors: [
        color.withAlpha(0),
        color.withAlpha(200),
        color,
        color.withAlpha(200),
        color.withAlpha(0),
      ],
      stops: const [0.0, 0.18, 0.5, 0.82, 1.0],
    ).createShader(rect);

    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final path = SmoothRectangleBorder(
      borderRadius:
          SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6),
    ).getOuterPath(rect.deflate(strokeWidth / 2));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SweepBorderPainter old) => old.progress != progress;
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ColorScheme scheme;
  final bool isDark;

  const _EmptyState({required this.scheme, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.link,
                  color: scheme.onSurfaceVariant, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              'No alignments yet',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap + to analyse your first link',
              style: GoogleFonts.inter(
                  fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sticky filter bar ─────────────────────────────────────────────────────────

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final Set<String> activeFilters;
  final ValueChanged<String> onToggle;
  final ColorScheme scheme;
  final bool isDark;
  final Color scaffoldBg;

  const _FilterBarDelegate({
    required this.activeFilters,
    required this.onToggle,
    required this.scheme,
    required this.isDark,
    required this.scaffoldBg,
  });

  @override
  double get minExtent => 58;
  @override
  double get maxExtent => 58;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: scaffoldBg.withAlpha(isDark ? 155 : 195),
            ),
          ),
          Align(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _kFilters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (key, label, chipColor, icon) = _kFilters[i];
                  final active = activeFilters.contains(key);
                  final color = chipColor ?? scheme.primary;
                  return _FilterChip(
                    label: label,
                    active: active,
                    color: color,
                    icon: icon,
                    isDark: isDark,
                    onTap: () => onToggle(key),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: overlapsContent ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                height: 0.5,
                color: isDark
                    ? const Color(0xFF424242)
                    : const Color(0xFFD1D1D6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_FilterBarDelegate old) => true;
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final IconData? icon;
  final bool isDark;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inactiveBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final inactiveBorder = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
    final contentColor = active ? Colors.white : scheme.onSurfaceVariant;

    return Tappable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? color : inactiveBg,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: active ? color : inactiveBorder,
            width: 1,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: active ? Colors.white : color),
                const SizedBox(width: 5),
              ],
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: contentColor,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── No filter results ─────────────────────────────────────────────────────────

class _NoFilterResults extends StatelessWidget {
  final ColorScheme scheme;
  const _NoFilterResults({super.key, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.slash_circle,
                color: scheme.onSurfaceVariant, size: 28),
            const SizedBox(height: 12),
            Text(
              'No matching alignments',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your filters',
              style: GoogleFonts.inter(
                  fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: ShapeDecoration(
            color: Colors.redAccent,
            shape: SmoothRectangleBorder(
              borderRadius:
                  SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.trash_fill,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Delete',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String initial;
  final Color primary;

  const _Avatar({required this.initial, required this.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: primary, width: 2),
      ),
      child: Container(
        width: 28, height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment(-0.7, -0.9),
            end: Alignment(0.7, 0.9),
            colors: [Color(0xFF8E8E93), Color(0xFF3A3A3C)],
          ),
        ),
        child: const Center(
          child: Icon(CupertinoIcons.person_fill, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
