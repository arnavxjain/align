import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_typography.dart';
import '../providers/theme_notifier.dart';
import '../services/auth_service.dart';
import '../services/milestone_service.dart';
import '../widgets/page_header.dart';
import '../widgets/status_bar_blur.dart';
import '../widgets/tappable.dart';
import '../widgets/user_card.dart';

// ── Profile screen ────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _scrollCtrl = ScrollController();
  String _firstName = '';
  String _memberSince = '';
  bool _showFloatingBack = false;
  double _topPad = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    // Back button lives at topPad + 16 (header padding) and is 40px tall
    final show = _scrollCtrl.offset > _topPad + 56;
    if (show != _showFloatingBack) setState(() => _showFloatingBack = show);
  }

  Future<void> _loadProfileData() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await client
          .from('user_profiles')
          .select('first_name, created_at')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted || data == null) return;
      final dt = DateTime.tryParse(data['created_at'] as String? ?? '');
      setState(() {
        _firstName = (data['first_name'] as String?) ?? '';
        _memberSince = dt != null ? _formatDate(dt) : '';
      });
    } catch (_) {}
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  static int _computeStreak(List<Map<String, dynamic>> alignments) {
    final dates = alignments
        .where((a) => a['is_analyzing'] != true && a['created_at'] != null)
        .map((a) {
          final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
          if (dt == null) return null;
          final l = dt.toLocal();
          return DateTime(l.year, l.month, l.day);
        })
        .whereType<DateTime>()
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (dates.isEmpty) return 0;

    final now = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (dates.first != today && dates.first != yesterday) return 0;

    int streak = 1;
    for (int i = 0; i < dates.length - 1; i++) {
      if (dates[i].difference(dates[i + 1]).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }


  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user   = Supabase.instance.client.auth.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final email  = user?.email ?? '';

    final topPad = MediaQuery.of(context).padding.top;
    _topPad = topPad; // keep in sync for scroll listener

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            top: false,
            child: CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
                // Space for status bar so content starts below it
                SliverToBoxAdapter(child: SizedBox(height: topPad)),

                SliverToBoxAdapter(
                  child: PageHeader(title: 'Profile', subtitle: email),
                ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: alignmentsNotifier,
                  builder: (context, alignments, _) {
                    final count = alignments
                        .where((a) => a['is_analyzing'] != true)
                        .length;
                    final current = MilestoneService.currentMilestone(count);
                    final next    = MilestoneService.nextMilestone(count);
                    final streak  = _computeStreak(alignments);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),

                        // ── User card ─────────────────────────────────────
                        UserCard(
                          firstName:      _firstName,
                          memberSince:    _memberSince,
                          analysisCount:  count,
                          streak:         streak,
                          milestoneTitle: current.title,
                          isDark:         isDark,
                        ),

                        const SizedBox(height: 28),

                        // ── Theme switcher ────────────────────────────────
                        Container(
                          width: double.infinity,
                          decoration: ShapeDecoration(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            shape: SmoothRectangleBorder(
                              borderRadius: SmoothBorderRadius(
                                cornerRadius: 16,
                                cornerSmoothing: 0.6,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(child: _PullCordThemeSwitcher(isDark: isDark)),
                        ),

                        const SizedBox(height: 32),

                        // ── Milestone badge + progress ────────────────────
                        _MilestoneSection(
                          current: current,
                          next:    next,
                          count:   count,
                          scheme:  scheme,
                          isDark:  isDark,
                        ),

                        const SizedBox(height: 32),

                        // ── Sign out ──────────────────────────────────────
                        Tappable(
                          onTap: () async => AuthService.signOut(),
                          child: Container(
                            width: double.infinity,
                            height: 52,
                            decoration: ShapeDecoration(
                              color: Colors.red.shade600.withAlpha(20),
                              shape: SmoothRectangleBorder(
                                borderRadius: SmoothBorderRadius(
                                  cornerRadius: 14,
                                  cornerSmoothing: 0.6,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Sign Out',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade500,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
          const StatusBarBlur(),

          // Floating back button — rendered above blur, ignored when hidden
          Positioned(
            top: topPad + 16,
            left: 20,
            child: IgnorePointer(
              ignoring: !_showFloatingBack,
              child: AnimatedOpacity(
                opacity: _showFloatingBack ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: AnimatedScale(
                  scale: _showFloatingBack ? 1.0 : 0.7,
                  duration: const Duration(milliseconds: 250),
                  curve: _showFloatingBack ? Curves.easeOutBack : Curves.easeIn,
                  child: Tappable(
                    onTap: () => Navigator.maybePop(context),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          width: 40,
                          height: 40,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.07),
                          child: Icon(
                            CupertinoIcons.chevron_left,
                            color: scheme.onSurface,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Milestone section ─────────────────────────────────────────────────────────

(Color, Color) _milestoneGradient(String title) =>
    kMilestoneGradients[title] ?? kMilestoneGradients['Newcomer']!;

class _MilestoneSection extends StatefulWidget {
  final MilestoneInfo current;
  final MilestoneInfo? next;
  final int count;
  final ColorScheme scheme;
  final bool isDark;

  const _MilestoneSection({
    required this.current,
    required this.next,
    required this.count,
    required this.scheme,
    required this.isDark,
  });

  @override
  State<_MilestoneSection> createState() => _MilestoneSectionState();
}

class _MilestoneSectionState extends State<_MilestoneSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final (c1, c2) = _milestoneGradient(widget.current.title);
    final nextM = widget.next;
    final progress = nextM == null
        ? 1.0
        : (widget.count - widget.current.count) /
          (nextM.count - widget.current.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero card ──────────────────────────────────────────────────────
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: Color.lerp(c1, c2, 0.5)!.withAlpha(widget.isDark ? 22 : 14),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 20, cornerSmoothing: 0.6),
              side: BorderSide(color: c1.withAlpha(70), width: 1),
            ),
            shadows: [
              BoxShadow(
                color: c1.withAlpha(widget.isDark ? 55 : 35),
                blurRadius: 32,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                child: Column(
                  children: [
                    // Glowing icon squircle
                    Container(
                      width: 84,
                      height: 84,
                      decoration: ShapeDecoration(
                        color: c1.withAlpha(widget.isDark ? 30 : 18),
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius(
                            cornerRadius: 22,
                            cornerSmoothing: 0.6,
                          ),
                          side: BorderSide(color: c1.withAlpha(60), width: 1),
                        ),
                        shadows: [
                          BoxShadow(
                            color: c1.withAlpha(widget.isDark ? 90 : 60),
                            blurRadius: 36,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: widget.current.icon,
                          size: 38,
                          color: c1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.current.title,
                      style: AppTypography.heading2(
                        color: widget.isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    if (widget.current.flavourText != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.current.flavourText!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: widget.isDark
                              ? Colors.white.withAlpha(100)
                              : const Color(0xFF1A1A1A).withAlpha(85),
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              // Gradient progress strip flush to card bottom
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: c1.withAlpha(widget.isDark ? 40 : 25),
                valueColor: AlwaysStoppedAnimation<Color>(c1),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Progress hint / max rank
        Center(
          child: nextM != null
              ? Text(
                  '${nextM.count - widget.count} '
                  '${nextM.count - widget.count == 1 ? 'analysis' : 'analyses'} '
                  'until ${nextM.title}',
                  style: AppTypography.dataSmall(color: widget.scheme.onSurfaceVariant)
                      .copyWith(fontWeight: FontWeight.w500),
                )
              : Text(
                  'Maximum rank achieved',
                  style: AppTypography.dataSmall(color: c1)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
        ),

        const SizedBox(height: 28),

        // ── Journey list header ────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Text(
                  'Journey',
                  style: AppTypography.sectionHeader(color: widget.scheme.onSurfaceVariant),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 13,
                    color: widget.scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? _JourneyList(
                    count: widget.count,
                    current: widget.current,
                    isDark: widget.isDark,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

// ── Journey timeline list ─────────────────────────────────────────────────────

class _JourneyList extends StatelessWidget {
  final int count;
  final MilestoneInfo current;
  final bool isDark;

  const _JourneyList({
    required this.count,
    required this.current,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(kMilestones.length, (i) {
          final m = kMilestones[i];
          return _JourneyRow(
            milestone: m,
            unlocked:  count >= m.count,
            isCurrent: m.title == current.title,
            isFirst:   i == 0,
            isLast:    i == kMilestones.length - 1,
            isDark:    isDark,
          );
        }),
      ),
    );
  }
}

class _JourneyRow extends StatelessWidget {
  final MilestoneInfo milestone;
  final bool unlocked;
  final bool isCurrent;
  final bool isFirst;
  final bool isLast;
  final bool isDark;

  const _JourneyRow({
    required this.milestone,
    required this.unlocked,
    required this.isCurrent,
    required this.isFirst,
    required this.isLast,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final (c1, c2) = _milestoneGradient(milestone.title);

    final lineColor = unlocked
        ? c1.withAlpha(isDark ? 90 : 65)
        : (isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12));

    final node = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unlocked
            ? LinearGradient(
                colors: [c1, c2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: unlocked
            ? null
            : (isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10)),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: c1.withAlpha(isDark ? 110 : 80),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Center(
        child: HugeIcon(
          icon: milestone.icon,
          size: 18,
          color: unlocked
              ? Colors.white.withAlpha(230)
              : (isDark ? Colors.white.withAlpha(50) : Colors.black.withAlpha(40)),
        ),
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline: line above + node + line below
          SizedBox(
            width: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isFirst)
                  Expanded(
                    child: Center(child: Container(width: 1.5, color: lineColor)),
                  )
                else
                  const SizedBox(height: 8),
                node,
                if (!isLast)
                  Expanded(
                    child: Center(child: Container(width: 1.5, color: lineColor)),
                  )
                else
                  const SizedBox(height: 8),
              ],
            ),
          ),

          // Title + count
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    milestone.title,
                    style: AppTypography.milestoneRowTitle(
                      color: unlocked
                          ? (isDark ? Colors.white : const Color(0xFF1A1A1A))
                          : (isDark
                              ? Colors.white.withAlpha(50)
                              : const Color(0xFF1A1A1A).withAlpha(50)),
                      weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    milestone.count == 0
                        ? 'From the start'
                        : '${milestone.count} analyses',
                    style: AppTypography.dataSmall(
                      color: unlocked
                          ? (isDark
                              ? Colors.white.withAlpha(75)
                              : const Color(0xFF1A1A1A).withAlpha(65))
                          : (isDark
                              ? Colors.white.withAlpha(30)
                              : const Color(0xFF1A1A1A).withAlpha(30)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Trailing icon
          SizedBox(
            width: 40,
            child: Center(
              child: unlocked
                  ? Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: c1)
                  : Icon(CupertinoIcons.lock_fill,
                      size: 14,
                      color: isDark
                          ? Colors.white.withAlpha(30)
                          : Colors.black.withAlpha(25)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings widgets ──────────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tappable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: scheme.onSurfaceVariant, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                color: scheme.onSurfaceVariant, size: 15),
          ],
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(CupertinoIcons.moon_fill, color: scheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Dark Mode',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, _) => CupertinoSwitch(
              value: isDark,
              activeTrackColor: scheme.primary,
              onChanged: (on) {
                final m = on ? ThemeMode.dark : ThemeMode.light;
                themeNotifier.value = m;
                saveTheme(m);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: Theme.of(context).colorScheme.outline.withAlpha(80),
      ),
    );
  }
}

// ── Pull-cord theme switcher ───────────────────────────────────────────────────
class _PullCordThemeSwitcher extends StatefulWidget {
  final bool isDark;
  const _PullCordThemeSwitcher({required this.isDark});

  @override
  State<_PullCordThemeSwitcher> createState() => _PullCordThemeSwitcherState();
}

class _PullCordThemeSwitcherState extends State<_PullCordThemeSwitcher>
    with SingleTickerProviderStateMixin {
  static const double _cordHeight = 80.0;
  static const double _triggerDistance = 60.0;
  static const double _maxPull = 100.0;

  double _pull = 0.0;
  bool _triggered = false;
  late AnimationController _snapCtrl;
  late Animation<double> _snapAnim;
  double _snapFrom = 0.0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _snapAnim = CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut);
    _snapCtrl.addListener(() {
      setState(() => _pull = _snapFrom * (1 - _snapAnim.value));
    });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_snapCtrl.isAnimating) return;
    setState(() {
      _pull = (_pull + d.delta.dy).clamp(0.0, _maxPull);
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (_pull >= _triggerDistance && !_triggered) {
      _triggered = true;
      final newMode = widget.isDark ? ThemeMode.light : ThemeMode.dark;
      themeNotifier.value = newMode;
      saveTheme(newMode);
    }
    _snapFrom = _pull;
    _snapCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _triggered = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final progress = (_pull / _triggerDistance).clamp(0.0, 1.0);

    // Ball color: blue-white in dark, golden-yellow in light
    final ballColor = isDark
        ? Color.lerp(const Color(0xFFB8D4FF), const Color(0xFFFFD060), progress)!
        : Color.lerp(const Color(0xFFFFD060), const Color(0xFFFFAA00), progress)!;

    final glowColor = isDark
        ? Color.lerp(const Color(0xFF6EA8FF), const Color(0xFFFFD060), progress)!
        : Color.lerp(const Color(0xFFFFD060), const Color(0xFFFF9500), progress)!;

    final glowRadius = isDark
        ? lerpDouble(18.0, 48.0, progress)!
        : lerpDouble(28.0, 56.0, progress)!;

    final cordColor = isDark
        ? Colors.white.withValues(alpha: 0.25)
        : Colors.black.withValues(alpha: 0.18);

    return Column(
      children: [
        GestureDetector(
          onVerticalDragUpdate: _onPanUpdate,
          onVerticalDragEnd: _onPanEnd,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 80,
            height: _cordHeight + _pull + 36,
            child: CustomPaint(
              painter: _CordPainter(
                pull: _pull,
                cordHeight: _cordHeight,
                cordColor: cordColor,
                ballColor: ballColor,
                glowColor: glowColor,
                glowRadius: glowRadius,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isDark ? 'Pull down for light mode' : 'Pull down for dark mode',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: isDark
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.35),
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _CordPainter extends CustomPainter {
  final double pull;
  final double cordHeight;
  final Color cordColor;
  final Color ballColor;
  final Color glowColor;
  final double glowRadius;

  const _CordPainter({
    required this.pull,
    required this.cordHeight,
    required this.cordColor,
    required this.ballColor,
    required this.glowColor,
    required this.glowRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cordEnd = cordHeight + pull;
    final ballCenter = Offset(cx, cordEnd + 12);

    // Cord
    final cordPaint = Paint()
      ..color = cordColor
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, 0), Offset(cx, cordEnd), cordPaint);

    // Glow
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);
    canvas.drawCircle(ballCenter, 14, glowPaint);

    // Ball
    final ballPaint = Paint()..color = ballColor;
    canvas.drawCircle(ballCenter, 12, ballPaint);
  }

  @override
  bool shouldRepaint(_CordPainter old) =>
      old.pull != pull ||
      old.ballColor != ballColor ||
      old.glowColor != glowColor ||
      old.glowRadius != glowRadius;
}
