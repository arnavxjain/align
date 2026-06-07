import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../providers/theme_notifier.dart';
import '../utils/retry.dart';
import 'gemini_service.dart';
import 'reel_service.dart';

const _uuid = Uuid();

// IDs of analyses currently running (prevents double-start on re-navigation).
final _running = <String>{};

class AnalysisService {
  // ── Load all alignments from Supabase into the global notifier ───────────────

  static Future<void> loadAlignments() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      alignmentsNotifier.value = [];
      return;
    }
    try {
      final data = await withRetry(() => client
          .from('user_profiles')
          .select('saved_analyses')
          .eq('id', userId)
          .single());
      final raw = data['saved_analyses'];
      final list = raw == null
          ? <Map<String, dynamic>>[]
          : (raw as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      list.sort((a, b) {
        final ad =
            DateTime.tryParse(a['created_at'] as String? ?? '') ?? DateTime(0);
        final bd =
            DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime(0);
        return bd.compareTo(ad);
      });
      // Preserve pending (in-progress) and failed entries not yet saved to Supabase.
      final loadedIds = list.map((e) => e['id'] as String? ?? '').toSet();
      final unsaved = alignmentsNotifier.value
          .where((e) =>
              (e['is_analyzing'] == true || e['status'] == 'failed') &&
              !loadedIds.contains(e['id']))
          .toList();
      alignmentsNotifier.value = [...unsaved, ...list];
    } catch (_) {
      alignmentsNotifier.value = [];
    }
  }

  // ── Create a pending entry locally, add to notifier, return it ───────────────

  static Map<String, dynamic> createPendingEntry({
    required String url,
    required String detectedType,
    required bool realismCheck,
    required bool identifyProducts,
    required bool createTimeline,
    required bool findSimilar,
    bool useProModel = false,
  }) {
    final entry = <String, dynamic>{
      'id': _uuid.v4(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'url': url,
      'content_type': _storageType(detectedType),
      'analyses': <String, dynamic>{},
      'is_analyzing': true,
      // Transient — stripped before saving to Supabase.
      '_pending': {
        'realism_check': realismCheck,
        'identify_products': identifyProducts,
        'create_timeline': createTimeline,
        'find_similar': findSimilar,
        'use_pro_model': useProModel,
      },
    };
    alignmentsNotifier.value = [entry, ...alignmentsNotifier.value];
    return entry;
  }

  // ── Run analysis on a pending entry, updating the notifier as results arrive ─

  static bool isRunning(String id) => _running.contains(id);

  static Future<void> runAnalysis({
    required Map<String, dynamic> pendingEntry,
    void Function(String)? onStatus,
    void Function(double)? onProgress,
  }) async {
    final id = pendingEntry['id'] as String;
    if (_running.contains(id)) return;
    _running.add(id);

    // Hoisted so catch block can reference the latest partial state.
    var cur = Map<String, dynamic>.from(pendingEntry);

    try {
      final url = pendingEntry['url'] as String;
      final contentType = pendingEntry['content_type'] as String;
      final isYouTube = contentType == 'youtube';
      final isReel = contentType == 'reel';
      final opts = pendingEntry['_pending'] as Map? ?? {};
      final realismCheck = opts['realism_check'] as bool? ?? false;
      final identifyProducts = opts['identify_products'] as bool? ?? false;
      final createTimeline = opts['create_timeline'] as bool? ?? false;
      final findSimilar = opts['find_similar'] as bool? ?? false;
      final useProModel = opts['use_pro_model'] as bool? ?? false;

      // Fetch title early so the home tile shows something meaningful.
      final title = await GeminiService.fetchTitle(url, isYouTube);
      if (title != null && title.isNotEmpty) {
        cur['title'] = title;
        _update(id, cur);
      }

      // Compute steps for accurate progress.
      final numAnalyses = [realismCheck, identifyProducts, createTimeline, findSimilar]
          .where((b) => b)
          .length;
      final total = (isReel ? 3 : 0) + numAnalyses;
      var done = 0;

      void step() {
        if (total == 0) return;
        done++;
        onProgress?.call(done / total);
      }

      String? geminiFileUri;
      if (isReel) {
        geminiFileUri = await ReelService.prepareForAnalysis(url, onStatus: (msg) {
          onStatus?.call(msg);
          step();
        });
        onStatus?.call('Analysing reel…');
      } else {
        onStatus?.call('Analysing…');
      }

      final analyses = <String, dynamic>{};

      Future<void> run(
        String label,
        String prompt, {
        bool useSearch = false,
        required String key,
      }) async {
        onStatus?.call(label);
        final r = await GeminiService.analyze(
          url: url,
          isYouTube: isYouTube,
          geminiFileUri: geminiFileUri,
          prompt: prompt,
          useSearch: useSearch,
          usePro: useProModel,
        );
        step();
        if (r != null) {
          analyses[key] = r;
          cur['analyses'] = Map<String, dynamic>.from(analyses);
          _update(id, cur);
        }
      }

      if (realismCheck) {
        await run(
          'Checking claims…',
          'Analyze this content and flag any misleading, biased, or exaggerated claims. '
              'Return ONLY a JSON array. Each element must have exactly these keys: '
              '"claim" (string), "verdict" (one of "true", "misleading", "unverified"), '
              '"explanation" (string).',
          key: 'realism_check',
        );
      }

      if (identifyProducts) {
        await run(
          'Identifying products…',
          'Identify all products, brands, or items shown or mentioned in this content. '
              'Return ONLY a JSON array. Each element must have exactly these keys: '
              '"product" (string), "brand" (string), '
              '"context" (timestamp for video, or description of where it appears for text).',
          key: 'products',
        );
      }

      if (createTimeline) {
        await run(
          'Building timeline…',
          'Extract all key events or moments in this content in chronological order. '
              'Return ONLY a JSON array. Each element must have exactly these keys: '
              '"position" (timestamp for video, or sequence number for article), '
              '"event" (string description).',
          key: 'timeline',
        );
      }

      if (findSimilar) {
        await run(
          'Finding similar content…',
          'Find 5 similar articles or videos on the same topic as this content. '
              'Return ONLY a JSON array. Each element must have exactly these keys: '
              '"title" (string), "url" (string), "summary" (one sentence).',
          useSearch: true,
          key: 'similar_content',
        );
      }

      // Extract countries (lightweight, always runs) — must run before file deletion
      final countries = await GeminiService.extractCountries(
        url: url,
        isYouTube: isYouTube,
        geminiFileUri: geminiFileUri,
        usePro: useProModel,
      );
      cur['countries'] = countries;
      _update(id, cur);

      if (geminiFileUri != null) await ReelService.deleteGeminiFile(geminiFileUri);

      cur['is_analyzing'] = false;
      _update(id, cur);

      // Save to Supabase, stripping transient fields.
      final toSave = Map<String, dynamic>.from(cur)
        ..remove('is_analyzing')
        ..remove('_pending');
      await _store(toSave);
    } catch (e) {
      final errMsg = e is ReelDownloadException
          ? e.message
          : _categorizeError(e);
      _update(id, {
        ...cur,
        'is_analyzing': false,
        'status': 'failed',
        'error_message': errMsg,
      });
      rethrow;
    } finally {
      _running.remove(id);
    }
  }

  // ── Star / unstar ─────────────────────────────────────────────────────────────

  static Future<void> loadStarred() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await withRetry(() => client
          .from('user_profiles')
          .select('starred_analyses')
          .eq('id', userId)
          .single());
      final list = (data['starred_analyses'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      starredNotifier.value = list.toSet();
    } catch (_) {}
  }

  static Future<void> toggleStar(String analysisId) async {
    final updated = Set<String>.from(starredNotifier.value);
    if (updated.contains(analysisId)) {
      updated.remove(analysisId);
    } else {
      updated.add(analysisId);
    }
    starredNotifier.value = updated;

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await client
          .from('user_profiles')
          .update({'starred_analyses': updated.toList()})
          .eq('id', userId);
    } catch (_) {}
  }

  // ── Delete ────────────────────────────────────────────────────────────────────

  static Future<void> deleteAlignment(String analysisId) async {
    // Optimistic notifier update.
    final list = List<Map<String, dynamic>>.from(alignmentsNotifier.value);
    list.removeWhere((e) => e['id'] == analysisId);
    alignmentsNotifier.value = list;

    final starred = Set<String>.from(starredNotifier.value);
    if (starred.remove(analysisId)) starredNotifier.value = starred;

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await client
          .from('user_profiles')
          .select('saved_analyses')
          .eq('id', userId)
          .single();
      final current = (data['saved_analyses'] as List?) ?? [];
      final updated =
          current.where((e) => (e as Map)['id'] != analysisId).toList();
      await client
          .from('user_profiles')
          .update({'saved_analyses': updated})
          .eq('id', userId);
    } catch (_) {}
  }

  // ── Chat history ──────────────────────────────────────────────────────────────

  static Future<void> saveChatHistory(
    String alignmentId,
    List<Map<String, dynamic>> messages,
  ) async {
    // Optimistic notifier update.
    final list = List<Map<String, dynamic>>.from(alignmentsNotifier.value);
    final idx = list.indexWhere((e) => e['id'] == alignmentId);
    if (idx >= 0) {
      final updated = Map<String, dynamic>.from(list[idx]);
      updated['chat_history'] = messages;
      list[idx] = updated;
      alignmentsNotifier.value = list;
    }

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await client
          .from('user_profiles')
          .select('saved_analyses')
          .eq('id', userId)
          .single();
      final current = ((data['saved_analyses'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final si = current.indexWhere((e) => e['id'] == alignmentId);
      if (si >= 0) {
        current[si]['chat_history'] = messages;
        await client
            .from('user_profiles')
            .update({'saved_analyses': current})
            .eq('id', userId);
      }
    } catch (_) {}
  }

  // ── Retry support ─────────────────────────────────────────────────────────────

  /// Resets a failed entry back to pending state so it can be re-analysed.
  /// Returns the reset entry, or null if the ID wasn't found.
  static Map<String, dynamic>? resetForRetry(String id) {
    final list = alignmentsNotifier.value;
    final idx = list.indexWhere((e) => e['id'] == id);
    if (idx < 0) return null;
    final reset = Map<String, dynamic>.from(list[idx])
      ..['is_analyzing'] = true
      ..remove('status')
      ..remove('error_message')
      ..['analyses'] = <String, dynamic>{};
    _update(id, reset);
    return reset;
  }

  // ── Private helpers ────────────────────────────────────────────────────────────

  static String _categorizeError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return 'Network error — check your connection and try again.';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'Request timed out — the server took too long to respond.';
    }
    if (msg.contains('429') || msg.contains('quota') || msg.contains('rate')) {
      return 'Rate limit reached — please wait a moment and try again.';
    }
    if (msg.contains('500') || msg.contains('503') || msg.contains('server')) {
      return 'Server error — something went wrong on our end.';
    }
    debugPrint('Analysis error: $e');
    return 'Something went wrong. Please try again.';
  }

  static void _update(String id, Map<String, dynamic> entry) {
    final list = List<Map<String, dynamic>>.from(alignmentsNotifier.value);
    final i = list.indexWhere((e) => e['id'] == id);
    if (i >= 0) {
      list[i] = entry;
      alignmentsNotifier.value = list;
    }
  }

  static String _storageType(String detected) => switch (detected) {
        'Video' => 'youtube',
        'Reel' || 'Short' => 'reel',
        _ => 'article',
      };

  static Future<void> _store(Map<String, dynamic> entry) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await withRetry(() => client.rpc('append_analysis', params: {
          'p_user_id': userId,
          'p_entry': entry,
        }));
  }
}
