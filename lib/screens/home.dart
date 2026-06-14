import 'dart:async';
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
import '../screens/creative_space.dart';
import '../screens/milestone_modal.dart';
import '../screens/new_alignment.dart';

import '../services/analysis_service.dart';
import '../services/auth_service.dart';
import '../services/milestone_service.dart';
import '../screens/insights.dart';
import '../screens/profile.dart';
import '../utils/transitions.dart';
import '../widgets/alignment_info_modal.dart';
import '../widgets/card_actions_modal.dart';
import '../widgets/delete_confirm_modal.dart';
import '../widgets/toast.dart';
import '../widgets/tappable.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

const _kFilters = <(String, String, Color?, IconData?)>[
  ('starred', 'Starred', Color(0xFFFF9F0A), CupertinoIcons.star_fill),
  ('youtube', 'YouTube', Colors.red, CupertinoIcons.play_rectangle_fill),
  ('reel', 'Reel', Color(0xFFBF5AF2), CupertinoIcons.film_fill),
  ('article', 'Article', null, CupertinoIcons.doc_text_fill),
  ('2plus', '2+ Analyses', null, null),
  ('24h', 'Last 24h', null, null),
];

class _HomeState extends State<Home> {
  final _user = Supabase.instance.client.auth.currentUser;
  String? _firstName;
  bool _isLoading = true;
  final Set<String> _activeFilters = {};
  int _prevCompletedCount = 0;
  Set<String> _inProgressIds = {};
  bool _initialLoadDone = false;

  Map<String, dynamic>? _activeDeckAlignment;
  final _homeScrollCtrl = ScrollController();
  bool _appBarBorderVisible = false;

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
    _homeScrollCtrl.addListener(_onHomeScroll);
    _loadFirstName();
    _loadAlignments();
    AnalysisService.loadStarred();
    alignmentsNotifier.addListener(_onAlignmentsChanged);
  }

  void _onHomeScroll() {
    final show = _homeScrollCtrl.offset > 2;
    if (show != _appBarBorderVisible) {
      setState(() => _appBarBorderVisible = show);
    }
  }

  @override
  void dispose() {
    _homeScrollCtrl.removeListener(_onHomeScroll);
    _homeScrollCtrl.dispose();
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
      final entry = alignments.firstWhere(
        (a) => a['id'] == id,
        orElse: () => {},
      );
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
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
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

  Future<bool> _confirmDelete(BuildContext ctx) =>
      showDeleteConfirmModal(ctx);

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
      if (_activeFilters.isEmpty) return true;

      final type = a['content_type'] as String? ?? 'article';
      final typeFilters = {
        'youtube',
        'reel',
        'article',
      }.intersection(_activeFilters);
      if (typeFilters.isNotEmpty && !typeFilters.contains(type)) return false;

      if (_activeFilters.contains('2plus')) {
        final raw = a['analyses'];
        final count = (raw is Map ? raw : {}).values
            .where((v) => v != null)
            .length;
        if (count < 2) return false;
      }

      if (_activeFilters.contains('24h')) {
        final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
        if (dt == null || DateTime.now().difference(dt).inHours >= 24) {
          return false;
        }
      }

      if (_activeFilters.contains('starred')) {
        if (!starredNotifier.value.contains(a['id'] as String? ?? '')) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _showUserModal(BuildContext context) {
    final alignments = alignmentsNotifier.value;
    final analysisCount = alignments
        .where((a) => a['is_analyzing'] != true && a['status'] != 'failed')
        .length;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'User',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutQuart, reverseCurve: Curves.easeOutCubic),
        ),
        child: child,
      ),
      pageBuilder: (ctx, _, __) => _UserInfoSheet(
        user: _user,
        firstName: _firstName,
        analysisCount: analysisCount,
      ),
    );
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
              controller: _homeScrollCtrl,
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
                  title: Row(
                    children: [
                      SvgPicture.asset(
                        'lib/assets/logo.svg',
                        width: 28,
                        height: 28.5,
                        colorFilter: ColorFilter.mode(
                          scheme.onSurface,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tappable(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _showUserModal(context);
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _greeting,
                                  style: AppTypography.navTitle(
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: scheme.onSurface,
                                  size: 18,
                                ),
                              ],
                            ),
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
                    Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Tappable(
                        onTap: () => showProfileModal(context),
                        child: _Avatar(
                          initial: _initial,
                          primary: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),

                if (!_isLoading)
                  SliverToBoxAdapter(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: _appBarBorderVisible ? 14 : 4,
                    ),
                  ),

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
                      onClear: () => setState(() => _activeFilters.clear()),
                      scheme: scheme,
                      isDark: isDark,
                      scaffoldBg: scaffoldBg,
                      isScrolled: _appBarBorderVisible,
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
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  24,
                                  20,
                                  150,
                                ),
                                child: _EmptyState(
                                  scheme: scheme,
                                  isDark: isDark,
                                ),
                              );
                            }
                            final filtered = _applyFilters(alignments);
                            return ValueListenableBuilder<Set<String>>(
                              valueListenable: starredNotifier,
                              builder: (context, starred, _) {
                                final screenH = MediaQuery.of(context).size.height;
                                return ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: screenH * 0.72),
                                  child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: 20,
                                    bottom: 150,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        switchInCurve: Curves.easeOut,
                                        switchOutCurve: Curves.easeIn,
                                        transitionBuilder: (child, animation) =>
                                            FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                        child: filtered.isEmpty
                                            ? Padding(
                                                key: const ValueKey(
                                                  '__no_results__',
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                    ),
                                                child: _NoFilterResults(
                                                  key: const ValueKey(
                                                    '__empty__',
                                                  ),
                                                  scheme: scheme,
                                                ),
                                              )
                                            : Column(
                                                key: ValueKey(
                                                  'deck_${_activeFilters.join(',')}',
                                                ),
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          20,
                                                          0,
                                                          20,
                                                          70,
                                                        ),
                                                    child: _SectionDividerLabel(
                                                      label: 'ALIGNMENTS',
                                                      scheme: scheme,
                                                    ),
                                                  ),
                                                  Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      // Title first → paints behind deck
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 293, left: 20, right: 20),
                                                        child: _DeckTitleBox(
                                                          alignment:
                                                              _activeDeckAlignment ??
                                                              (filtered.isNotEmpty
                                                                  ? filtered.first
                                                                  : null),
                                                          scheme: scheme,
                                                        ),
                                                      ),
                                                      // Deck last → paints on top
                                                      Padding(
                                                        padding: const EdgeInsets.only(left: 10),
                                                        child: AlignmentDeck(
                                                          alignments: filtered,
                                                          starred: starred,
                                                          isDark: isDark,
                                                          scheme: scheme,
                                                          confirmDelete: () =>
                                                              _confirmDelete(context),
                                                          onOpen: (id) =>
                                                              Navigator.push(
                                                                context,
                                                                AppRoute.transparentModal(AlignmentDetailScreen(
                                                                  alignmentId: id,
                                                                )),
                                                              ),
                                                          onDelete: AnalysisService
                                                              .deleteAlignment,
                                                          onActiveChanged: (a) =>
                                                              setState(
                                                                () =>
                                                                    _activeDeckAlignment =
                                                                        a,
                                                              ),
                                                          onCreativeSpace: (id) =>
                                                              openCreativeSpace(context, id),
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
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
            // ── Detail page blur overlay ─────────────────────────────────────
            ValueListenableBuilder<double>(
              valueListenable: detailBlurNotifier,
              builder: (_, amount, __) {
                if (amount <= 0) return const SizedBox.shrink();
                return Positioned.fill(
                  child: IgnorePointer(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: amount * 14,
                        sigmaY: amount * 14,
                      ),
                      child: Container(
                        color: Colors.black.withValues(alpha: amount * (isDark ? 0.28 : 0.18)),
                      ),
                    ),
                  ),
                );
              },
            ),
            // ── Floating nav bar ──────────────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
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

