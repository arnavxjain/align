import 'package:flutter/material.dart';
import '../widgets/spline_orb.dart';

class SplineOrbDemo extends StatelessWidget {
  const SplineOrbDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SplineOrb(width: 300, height: 300),
      ),
    );
  }
}
