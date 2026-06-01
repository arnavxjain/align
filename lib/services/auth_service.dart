import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _supabase = Supabase.instance.client;

  static User? get currentUser => _supabase.auth.currentUser;

  static Future<void> sendEmailOtp(String email) {
    return _supabase.auth.signInWithOtp(email: email);
  }

  static Future<AuthResponse> verifyEmailOtp(String email, String token) {
    return _supabase.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
  }

  // Opens Safari for Google OAuth. Supabase + app_links handles the redirect
  // back automatically via the io.supabase.align:// URL scheme.
  static Future<bool> signInWithGoogle() {
    return _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.align://login-callback/',
    );
  }

  static Future<AuthResponse> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256ofString(rawNonce);

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null) throw Exception('No ID token returned from Apple');

    return _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  static Future<bool> hasProfile(String userId) async {
    final data = await _supabase
        .from('user_profiles')
        .select('id')
        .eq('id', userId)
        .maybeSingle();
    return data != null;
  }

  static Future<void> saveProfile({
    required String userId,
    required String email,
    required String firstName,
    required List<String> useCases,
    required int age,
  }) async {
    await _supabase.from('user_profiles').upsert({
      'id': userId,
      'email': email,
      'first_name': firstName,
      'use_cases': useCases,
      'age': age,
    });
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