// ── Alignment deck ────────────────────────────────────────────────────────────

class AlignmentDeck extends StatefulWidget {
  final List<Map<String, dynamic>> alignments;
  final Set<String> starred;
  final bool isDark;
  final ColorScheme scheme;
  final Future<bool> Function() confirmDelete;
  final void Function(String id) onOpen;
  final Future<void> Function(String id) onDelete;
  final ValueChanged<Map<String, dynamic>>? onActiveChanged;
  final void Function(String id)? onCreativeSpace;

  const AlignmentDeck({
    required this.alignments,
    required this.starred,
    required this.isDark,
    required this.scheme,
    required this.confirmDelete,
    required this.onOpen,
    required this.onDelete,
    this.onActiveChanged,
    this.onCreativeSpace,
    super.key,
  });

  @override
  State<AlignmentDeck> createState() => _AlignmentDeckState();
}

class _AlignmentDeckState extends State<AlignmentDeck> {
  static const _deckHeight = 258.0;
  static const _cardHeight = 220.0;
  static const _cardBodyHeight = 168.0;
  static const _cardWidthFactor = 0.56;
  static const _cardHorizontalMargin = 10.0;
  static const _slotOffset = 86.0;
  static const _restingDrop = 42.0;
  static const _renderWindowSlots = 6.0;
  static const _snapDelay = Duration(milliseconds: 30);
  static const _snapDuration = Duration(milliseconds: 380);

