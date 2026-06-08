import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'theme_mode';

// ── Theme ─────────────────────────────────────────────────────────────────────

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> loadSavedTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_kThemeKey);
  themeNotifier.value = switch (saved) {
    'dark'  => ThemeMode.dark,
    'light' => ThemeMode.light,
    _       => ThemeMode.system,
  };
}

Future<void> saveTheme(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kThemeKey, switch (mode) {
    ThemeMode.dark  => 'dark',
    ThemeMode.light => 'light',
    _               => 'system',
  });
}

// ── Starred alignments ────────────────────────────────────────────────────────

final starredNotifier = ValueNotifier<Set<String>>({});

// ── Alignments list ───────────────────────────────────────────────────────────

final alignmentsNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);

// ── Detail page blur (0.0 = no blur, 1.0 = full blur) ────────────────────────
// Updated by AlignmentDetailScreen; home page listens and blurs its content.
final detailBlurNotifier = ValueNotifier<double>(0.0);
