import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dynamic_icon/flutter_dynamic_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/theme_notifier.dart';
import '../services/auth_service.dart';
import '../widgets/page_header.dart';
import '../widgets/tappable.dart';
import '../widgets/user_card.dart';

// ── Profile modal ─────────────────────────────────────────────────────────────

Future<void> showProfileModal(BuildContext context) {
  HapticFeedback.lightImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Profile',
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
          // Blurred backdrop
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
          // Sliding modal
          SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        ],
      );
    },
    pageBuilder: (_, __, ___) => const _ProfileSheet(),
  );
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet>
    with SingleTickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  String? _firstName;
  String _memberSince = '';
  double _dragX = 0;
  late AnimationController _snapBackCtrl;
  late Animation<double> _snapBackAnim;
  double _snapBackFrom = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
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
    _scrollCtrl.dispose();
    super.dispose();
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
        _memberSince = dt != null ? _fmtDate(dt) : '';
      });
    } catch (_) {}
  }

  static String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.year}';
  }

  static int _streak(List<Map<String, dynamic>> alignments) {
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
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (dates.first != today && dates.first != yesterday) return 0;
    int s = 1;
    for (int i = 0; i < dates.length - 1; i++) {
      if (dates[i].difference(dates[i + 1]).inDays == 1) s++;
      else break;
    }
    return s;
  }

  void _showIconPicker(BuildContext ctx) {
    showGeneralDialog<void>(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'App Icon',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutQuart, reverseCurve: Curves.easeOutCubic),
        ),
        child: child,
      ),
      pageBuilder: (_, __, ___) => const _IconPickerSheet(),
    );
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
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

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
                        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                          valueListenable: alignmentsNotifier,
                          builder: (context, alignments, _) {
                            final count = alignments.where((a) => a['is_analyzing'] != true).length;
                            final streak = _streak(alignments);
                            return Stack(
                              children: [
                                ListView(
                              controller: _scrollCtrl,
                              padding: EdgeInsets.fromLTRB(20, 88, 20, 40),
                              children: [
                                const SizedBox(height: 0),
                                if (_firstName == null)
                                  Container(
                                    height: 180,
                                    decoration: ShapeDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.06)
                                          : Colors.black.withValues(alpha: 0.04),
                                      shape: SmoothRectangleBorder(
                                        borderRadius: SmoothBorderRadius(cornerRadius: 20, cornerSmoothing: 0.6),
                                      ),
                                    ),
                                  )
                                else
                                  UserCard(
                                    firstName: _firstName!,
                                    memberSince: _memberSince,
                                    analysisCount: count,
                                    streak: streak,
                                    isDark: isDark,
                                  ),
                                const SizedBox(height: 28),
                                Container(
                                  decoration: ShapeDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.04),
                                    shape: SmoothRectangleBorder(
                                      borderRadius: SmoothBorderRadius(cornerRadius: 16, cornerSmoothing: 0.6),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 32),
                                  child: Center(child: _PullCordThemeSwitcher(isDark: isDark)),
                                ),
                                const SizedBox(height: 16),
                                Tappable(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _showIconPicker(context);
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    height: 52,
                                    decoration: ShapeDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.06)
                                          : Colors.black.withValues(alpha: 0.04),
                                      shape: SmoothRectangleBorder(
                                        borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Row(
                                        children: [
                                          Icon(CupertinoIcons.app_fill,
                                              size: 18,
                                              color: isDark
                                                  ? Colors.white.withValues(alpha: 0.55)
                                                  : Colors.black.withValues(alpha: 0.4)),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'App Icon',
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: isDark
                                                    ? Colors.white.withValues(alpha: 0.85)
                                                    : Colors.black.withValues(alpha: 0.75),
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          ),
                                          Icon(CupertinoIcons.chevron_right,
                                              size: 14,
                                              color: isDark
                                                  ? Colors.white.withValues(alpha: 0.25)
                                                  : Colors.black.withValues(alpha: 0.2)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Tappable(
                                  onTap: () async => AuthService.signOut(),
                                  child: Container(
                                    width: double.infinity,
                                    height: 52,
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
                                          fontSize: 16,
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
                            // ── Pinned gradient header ──
                            Positioned(
                              top: 0, left: 0, right: 0,
                              child: _ProfileGradientHeader(isDark: isDark, email: email),
                            ),
                          ],
                            );
                          },
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


// ── Profile gradient header ───────────────────────────────────────────────────
class _ProfileGradientHeader extends StatelessWidget {
  final bool isDark;
  final String email;
  const _ProfileGradientHeader({required this.isDark, required this.email});

  @override
  Widget build(BuildContext context) {
    const topPad = 8.0;
    const titleH = 52.0;
    const totalH = 72.0;
    final fadeColor = isDark ? Colors.black : Colors.white;
    final a = isDark ? 0.65 : 0.85;

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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Profile',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
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

// ── App Icon Picker ───────────────────────────────────────────────────────────

/// Null iconKey means the primary (default) icon.
const _kAppIcons = [
  (null,               'dark mode.png',                        'Dark'),
  ('icon_light_mode',  'light mode.png',                       'Light'),
  ('icon_cloudy_sky',  'cloudy sky.png',                       'Cloudy Sky'),
  ('icon_cool_candy',  'cool candy.png',                       'Cool Candy'),
  ('icon_gradient',    'gradient display.png',                 'Gradient'),
  ('icon_hard_candy',  'hard candy.png',                       'Hard Candy'),
  ('icon_mint_dark',   'mint green with dark accents.png',     'Mint Dark'),
  ('icon_mint_white',  'mint green with white accents.png',    'Mint White'),
  ('icon_pulse',       'pulse.png',                            'Pulse'),
  ('icon_sea_green',   'sea green.png',                        'Sea Green'),
];

class _IconPickerSheet extends StatefulWidget {
  const _IconPickerSheet();

  @override
  State<_IconPickerSheet> createState() => _IconPickerSheetState();
}

class _IconPickerSheetState extends State<_IconPickerSheet>
    with SingleTickerProviderStateMixin {
  String? _current; // null = primary/default

  OverlayEntry? _toastEntry;
  late final AnimationController _toastCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void dispose() {
    _toastCtrl.dispose();
    _toastEntry?.remove();
    super.dispose();
  }

  Future<void> _loadCurrent() async {
    try {
      final name = await FlutterDynamicIcon.getAlternateIconName();
      if (mounted) setState(() => _current = name);
    } catch (_) {}
  }

  void _showPillToast() {
    _toastEntry?.remove();
    _toastCtrl.value = 0;

    _toastEntry = OverlayEntry(
      builder: (_) => _IconChangedToast(slideAnim: _toastCtrl),
    );
    Overlay.of(context).insert(_toastEntry!);
    _toastCtrl.forward();

    Future.delayed(const Duration(milliseconds: 1600), () async {
      if (!mounted) return;
      await _toastCtrl.reverse();
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  Future<void> _setIcon(String? iconKey) async {
    if (_current == iconKey) return;
    try {
      final supported = await FlutterDynamicIcon.supportsAlternateIcons;
      if (!supported) return;
      await FlutterDynamicIcon.setAlternateIconName(iconKey);
      if (!mounted) return;
      setState(() => _current = iconKey);
      HapticFeedback.mediumImpact();
      _showPillToast();
    } catch (e) {
      debugPrint('Icon change failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final cardRadius = SmoothBorderRadius(cornerRadius: 26, cornerSmoothing: 0.6);

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
              padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'App Icon',
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: scheme.onSurface,
                            decoration: TextDecoration.none,
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
                  const SizedBox(height: 2),
                  Text(
                    'Choose how Align looks on your home screen',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Icon grid — fixed 90px cell height to avoid overflow
                  GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: _kAppIcons.length,
                    itemBuilder: (_, i) {
                      final (key, file, label) = _kAppIcons[i];
                      final selected = _current == key;
                      return Tappable(
                        onTap: () => _setIcon(key),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.all(2.5),
                                decoration: ShapeDecoration(
                                  shape: SmoothRectangleBorder(
                                    borderRadius: SmoothBorderRadius(cornerRadius: 17, cornerSmoothing: 0.6),
                                    side: BorderSide(
                                      color: selected ? scheme.primary : Colors.transparent,
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                                child: ClipSmoothRect(
                                  radius: SmoothBorderRadius(cornerRadius: 13, cornerSmoothing: 0.6),
                                  child: Image.asset(
                                    'lib/assets/app_icons/$file',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                color: selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
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
    );
  }
}

class _IconChangedToast extends StatelessWidget {
  final Animation<double> slideAnim;
  const _IconChangedToast({required this.slideAnim});

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
                              const Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                size: 22,
                                color: Color(0xFF30D158),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'App icon changed',
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
