import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'providers/theme_notifier.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/new_alignment.dart';
import 'screens/onboarding.dart';
import 'screens/splash.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'theme/app_theme.dart';
import 'widgets/creative_session_pill.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled Flutter framework errors — log in debug, suppress stack
  // traces in release so internal paths are never exposed to the user.
  FlutterError.onError = (details) {
    if (kDebugMode) {
      FlutterError.presentError(details);
    } else {
      debugPrint('Unhandled Flutter error: ${details.exceptionAsString()}');
    }
  };

  // Catch unhandled async errors on the root isolate.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled platform error: $error');
    return true; // mark as handled so the app doesn't crash
  };

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  await loadSavedTheme();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeNotifier.addListener(_onThemeChanged);
    _initDeepLinks();
  }

  void _initDeepLinks() {
    DeepLinkService.init(_handleDeepLink);
    // Drain any URL the app was cold-started with.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => DeepLinkService.checkInitialLink(),
    );
  }

  void _handleDeepLink(String rawUrl) {
    final url = DeepLinkService.parseNewAlignmentUrl(rawUrl);
    if (url == null) return;
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    // Only open if the user is signed in; otherwise the deep link is silently dropped.
    if (Supabase.instance.client.auth.currentSession == null) return;
    showNewAlignmentModal(ctx, initialUrl: url);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final systemBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    // User override takes priority; fall back to system brightness
    final themeMode = themeNotifier.value == ThemeMode.system
        ? (systemBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light)
        : themeNotifier.value;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.light(const Color(0xFF007AFF)),
      darkTheme: AppTheme.dark(const Color(0xFF0A84FF)),
      themeMode: themeMode,
      home: const AuthGate(),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          const CreativeSessionPill(),
        ],
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with SingleTickerProviderStateMixin {
  String? _checkedUserId;
  bool? _hasProfile;

  late final AnimationController _fadeIn;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeIn, curve: Curves.easeOut);
    _fadeIn.forward();
  }

  @override
  void dispose() {
    _fadeIn.dispose();
    super.dispose();
  }

  void _fetchProfile(String userId) {
    if (_checkedUserId == userId) return;
    _checkedUserId = userId;
    _hasProfile = null;
    AuthService.hasProfile(userId).then((result) {
      if (mounted) setState(() => _hasProfile = result);
    });
  }

  Widget _currentScreen(AsyncSnapshot<AuthState> snapshot, Session? session) {
    if (!snapshot.hasData && session == null) {
      return const SplashScreen(key: ValueKey('splash'));
    }
    if (session == null) {
      _checkedUserId = null;
      _hasProfile = null;
      return const LoginScreen(key: ValueKey('login'));
    }
    _fetchProfile(session.user.id);
    if (_hasProfile == null) {
      return const SplashScreen(key: ValueKey('splash'));
    }
    if (_hasProfile!) return const Home(key: ValueKey('home'));
    return OnboardingScreen(
      key: const ValueKey('onboarding'),
      onComplete: () => setState(() => _hasProfile = true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = snapshot.data?.session
              ?? Supabase.instance.client.auth.currentSession;

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _currentScreen(snapshot, session),
          );
        },
      ),
    );
  }
}
