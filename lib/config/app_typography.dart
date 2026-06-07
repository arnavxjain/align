import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralised typography tokens for the app.
///
/// Three fonts with distinct roles:
///   • Space Grotesk — headings, screen titles, section labels
///   • Geist          — numbers, data values, technical / content-type labels
///   • Inter          — body text, descriptions, settings labels
class AppTypography {
  AppTypography._();

  // ── Space Grotesk ─────────────────────────────────────────────────────────

  /// 40 px / w800 — milestone modal hero title, major display text
  static TextStyle displayHero({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: color,
      );

  /// 36 px / w800 — paywall benefit slide titles
  static TextStyle displayLarge({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1.0, color: color,
      );

  /// 28 px / w700 — page headers (Profile, etc.)
  static TextStyle heading1({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: color,
      );

  /// 24 px / w700 — milestone hero card title
  static TextStyle heading2({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: color,
      );

  /// 17 px / w700 — navigation bar and screen titles
  static TextStyle navTitle({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: color,
      );

  /// 15 px / w500 — journey milestone row titles (weight varies by state)
  static TextStyle milestoneRowTitle({Color? color, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 15, fontWeight: weight, letterSpacing: -0.2, color: color,
      );

  /// 14 px / w600 — insight card section titles ("Content Type Breakdown", etc.)
  static TextStyle sectionTitle({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: color,
      );

  /// 13 px / w600 + letterSpacing 0.4 — "Settings", "Journey", "RECENT" area labels
  static TextStyle sectionHeader({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: color,
      );

  /// 11 px / w600 — all-caps category labels ("RECENT", "N RESULTS"); callers add letterSpacing
  static TextStyle categoryLabel({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 11, fontWeight: FontWeight.w600, color: color,
      );

  // ── Geist ─────────────────────────────────────────────────────────────────

  /// 26 px / w700 — stat hero values on the insights screen
  static TextStyle statValue({Color? color}) => GoogleFonts.geist(
        fontSize: 26, fontWeight: FontWeight.w700, height: 1, letterSpacing: -0.5, color: color,
      );

  /// 18 px / w700 — stamp badge numeric values on the user card
  static TextStyle stampValue({Color? color}) => GoogleFonts.geist(
        fontSize: 18, fontWeight: FontWeight.w700, height: 1.0, color: color,
      );

  /// 13 px / w600 — chart counts, legend percentages, bar values
  static TextStyle dataLabel({Color? color}) => GoogleFonts.geist(
        fontSize: 13, fontWeight: FontWeight.w600, color: color,
      );

  /// 13 px / w500 — filter chip labels, content-type chips
  static TextStyle chipLabel({Color? color}) => GoogleFonts.geist(
        fontSize: 13, fontWeight: FontWeight.w500, color: color,
      );

  /// 12 px / regular — timestamps, journey counts, minor data labels
  static TextStyle dataSmall({Color? color}) => GoogleFonts.geist(
        fontSize: 12, color: color,
      );

  /// 12 px / regular — "Article · 2 Analyses" content-type subtitles
  static TextStyle contentTypeLabel({Color? color}) => GoogleFonts.geist(
        fontSize: 12, color: color,
      );

  /// 12 px / w600 — timeline position badge ("0:32", "2")
  static TextStyle positionLabel({Color? color}) => GoogleFonts.geist(
        fontSize: 12, fontWeight: FontWeight.w600, color: color,
      );

  /// 10 px / w700 / letterSpacing 0.5 — verdict chips ("TRUE", "MISLEADING")
  static TextStyle verdict({Color? color}) => GoogleFonts.geist(
        fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: color,
      );

  /// 10 px / regular — bar-chart axis day labels
  static TextStyle chartAxisLabel({Color? color}) => GoogleFonts.geist(
        fontSize: 10, color: color,
      );
}
