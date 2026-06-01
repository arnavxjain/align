import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

class ReelDownloadException implements Exception {
  final String message;
  const ReelDownloadException(this.message);
  @override
  String toString() => message;
}

class ReelService {
  static const _uploadBase =
      'https://generativelanguage.googleapis.com/upload/v1beta/files';
  static const _filesBase =
      'https://generativelanguage.googleapis.com/v1beta/files';

  /// Downloads the reel from the local backend, uploads it to the Gemini
  /// File API, and returns the Gemini file URI ready for analysis.
  /// [onStatus] receives user-facing progress strings.
  static Future<String> prepareForAnalysis(
    String reelUrl, {
    required void Function(String) onStatus,
  }) async {
    onStatus('Downloading reel…');
    final bytes = await _downloadFromBackend(reelUrl);

    final tempFile = await _saveTempFile(bytes);
    try {
      onStatus('Uploading to Gemini…');
      final (fileName, fileUri) = await _uploadToGemini(bytes);

      onStatus('Processing reel…');
      await _waitForActive(fileName);

      return fileUri;
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  /// Deletes a previously uploaded file from the Gemini File API.
  static Future<void> deleteGeminiFile(String fileUri) async {
    final match = RegExp(r'files/([^/?]+)').firstMatch(fileUri);
    if (match == null) return;
    try {
      await http
          .delete(Uri.parse(
              '$_filesBase/${match.group(1)}?key=${AppConfig.geminiApiKey}'))
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static Future<Uint8List> _downloadFromBackend(String url) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.reelBackendUrl}/download'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${AppConfig.reelBackendApiKey}',
            },
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(minutes: 3));

      if (response.statusCode == 200) return response.bodyBytes;

      String reason = '';
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        reason = (json['error'] ?? json['message'] ?? '').toString();
      } catch (_) {}

      throw ReelDownloadException(
        reason.isNotEmpty
            ? reason
            : "Couldn't download this reel. Make sure the link is public.",
      );
    } on ReelDownloadException {
      rethrow;
    } catch (_) {
      throw const ReelDownloadException(
          "Couldn't download this reel. Make sure the link is public.");
    }
  }

  static Future<File> _saveTempFile(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/reel_${DateTime.now().millisecondsSinceEpoch}.mp4');
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<(String fileName, String fileUri)> _uploadToGemini(
      Uint8List bytes) async {
    const boundary = '----AlignGeminiBoundary';
    const meta = '{"file":{"display_name":"reel.mp4"}}';

    final prefix = '--$boundary\r\n'
        'Content-Type: application/json; charset=utf-8\r\n\r\n'
        '$meta\r\n'
        '--$boundary\r\n'
        'Content-Type: video/mp4\r\n\r\n';
    final suffix = '\r\n--$boundary--\r\n';

    final prefixBytes = utf8.encode(prefix);
    final suffixBytes = utf8.encode(suffix);
    final body =
        Uint8List(prefixBytes.length + bytes.length + suffixBytes.length);
    body.setAll(0, prefixBytes);
    body.setAll(prefixBytes.length, bytes);
    body.setAll(prefixBytes.length + bytes.length, suffixBytes);

    final response = await http
        .post(
          Uri.parse(
              '$_uploadBase?uploadType=multipart&key=${AppConfig.geminiApiKey}'),
          headers: {
            'Content-Type': 'multipart/related; boundary=$boundary',
          },
          body: body,
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw Exception('Gemini upload failed (${response.statusCode})');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final file = json['file'] as Map<String, dynamic>;
    return (file['name'] as String, file['uri'] as String);
  }

  static Future<void> _waitForActive(String fileName) async {
    // fileName is like "files/abc123"
    final fileId = fileName.split('/').last;
    for (int i = 0; i < 40; i++) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final response = await http
            .get(Uri.parse(
                '$_filesBase/$fileId?key=${AppConfig.geminiApiKey}'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) continue;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final state = json['state'] as String?;
        if (state == 'ACTIVE') return;
        if (state == 'FAILED') throw Exception('Gemini file processing failed');
      } catch (e) {
        if (e.toString().contains('processing failed')) rethrow;
      }
    }
    throw Exception('Gemini file processing timed out');
  }
}
