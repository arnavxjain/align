import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0F) : Colors.white;
    final logoColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SvgPicture.asset(
          'lib/assets/logo.svg',
          width: 72,
          colorFilter: ColorFilter.mode(logoColor, BlendMode.srcIn),
        ),
      ),
    );
  }
}
