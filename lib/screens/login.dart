import 'dart:io';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:google_fonts/google_fonts.dart';

import '../config/app_typography.dart';
import '../services/auth_service.dart';
import '../widgets/tappable.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  int _step = 0;
  String _email = '';
  bool _isSignUp = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await AuthService.sendEmailOtp(email);
      setState(() {
        _email = email;
        _step = 1;
      });
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOtp() async {
    try {
      await AuthService.sendEmailOtp(_email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Code resent.'),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 0.6),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  Future<void> _verifyOtp(String code) async {
    if (code.length < 6) return;
    setState(() => _isLoading = true);
    try {
      await AuthService.verifyEmailOtp(_email, code);
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithApple();
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 0.6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = Theme.of(context).copyWith(brightness: Brightness.light);
    final scheme = lightTheme.colorScheme;
    final canUseApple = Platform.isIOS || Platform.isMacOS;

    return Theme(
      data: lightTheme,
      child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                Center(
                  child: SvgPicture.asset(
                    'lib/assets/logo.svg',
                    width: 64,
                    height: 64,
                    colorFilter: ColorFilter.mode(scheme.onSurface, BlendMode.srcIn),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Align',
                  style: AppTypography.displayLarge(color: scheme.onSurface)
                      .copyWith(fontSize: 34, letterSpacing: -0.8),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 6),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    _step == 0
                        ? (_isSignUp ? 'Create your account' : 'Sign in to continue')
                        : 'Enter the code sent to\n$_email',
                    key: ValueKey('$_step$_isSignUp'),
                    style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ),

                const SizedBox(height: 40),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _step == 0
                      ? _EmailStep(
                          key: const ValueKey(0),
                          emailController: _emailController,
                          isLoading: _isLoading,
                          isSignUp: _isSignUp,
                          onToggleMode: () => setState(() => _isSignUp = !_isSignUp),
                          onSend: _sendOtp,
                          onGoogle: _handleGoogleSignIn,
                          onApple: canUseApple ? _handleAppleSignIn : null,
                        )
                      : _OtpStep(
                          key: const ValueKey(1),
                          isLoading: _isLoading,
                          onComplete: _verifyOtp,
                          onResend: _resendOtp,
                          onBack: () => setState(() => _step = 0),
                        ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// ── Step 0: Email ─────────────────────────────────────────────────────────────

class _EmailStep extends StatelessWidget {
  final TextEditingController emailController;
  final bool isLoading;
  final bool isSignUp;
  final VoidCallback onToggleMode;
  final VoidCallback onSend;
  final VoidCallback onGoogle;
  final VoidCallback? onApple;

  const _EmailStep({
    super.key,
    required this.emailController,
    required this.isLoading,
    required this.isSignUp,
    required this.onToggleMode,
    required this.onSend,
    required this.onGoogle,
    this.onApple,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Field(controller: emailController, label: 'Email', keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 14),
        _PrimaryButton(
          label: isSignUp ? 'Create Account' : 'Sign In',
          onTap: isLoading ? null : onSend,
          isLoading: isLoading,
        ),
        const SizedBox(height: 12),
        Center(
          child: Tappable(
            onTap: isLoading ? null : onToggleMode,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                isSignUp ? 'Already have an account? Sign in' : "Don't have an account? Sign up",
                style: TextStyle(color: scheme.primary, fontSize: 15),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(child: Divider(color: scheme.outline, thickness: 0.8)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('or', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
            ),
            Expanded(child: Divider(color: scheme.outline, thickness: 0.8)),
          ],
        ),
        const SizedBox(height: 20),
        _SocialButton(label: 'Continue with Google', icon: const _GoogleG(), onTap: isLoading ? null : onGoogle),
        if (onApple != null) ...[
          const SizedBox(height: 10),
          _SocialButton(
            label: 'Continue with Apple',
            icon: const Icon(Icons.apple, size: 22),
            onTap: isLoading ? null : onApple,
            appleStyle: true,
          ),
        ],
      ],
    );
  }
}

// ── Step 1: OTP ───────────────────────────────────────────────────────────────

class _OtpStep extends StatelessWidget {
  final bool isLoading;
  final ValueChanged<String> onComplete;
  final VoidCallback onResend;
  final VoidCallback onBack;

  const _OtpStep({
    super.key,
    required this.isLoading,
    required this.onComplete,
    required this.onResend,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OtpInput(onComplete: onComplete, enabled: !isLoading),
        const SizedBox(height: 24),
        if (isLoading)
          Center(
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Tappable(
              onTap: onResend,
              child: Text('Resend code', style: TextStyle(color: scheme.primary, fontSize: 15)),
            ),
            Text('  ·  ', style: TextStyle(color: scheme.onSurfaceVariant)),
            Tappable(
              onTap: onBack,
              child: Text('Change email', style: TextStyle(color: scheme.primary, fontSize: 15)),
            ),
          ],
        ),
      ],
    );
  }
}

// ── OTP Input ─────────────────────────────────────────────────────────────────

class _OtpInput extends StatefulWidget {
  final ValueChanged<String> onComplete;
  final bool enabled;

  const _OtpInput({required this.onComplete, this.enabled = true});

  @override
  State<_OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<_OtpInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _focusNode.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _onChanged() {
    setState(() {});
    if (_controller.text.length == 6) widget.onComplete(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            for (int i = 0; i < 6; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _OtpBox(
                  char: i < text.length ? text[i] : '',
                  isActive: i == text.length && _focusNode.hasFocus,
                ),
              ),
            ],
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(counterText: ''),
            ),
          ),
        ),
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  final String char;
  final bool isActive;

  const _OtpBox({required this.char, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 60,
      decoration: ShapeDecoration(
        color: scheme.surface,
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 0.6),
          side: isActive
              ? BorderSide(color: scheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        shadows: isDark ? [] : const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Text(
          char,
          style: GoogleFonts.geist(fontSize: 24, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  const _Field({required this.controller, required this.label, this.keyboardType});

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
        shadows: isDark ? [] : const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        autocorrect: false,
        style: TextStyle(fontSize: 16, color: scheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  const _PrimaryButton({required this.label, this.onTap, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tappable(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 56,
          decoration: ShapeDecoration(
            color: scheme.onSurface,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
            ),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.surface),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: scheme.surface,
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

// appleStyle: true flips bg/fg in dark mode to follow Apple's button guidelines
class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onTap;
  final bool appleStyle;

  const _SocialButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.appleStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg;
    final Color fg;

    if (appleStyle) {
      // Apple guidelines: black in light mode, white in dark mode
      bg = isDark ? Colors.white : const Color(0xFF1C1C1E);
      fg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    } else {
      bg = scheme.surface;
      fg = scheme.onSurface;
    }

    return Tappable(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 56,
          decoration: ShapeDecoration(
            color: bg,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
            ),
            shadows: isDark ? [] : const [
              BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(data: IconThemeData(color: fg, size: 22), child: icon),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: Text(
        'G',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF4285F4), height: 1.18),
      ),
    );
  }
}
