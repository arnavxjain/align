import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/theme_notifier.dart';
import '../services/auth_service.dart';
import '../widgets/page_header.dart';
import '../widgets/tappable.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final email = user?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: PageHeader(title: 'Profile', subtitle: email),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),

                    // Avatar
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.primary, width: 2.5),
                        ),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment(-0.7, -0.9),
                              end: Alignment(0.7, 0.9),
                              colors: [Color(0xFF8E8E93), Color(0xFF3A3A3C)],
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.person, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Settings section label
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

                    // Settings group
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

                    // Sign out
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings row widgets ──────────────────────────────────────────────────────

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
            Icon(
              CupertinoIcons.chevron_right,
              color: scheme.onSurfaceVariant,
              size: 15,
            ),
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
                final mode = on ? ThemeMode.dark : ThemeMode.light;
                themeNotifier.value = mode;
                saveTheme(mode);
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
        width: 32,
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: swatch, width: 2),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isSelected ? 22 : 26,
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
              Icon(CupertinoIcons.paintbrush_fill, color: scheme.onSurfaceVariant, size: 20),
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
            builder: (context, selectedId, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: kAccentOptions.map((option) => _ColorSwatch(
                  option: option,
                  isSelected: option.id == selectedId,
                  isDark: isDark,
                )).toList(),
              );
            },
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
