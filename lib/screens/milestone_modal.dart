import 'package:confetti/confetti.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../config/app_typography.dart';
import '../services/milestone_service.dart';
import '../widgets/tappable.dart';

class MilestoneModal extends StatefulWidget {
  final MilestoneInfo milestone;

  const MilestoneModal({super.key, required this.milestone});

  static Future<void> show(BuildContext context, MilestoneInfo milestone) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      pageBuilder: (_, __, ___) => MilestoneModal(milestone: milestone),
    );
  }

  @override
  State<MilestoneModal> createState() => _MilestoneModalState();
}

class _MilestoneModalState extends State<MilestoneModal> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 5));
    _confetti.play();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Material(
      color: Colors.black.withAlpha(225),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Confetti from top
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 45,
              gravity: 0.12,
              emissionFrequency: 0.05,
              colors: [
                primary,
                primary.withAlpha(160),
                Colors.white,
                Colors.white.withAlpha(160),
                primary.withAlpha(220),
              ],
            ),
          ),

          // Main content
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(36, 0, 36, bottomPad + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing icon container
                  Container(
                    width: 120,
                    height: 120,
                    decoration: ShapeDecoration(
                      color: primary.withAlpha(22),
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 32,
                          cornerSmoothing: 0.7,
                        ),
                        side: BorderSide(color: primary.withAlpha(75), width: 1.5),
                      ),
                      shadows: [
                        BoxShadow(
                          color: primary.withAlpha(70),
                          blurRadius: 50,
                          spreadRadius: 12,
                        ),
                      ],
                    ),
                    child: HugeIcon(icon: widget.milestone.icon, size: 64, color: primary),
                  ),
                  const SizedBox(height: 28),

                  Text(
                    widget.milestone.title,
                    style: AppTypography.displayHero(color: Colors.white),
                  ),

                  if (widget.milestone.flavourText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.milestone.flavourText!,
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        color: Colors.white60,
                        height: 1.55,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 52),

                  Tappable(
                    onTap: () => Navigator.pop(context),
                    scaleOnPress: true,
                    child: ClipSmoothRect(
                      radius: SmoothBorderRadius(
                        cornerRadius: 16,
                        cornerSmoothing: 0.6,
                      ),
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        color: primary,
                        child: Center(
                          child: Text(
                            'Keep Going',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
