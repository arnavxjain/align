import 'dart:ui';

import 'package:flutter/material.dart';

/// Gradient frosted-glass blur over the status bar area.
/// Blur intensity is strongest at the top and fades to zero using stacked strips.
/// Must be a direct child of a [Stack].
class StatusBarBlur extends StatelessWidget {
  const StatusBarBlur({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    if (topPad == 0) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0F) : Colors.white;
    final totalHeight = topPad + 45.0;
    const steps = 20;
    const maxSigma = 18.0;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          children: [
            // Gradient blur: 10 strips, sigma falls off quadratically from top to bottom
            ...List.generate(steps, (i) {
              final t = 1.0 - (i / (steps - 1));
              final sigma = maxSigma * t * t * t; // cubic falloff — slower fade
              if (sigma < 0.5) return const SizedBox.shrink();
              final stripTop = totalHeight * i / steps;
              final stripHeight = totalHeight / steps + 1; // +1px to avoid gaps

              return Positioned(
                top: stripTop,
                left: 0,
                right: 0,
                height: stripHeight,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              );
            }),

            // Subtle tint that fades toward transparent at the bottom
            Container(
              height: totalHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bg.withValues(alpha: 0.5),
                    bg.withValues(alpha: 0.0),
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
