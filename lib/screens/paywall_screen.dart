import 'dart:async';
import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_typography.dart';
import '../services/subscription_service.dart';
import '../widgets/tappable.dart';

class _Benefit {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _Benefit(this.icon, this.color, this.title, this.subtitle);
}

const _kBenefits = [
  _Benefit(CupertinoIcons.star_fill, Color(0xFFBF5AF2),
      'Gemini 2.5 Pro', 'The most advanced AI model\nfor deeper, smarter analysis'),
  _Benefit(CupertinoIcons.shield_fill, Color(0xFF5AC8FA),
      'Realism Checks', 'Catch misleading claims and bias\nwith greater precision'),
  _Benefit(CupertinoIcons.search, Color(0xFF30D158),
      'Product Detection', 'Identify every brand, product,\nand item shown in detail'),
  _Benefit(CupertinoIcons.bubble_left_fill, Color(0xFF64D2FF),
      'Alignment Chat', 'Ask follow-up questions with\nfull context-aware AI'),
  _Benefit(CupertinoIcons.bolt_fill, Color(0xFFFF9F0A),
      'Priority Speed', 'Jump the queue for faster\nanalysis results'),
];

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Offerings? _offerings;
  bool _loadingOfferings = true;
  bool _purchasing = false;
  bool _restoring = false;

  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final next = (_currentPage + 1) % _kBenefits.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
    _loadOfferings();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _loadingOfferings = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingOfferings = false);
    }
  }

  Package? get _package =>
      _offerings?.current?.monthly ??
      _offerings?.current?.availablePackages.firstOrNull;

  Future<void> _subscribe() async {
    final pkg = _package;
    if (pkg == null || _purchasing) return;
    setState(() => _purchasing = true);
    final success = await SubscriptionService.instance.purchase(pkg);
    if (!mounted) return;
    setState(() => _purchasing = false);
    if (success) Navigator.pop(context);
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    final restored = await SubscriptionService.instance.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    if (restored) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active subscription found')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-screen benefit carousel ─────────────────────────────────
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: _kBenefits.length,
            itemBuilder: (context, i) => _BenefitSlide(benefit: _kBenefits[i]),
          ),

          // ── Top bar: logo + close ────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'lib/assets/logo-pro.svg',
                      width: 22, height: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Align Pro',
                      style: AppTypography.navTitle(color: Colors.white)
                          .copyWith(fontSize: 16),
                    ),
                    const Spacer(),
                    ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Tappable(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 38,
                            height: 38,
                            color: Colors.white.withAlpha(35),
                            child: const Icon(
                              CupertinoIcons.xmark,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom floating subscribe bar ────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: ShapeDecoration(
                    color: Colors.black.withAlpha(130),
                    shape: SmoothRectangleBorder(
                      borderRadius: SmoothBorderRadius(
                        cornerSmoothing: 0.6,
                        cornerRadius: 23
                      )
                    )
                  ),
                  padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad + 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Page indicator dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_kBenefits.length, (i) {
                          final active = i == _currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: active ? 22 : 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.white
                                  : Colors.white.withAlpha(70),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),

                      // Frosted glass subscribe button
                      Tappable(
                        onTap: _subscribe,
                        scaleOnPress: true,
                        child: ClipSmoothRect(
                          radius: SmoothBorderRadius(
                            cornerRadius: 14,
                            cornerSmoothing: 0.6,
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              width: double.infinity,
                              height: 54,
                              decoration: ShapeDecoration(
                                color: Colors.white.withAlpha(45),
                                shape: SmoothRectangleBorder(
                                  borderRadius: SmoothBorderRadius(
                                    cornerRadius: 14,
                                    cornerSmoothing: 0.6,
                                  ),
                                  side: BorderSide(
                                    color: Colors.white.withAlpha(65),
                                    width: 0.8,
                                  ),
                                ),
                              ),
                              child: Center(
                                child: _loadingOfferings || _purchasing
                                    ? const SizedBox(
                                        width: 20, height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _package != null
                                            ? 'Subscribe · ${_package!.storeProduct.priceString} / month'
                                            : 'Subscribe',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Column(
                        children: [
                          Tappable(
                            onTap: _restore,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: _restoring
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white38,
                                      ),
                                    )
                                  : Text(
                                      'Restore purchases',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: Colors.white54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                            ),
                          ),
                          Text(r'$2.99/mo')
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitSlide extends StatelessWidget {
  const _BenefitSlide({required this.benefit});
  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.25),
          radius: 1.4,
          colors: [
            benefit.color.withAlpha(75),
            Colors.black,
          ],
        ),
      ),
      // Bottom padding clears the floating subscribe bar
      child: Padding(
        padding: const EdgeInsets.only(bottom: 210),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: ShapeDecoration(
                  color: benefit.color.withAlpha(40),
                  shape: SmoothRectangleBorder(
                    borderRadius: SmoothBorderRadius(
                      cornerRadius: 32,
                      cornerSmoothing: 0.7,
                    ),
                    side: BorderSide(
                      color: benefit.color.withAlpha(85),
                      width: 1.5,
                    ),
                  ),
                ),
                child: Icon(benefit.icon, size: 50, color: benefit.color),
              ),
              const SizedBox(height: 32),
              Text(
                benefit.title,
                style: AppTypography.displayLarge(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                benefit.subtitle,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.white70,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
