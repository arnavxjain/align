import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../widgets/tappable.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({required this.onComplete, super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  int _page = 0;
  final Set<String> _selected = {};
  double _age = 22;
  bool _isLoading = false;

  static const _useCases = [
    ('Articles',    CupertinoIcons.doc_text_fill),
    ('Posts',       CupertinoIcons.pencil),
    ('Videos',      CupertinoIcons.play_rectangle_fill),
    ('Podcasts',    CupertinoIcons.mic_fill),
    ('Research',    CupertinoIcons.search),
    ('Newsletters', CupertinoIcons.mail_solid),
    ('Social Media',CupertinoIcons.globe),
    ('Learning',    CupertinoIcons.book_fill),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _next() {
    setState(() => _page++);
    _pageController.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _submit() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.saveProfile(
        userId: user.id,
        email: user.email ?? '',
        firstName: _nameController.text.trim(),
        useCases: _selected.toList(),
        age: _age.round(),
      );
      widget.onComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = Theme.of(context).copyWith(brightness: Brightness.light);
    final scheme = lightTheme.colorScheme;

    return Theme(
      data: lightTheme,
      child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),

            // Step indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: active
                        ? scheme.primary
                        : scheme.onSurface.withAlpha(40),
                  ),
                );
              }),
            ),

            const SizedBox(height: 8),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _NameStep(
                    controller: _nameController,
                    onNext: _next,
                  ),
                  _UseCasesStep(
                    useCases: _useCases,
                    selected: _selected,
                    onToggle: (label) => setState(() =>
                        _selected.contains(label)
                            ? _selected.remove(label)
                            : _selected.add(label)),
                    onNext: _next,
                  ),
                  _AgeStep(
                    age: _age,
                    onChanged: (v) => setState(() => _age = v),
                    onSubmit: _isLoading ? null : _submit,
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _NameStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onNext;

  const _NameStep({required this.controller, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            "What should\nwe call you?",
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              height: 1.15,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Just your first name is fine.",
            style: GoogleFonts.inter(
              fontSize: 15,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 40),
          _OnboardingField(controller: controller, label: 'First name'),
          const Spacer(),
          _OnboardingButton(
            label: 'Continue',
            onTap: controller.text.trim().isEmpty ? () => print('eh') : onNext,
            // rebuild on text change
            listenable: controller,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _UseCasesStep extends StatelessWidget {
  final List<(String, IconData)> useCases;
  final Set<String> selected;
  final void Function(String) onToggle;
  final VoidCallback onNext;

  const _UseCasesStep({
    required this.useCases,
    required this.selected,
    required this.onToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            "What will you\nuse Align for?",
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              height: 1.15,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Pick as many as you like.",
            style: GoogleFonts.inter(
              fontSize: 15,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              itemCount: useCases.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemBuilder: (context, i) {
                final (label, icon) = useCases[i];
                final isSelected = selected.contains(label);
                return Tappable(
                  onTap: () => onToggle(label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: ShapeDecoration(
                      color: isSelected
                          ? scheme.primary.withAlpha(30)
                          : isDark
                              ? const Color(0xFF1C1C1E)
                              : const Color(0xFFF2F2F7),
                      shape: SmoothRectangleBorder(
                        borderRadius: SmoothBorderRadius(
                          cornerRadius: 16,
                          cornerSmoothing: 0.6,
                        ),
                        side: isSelected
                            ? BorderSide(color: scheme.primary, width: 1.5)
                            : BorderSide.none,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: isSelected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _OnboardingButton(label: 'Continue', onTap: onNext),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Step 3: Age ───────────────────────────────────────────────────────────────

class _AgeStep extends StatelessWidget {
  final double age;
  final ValueChanged<double> onChanged;
  final VoidCallback? onSubmit;
  final bool isLoading;

  const _AgeStep({
    required this.age,
    required this.onChanged,
    required this.onSubmit,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Text(
            "How old are you?",
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              height: 1.15,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "We use this to personalise your experience.",
            style: GoogleFonts.inter(
              fontSize: 15,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),

          // Large age display
          Center(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${age.round()}',
                    style: GoogleFonts.inter(
                      fontSize: 72,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      letterSpacing: -2,
                    ),
                  ),
                  TextSpan(
                    text: ' yrs',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          _Ios26Slider(value: age, min: 13, max: 80, onChanged: onChanged),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('13', style: GoogleFonts.inter(fontSize: 12, color: scheme.onSurfaceVariant)),
              Text('80', style: GoogleFonts.inter(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),

          const Spacer(),
          _OnboardingButton(
            label: "Let's go",
            onTap: onSubmit,
            isLoading: isLoading,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _OnboardingField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _OnboardingField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: ShapeDecoration(
        color: scheme.surface,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
        ),
        shadows: isDark
            ? []
            : [const BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: GoogleFonts.inter(fontSize: 16, color: scheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 15, color: scheme.onSurfaceVariant),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      ),
    );
  }
}

// Button that can optionally listen to a Listenable to rebuild when e.g. a
// TextEditingController changes (so disabled state updates live).
class _OnboardingButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final Listenable? listenable;

  const _OnboardingButton({
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.listenable,
  });

  @override
  Widget build(BuildContext context) {
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable!,
        builder: (_, _) => _button(context),
      );
    }
    return _button(context);
  }

  Widget _button(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tappable(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: ShapeDecoration(
            color: scheme.primary,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
            ),
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── iOS 26-style slider ───────────────────────────────────────────────────────

class _Ios26Slider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  static const double _trackHeight = 30;
  static const double _thumbRadius = 12;

  const _Ios26Slider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: _trackHeight,
        trackShape: const _CapsuleTrackShape(),
        thumbShape: const _InsetThumbShape(radius: _thumbRadius),
        overlayShape: SliderComponentShape.noOverlay,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: isDark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFFDDDDDD),
        thumbColor: Colors.white,
      ),
      child: Slider(value: value, min: min, max: max, onChanged: onChanged),
    );
  }
}

class _CapsuleTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _CapsuleTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final canvas = context.canvas;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final radius = Radius.circular(rect.height / 2);
    final capsule = RRect.fromRectAndRadius(rect, radius);

    // Full inactive track
    canvas.drawRRect(capsule, Paint()..color = sliderTheme.inactiveTrackColor!);

    // Active fill — clipped to capsule so the left edge stays rounded
    canvas.save();
    canvas.clipRRect(capsule);
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.top, thumbCenter.dx, rect.bottom),
      Paint()..color = sliderTheme.activeTrackColor!,
    );
    canvas.restore();
  }
}

class _InsetThumbShape extends SliderComponentShape {
  final double radius;

  const _InsetThumbShape({required this.radius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // Soft drop shadow
    canvas.drawCircle(
      center + const Offset(0, 1.5),
      radius,
      Paint()
        ..color = Colors.black.withAlpha(55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // White thumb
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
  }
}
