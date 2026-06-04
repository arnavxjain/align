import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'providers/theme_notifier.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/onboarding.dart';
import 'services/auth_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  await loadSavedTheme();
  await loadSavedAccent();
  await SubscriptionService.instance.init();

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
    accentNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeNotifier.removeListener(_onThemeChanged);
    accentNotifier.removeListener(_onThemeChanged);
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

    final accent = currentAccent;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent.light),
      darkTheme: AppTheme.dark(accent.dark),
      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _checkedUserId;
  bool? _hasProfile;

  void _fetchProfile(String userId) {
    if (_checkedUserId == userId) return;
    _checkedUserId = userId;
    _hasProfile = null;
    SubscriptionService.instance.identify(userId);
    AuthService.hasProfile(userId).then((result) {
      if (mounted) setState(() => _hasProfile = result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session
            ?? Supabase.instance.client.auth.currentSession;

        if (!snapshot.hasData && session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (session == null) {
          _checkedUserId = null;
          _hasProfile = null;
          return const LoginScreen();
        }

        _fetchProfile(session.user.id);

        if (_hasProfile == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_hasProfile!) return const Home();

        return OnboardingScreen(
          onComplete: () => setState(() => _hasProfile = true),
        );
      },
    );
  }
}
