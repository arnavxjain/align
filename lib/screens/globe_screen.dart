import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_typography.dart';

enum _GlobeView { analyses, markets }

class GlobeScreen extends StatefulWidget {
  const GlobeScreen({super.key});

  @override
  State<GlobeScreen> createState() => _GlobeScreenState();
}

class _GlobeScreenState extends State<GlobeScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  Map<String, List<Map<String, dynamic>>> _countryAnalyses = {};
  Timer? _retryTimer;

  static const _kSymbolToCountry = {
    '^GSPC': 'US', '^FTSE': 'GB', '^N225': 'JP', '^GDAXI': 'DE', '^FCHI': 'FR',
    '000300.SS': 'CN', '^NSEI': 'IN', '^AXJO': 'AU', '^GSPTSE': 'CA', '^KS11': 'KR',
    '^BVSP': 'BR', '^HSI': 'HK', 'FTSEMIB.MI': 'IT', '^IBEX': 'ES', '^AEX': 'NL',
    '^SSMI': 'CH', '^OMX': 'SE', '^STI': 'SG', '^MXX': 'MX', '^TASI.SR': 'SA',
    '^J200.JO': 'ZA', '^TWII': 'TW', 'IMOEX.ME': 'RU', '^FTADGI': 'AE', '^JKSE': 'ID',
  };
  static const _kIndexDescriptions = {
    '^GSPC': 'Tracks the 500 largest US companies',
    '^FTSE': 'Top 100 companies on the London Stock Exchange',
    '^N225': "Japan's leading 225 blue-chip companies",
    '^GDAXI': "Germany's 40 largest publicly traded companies",
    '^FCHI': "France's 40 most significant listed companies",
    '000300.SS': '300 stocks traded on Shanghai and Shenzhen exchanges',
    '^NSEI': '50 largest Indian companies across key sectors',
    '^AXJO': "Australia's top 200 ASX-listed companies",
    '^GSPTSE': 'Largest companies on the Toronto Stock Exchange',
    '^KS11': 'All common stocks traded on the Korea Exchange',
    '^BVSP': "Brazil's most traded and representative stocks",
    '^HSI': "Hong Kong's largest and most liquid companies",
    'FTSEMIB.MI': "Italy's 40 most liquid and capitalised stocks",
    '^IBEX': "Spain's 35 most liquid stocks",
    '^AEX': "Amsterdam's 25 most actively traded companies",
    '^SSMI': "Switzerland's 20 most significant blue-chip stocks",
    '^OMX': "Sweden's most-traded large-cap companies",
    '^STI': "Singapore's 30 representative listed companies",
    '^MXX': "Mexico's 35 most actively traded stocks",
    '^TASI.SR': 'All listed companies on the Saudi Exchange',
    '^J200.JO': "South Africa's 40 largest listed companies",
    '^TWII': 'All common shares listed on the Taiwan Stock Exchange',
    'IMOEX.ME': "Russia's 50 most liquid exchange-listed stocks",
    '^FTADGI': 'All stocks listed on the Abu Dhabi Stock Exchange',
    '^JKSE': "Indonesia's composite index of all listed stocks",
  };
  static const _kCountryNames = {
    'US': 'United States', 'GB': 'United Kingdom', 'JP': 'Japan',
    'DE': 'Germany', 'FR': 'France', 'CN': 'China', 'IN': 'India',
    'AU': 'Australia', 'CA': 'Canada', 'KR': 'South Korea',
    'BR': 'Brazil', 'HK': 'Hong Kong', 'IT': 'Italy', 'ES': 'Spain',
    'NL': 'Netherlands', 'CH': 'Switzerland', 'SE': 'Sweden',
    'SG': 'Singapore', 'MX': 'Mexico', 'SA': 'Saudi Arabia',
    'ZA': 'South Africa', 'TW': 'Taiwan', 'RU': 'Russia',
    'AE': 'UAE', 'ID': 'Indonesia',
  };

  _GlobeView _currentView = _GlobeView.analyses;
  Map<String, Map<String, dynamic>> _marketData = {};
  DateTime? _marketFetchTime;
  bool _fetchingMarkets = false;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'CountryTapped',
        onMessageReceived: (msg) => _onCountryTapped(msg.message),
      )
      ..addJavaScriptChannel(
        'GlobeReady',
        onMessageReceived: (_) => _cancelRetry(),
      )
      ..addJavaScriptChannel(
        'MarketCountryTapped',
        onMessageReceived: (msg) => _onMarketCountryTapped(msg.message),
      )
      ..addJavaScriptChannel(
        'GlobeStatus',
        onMessageReceived: (msg) => debugPrint('[GlobeStatus] ${msg.message}'),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          setState(() => _isLoading = false);
          _loadGeoJson();
        },
      ))
      ..loadFlutterAsset('lib/assets/globe.html');

    _fetchAnalyses();
  }

  Future<void> _loadGeoJson() async {
    const urls = [
      'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson',
      'https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector/geojson/ne_110m_admin_0_countries.geojson',
    ];
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          await _controller.runJavaScript('setGeoJson(${response.body})');
          debugPrint('[GeoJSON] injected ${response.body.length} chars');
          return;
        }
        debugPrint('[GeoJSON] $url → ${response.statusCode}');
      } catch (e) {
        debugPrint('[GeoJSON] $url error: $e');
      }
    }
    debugPrint('[GeoJSON] all sources failed');
  }

  Future<void> _fetchAnalyses() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('saved_analyses')
        .eq('id', user.id)
        .single();

    final List<dynamic> analyses = response['saved_analyses'] ?? [];
    final Map<String, List<Map<String, dynamic>>> countryMap = {};

    for (final analysis in analyses) {
      final raw = analysis['countries'];
      if (raw is! List) continue;
      for (final country in raw) {
        final String code;
        final String? reason;
        if (country is Map) {
          code = ((country['code'] as String?) ?? '').trim().toUpperCase();
          reason = (country['reason'] as String?)?.trim();
        } else {
          code = country.toString().trim().toUpperCase();
          reason = null;
        }
        if (code.length != 2) continue;
        countryMap.putIfAbsent(code, () => []);
        final entry = Map<String, dynamic>.from(analysis);
        if (reason != null && reason.isNotEmpty) entry['_reason'] = reason;
        countryMap[code]!.add(entry);
      }
    }

    setState(() => _countryAnalyses = countryMap);
    _startRetry();
  }

  void _startRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) { _retryTimer?.cancel(); return; }
      _injectData();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _injectData() {
    if (_countryAnalyses.isEmpty) return;
    final data = _countryAnalyses.map((code, analyses) => MapEntry(code, analyses.length));
    final json = jsonEncode(data);
    try { _controller.runJavaScript('setCountryData($json)'); } catch (_) {}
  }

  void _injectMarketData() {
    if (_marketData.isEmpty) return;
    final json = jsonEncode(_marketData);
    try { _controller.runJavaScript('setMarketData($json)'); } catch (_) {}
  }

  Future<void> _fetchMarketData() async {
    if (_fetchingMarkets) return;
    if (_marketFetchTime != null &&
        DateTime.now().difference(_marketFetchTime!) < const Duration(hours: 1) &&
        _marketData.isNotEmpty) {
      _injectMarketData();
      return;
    }
    setState(() => _fetchingMarkets = true);
    try {
      // Fetch all symbols in parallel via the chart endpoint (no auth required).
      final futures = _kSymbolToCountry.keys.map((symbol) async {
        final uri = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/'
          '${Uri.encodeComponent(symbol)}'
          '?range=2d&interval=1d&includePrePost=false',
        );
        try {
          final response = await http
              .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
              .timeout(const Duration(seconds: 12));
          if (response.statusCode != 200) {
            debugPrint('[Markets] $symbol → ${response.statusCode}');
            return null;
          }
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final resultList = data['chart']?['result'] as List<dynamic>?;
          if (resultList == null || resultList.isEmpty) return null;
          final meta = resultList.first['meta'] as Map<String, dynamic>?;
          if (meta == null) return null;
          final price = (meta['regularMarketPrice'] as num?)?.toDouble();
          final prev  = (meta['chartPreviousClose'] as num?)?.toDouble()
                     ?? (meta['previousClose'] as num?)?.toDouble();
          if (price == null || prev == null || prev == 0) return null;
          final change = price - prev;
          final pct    = (change / prev) * 100;
          return MapEntry(_kSymbolToCountry[symbol]!, {
            'symbol': symbol,
            'name': meta['shortName'] as String? ?? meta['longName'] as String? ?? symbol,
            'close': price.toString(),
            'change': change.toString(),
            'percent_change': pct.toString(),
            'is_market_open': meta['marketState'] == 'REGULAR',
            'fifty_two_week': {
              'low':  (meta['fiftyTwoWeekLow']  as num?)?.toString(),
              'high': (meta['fiftyTwoWeekHigh'] as num?)?.toString(),
            },
            'description': _kIndexDescriptions[symbol] ?? '',
          });
        } catch (e) {
          debugPrint('[Markets] $symbol error: $e');
          return null;
        }
      }).toList();

      final results = await Future.wait(futures);
      final byCountry = <String, Map<String, dynamic>>{};
      for (final entry in results) {
        if (entry != null) byCountry[entry.key] = entry.value;
      }
      debugPrint('[Markets] fetched ${byCountry.length}/${_kSymbolToCountry.length} countries');

      if (mounted) {
        setState(() {
          _marketData = byCountry;
          _marketFetchTime = DateTime.now();
          _fetchingMarkets = false;
        });
        if (byCountry.isNotEmpty) _injectMarketData();
      }
    } catch (e) {
      debugPrint('Market data fetch error: $e');
      if (mounted) setState(() => _fetchingMarkets = false);
    }
  }

  void _switchView(_GlobeView view) {
    if (view == _currentView) return;
    setState(() => _currentView = view);
    try {
      if (view == _GlobeView.analyses) {
        _controller.runJavaScript('showAnalysesView()');
      } else {
        _controller.runJavaScript('showMarketsView()');
        _fetchMarketData();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  String _refreshedAgo() {
    if (_marketFetchTime == null) return '';
    final diff = DateTime.now().difference(_marketFetchTime!);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  void _forceRefreshMarkets() {
    setState(() => _marketFetchTime = null);
    _fetchMarketData();
  }

  void _onCountryTapped(String countryCode) {
    final analyses = _countryAnalyses[countryCode];
    if (analyses == null || analyses.isEmpty) return;
    showCupertinoModalPopup(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => _CountryBottomSheet(countryCode: countryCode, analyses: analyses),
    );
  }

  void _onMarketCountryTapped(String countryCode) {
    final data = _marketData[countryCode];
    showCupertinoModalPopup(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => _MarketBottomSheet(countryCode: countryCode, data: data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF00050F),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CupertinoActivityIndicator(color: Colors.white)),
          if (!_isLoading && _countryAnalyses.isEmpty && _currentView == _GlobeView.analyses)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.globe, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'Analyse some content to\nsee it mapped here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15),
                  ),
                ],
              ),
            ),

          // ── Back button ──────────────────────────────────────────────────────
          Positioned(
            left: 16, top: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(30),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withAlpha(55), width: 0.7),
                        ),
                        child: const Icon(CupertinoIcons.chevron_left, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 10,),
          Positioned(
            bottom: bottomPad + 70,
            left: 0, right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipSmoothRect(
                    radius: SmoothBorderRadius(cornerRadius: 50, cornerSmoothing: 0.6),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: SmoothBorderRadius(cornerRadius: 50, cornerSmoothing: 0.6),
                          border: Border.all(color: Colors.white.withAlpha(40), width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ToggleOption(
                              label: 'Analyses',
                              active: _currentView == _GlobeView.analyses,
                              onTap: () => _switchView(_GlobeView.analyses),
                            ),
                            _ToggleOption(
                              label: 'Markets',
                              active: _currentView == _GlobeView.markets,
                              loading: _fetchingMarkets,
                              onTap: () => _switchView(_GlobeView.markets),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_currentView == _GlobeView.markets && _marketFetchTime != null) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _fetchingMarkets ? null : _forceRefreshMarkets,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Updated ${_refreshedAgo()}',
                            style: AppTypography.dataSmall(
                              color: Colors.white.withAlpha(90),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            CupertinoIcons.arrow_clockwise,
                            size: 12,
                            color: Colors.white.withAlpha(90),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Toggle option pill ────────────────────────────────────────────────────────

class _ToggleOption extends StatelessWidget {
  final String label;
  final bool active;
  final bool loading;
  final VoidCallback onTap;
  const _ToggleOption({
    required this.label,
    required this.active,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.white.withAlpha(55) : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? Colors.white : Colors.white.withAlpha(130),
              ),
            ),
            if (loading) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white.withAlpha(active ? 220 : 130),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Analyses bottom sheet ─────────────────────────────────────────────────────

class _CountryBottomSheet extends StatelessWidget {
  final String countryCode;
  final List<Map<String, dynamic>> analyses;

  const _CountryBottomSheet({required this.countryCode, required this.analyses});

  String _timeAgo(String? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.tryParse(timestamp);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: ClipSmoothRect(
        radius: SmoothBorderRadius.only(
          topLeft: SmoothRadius(cornerRadius: 24, cornerSmoothing: 0.6),
          topRight: SmoothRadius(cornerRadius: 24, cornerSmoothing: 0.6),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
            color: isDark ? const Color(0xFF1C1C1E).withAlpha(210) : Colors.white.withAlpha(215),
            padding: const EdgeInsets.only(top: 12, left: 16, right: 16, bottom: 0),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: SmoothBorderRadius(cornerRadius: 2, cornerSmoothing: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(_countryFlag(countryCode), style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 8),
                    Text(
                      countryCode,
                      style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${analyses.length} alignment${analyses.length > 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 14, letterSpacing: -0.3,
                          color: Colors.grey.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 0),
                    shrinkWrap: false,
                    itemCount: analyses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final a = analyses[i];
                      final type = a['content_type'] ?? 'article';
                      final reason = a['_reason'] as String?;
                      final IconData icon = type == 'youtube'
                          ? CupertinoIcons.play_circle_fill
                          : type == 'reel' ? CupertinoIcons.film : CupertinoIcons.doc_text_fill;
                      final Color iconColor = type == 'youtube'
                          ? Colors.red : type == 'reel' ? Colors.purple : Colors.blue;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.04),
                          borderRadius: SmoothBorderRadius(cornerRadius: 12, cornerSmoothing: 0.6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(icon, size: 18, color: iconColor),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    a['title'] ?? a['url'] ?? 'Untitled',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                                        color: isDark ? Colors.white : Colors.black),
                                    maxLines: 2, overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(_timeAgo(a['created_at']),
                                    style: TextStyle(fontSize: 12,
                                        color: Colors.grey.withValues(alpha: 0.5))),
                              ],
                            ),
                            if (reason != null) ...[
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.only(left: 28),
                                child: Text(
                                  reason,
                                  style: TextStyle(fontSize: 12,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.45)
                                          : Colors.black.withValues(alpha: 0.45)),
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _countryFlag(String code) => code.toUpperCase().split('').map((c) {
    return String.fromCharCode(c.codeUnitAt(0) + 127397);
  }).join();
}

// ── Markets bottom sheet ──────────────────────────────────────────────────────

class _MarketBottomSheet extends StatelessWidget {
  final String countryCode;
  final Map<String, dynamic>? data;

  const _MarketBottomSheet({required this.countryCode, required this.data});

  static String _fmt(String? v, {int decimals = 2}) {
    if (v == null) return '--';
    final d = double.tryParse(v);
    if (d == null) return v;
    if (d.abs() >= 1000) {
      final s = d.toStringAsFixed(decimals);
      final parts = s.split('.');
      final buf = StringBuffer();
      final int = parts[0];
      for (var i = 0; i < int.length; i++) {
        if (i > 0 && (int.length - i) % 3 == 0) buf.write(',');
        buf.write(int[i]);
      }
      return '${buf.toString()}.${parts[1]}';
    }
    return d.toStringAsFixed(decimals);
  }

  String _flag(String code) => code.toUpperCase().split('').map((c) {
    return String.fromCharCode(c.codeUnitAt(0) + 127397);
  }).join();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E).withAlpha(220) : Colors.white.withAlpha(220);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textMuted = isDark ? Colors.white38 : Colors.black38;

    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: ClipSmoothRect(
        radius: SmoothBorderRadius.only(
          topLeft: SmoothRadius(cornerRadius: 24, cornerSmoothing: 0.6),
          topRight: SmoothRadius(cornerRadius: 24, cornerSmoothing: 0.6),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: bg,
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 24),
            child: data == null ? _noData(isDark, textPrimary, textMuted) : _withData(context, isDark, textPrimary, textMuted),
          ),
        ),
      ),
    );
  }

  Widget _handle() => Center(
    child: Container(
      width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _noData(bool isDark, Color textPrimary, Color textMuted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _handle(),
        const SizedBox(height: 8),
        Text(_flag(countryCode), style: const TextStyle(fontSize: 44)),
        const SizedBox(height: 14),
        Text(
          'Market data unavailable for this country',
          style: GoogleFonts.inter(fontSize: 15, color: textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _withData(BuildContext context, bool isDark, Color textPrimary, Color textMuted) {
    final d = data!;
    final symbol     = d['symbol'] as String? ?? '';
    final name       = d['name'] as String? ?? symbol;
    final close      = d['close'] as String?;
    final change     = d['change'] as String?;
    final pct        = d['percent_change'] as String?;
    final isOpen     = d['is_market_open'] == true;
    final w52        = d['fifty_two_week'] as Map<String, dynamic>?;
    final description = d['description'] as String? ?? '';

    final changeVal  = double.tryParse(change ?? '') ?? 0;
    final pctVal     = double.tryParse(pct ?? '') ?? 0;
    final isPositive = changeVal >= 0;
    final changeColor = isPositive ? const Color(0xFF30D158) : const Color(0xFFFF3B30);
    final countryName = _GlobeScreenState._kCountryNames[countryCode] ?? countryCode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _handle(),

        // Country row
        Row(
          children: [
            Text(_flag(countryCode), style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(countryName,
                  style: AppTypography.navTitle(color: textPrimary)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isOpen ? const Color(0xFF30D158) : const Color(0xFFFF3B30)).withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (isOpen ? const Color(0xFF30D158) : const Color(0xFFFF3B30)).withAlpha(80),
                  width: 0.8,
                ),
              ),
              child: Text(
                isOpen ? 'Open' : 'Closed',
                style: AppTypography.dataSmall(
                  color: isOpen ? const Color(0xFF30D158) : const Color(0xFFFF3B30),
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Price card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: ShapeDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 14, cornerSmoothing: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: GoogleFonts.inter(fontSize: 13, color: textMuted)),
              const SizedBox(height: 4),
              Text(
                _fmt(close),
                style: AppTypography.statValue(color: textPrimary)
                    .copyWith(fontSize: 34, letterSpacing: -1.2),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isPositive ? CupertinoIcons.arrow_up_right : CupertinoIcons.arrow_down_right,
                    size: 14, color: changeColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${isPositive ? '+' : ''}${changeVal.toStringAsFixed(2)}  '
                    '(${isPositive ? '+' : ''}${pctVal.toStringAsFixed(2)}%)',
                    style: AppTypography.chipLabel(color: changeColor)
                        .copyWith(fontSize: 15),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (w52 != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _StatBox(label: '52W Low', value: _fmt(w52['low'] as String?), isDark: isDark)),
              const SizedBox(width: 8),
              Expanded(child: _StatBox(label: '52W High', value: _fmt(w52['high'] as String?), isDark: isDark)),
            ],
          ),
        ],

        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(description,
              style: GoogleFonts.inter(fontSize: 13, color: textMuted, height: 1.4)),
        ],
      ],
    );
  }
}

// ── Stat box ──────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _StatBox({required this.label, required this.value, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: ShapeDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
        shape: SmoothRectangleBorder(
          borderRadius: SmoothBorderRadius(cornerRadius: 10, cornerSmoothing: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(height: 3),
          Text(value,
              style: AppTypography.dataLabel(
                  color: isDark ? Colors.white : Colors.black)),
        ],
      ),
    );
  }
}