  late final ScrollController _scrollController;
  Timer? _snapTimer;
  int _activeIndex = 0;
  bool _isSnapping = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _snapTimer?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AlignmentDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alignments.isEmpty) {
      if (_activeIndex != 0) _activeIndex = 0;
      return;
    }

    final currentId = _idFor(oldWidget.alignments, _activeIndex);
    final preservedIndex = currentId == null
        ? -1
        : widget.alignments.indexWhere((a) => a['id'] == currentId);
    final nextIndex = preservedIndex >= 0
        ? preservedIndex
        : _activeIndex.clamp(0, widget.alignments.length - 1);

    if (nextIndex != _activeIndex) {
      _activeIndex = nextIndex;
      _isSnapping = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollOffsetForIndex(_activeIndex));
      });
    }
  }

  static String? _idFor(List<Map<String, dynamic>> alignments, int index) {
    if (index < 0 || index >= alignments.length) return null;
    return alignments[index]['id'] as String?;
  }

  double _scrollOffsetForIndex(int index) => index * _slotOffset;

  double get _rawActivePosition {
    if (!_scrollController.hasClients) return _activeIndex.toDouble();
    return (_scrollController.offset / _slotOffset).clamp(
      0,
      (widget.alignments.length - 1).toDouble(),
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || widget.alignments.isEmpty) return;
    _scheduleSnap();
    final nextIndex = _rawActivePosition.round().clamp(
      0,
      widget.alignments.length - 1,
    );
    if (nextIndex == _activeIndex) {
      setState(() {});
      return;
    }
    setState(() => _activeIndex = nextIndex);
    HapticFeedback.selectionClick();
    widget.onActiveChanged?.call(widget.alignments[nextIndex]);
  }

  void _scheduleSnap() {
    if (_isSnapping || widget.alignments.length < 2) return;
    _snapTimer?.cancel();
    _snapTimer = Timer(_snapDelay, _snapToNearestCard);
  }

  Future<void> _snapToNearestCard() async {
    _snapTimer?.cancel();
    if (_isSnapping || !_scrollController.hasClients) return;
    final targetIndex = _rawActivePosition.round().clamp(
      0,
      widget.alignments.length - 1,
    );
    final target = _scrollOffsetForIndex(targetIndex);
    final distance = (_scrollController.offset - target).abs();
    if (distance < 1) {
      if (_activeIndex != targetIndex) {
        setState(() => _activeIndex = targetIndex);
      }
      return;
    }

    setState(() => _isSnapping = true);
    try {
      await _scrollController.animateTo(
        target,
        duration: _snapDuration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted) {
        setState(() {
          _activeIndex = targetIndex;
          _isSnapping = false;
        });
      }
    }
    if (!mounted) return;
    widget.onActiveChanged?.call(widget.alignments[targetIndex]);

    // If the scroll settled off-target (e.g. interrupted), snap once more.
    final residual = (_scrollController.offset - target).abs();
    if (residual > 1) _snapTimer = Timer(_snapDelay, _snapToNearestCard);
  }

  Future<void> _onCardLongPress(BuildContext context, String id) async {
    if (_isSnapping) return;
    final alignment = widget.alignments.firstWhere(
      (a) => a['id'] == id, orElse: () => {},
    );
    final rawTitle = alignment['title'] as String?;
    final url = alignment['url'] as String? ?? '';
    final title = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? 'Untitled';
    final contentType = alignment['content_type'] as String? ?? 'article';
    final action = await showCardActionsModal(context, id, title, contentType);
    if (!mounted || action == null) return;
    switch (action) {
      case CardAction.star:
        AnalysisService.toggleStar(id);
      case CardAction.info:
        if (mounted) await showAlignmentInfoModal(context, alignment);
      case CardAction.delete:
        final confirmed = await showDeleteConfirmModal(context);
        if (!mounted || !confirmed) return;
        HapticFeedback.mediumImpact();
        await widget.onDelete(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.alignments.isEmpty) return const SizedBox.shrink();

        final deckWidth = constraints.maxWidth;
        final screenWidth = MediaQuery.of(context).size.width;
        final cardOuterWidth =
            (screenWidth * _cardWidthFactor) + (_cardHorizontalMargin * 2);
        final sideInset = (deckWidth - cardOuterWidth) / 2;
        final contentWidth =
            (sideInset * 2) +
            cardOuterWidth +
            (_slotOffset * (widget.alignments.length - 1));
        final rawPosition = _rawActivePosition;
        final cardEntries = <({int index, Widget child})>[];

        for (var index = 0; index < widget.alignments.length; index++) {
          final relative = index - rawPosition;
          if (relative.abs() > _renderWindowSlots) continue;

          final alignment = widget.alignments[index];
          final id = alignment['id'] as String? ?? '$index';
          final activation = (1 - relative.abs()).clamp(0.0, 1.0);
          final dimAmount = ((1 - activation) * (widget.isDark ? 0.34 : 0.14)).clamp(0.0, 1.0);
          final offsetX = sideInset + (_slotOffset * index);
          final offsetY =
              _restingDrop * (1 - Curves.easeOut.transform(activation));
          final isActive = index == _activeIndex;

          cardEntries.add((
            index: index,
            child: Positioned(
              key: ValueKey('deck_position_$id'),
              left: offsetX,
              top: 0,
              child: Transform.translate(
                offset: Offset(0, offsetY),
                child: _SwipeUpCard(
                  key: ValueKey('swipe_$id'),
                  onOpen: () => widget.onOpen(id),
                  onActions: () => _onCardLongPress(context, id),
                  onSwipeDown: widget.onCreativeSpace != null
                      ? () => widget.onCreativeSpace!(id)
                      : null,
                  child: _FeaturedCard(
                    alignment: alignment,
                    isStarred: widget.starred.contains(id),
                    isDark: widget.isDark,
                    scheme: widget.scheme,
                    widthFactor: _cardWidthFactor,
                    cardHeight: _cardBodyHeight,
                    horizontalMargin: _cardHorizontalMargin,
                    dimAmount: dimAmount,
                    onTap: () => widget.onOpen(id),
                  ),
                ),
              ),
            ),
          ));
        }

        cardEntries.sort((a, b) => a.index.compareTo(b.index));

        return SizedBox(
          height: _deckHeight,
          width: double.infinity,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              _snapToNearestCard();
              return false;
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              clipBehavior: Clip.none,
              child: SizedBox(
                width: contentWidth,
                height: _cardHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: cardEntries.map((entry) => entry.child).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Deck title box ────────────────────────────────────────────────────────────

class _DeckTitleBox extends StatelessWidget {
  final Map<String, dynamic>? alignment;
  final ColorScheme scheme;

  const _DeckTitleBox({required this.alignment, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final a = alignment;
    if (a == null) return const SizedBox.shrink();

    final rawTitle = a['title'] as String?;
    final url = a['original_url'] as String? ?? '';
    final displayTitle = (rawTitle != null && rawTitle.isNotEmpty)
        ? rawTitle
        : Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? 'Untitled';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: SizedBox(
        height: 36,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: Text(
            displayTitle,
            key: ValueKey(displayTitle),
            style: AppTypography.dataSmall(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ── Activity heatmap ──────────────────────────────────────────────────────────

class _ActivityHeatmap extends StatefulWidget {
  final List<Map<String, dynamic>> alignments;
  final bool isDark;
  final ColorScheme scheme;

  const _ActivityHeatmap({
    required this.alignments,
    required this.isDark,
    required this.scheme,
  });

  @override
  State<_ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<_ActivityHeatmap> {
  static const _weeks = 16;
  static const _gap = 3.0;

  int? _tipCol;
  DateTime? _tipDate;
  int _tipCount = 0;
  Timer? _tipTimer;

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
    setState(() {
      _tipCol = col;
      _tipDate = date;
      _tipCount = count;
    });
    _tipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _tipCol = null);
    });
  }

  static String _mon(int m) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayRow = today.weekday - 1; // Mon=0 … Sun=6
    final dayMap = _buildDayMap();

    final legendColors = widget.isDark
        ? const [
            Color(0x0FFFFFFF),
            Color(0xFF1a3a5c),
            Color(0xFF1e6bb8),
            Color(0xFF2188ff),
            Color(0xFF79c0ff),
          ]
        : const [
            Color(0x12000000),
            Color(0xFFBBDEFB),
            Color(0xFF64B5F6),
            Color(0xFF1E88E5),
            Color(0xFF0D47A1),
          ];
    final mutedText = widget.scheme.onSurfaceVariant.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (_, constraints) {
          // Fit exactly _weeks columns into the available width
          final step = (constraints.maxWidth + _gap) / _weeks;
          final cellSize = step - _gap;
          final gridW = constraints.maxWidth;
          final gridH = 7 * step - _gap;

          // ── Month labels ────────────────────────────────────────────────
          final monthLabels = <Widget>[];
          String? lastLbl;
          for (int col = 0; col < _weeks; col++) {
            final daysBack = ((_weeks - 1) - col) * 7 + todayRow;
            final monday = today.subtract(Duration(days: daysBack));
            final lbl = _mon(monday.month);
            if (lbl != lastLbl) {
              lastLbl = lbl;
              monthLabels.add(
                Positioned(
                  left: col * step,
                  top: 0,
                  child: Text(
                    lbl,
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: widget.scheme.onSurfaceVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // ── Grid cells ──────────────────────────────────────────────────
          final cells = <Widget>[];
          for (int col = 0; col < _weeks; col++) {
            for (int row = 0; row < 7; row++) {
              final daysBack = ((_weeks - 1) - col) * 7 + (todayRow - row);
              final isFuture = daysBack < 0;
              final date = today.subtract(Duration(days: daysBack));
              final count = isFuture ? 0 : (dayMap[date] ?? 0);

              cells.add(
                Positioned(
                  left: col * step,
                  top: row * step,
                  child: GestureDetector(
                    onTap: isFuture ? null : () => _showTip(col, date, count),
                    child: Container(
                      width: cellSize,
                      height: cellSize,
                      decoration: BoxDecoration(
                        color: isFuture
                            ? Colors.transparent
                            : _cellColor(count),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // ── Tooltip ─────────────────────────────────────────────────────
          Widget? tooltip;
          if (_tipCol != null && _tipDate != null) {
            final d = _tipDate!;
            final lbl = _tipCount == 0
                ? 'No analyses · ${_mon(d.month)} ${d.day}'
                : '$_tipCount ${_tipCount == 1 ? 'analysis' : 'analyses'} · ${_mon(d.month)} ${d.day}';

            const tipW = 150.0;
            final rawLeft = _tipCol! * step + cellSize / 2 - tipW / 2;
            final tipLeft = rawLeft.clamp(0.0, gridW - tipW);

            tooltip = Positioned(
              left: tipLeft,
              bottom: gridH + 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    width: tipW,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
                    child: Text(
                      lbl,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: widget.isDark
                            ? Colors.white
                            : const Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: gridW,
                height: 14,
                child: Stack(children: monthLabels),
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: gridW,
                height: gridH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [...cells, ?tooltip],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // Legend — left-aligned
                  Text(
                    'Less',
                    style: GoogleFonts.inter(fontSize: 9, color: mutedText),
                  ),
                  const SizedBox(width: 4),
                  ...legendColors.map(
                    (c) => Container(
                      width: cellSize,
                      height: cellSize,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'More',
                    style: GoogleFonts.inter(fontSize: 9, color: mutedText),
                  ),
                  const Spacer(),
                  // View More Insights link — right-aligned
                  GestureDetector(
                    onTap: () => showInsightsModal(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View More Insights',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: mutedText,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 10,
                          color: mutedText,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionDividerLabel extends StatelessWidget {
  final String label;
  final ColorScheme scheme;

  const _SectionDividerLabel({required this.label, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final lineColor = scheme.onSurfaceVariant.withValues(alpha: 0.28);
    final textColor = scheme.onSurfaceVariant.withValues(alpha: 0.72);

    return Row(
      children: [
        Expanded(child: Container(height: 0.7, color: lineColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 5.2,
              color: textColor,
            ),
          ),
        ),
        Expanded(child: Container(height: 0.7, color: lineColor)),
      ],
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
    final inactiveBg = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFE8E4DF);
    final inactiveIcon = isDark ? Colors.white70 : const Color(0xFF7A7470);
    final borderColor = isDark
        ? Colors.white.withAlpha(28)
        : Colors.black.withAlpha(18);
    final bgColor = isDark
        ? const Color(0xFF1C1C1E).withAlpha(140)
        : Colors.white.withAlpha(160);

    return Container(
      decoration: BoxDecoration(
        borderRadius: SmoothBorderRadius(
          cornerRadius: 50,
          cornerSmoothing: 0.6,
        ),
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
              borderRadius: SmoothBorderRadius(
                cornerRadius: 50,
                cornerSmoothing: 0.6,
              ),
              border: Border.all(color: borderColor, width: 0.7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tappable(
                  scaleOnPress: true,
                  onTap: () => showGlobeModal(context),
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: inactiveBg.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.globe,
                      color: inactiveIcon,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Tappable(
                  scaleOnPress: true,
                  onTap: () => showInsightsModal(context),
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: inactiveBg.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.chartBarFill,
                      color: inactiveIcon,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Tappable(
                  scaleOnPress: true,
                  onTap: () => showNewAlignmentModal(context),
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.plus,
                      color: scheme.primary,
                      size: 18,
                    ),
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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.link,
                color: scheme.onSurfaceVariant,
                size: 26,
              ),
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
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
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
  final VoidCallback onClear;
  final ColorScheme scheme;
  final bool isDark;
  final Color scaffoldBg;
  final bool isScrolled;

  const _FilterBarDelegate({
    required this.activeFilters,
    required this.onToggle,
    required this.onClear,
    required this.scheme,
    required this.isDark,
    required this.scaffoldBg,
    required this.isScrolled,
  });

  @override
  double get minExtent => 58;
  @override
  double get maxExtent => 58;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: const BoxDecoration(),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: scaffoldBg.withAlpha(isDark ? 110 : 150)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Filter chips ───────────────────────────────────────
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // Filter chips
                      ..._kFilters.map((f) {
                        final (key, label, chipColor, icon) = f;
                        final active = activeFilters.contains(key);
                        final color = chipColor ?? scheme.primary;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FilterChip(
                            label: label,
                            active: active,
                            color: color,
                            icon: icon,
                            isDark: isDark,
                            onTap: () => onToggle(key),
                          ),
                        );
                      }),
                      // Clear chip — only shown when filters are active
                      if (activeFilters.isNotEmpty)
                        Center(
                          child: GestureDetector(
                            onTap: onClear,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.14)
                                      : Colors.black.withValues(alpha: 0.10),
                                  width: 0.7,
                                ),
                              ),
                              child: Text(
                                'Clear',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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
        : const Color(0xFFD8D0C8).withValues(alpha: 0.6);

    return Tappable(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _t,
        builder: (_, _) {
          final v = _t.value;
          final contentColor = Color.lerp(
            scheme.onSurfaceVariant,
            Colors.white,
            v,
          )!;
          return Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.transparent,
                widget.color.withValues(alpha: 0.3),
                v,
              ),
              borderRadius: SmoothBorderRadius(
                cornerRadius: 50,
                cornerSmoothing: 0.6,
              ),
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
                    Icon(
                      widget.icon,
                      size: 13,
                      color: Color.lerp(widget.color, Colors.white, v)!,
                    ),
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
            Icon(
              CupertinoIcons.slash_circle,
              color: scheme.onSurfaceVariant,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              'No matching alignments',
              style: AppTypography.navTitle(
                color: scheme.onSurface,
              ).copyWith(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your filters',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
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
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment(-0.7, -0.9),
            end: Alignment(0.7, 0.9),
            colors: [Color(0xFF8E8E93), Color(0xFF3A3A3C)],
          ),
        ),
        child: const Center(
          child: Icon(
            CupertinoIcons.person_fill,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── Swipe-completed toast ──────────────────────────────────────────────────────

class _SwipeCompletedToast extends StatelessWidget {
  final Animation<double> slideAnim;
  const _SwipeCompletedToast({required this.slideAnim});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    const toastH = 42.0;

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: slideAnim,
          builder: (_, __) {
            final offsetY = -toastH + (topPad + toastH + 6) * slideAnim.value;
            return Stack(
              children: [
                Positioned(
                  top: offsetY,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(toastH / 2),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          height: toastH,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(toastH / 2),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                size: 22,
                                color: const Color(0xFF30D158),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Completed',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
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
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      // left edge
      ..lineTo(0, radius)
      // top-left rounded corner
      ..quadraticBezierTo(0, 0, radius, 0)
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
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
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

// ── Swipe-up-to-actions card wrapper ─────────────────────────────────────────

class _SwipeUpCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onOpen;
  final VoidCallback onActions;
  final VoidCallback? onSwipeDown;

  const _SwipeUpCard({
    super.key,
    required this.child,
    required this.onOpen,
    required this.onActions,
    this.onSwipeDown,
  });

  @override
  State<_SwipeUpCard> createState() => _SwipeUpCardState();
}

class _SwipeUpCardState extends State<_SwipeUpCard>
    with TickerProviderStateMixin {
  double _dragY = 0;
  late AnimationController _snapCtrl;
  late Animation<double> _snapAnim;
  double _snapFrom = 0;
  bool _triggered = false;
  bool _isDragging = false;
  double _lastHapticY = 0;

  // Up swipe → actions modal
  static const _downTrigger = 52.0;
  // Up swipe → progress toast
  static const _upTrigger = 88.0;
  static const _hapticInterval = 4.0;

  // Toast overlay state
  OverlayEntry? _toastEntry;
  AnimationController? _toastSlideCtrl;
  final _progressNotifier = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _snapAnim = CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic);
    _snapCtrl.addListener(() {
      setState(() => _dragY = _snapFrom * (1 - _snapAnim.value));
    });
  }

  @override
  void dispose() {
    _toastEntry?.remove();
    _toastEntry = null;
    _toastSlideCtrl?.dispose();
    _progressNotifier.dispose();
    _snapCtrl.dispose();
    super.dispose();
  }

  void _showToast() {
    if (_toastEntry != null) return;
    final slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _toastSlideCtrl = slideCtrl;
    _toastEntry = OverlayEntry(
      builder: (_) => _SwipeProgressToast(
        progress: _progressNotifier,
        slideAnim: CurvedAnimation(parent: slideCtrl, curve: Curves.easeOutCubic),
      ),
    );
    Overlay.of(context).insert(_toastEntry!);
    slideCtrl.forward();
  }

  void _hideToast() {
    final entry = _toastEntry;
    final ctrl = _toastSlideCtrl;
    if (entry == null || ctrl == null) return;
    _toastEntry = null;
    _toastSlideCtrl = null;
    ctrl.reverse().then((_) {
      entry.remove();
      ctrl.dispose();
    });
  }

  void _showCompletedToast() {
    final slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (_) => _SwipeCompletedToast(
        slideAnim: CurvedAnimation(parent: slideCtrl, curve: Curves.easeOutCubic),
      ),
    );
    Overlay.of(context).insert(entry);
    slideCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) {
          entry?.remove();
          slideCtrl.dispose();
          return;
        }
        slideCtrl.reverse().then((_) {
          entry?.remove();
          slideCtrl.dispose();
        });
      });
    });
  }

  void _onStart(DragStartDetails _) {
    _isDragging = true;
    _lastHapticY = _dragY;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_triggered) return;
    if (_snapCtrl.isAnimating) _snapCtrl.stop();

    final newY = _dragY + d.delta.dy;

    if (newY <= 0) {
      // ── Up swipe → actions modal ──────────────────────────────────────
      _hideToast();
      _progressNotifier.value = 0;
      setState(() => _dragY = newY.clamp(-_downTrigger * 1.5, 0.0));
      if (_dragY <= -_downTrigger && !_triggered) {
        _triggered = true;
        HapticFeedback.mediumImpact();
        _snapBack();
        widget.onActions();
      }
    } else {
      // ── Down swipe → progress toast (damped) ─────────────────────────
      final damped = (_dragY + d.delta.dy * 0.38).clamp(0.0, _upTrigger * 1.15);
      setState(() => _dragY = damped);
      final progress = (_dragY / _upTrigger).clamp(0.0, 1.0);
      _progressNotifier.value = progress;
      _showToast();

      if ((_dragY - _lastHapticY).abs() >= _hapticInterval) {
        HapticFeedback.selectionClick();
        _lastHapticY = _dragY;
      }
      if (_dragY >= _upTrigger && !_triggered) {
        _triggered = true;
        _hideToast();
        _snapBack();
        if (widget.onSwipeDown != null) {
          HapticFeedback.mediumImpact();
          widget.onSwipeDown!();
        } else {
          _showCompletedToast();
        }
      }
    }
  }

  void _onEnd(DragEndDetails _) {
    _isDragging = false;
    _triggered = false;
    _progressNotifier.value = 0;
    _hideToast();
    _snapBack();
  }

  void _snapBack() {
    _snapFrom = _dragY;
    _snapCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onStart,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
      onLongPress: _isDragging
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onActions();
            },
      onTap: widget.onOpen,
      child: Transform.translate(
        offset: Offset(0, _dragY),
        child: widget.child,
      ),
    );
  }
}

// ── Swipe-progress toast ───────────────────────────────────────────────────────

class _SwipeProgressToast extends StatelessWidget {
  final ValueNotifier<double> progress;
  final Animation<double> slideAnim;

  const _SwipeProgressToast({
    required this.progress,
    required this.slideAnim,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    const toastH = 42.0;

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([progress, slideAnim]),
          builder: (_, __) {
            // slideAnim 0 → fully above screen, 1 → resting below status bar
            final offsetY = -toastH + (topPad + toastH + 6) * slideAnim.value;
            return Stack(
              children: [
                Positioned(
                  top: offsetY,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(toastH / 2),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          height: toastH,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(toastH / 2),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  value: progress.value,
                                  strokeWidth: 2.0,
                                  backgroundColor: Colors.white.withValues(alpha: 0.20),
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Text(
                                'Keep swiping…',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final Map<String, dynamic> alignment;
  final bool isStarred;
  final bool isDark;
  final ColorScheme scheme;
  final double widthFactor;
  final double cardHeight;
  final double horizontalMargin;
  final double dimAmount;
  final VoidCallback onTap;
  const _FeaturedCard({
    required this.alignment,
    required this.isStarred,
    required this.isDark,
    required this.scheme,
    required this.onTap,
    this.widthFactor = 0.65,
    this.cardHeight = 200,
    this.horizontalMargin = 28,
    this.dimAmount = 0,
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
    final cardWidth = screenWidth * widthFactor;

    final url = alignment['url'] as String? ?? '';
    final title = alignment['title'] as String?;
    final contentType = alignment['content_type'] as String? ?? 'article';
    final createdAt = alignment['created_at'] as String?;
    final raw = alignment['analyses'];
    final analyses = raw is Map ? raw : {};
    final count = analyses.values.where((v) => v != null).length;
    final isAnalysing = alignment['is_analyzing'] == true;
    final isFailed = alignment['status'] == 'failed';
    final displayTitle = (title != null && title.isNotEmpty)
        ? title
        : _domain(url);

    final (
      IconData typeIcon,
      Color typeColor,
      String typeLabel,
    ) = switch (contentType) {
      'youtube' => (
        CupertinoIcons.play_rectangle_fill,
        const Color(0xFFFF3B30),
        'YouTube',
      ),
      'reel' => (CupertinoIcons.film_fill, const Color(0xFFBF5AF2), 'Reel'),
      _ => (CupertinoIcons.doc_text_fill, scheme.primary, 'Article'),
    };
    const failedRed = Color(0xFFFF3B30);
    final effectiveTypeColor = isFailed ? failedRed : typeColor;
    final cardRadius = SmoothBorderRadius(
      cornerRadius: 22,
      cornerSmoothing: 0.6,
    );

    Widget cardBody() => Container(
      width: cardWidth,
      height: cardHeight,
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 18),
      decoration: ShapeDecoration(
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 32,
            spreadRadius: 0,
            offset: const Offset(0, 14),
          ),
        ],
        shape: SmoothRectangleBorder(borderRadius: cardRadius),
      ),
      child: ClipSmoothRect(
        radius: cardRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Container(
                decoration: ShapeDecoration(
                  color: isDark ? const Color(0xFF1E1E20) : Colors.white,
                  shape: SmoothRectangleBorder(
                    borderRadius: cardRadius,
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.07),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
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
                        const Icon(CupertinoIcons.star_fill, size: 12, color: Color(0xFFFF9F0A)),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _relativeTime(createdAt),
                        style: AppTypography.dataSmall(color: scheme.onSurface.withValues(alpha: 0.50)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (isAnalysing && (title == null || title.isEmpty))
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    )
                  else
                    Text(
                      displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading2(color: scheme.onSurface).copyWith(fontSize: 15.5, height: 1.2),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (isAnalysing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(50)),
                          child: Text('Analysing…', style: AppTypography.dataSmall(color: scheme.primary).copyWith(fontStyle: FontStyle.italic)),
                        )
                      else if (isFailed)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: failedRed.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(50)),
                          child: Text('Failed', style: AppTypography.dataSmall(color: failedRed)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: scheme.onSurface.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(50)),
                          child: Text('$count ${count == 1 ? 'Analysis' : 'Analyses'}', style: AppTypography.dataSmall(color: scheme.onSurface.withValues(alpha: 0.75))),
                        ),
                      const SizedBox(width: 8),
                      Text(typeLabel, style: AppTypography.contentTypeLabel(color: scheme.onSurface.withValues(alpha: 0.45))),
                    ],
                  ),
                ],
              ),
            ),
            if (dimAmount > 0)
              Positioned.fill(
                child: IgnorePointer(child: Container(color: Colors.black.withValues(alpha: dimAmount))),
              ),
          ],
        ),
      ),
    );

    return _TappableCard(
      onTap: isFailed ? null : onTap,
      cardBody: cardBody,
    );
  }
}

/// Handles tap press feedback (scale + opacity) then calls [onTap].
class _TappableCard extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function() cardBody;

  const _TappableCard({required this.onTap, required this.cardBody});

  @override
  State<_TappableCard> createState() => _TappableCardState();
}

class _TappableCardState extends State<_TappableCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;
  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.93).animate(CurvedAnimation(parent: _press, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    if (widget.onTap != null) {
      HapticFeedback.lightImpact();
      _press.forward();
    }
  }
  void _onTapUp(_) {
    _press.reverse().then((_) {
      if (!mounted) return;
      widget.onTap?.call();
    });
  }
  void _onCancel() { _press.reverse(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onCancel,
      behavior: HitTestBehavior.deferToChild,
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewY(-0.35),
          child: widget.cardBody(),
        ),
      ),
    );
  }
}

// ── User info sheet ───────────────────────────────────────────────────────────

class _UserInfoSheet extends StatefulWidget {
  final dynamic user; // supabase User
  final String? firstName;
  final int analysisCount;

  const _UserInfoSheet({
    required this.user,
    required this.firstName,
    required this.analysisCount,
  });

  @override
  State<_UserInfoSheet> createState() => _UserInfoSheetState();
}

class _UserInfoSheetState extends State<_UserInfoSheet> {
  String? _createdAt;

  @override
  void initState() {
    super.initState();
    _loadCreatedAt();
  }

  Future<void> _loadCreatedAt() async {
    final userId = widget.user?.id;
    if (userId == null) return;
    final data = await Supabase.instance.client
        .from('user_profiles')
        .select('created_at')
        .eq('id', userId)
        .maybeSingle();
    if (mounted && data != null) {
      setState(() => _createdAt = data['created_at'] as String?);
    }
  }

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final cardRadius = SmoothBorderRadius(cornerRadius: 26, cornerSmoothing: 0.6);

    final email = widget.user?.email as String? ?? '—';
    final displayName = (widget.firstName != null && widget.firstName!.isNotEmpty)
        ? widget.firstName![0].toUpperCase() + widget.firstName!.substring(1)
        : '—';

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
              padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                            decoration: TextDecoration.none,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      Tappable(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Info rows
                  _InfoTile(
                    icon: CupertinoIcons.calendar,
                    label: 'Member since',
                    value: _formatDate(_createdAt),
                    isDark: isDark,
                    scheme: scheme,
                  ),
                  const SizedBox(height: 10),
                  _InfoTile(
                    icon: CupertinoIcons.checkmark_shield,
                    label: 'Analyses',
                    value: '${widget.analysisCount}',
                    isDark: isDark,
                    scheme: scheme,
                  ),
                  const SizedBox(height: 24),
                  // Sign out
                  Tappable(
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop();
                      await AuthService.signOut();
                    },
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: ShapeDecoration(
                        color: Colors.red.shade600.withAlpha(20),
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Sign Out',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final ColorScheme scheme;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: ShapeDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 0.6),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              decoration: TextDecoration.none,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
