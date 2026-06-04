import 'dart:io';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/theme_notifier.dart';
import '../services/auth_service.dart';
import '../services/milestone_service.dart';
import '../widgets/page_header.dart';
import '../widgets/tappable.dart';
import '../widgets/user_card.dart';

// ── Profile screen ────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _screenshotCtrl = ScreenshotController();
  String _firstName = '';
  String _memberSince = '';
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
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

  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _screenshotCtrl.capture(pixelRatio: 3.0);
      if (bytes == null) return;
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/align_card.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      debugPrint('Share error: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user   = Supabase.instance.client.auth.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final email  = user?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
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
                        Screenshot(
                          controller: _screenshotCtrl,
                          child: UserCard(
                            firstName:      _firstName,
                            memberSince:    _memberSince,
                            analysisCount:  count,
                            streak:         streak,
                            milestoneTitle: current.title,
                            isDark:         isDark,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── Share button ──────────────────────────────────
                        Center(
                          child: Tappable(
                            onTap: _sharing ? null : _shareCard,
                            scaleOnPress: true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 11),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100),
                                color: scheme.primary.withAlpha(isDark ? 22 : 14),
                                border: Border.all(
                                  color: scheme.primary.withAlpha(isDark ? 55 : 40),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _sharing
                                      ? SizedBox(
                                          width: 13, height: 13,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: scheme.primary,
                                          ),
                                        )
                                      : Icon(
                                          CupertinoIcons.share,
                                          size: 14,
                                          color: scheme.primary,
                                        ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'Share Card',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── Milestone badge + progress ────────────────────
                        _MilestoneSection(
                          current: current,
                          next:    next,
                          count:   count,
                          scheme:  scheme,
                          isDark:  isDark,
                        ),

                        const SizedBox(height: 32),

                        // ── Settings label ────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            'Settings',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),

                        // ── Settings group ────────────────────────────────
                        Container(
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
                          child: Column(
                            children: [
                              _SettingsRow(
                                icon: CupertinoIcons.info_circle_fill,
                                label: 'About App',
                                onTap: () {},
                              ),
                              _Divider(),
                              _SettingsRow(
                                icon: CupertinoIcons.person_crop_circle_fill,
                                label: 'About Developer',
                                onTap: () {},
                              ),
                              _Divider(),
                              _ThemeRow(),
                              _Divider(),
                              _ColorPickerRow(),
                            ],
                          ),
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
    );
  }
}

// ── Milestone badge + progress + list ─────────────────────────────────────────

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
    final nextM = widget.next;
    final progressFraction = nextM == null
        ? 1.0
        : (widget.count - widget.current.count) /
          (nextM.count - widget.current.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Badge: icon + title with subtle glow
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            color: widget.scheme.primary.withAlpha(widget.isDark ? 22 : 14),
            boxShadow: [
              BoxShadow(
                color: widget.scheme.primary.withAlpha(widget.isDark ? 50 : 30),
                blurRadius: 24,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                  icon: widget.current.icon,
                  size: 22,
                  color: widget.scheme.primary),
              const SizedBox(width: 10),
              Text(
                widget.current.title,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: widget.scheme.primary,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (nextM != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressFraction.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor:
                  widget.scheme.primary.withAlpha(widget.isDark ? 35 : 25),
              valueColor:
                  AlwaysStoppedAnimation<Color>(widget.scheme.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${nextM.count - widget.count} '
            '${nextM.count - widget.count == 1 ? 'analysis' : 'analyses'} '
            'until ${nextM.title}',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: widget.scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ] else ...[
          Text(
            'Maximum rank achieved',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: widget.scheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],

        const SizedBox(height: 28),

        // ── Expandable milestones list ─────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Text(
                  'Milestones',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.scheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
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
                ? Container(
                    decoration: ShapeDecoration(
                      color: widget.isDark
                          ? const Color(0xFF1C1C1E)
                          : Colors.white,
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 16,
                          cornerSmoothing: 0.6,
                        ),
                      ),
                    ),
                    child: Column(
                      children: List.generate(kMilestones.length, (i) {
                        final m       = kMilestones[i];
                        final unlocked = widget.count >= m.count;
                        final isLast  = i == kMilestones.length - 1;
                        return Column(
                          children: [
                            _MilestoneRow(
                              milestone: m,
                              unlocked:  unlocked,
                              scheme:    widget.scheme,
                              isDark:    widget.isDark,
                            ),
                            if (!isLast) _Divider(),
                          ],
                        );
                      }),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final MilestoneInfo milestone;
  final bool unlocked;
  final ColorScheme scheme;
  final bool isDark;

  const _MilestoneRow({
    required this.milestone,
    required this.unlocked,
    required this.scheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = unlocked
        ? scheme.primary
        : scheme.onSurfaceVariant.withAlpha(60);
    final textColor = unlocked
        ? scheme.onSurface
        : scheme.onSurface.withAlpha(55);
    final subColor = unlocked
        ? scheme.onSurfaceVariant
        : scheme.onSurfaceVariant.withAlpha(50);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          HugeIcon(icon: milestone.icon, size: 22, color: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                Text(
                  milestone.count == 0
                      ? 'From the start'
                      : '${milestone.count} analyses',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
          if (unlocked)
            Icon(CupertinoIcons.checkmark_circle_fill,
                size: 18, color: scheme.primary)
          else
            Icon(CupertinoIcons.lock_fill,
                size: 15, color: scheme.onSurfaceVariant.withAlpha(45)),
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

class _ColorSwatch extends StatelessWidget {
  final AccentOption option;
  final bool isSelected;
  final bool isDark;

  const _ColorSwatch({
    required this.option,
    required this.isSelected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = isDark ? option.dark : option.light;
    return Tappable(
      onTap: () {
        accentNotifier.value = option.id;
        saveAccent(option.id);
      },
      child: SizedBox(
        width: 32, height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: swatch, width: 2),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width:  isSelected ? 22 : 26,
              height: isSelected ? 22 : 26,
              decoration: BoxDecoration(shape: BoxShape.circle, color: swatch),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.paintbrush_fill,
                  color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: 14),
              Text(
                'Accent Color',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<String>(
            valueListenable: accentNotifier,
            builder: (context, selectedId, _) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: kAccentOptions
                  .map((o) => _ColorSwatch(
                        option: o,
                        isSelected: o.id == selectedId,
                        isDark: isDark,
                      ))
                  .toList(),
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
