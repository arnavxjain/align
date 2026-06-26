import 'package:flutter/services.dart';

/// Handles incoming align:// deep links from the iOS share extension.
/// Uses a MethodChannel wired to AppDelegate.swift.
class DeepLinkService {
  static const _channel = MethodChannel('com.arnav.align/deeplink');

  static void Function(String url)? _onLink;

  /// Call once at app start. [onLink] is invoked whenever an align:// URL
  /// arrives (both cold-start and while running).
  static void init(void Function(String url) onLink) {
    _onLink = onLink;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final url = call.arguments as String?;
        if (url != null) _onLink?.call(url);
      }
    });
  }

  /// Call after Flutter is fully initialised to drain any URL the app was
  /// opened with before the channel was ready.
  static Future<void> checkInitialLink() async {
    try {
      final url = await _channel.invokeMethod<String>('getInitialLink');
      if (url != null) _onLink?.call(url);
    } catch (_) {}
  }

  /// Parses `align://new?url=<encoded_url>` and returns the URL, or null.
  static String? parseNewAlignmentUrl(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme == 'align' && uri.host == 'new') {
        return uri.queryParameters['url'];
      }
    } catch (_) {}
    return null;
  }
}
