import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:align/screens/globe_screen.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_typography.dart';
import '../providers/theme_notifier.dart';
import '../screens/alignment_detail.dart';
import '../screens/milestone_modal.dart';
import '../screens/new_alignment.dart';
import '../screens/paywall_screen.dart';
import '../services/analysis_service.dart';
import '../services/milestone_service.dart';
import '../screens/insights.dart';
import '../screens/profile.dart';
import '../utils/transitions.dart';
import '../widgets/toast.dart';
import '../widgets/tappable.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

const _kFilters = <(String, String, Color?, IconData?)>[
  ('youtube',  'YouTube',      Colors.red, CupertinoIcons.play_rectangle_fill),
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
  int _prevCompletedCount = 0;
  Set<String> _inProgressIds = {};
  bool _initialLoadDone = false;


  late final TextEditingController _searchCtrl;
  String _searchQuery = '';

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
    _searchCtrl = TextEditingController()
      ..addListener(() {
        if (_searchQuery != _searchCtrl.text) {
          setState(() => _searchQuery = _searchCtrl.text);
        }
      });
    _loadFirstName();
    _loadAlignments();
    AnalysisService.loadStarred();
    alignmentsNotifier.addListener(_onAlignmentsChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    alignmentsNotifier.removeListener(_onAlignmentsChanged);
    super.dispose();
  }

  void _onAlignmentsChanged() {
    if (!_initialLoadDone) return;
    final alignments = alignmentsNotifier.value;

    final currentInProgress = alignments
        .where((a) => a['is_analyzing'] == true)
        .map((a) => a['id'] as String)
        .toSet();

    // IDs that just transitioned from in-progress to complete (not failed).
    final justFinished = _inProgressIds.difference(currentInProgress);
    for (final id in justFinished) {
      final entry =
          alignments.firstWhere((a) => a['id'] == id, orElse: () => {});
      if (entry.isEmpty || entry['status'] == 'failed') continue;
      if (mounted) {
        ToastService.show(
          context,
          message: 'Analysis complete',
          icon: CupertinoIcons.checkmark_circle_fill,
          iconColor: const Color(0xFF30D158),
          onTap: () => Navigator.push(
            context,
            AppRoute.push(AlignmentDetailScreen(alignmentId: id)),
          ),
        );
      }
    }

    _inProgressIds = currentInProgress;

    final completed = alignments
        .where((a) => a['is_analyzing'] != true && a['status'] != 'failed')
        .length;
    if (completed > _prevCompletedCount) {
      _prevCompletedCount = completed;
      _checkMilestones(completed);
    }
  }

  Future<void> _checkMilestones(int count) async {
    if (!mounted) return;
    final unseen = await MilestoneService.firstUnseenMilestone(count);
    if (unseen != null && mounted) {
      await MilestoneService.markSeen(unseen.count);
      if (mounted) await MilestoneModal.show(context, unseen);
    }
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
    if (mounted) {
      _inProgressIds = alignmentsNotifier.value
          .where((a) => a['is_analyzing'] == true)
          .map((a) => a['id'] as String)
          .toSet();
      _prevCompletedCount = alignmentsNotifier.value
          .where((a) => a['is_analyzing'] != true && a['status'] != 'failed')
          .length;
      _initialLoadDone = true;
      setState(() => _isLoading = false);
    }
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
    return list.where((a) {
      // Search query
      if (_searchQuery.isNotEmpty && !_matchesSearch(a, _searchQuery)) {
        return false;
      }

      if (_activeFilters.isEmpty) return true;

      final type = a['content_type'] as String? ?? 'article';
      final typeFilters =
          {'youtube', 'reel', 'article'}.intersection(_activeFilters);
      if (typeFilters.isNotEmpty && !typeFilters.contains(type)) return false;

      if (_activeFilters.contains('2plus')) {
        final raw = a['analyses'];
        final count =
            (raw is Map ? raw : {}).values.where((v) => v != null).length;
        if (count < 2) return false;
      }

      if (_activeFilters.contains('24h')) {
        final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
        if (dt == null || DateTime.now().difference(dt).inHours >= 24) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  static bool _matchesSearch(Map<String, dynamic> a, String q) {
    final lower = q.toLowerCase();

    if ((a['title'] as String? ?? '').toLowerCase().contains(lower)) return true;
    if ((a['content_type'] as String? ?? '').toLowerCase().contains(lower)) return true;

    for (final c in (a['countries'] as List? ?? [])) {
      if ((c['code'] as String? ?? '').toLowerCase().contains(lower)) return true;
      if ((c['reason'] as String? ?? '').toLowerCase().contains(lower)) return true;
    }

    final analyses = a['analyses'] as Map? ?? {};

    for (final p in (analyses['products'] as List? ?? [])) {
      if ((p['product'] as String? ?? '').toLowerCase().contains(lower)) return true;
      if ((p['brand'] as String? ?? '').toLowerCase().contains(lower)) return true;
    }

    for (final c in (analyses['realism_check'] as List? ?? [])) {
      if ((c['claim'] as String? ?? '').toLowerCase().contains(lower)) return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
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
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: scaffoldBg.withAlpha(isDark ? 80 : 110),
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
                  height: 29,
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
                          style: AppTypography.navTitle(color: scheme.onSurface),
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
                scaleOnPress: true,
                onTap: () => Navigator.push(
                  context,
                  AppRoute.modal(const PaywallScreen()),
                ),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5EA),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'lib/assets/logo-pro.svg',
                      // width: 20,
                      height: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Tappable(
                  onTap: () => Navigator.push(
                    context,
                    AppRoute.push(const ProfileScreen()),
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
                searchController: _searchCtrl,
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
                          final featuredItem = filtered.first;
                          final restItems = filtered.length > 1
                              ? filtered.sublist(1)
                              : <Map<String, dynamic>>[];
                          final featuredId = featuredItem['id'] as String? ?? '';

                          return Padding(
                            padding: const EdgeInsets.only(top: 20, bottom: 150),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(opacity: animation, child: child),
                                  child: filtered.isEmpty
                                      ? Padding(
                                          key: const ValueKey('__no_results__'),
                                          padding: const EdgeInsets.symmetric(horizontal: 20),
                                          child: _searchQuery.isNotEmpty
                                              ? _NoSearchResults(
                                                  key: const ValueKey('__search_empty__'),
                                                  scheme: scheme,
                                                )
                                              : _NoFilterResults(
                                                  key: const ValueKey('__empty__'),
                                                  scheme: scheme,
                                                ),
                                        )
                                      : Column(
                                          key: ValueKey(
                                              'list_${_activeFilters.join(',')}_$_searchQuery'),
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Featured card
                                            Center(
                                              child: _FeaturedCard(
                                                alignment: featuredItem,
                                                isStarred: starred.contains(featuredId),
                                                isDark: isDark,
                                                scheme: scheme,
                                                onTap: () => Navigator.push(
                                                  context,
                                                  AppRoute.push(
                                                    AlignmentDetailScreen(alignmentId: featuredId),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (restItems.isNotEmpty) ...[
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: Container(
                                                        height: 0.5,
                                                        color: scheme.onSurfaceVariant
                                                            .withValues(alpha: 0.2),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 12),
                                                      child: Text(
                                                        'RECENT',
                                                        style: AppTypography.categoryLabel(
                                                          color: scheme.onSurfaceVariant
                                                              .withValues(alpha: 0.45),
                                                        ).copyWith(letterSpacing: 3.4),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Container(
                                                        height: 0.5,
                                                        color: scheme.onSurfaceVariant
                                                            .withValues(alpha: 0.2),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                                child: Column(
                                                  children: List.generate(restItems.length, (i) {
                                                    final alignment = restItems[i];
                                                    final id = alignment['id'] as String? ?? '$i';
                                                    final isAnalysing =
                                                        alignment['is_analyzing'] == true;
                                                    final isFailed =
                                                        alignment['status'] == 'failed';
                                                    return Padding(
                                                      padding: const EdgeInsets.only(bottom: 10),
                                                      child: Dismissible(
                                                        key: ValueKey(id),
                                                        direction: DismissDirection.endToStart,
                                                        background: const _DeleteBackground(),
                                                        confirmDismiss: isAnalysing
                                                            ? null
                                                            : (_) => _confirmDelete(context),
                                                        onDismissed: isAnalysing
                                                            ? null
                                                            : (_) => AnalysisService
                                                                .deleteAlignment(id),
                                                        child: _AlignmentTile(
                                                          key: ValueKey('tile_$id'),
                                                          index: i,
                                                          alignment: alignment,
                                                          isStarred: starred.contains(id),
                                                          isAnalysing: isAnalysing,
                                                          isFailed: isFailed,
                                                          isDark: isDark,
                                                          scheme: scheme,
                                                          onTap: isFailed
                                                              ? null
                                                              : () => Navigator.push(
                                                                    context,
                                                                    AppRoute.push(
                                                                      AlignmentDetailScreen(
                                                                          alignmentId: id),
                                                                    ),
                                                                  ),
                                                          onRetry: isFailed
                                                              ? () {
                                                                  final entry =
                                                                      AnalysisService
                                                                          .resetForRetry(id);
                                                                  if (entry != null) {
                                                                    AnalysisService
                                                                        .runAnalysis(
                                                                            pendingEntry: entry)
                                                                        .catchError((_) {});
                                                                  }
                                                                }
                                                              : null,
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                ),
                                              ),
                                            ],
                                          ],
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
        ? Colors.white.withAlpha(50)
        : Colors.black.withAlpha(35);
    final bgColor = isDark
        ? const Color(0xFF1C1C1E).withAlpha(140)
        : Colors.white.withAlpha(160);

    return Container(
      decoration: BoxDecoration(
        borderRadius: SmoothBorderRadius(cornerRadius: 50, cornerSmoothing: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 40),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipSmoothRect(
        radius: SmoothBorderRadius(cornerRadius: 50, cornerSmoothing: 0.6),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: SmoothBorderRadius(cornerRadius: 50, cornerSmoothing: 0.6),
              border: Border.all(color: borderColor, width: 0.7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tappable(
                  scaleOnPress: true,
                  onTap: () => Navigator.push(
                    context,
                    AppRoute.push(const GlobeScreen()),
                  ),
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(color: inactiveBg.withValues(alpha: 0.5), shape: BoxShape.circle),
                    child: Icon(CupertinoIcons.globe, color: inactiveIcon, size: 18),
                  ),
                ),
                const SizedBox(width: 6),
                Tappable(
                  scaleOnPress: true,
                  onTap: () => Navigator.push(
                    context,
                    AppRoute.push(const InsightsScreen()),
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
                  scaleOnPress: true,
                  onTap: () => Navigator.push(
                    context,
                    AppRoute.modal(const NewAlignmentScreen()),
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
  final bool isFailed;
  final bool isDark;
  final ColorScheme scheme;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final int index;

  const _AlignmentTile({
    required this.alignment,
    required this.isStarred,
    required this.isAnalysing,
    required this.isFailed,
    required this.isDark,
    required this.scheme,
    required this.onTap,
    required this.index,
    this.onRetry,
    super.key,
  });

  @override
  State<_AlignmentTile> createState() => _AlignmentTileState();
}

class _AlignmentTileState extends State<_AlignmentTile>
    with TickerProviderStateMixin {
  late AnimationController _sweep;
  late AnimationController _entry;
  late Animation<double> _entryFade;
  late Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isAnalysing) _sweep.repeat();

    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _entryFade = CurvedAnimation(parent: _entry, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));

    final delay = widget.index.clamp(0, 5) * 40;
    if (delay == 0) {
      _entry.forward();
    } else {
      Future.delayed(Duration(milliseconds: delay), () {
        if (mounted) _entry.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_AlignmentTile old) {
    super.didUpdateWidget(old);
    if (widget.isAnalysing && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if ((!widget.isAnalysing || widget.isFailed) && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _entry.dispose();
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

  @override
  Widget build(BuildContext context) {
    final url = widget.alignment['url'] as String? ?? '';
    final title = widget.alignment['title'] as String?;
    final contentType =
        widget.alignment['content_type'] as String? ?? 'article';
    final raw = widget.alignment['analyses'];
    final analyses = raw is Map ? raw : {};
    final count = analyses.values.where((v) => v != null).length;

    final displayTitle =
        (title != null && title.isNotEmpty) ? title : _domain(url);
    final (icon, color, typeLabel) = _typeConfig(contentType, widget.scheme);
    const failedRed = Color(0xFFFF3B30);

    Widget tile = Tappable(
      onTap: widget.onTap,
      scaleOnPress: widget.onTap != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: ShapeDecoration(
          color: widget.isFailed
              ? failedRed.withValues(alpha: widget.isDark ? 0.07 : 0.04)
              : widget.isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.03),
          shape: SmoothRectangleBorder(
            borderRadius:
                SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6),
            side: widget.isFailed
                ? BorderSide(
                    color: failedRed.withValues(alpha: 0.25), width: 0.7)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.isFailed
                    ? failedRed.withValues(alpha: widget.isDark ? 0.15 : 0.1)
                    : color.withValues(alpha: widget.isDark ? 0.12 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.isFailed ? CupertinoIcons.exclamationmark_circle : icon,
                color: widget.isFailed ? failedRed : color,
                size: 16,
              ),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: widget.scheme.onSurface.withValues(alpha: 0.85),
                      height: 1.3,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  widget.isAnalysing
                      ? Text(
                          '$typeLabel · Analysing…',
                          style: AppTypography.contentTypeLabel(color: widget.scheme.primary)
                              .copyWith(fontStyle: FontStyle.italic),
                        )
                      : widget.isFailed
                          ? Text(
                              '$typeLabel · Analysis failed',
                              style: AppTypography.contentTypeLabel(
                                color: failedRed.withValues(alpha: 0.8),
                              ),
                            )
                          : Text(
                              '$typeLabel · $count ${count == 1 ? 'Analysis' : 'Analyses'}',
                              style: AppTypography.contentTypeLabel(
                                color: widget.isDark
                                    ? Colors.white.withValues(alpha: 0.35)
                                    : Colors.black.withValues(alpha: 0.35),
                              ),
                            ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isFailed && widget.onRetry != null)
              Tappable(
                onTap: widget.onRetry,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: failedRed.withValues(
                        alpha: widget.isDark ? 0.15 : 0.1),
                  ),
                  child: const Icon(
                    CupertinoIcons.arrow_clockwise,
                    size: 14,
                    color: failedRed,
                  ),
                ),
              )
            else if (widget.isStarred)
              const Icon(CupertinoIcons.star_fill,
                  size: 11, color: Color(0xFFFF9F0A)),
          ],
        ),
      ),
    );

    final Widget body = widget.isAnalysing
        ? Stack(
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
          )
        : tile;

    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: body,
      ),
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
              style: AppTypography.navTitle(color: scheme.onSurface),
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
  final TextEditingController searchController;
  final ValueChanged<String> onToggle;
  final ColorScheme scheme;
  final bool isDark;
  final Color scaffoldBg;

  const _FilterBarDelegate({
    required this.activeFilters,
    required this.searchController,
    required this.onToggle,
    required this.scheme,
    required this.isDark,
    required this.scaffoldBg,
  });

  @override
  double get minExtent => 128;
  @override
  double get maxExtent => 128;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 55 : 22),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: scaffoldBg.withAlpha(isDark ? 110 : 150),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Search bar ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _SearchBar(
                    controller: searchController,
                    scheme: scheme,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(height: 14),
                // ── Filter chips ───────────────────────────────────────
                SizedBox(
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
                  const SizedBox(height: 12),
                ],
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
      ),
    );
  }

  @override
  bool shouldRebuild(_FilterBarDelegate old) => true;
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatefulWidget {
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
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.active ? 1.0 : 0.0,
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(_FilterChip old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inactiveBorder = widget.isDark
        ? const Color(0xFF3A3A3C)
        : Colors.grey.withValues(alpha: 0.25);

    return Tappable(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, __) {
          final v = _t.value;
          final contentColor =
              Color.lerp(scheme.onSurfaceVariant, Colors.white, v)!;
          return Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.transparent,
                widget.color.withValues(alpha: 0.3),
                v,
              ),
              borderRadius: SmoothBorderRadius(cornerRadius: 50, cornerSmoothing: 0.6),
              border: Border.all(
                color: Color.lerp(inactiveBorder, widget.color, v)!,
                width: 1,
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 13, color: Color.lerp(widget.color, Colors.white, v)!),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    widget.label,
                    style: AppTypography.chipLabel(color: contentColor),
                  ),
                ],
              ),
            ),
          );
        },
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
              style: AppTypography.navTitle(color: scheme.onSurface)
                  .copyWith(fontSize: 15, fontWeight: FontWeight.w500),
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

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  final TextEditingController controller;
  final ColorScheme scheme;
  final bool isDark;

  const _SearchBar({
    required this.controller,
    required this.scheme,
    required this.isDark,
  });

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    return ClipSmoothRect(
      radius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
      child: Container(
        height: 46,
        decoration: ShapeDecoration(
          color: widget.isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
          shape: SmoothRectangleBorder(
            borderRadius:
                SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
            side: BorderSide(color: borderColor, width: 0.6),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 12),
            Icon(
              CupertinoIcons.search,
              size: 16,
              color: widget.scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: TextField(
                controller: widget.controller,
                textAlignVertical: TextAlignVertical.center,
                style: GoogleFonts.inter(
                    fontSize: 14, color: widget.scheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search alignments…',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color:
                        widget.scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            if (widget.controller.text.isNotEmpty) ...[
              GestureDetector(
                onTap: widget.controller.clear,
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 15,
                  color: widget.scheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

// ── No search results ─────────────────────────────────────────────────────────

class _NoSearchResults extends StatelessWidget {
  final ColorScheme scheme;
  const _NoSearchResults({super.key, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.search, color: scheme.onSurfaceVariant, size: 28),
            const SizedBox(height: 12),
            Text(
              'No alignments found',
              style: AppTypography.navTitle(color: scheme.onSurface)
                  .copyWith(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search term',
              style: GoogleFonts.inter(
                  fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Delete background ─────────────────────────────────────────────────────────

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

// ── Alignment cascade deck ──────────────────────────────────────────────────────

// Fixed 3D slot transforms: [rotateY, translateX, translateY, translateZ, scale, opacity]
// ── Featured card ─────────────────────────────────────────────────────────────


class SlantedCardClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const radius = 22.0;
    const slope = 28.0;
    const inset = 24.0;

    final path = Path()
      ..moveTo(radius, 0)

    // top edge
      ..lineTo(size.width - inset, slope)

    // right edge
      ..lineTo(size.width - inset, size.height - slope)

    // bottom edge
      ..lineTo(radius, size.height)

    // bottom-left rounded corner
      ..quadraticBezierTo(
        0,
        size.height,
        0,
        size.height - radius,
      )

    // left edge
      ..lineTo(0, radius)

    // top-left rounded corner
      ..quadraticBezierTo(
        0,
        0,
        radius,
        0,
      )

      ..close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class SlantedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const radius = 22.0;
    const slope = 28.0;
    const inset = 24.0;

    final path = Path()
      ..moveTo(radius, 0)
      ..lineTo(size.width - inset, slope)
      ..lineTo(size.width - inset, size.height - slope)
      ..lineTo(radius, size.height)
      ..quadraticBezierTo(
        0,
        size.height,
        0,
        size.height - radius,
      )
      ..lineTo(0, radius)
      ..quadraticBezierTo(
        0,
        0,
        radius,
        0,
      )
      ..close();

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.08);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}


class _FeaturedCard extends StatelessWidget {
  final Map<String, dynamic> alignment;
  final bool isStarred;
  final bool isDark;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _FeaturedCard({
    required this.alignment,
    required this.isStarred,
    required this.isDark,
    required this.scheme,
    required this.onTap,
  });

  static String _relativeTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  static String _domain(String url) {
    try {
      final h = Uri.parse(url).host.replaceAll('www.', '');
      return h.isNotEmpty ? h : url;
    } catch (_) {
      return url.length > 30 ? '${url.substring(0, 30)}…' : url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth * 0.65;
    const cardHeight = 200.0;

    final url = alignment['url'] as String? ?? '';
    final title = alignment['title'] as String?;
    final contentType = alignment['content_type'] as String? ?? 'article';
    final thumbnailUrl = alignment['thumbnail'] as String?;
    final createdAt = alignment['created_at'] as String?;
    final raw = alignment['analyses'];
    final analyses = raw is Map ? raw : {};
    final count = analyses.values.where((v) => v != null).length;
    final isAnalysing = alignment['is_analyzing'] == true;
    final isFailed = alignment['status'] == 'failed';
    final displayTitle = (title != null && title.isNotEmpty) ? title : _domain(url);

    final (IconData typeIcon, Color typeColor, String typeLabel) = switch (contentType) {
      'youtube' => (CupertinoIcons.play_rectangle_fill, const Color(0xFFFF3B30), 'YouTube'),
      'reel'    => (CupertinoIcons.film_fill, const Color(0xFFBF5AF2), 'Reel'),
      _         => (CupertinoIcons.doc_text_fill, scheme.primary, 'Article'),
    };
    const failedRed = Color(0xFFFF3B30);
    final effectiveTypeColor = isFailed ? failedRed : typeColor;

    return GestureDetector(
      onTap: isFailed ? null : onTap,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.skewY(-0.35),
        child: Container(
          width: cardWidth,
          height: cardHeight,
          margin: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 18,
          ),
          decoration: ShapeDecoration(
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 32,
                spreadRadius: 0,
                offset: const Offset(0, 14),
              ),
            ],
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 22,
                cornerSmoothing: 0.6,
              ),
            ),
          ),
          child: ClipSmoothRect(
            radius: SmoothBorderRadius(
              cornerRadius: 22,
              cornerSmoothing: 0.6,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
                  Positioned.fill(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: 20,
                        sigmaY: 20,
                      ),
                      child: Image.network(
                        thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                        const SizedBox.shrink(),
                      ),
                    ),
                  ),

                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 12,
                      sigmaY: 12,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: effectiveTypeColor.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFailed
                                  ? CupertinoIcons.exclamationmark_circle
                                  : typeIcon,
                              color: effectiveTypeColor,
                              size: 14,
                            ),
                          ),
                          const Spacer(),
                          if (isStarred) ...[
                            const Icon(
                              CupertinoIcons.star_fill,
                              size: 12,
                              color: Color(0xFFFF9F0A),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            _relativeTime(createdAt),
                            style: AppTypography.dataSmall(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.heading2(
                          color: Colors.white,
                        ).copyWith(
                          fontSize: 18,
                          height: 1.25,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          if (isAnalysing)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.25),
                                borderRadius:
                                BorderRadius.circular(50),
                              ),
                              child: Text(
                                'Analysing…',
                                style: AppTypography.dataSmall(
                                  color: scheme.primary,
                                ).copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            )
                          else if (isFailed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: failedRed.withValues(alpha: 0.2),
                                borderRadius:
                                BorderRadius.circular(50),
                              ),
                              child: Text(
                                'Failed',
                                style: AppTypography.dataSmall(
                                  color: failedRed,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius:
                                BorderRadius.circular(50),
                              ),
                              child: Text(
                                '$count ${count == 1 ? 'Analysis' : 'Analyses'}',
                                style: AppTypography.dataSmall(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),

                          const SizedBox(width: 8),

                          Text(
                            typeLabel,
                            style: AppTypography.contentTypeLabel(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
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
