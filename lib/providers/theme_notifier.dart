import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey  = 'theme_mode';
const _kAccentKey = 'accent_color';

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

// ── Accent color ──────────────────────────────────────────────────────────────

class AccentOption {
  final String id;
  final String label;
  final Color light;
  final Color dark;
  const AccentOption({required this.id, required this.label, required this.light, required this.dark});
}

const kAccentOptions = <AccentOption>[
  AccentOption(id: 'blue',   label: 'Blue',   light: Color(0xFF007AFF), dark: Color(0xFF0A84FF)),
  AccentOption(id: 'teal',   label: 'Teal',   light: Color(0xFF32ADE6), dark: Color(0xFF40C8E0)),
  AccentOption(id: 'green',  label: 'Green',  light: Color(0xFF34C759), dark: Color(0xFF30D158)),
  AccentOption(id: 'orange', label: 'Orange', light: Color(0xFFFF9500), dark: Color(0xFFFF9F0A)),
  AccentOption(id: 'red',    label: 'Red',    light: Color(0xFFFF3B30), dark: Color(0xFFFF453A)),
  AccentOption(id: 'pink',   label: 'Pink',   light: Color(0xFFFF2D55), dark: Color(0xFFFF375F)),
  AccentOption(id: 'purple', label: 'Purple', light: Color(0xFFAF52DE), dark: Color(0xFFBF5AF2)),
  AccentOption(id: 'indigo', label: 'Indigo', light: Color(0xFF5856D6), dark: Color(0xFF6E6CF5)),
];

final accentNotifier = ValueNotifier<String>('blue');

AccentOption get currentAccent =>
    kAccentOptions.firstWhere((o) => o.id == accentNotifier.value, orElse: () => kAccentOptions.first);

Future<void> loadSavedAccent() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_kAccentKey);
  if (saved != null && kAccentOptions.any((o) => o.id == saved)) {
    accentNotifier.value = saved;
  }
}

Future<void> saveAccent(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kAccentKey, id);
}

// ── Starred alignments ────────────────────────────────────────────────────────

final starredNotifier = ValueNotifier<Set<String>>({});

// ── Alignments list ───────────────────────────────────────────────────────────

final alignmentsNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
