import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'subscription_service.dart';

class GeminiService {
  static String _buildEndpoint({bool? usePro}) {
    final model = (usePro ?? SubscriptionService.instance.isPro.value)
        ? 'gemini-2.5-pro'
        : 'gemini-2.5-flash';
    return 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
  }

  static Future<List<Map<String, dynamic>>?> analyze({
    required String url,
    required bool isYouTube,
    required String prompt,
    bool useSearch = false,
    String? geminiFileUri,
    bool? usePro,
  }) async {
    final List<Map<String, dynamic>> parts;

    if (geminiFileUri != null) {
      parts = [
        {'text': prompt},
        {'fileData': {'mimeType': 'video/mp4', 'fileUri': geminiFileUri}},
      ];
    } else if (isYouTube) {
      parts = [
        {'text': prompt},
        {'fileData': {'mimeType': 'video/youtube', 'fileUri': sanitizeYouTubeUrl(url)}},
      ];
    } else {
      final text = await _fetchText(url);
      if (text == null) return null;
      parts = [{'text': '$prompt\n\nContent from $url:\n$text'}];
    }

    final body = <String, dynamic>{
      'contents': [
        {'parts': parts}
      ],
      if (useSearch) 'tools': [{'google_search': {}}],
      // Disable thinking to reduce token usage and stay within free-tier quota.
      'generationConfig': {
        'thinkingConfig': {'thinkingBudget': 0},
      },
    };

    try {
      var response = await http
          .post(
            Uri.parse('${_buildEndpoint(usePro: usePro)}?key=${AppConfig.geminiApiKey}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 429) {
        final delay = _parseRetryDelay(response.body);
        debugPrint('Gemini 429 — retrying in ${delay}s');
        await Future.delayed(Duration(seconds: delay + 1));
        response = await http
            .post(
              Uri.parse('${_buildEndpoint(usePro: usePro)}?key=${AppConfig.geminiApiKey}'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 90));
      }

      if (response.statusCode != 200) {
        debugPrint('Gemini ${response.statusCode}: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Thinking models (gemini-2.5-*) prepend thought parts before the real
      // answer. Skip any part where "thought" == true.
      final parts =
          (json['candidates']?[0]?['content']?['parts'] as List?) ?? [];
      final text2 = parts
          .whereType<Map>()
          .where((p) => p['thought'] != true && p['text'] != null)
          .map((p) => p['text'] as String)
          .firstOrNull;
      if (text2 == null) {
        debugPrint('Gemini null text. body=${response.body}');
        return null;
      }

      return _parseJsonArray(text2);
    } catch (e) {
      debugPrint('Gemini analyze error: $e');
      return null;
    }
  }

  static Future<String?> fetchTitle(String url, bool isYouTube) async {
    if (isYouTube) return _fetchYouTubeTitle(url);
    return fetchArticleTitle(url);
  }

  static Future<String?> fetchArticleTitle(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _extractTitle(response.body);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fetchYouTubeTitle(String url) async {
    try {
      final oembedUrl =
          'https://www.youtube.com/oembed?url=${Uri.encodeComponent(sanitizeYouTubeUrl(url))}&format=json';
      final response =
          await http.get(Uri.parse(oembedUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return (jsonDecode(response.body) as Map<String, dynamic>)['title'] as String?;
    } catch (_) {
      return null;
    }
  }

  static String? _extractTitle(String html) {
    // og:title is most reliable
    final ogTag = RegExp(r'<meta[^>]+og:title[^>]*>', caseSensitive: false).firstMatch(html);
    if (ogTag != null) {
      final tag = ogTag.group(0)!;
      final c = RegExp(r'content="([^"]+)"').firstMatch(tag) ??
                RegExp(r"content='([^']+)'").firstMatch(tag);
      if (c != null) return _htmlDecode(c.group(1)!);
    }
    // Fallback to <title>
    final title = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
        .firstMatch(html);
    if (title != null) return _htmlDecode(title.group(1)!.trim());
    return null;
  }

  static String _htmlDecode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();

  static Future<String?> _fetchText(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return _stripHtml(response.body);
    } catch (_) {
      return null;
    }
  }

  static String _stripHtml(String html) {
    var t = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>',
            dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>',
            dotAll: true, caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length > 8000 ? t.substring(0, 8000) : t;
  }

  static String sanitizeYouTubeUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      String? videoId;

      // youtu.be/VIDEO_ID
      if (uri.host == 'youtu.be') {
        videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }

      // youtube.com/watch?v=VIDEO_ID  (www, m, or bare)
      if (videoId == null &&
          (uri.host.endsWith('youtube.com'))) {
        videoId = uri.queryParameters['v'];
      }

      if (videoId != null && videoId.isNotEmpty) {
        return 'https://www.youtube.com/watch?v=$videoId';
      }
    } catch (_) {}
    return url; // return original if parsing fails
  }

  static Future<List<Map<String, dynamic>>> extractCountries({
    required String url,
    required bool isYouTube,
    String? geminiFileUri,
    bool? usePro,
  }) async {
    final result = await analyze(
      url: url,
      isYouTube: isYouTube,
      geminiFileUri: geminiFileUri,
      usePro: usePro,
      prompt:
          'Identify ALL countries that have any meaningful connection to this content. '
          'Include countries where: events or news takes place, people mentioned were born or are from, '
          'brands or products shown originate from, companies are headquartered, locations are filmed or set in, '
          'cultural references originate from, sports teams or athletes are from, or any other meaningful '
          'geographic connection exists. Be thorough and inclusive — if there is any reasonable connection '
          'to a country include it. Return ONLY a JSON array of objects with keys "code" (ISO 3166-1 alpha-2 '
          'uppercase) and "reason" (max 15 words explaining the specific connection). '
          'Example: [{"code":"US","reason":"Jensen Huang is American, NVIDIA headquartered in US"},'
          '{"code":"CN","reason":"China GPU export restrictions central to content"}]. '
          'Return [] only if there is truly no geographic connection whatsoever.',
    );
    if (result == null) return [];
    return result
        .where((e) => e['code'] is String && (e['code'] as String).trim().length == 2)
        .map((e) => <String, dynamic>{
              'code': (e['code'] as String).trim().toUpperCase(),
              'reason': ((e['reason'] as String?) ?? '').trim(),
            })
        .toList();
  }

  static int _parseRetryDelay(String body) {
    try {
      final match = RegExp(r'retry in ([\d.]+)s').firstMatch(body);
      if (match != null) return double.parse(match.group(1)!).ceil();
    } catch (_) {}
    return 60; // safe fallback
  }

  static Future<String?> chat({
    required String systemContext,
    required List<Map<String, dynamic>> history,
    bool? usePro,
  }) async {
    final contents = <Map<String, dynamic>>[];
    for (int i = 0; i < history.length; i++) {
      final msg = history[i];
      final geminiRole = msg['role'] == 'user' ? 'user' : 'model';
      var text = msg['content'] as String;
      if (i == 0 && msg['role'] == 'user') {
        text = '$systemContext\n\n---\n\n$text';
      }
      contents.add({
        'role': geminiRole,
        'parts': [
          {'text': text}
        ],
      });
    }

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'thinkingConfig': {'thinkingBudget': 0},
      },
    };

    try {
      var response = await http
          .post(
            Uri.parse('${_buildEndpoint(usePro: usePro)}?key=${AppConfig.geminiApiKey}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 429) {
        final delay = _parseRetryDelay(response.body);
        debugPrint('Gemini chat 429 — retrying in ${delay}s');
        await Future.delayed(Duration(seconds: delay + 1));
        response = await http
            .post(
              Uri.parse('${_buildEndpoint(usePro: usePro)}?key=${AppConfig.geminiApiKey}'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 60));
      }

      if (response.statusCode != 200) {
        debugPrint('Gemini chat ${response.statusCode}: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final parts =
          (json['candidates']?[0]?['content']?['parts'] as List?) ?? [];
      return parts
          .whereType<Map>()
          .where((p) => p['thought'] != true && p['text'] != null)
          .map((p) => p['text'] as String)
          .firstOrNull;
    } catch (e) {
      debugPrint('Gemini chat error: $e');
      return null;
    }
  }

  static List<Map<String, dynamic>>? _parseJsonArray(String text) {
    try {
      var s = text.trim();
      if (s.startsWith('```')) {
        final lines = s.split('\n');
        s = lines.skip(1).join('\n');
        final end = s.lastIndexOf('```');
        if (end > 0) s = s.substring(0, end).trim();
      }
      final parsed = jsonDecode(s);
      if (parsed is List) return parsed.cast<Map<String, dynamic>>();
    } catch (_) {}
    return null;
  }
}
