import 'dart:ui' show lerpDouble;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppRoute {
  static CupertinoPageRoute<T> push<T>(Widget page) =>
      CupertinoPageRoute<T>(builder: (_) => page);

  static CupertinoPageRoute<T> modal<T>(Widget page) =>
      CupertinoPageRoute<T>(builder: (_) => page, fullscreenDialog: true);

  /// Like [modal] but transparent — the page below stays painted so it shows
  /// through when the detail page is dragged away from its resting position.
  static _TransparentModalRoute<T> transparentModal<T>(Widget page) =>
      _TransparentModalRoute<T>(builder: (_) => page);
}

class _TransparentModalRoute<T> extends PageRoute<T> {
  _TransparentModalRoute({required this.builder});

  final WidgetBuilder builder;

  @override bool get opaque => false;
  @override bool get maintainState => true;
  @override Color? get barrierColor => null;
  @override String? get barrierLabel => null;
  @override Duration get transitionDuration => const Duration(milliseconds: 380);
  @override Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildPage(context, animation, secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (_, child) => FractionalTranslation(
        translation: Offset(0, 1.0 - curved.value),
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    );
  }
}

/// Expands from [sourceRect] to fill the screen.
/// [initialSkew] is the Y-skew (radians) of the source card — it animates to
/// 0 alongside the expansion so the card visually un-tilts as it grows.
class CardExpandRoute extends PageRoute<void> {
  CardExpandRoute({
    required this.sourceRect,
    required this.builder,
    this.initialSkew = 0.0,
  });

  final Rect sourceRect;
  final WidgetBuilder builder;
  final double initialSkew;

  @override bool get opaque => false;
  @override Color? get barrierColor => null;
  @override String? get barrierLabel => null;
  @override bool get maintainState => true;
  @override Duration get transitionDuration => const Duration(milliseconds: 540);
  @override Duration get reverseTransitionDuration => const Duration(milliseconds: 460);

  // easeOutBack: overshoots slightly as the card fills the screen (spring in).
  static const _pushCurve = Cubic(0.175, 0.885, 0.320, 1.275);
  // easeInBack: dips slightly past the card size on landing then bounces back.
  static const _popCurve  = Cubic(0.600, -0.280, 0.735, 0.045);

  @override
  Widget buildPage(context, animation, secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: _pushCurve,
      reverseCurve: _popCurve,
    );

    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (ctx, child) {
        final t = curved.value;
        // Clamp only the rect/radius so the clip never escapes the screen;
        // let skew overshoot freely so the spring feels physical.
        final tRect = t.clamp(0.0, 1.0);
        final size = MediaQuery.of(ctx).size;
        final full = Rect.fromLTWH(0, 0, size.width, size.height);
        final rect   = Rect.lerp(sourceRect, full, tRect)!;
        final radius = lerpDouble(22.0, 0.0, tRect)!;
        final skew   = lerpDouble(initialSkew, 0.0, t)!;   // unclamped → spring

        // Direction-aware opacities so push and pop behave independently.
        final isPop = animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;

        // Push: overlay fades in over the first ~14% so the source card stays
        //       at its z-order in the deck until the overlay is large enough.
        // Pop:  overlay fades out in the last 35% so the real deck card shows
        //       through at its correct z-order before the overlay shrinks to it.
        final overlayOpacity = isPop
            ? (tRect / 0.35).clamp(0.0, 1.0)
            : (tRect * 7).clamp(0.0, 1.0);

        // Push: detail content fades in during the second half of expansion.
        // Pop:  detail content fades out quickly (gone by 65% shrinkage) so the
        //       card never shows a half-sized detail layout.
        final contentOpacity = isPop
            ? ((tRect - 0.65) / 0.35).clamp(0.0, 1.0)
            : ((tRect - 0.45) / 0.55).clamp(0.0, 1.0);

        return Stack(
          children: [
            // Scaffold background fades in/out.
            Opacity(
              opacity: Curves.easeIn.transform(tRect),
              child: Container(color: Theme.of(ctx).scaffoldBackgroundColor),
            ),
            // Card expands/contracts: rect, skew, and corner radius all animate.
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: overlayOpacity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.skewY(skew),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: size.width,
                      maxWidth: size.width,
                      minHeight: size.height,
                      maxHeight: size.height,
                      child: Opacity(
                        opacity: contentOpacity,
                        child: child!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
