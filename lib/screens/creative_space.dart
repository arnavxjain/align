import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:uuid/uuid.dart';

import '../providers/theme_notifier.dart';
import '../services/analysis_service.dart';
import '../services/gemini_service.dart';

const _uuid = Uuid();
final _rng = Random();

// ── Color palettes (randomised per session) ───────────────────────────────────

const _kPalettes = <List<Color>>[
  // Deep blue / purple
  [Color(0xFF1A3AFF), Color(0xFF7B2FFF), Color(0xFF0055DD), Color(0xFF4410CC)],
  // Electric blue / cyan
  [Color(0xFF0040FF), Color(0xFF00AAFF), Color(0xFF0088CC), Color(0xFF2244EE)],
  // Purple / violet / indigo
  [Color(0xFF8822FF), Color(0xFF4422BB), Color(0xFF6600FF), Color(0xFFAA33FF)],
  // Midnight blue / cobalt
  [Color(0xFF220088), Color(0xFF1144BB), Color(0xFF0033AA), Color(0xFF5533CC)],
  // Teal / cerulean
  [Color(0xFF006688), Color(0xFF0099DD), Color(0xFF0055AA), Color(0xFF33AACC)],
];

// ── Entry point ───────────────────────────────────────────────────────────────

void openCreativeSpace(BuildContext context, String alignmentId) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) =>
          CreativeSpaceScreen(alignmentId: alignmentId),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ),
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CreativeSpaceScreen extends StatefulWidget {
  final String alignmentId;
  const CreativeSpaceScreen({super.key, required this.alignmentId});

  @override
  State<CreativeSpaceScreen> createState() => _CreativeSpaceScreenState();
}

class _CreativeSpaceScreenState extends State<CreativeSpaceScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Pick a random palette once for this session.
  late final List<Color> _palette =
      _kPalettes[_rng.nextInt(_kPalettes.length)];

  // Mesh gradient — driven by our own AnimationController so disposal is safe.
  late final MeshGradientController _meshCtrl;
  late final AnimationController _meshAnimCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late List<MeshGradientPoint> _fromPoints = _makePoints();
  late List<MeshGradientPoint> _toPoints = _makePoints();
  bool _meshDisposed = false;

  // Session timer.
  final _elapsed = ValueNotifier<int>(0);
  Timer? _timer;

  Map<String, dynamic> get _alignment =>
      alignmentsNotifier.value.firstWhere(
        (e) => e['id'] == widget.alignmentId,
        orElse: () => <String, dynamic>{},
      );

  @override
  void initState() {
    super.initState();

    _meshCtrl = MeshGradientController(
      vsync: this,
      points: _fromPoints,
    );

    // Drive mesh animation ourselves — avoids the "used after disposed" crash
    // that happens when animateSequence's internal controllers outlive us.
    _meshAnimCtrl
      ..addListener(_onMeshTick)
      ..addStatusListener(_onMeshStatus)
      ..forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed.value++;
    });

    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(animated: false),
    );
  }

  List<MeshGradientPoint> _makePoints() {
    double rand(double lo, double hi) => lo + _rng.nextDouble() * (hi - lo);
    return [
      MeshGradientPoint(
        position: Offset(rand(-0.1, 0.55), rand(-0.1, 0.55)),
        color: _palette[0],
      ),
      MeshGradientPoint(
        position: Offset(rand(0.45, 1.1), rand(-0.1, 0.55)),
        color: _palette[1],
      ),
      MeshGradientPoint(
        position: Offset(rand(-0.1, 0.55), rand(0.45, 1.1)),
        color: _palette[2],
      ),
      MeshGradientPoint(
        position: Offset(rand(0.45, 1.1), rand(0.45, 1.1)),
        color: _palette[3],
      ),
    ];
  }

  void _onMeshTick() {
    if (_meshDisposed) return;
    final t = Curves.easeInOut.transform(_meshAnimCtrl.value);
    _meshCtrl.points.value = List.generate(
      4,
      (i) => MeshGradientPoint(
        position: Offset.lerp(
          _fromPoints[i].position,
          _toPoints[i].position,
          t,
        )!,
        color: _palette[i],
      ),
    );
  }

  void _onMeshStatus(AnimationStatus status) {
    if (_meshDisposed || status != AnimationStatus.completed) return;
    _fromPoints = _toPoints;
    _toPoints = _makePoints();
    _meshAnimCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _meshDisposed = true;
    // Stop our AnimationController first so its listeners never fire again,
    // then dispose the MeshGradientController safely.
    _meshAnimCtrl
      ..removeListener(_onMeshTick)
      ..removeStatusListener(_onMeshStatus)
      ..dispose();
    _meshCtrl.dispose();
    _timer?.cancel();
    _elapsed.dispose();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _loadHistory() {
    final a = _alignment;
    final cs = a['creative_space'];
    if (cs is Map) {
      final raw = cs['chat_history'];
      if (raw is List) {
        _messages = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        return;
      }
    }
    // Migrate old chat_history into creative_space on first open.
    final oldHistory = a['chat_history'];
    if (oldHistory is List && oldHistory.isNotEmpty) {
      _messages = oldHistory
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      AnalysisService.saveCreativeSpace(
        widget.alignmentId,
        List.from(_messages),
      ).ignore();
    }
  }

  String _buildSystemContext() {
    final a = _alignment;
    final title = a['title'] as String? ?? 'Unknown';
    final type = a['content_type'] as String? ?? 'article';
    final url = a['url'] as String? ?? '';
    final raw = a['analyses'];
    final analyses =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    final sb = StringBuffer()
      ..writeln('You are a creative AI assistant in "Creative Space" mode.')
      ..writeln('The user is exploring content they analysed:')
      ..writeln('Title: $title')
      ..writeln('Type: $type')
      ..writeln('URL: $url')
      ..writeln();

    final realismCheck = analyses['realism_check'];
    if (realismCheck is List && realismCheck.isNotEmpty) {
      sb.writeln('Realism Check (${realismCheck.length} claims):');
      for (final c in realismCheck.take(6)) {
        if (c is Map) sb.writeln('  ${c['claim']} → ${c['verdict']}');
      }
    }
    final products = analyses['products'];
    if (products is List && products.isNotEmpty) {
      sb.writeln(
        'Products: ${products.whereType<Map>().map((p) => p['product']).join(', ')}',
      );
    }
    final timeline = analyses['timeline'];
    if (timeline is List && timeline.isNotEmpty) {
      sb.writeln('Timeline: ${timeline.length} events extracted.');
    }

    sb.writeln(
      '\nBe creative, insightful, and concise. Keep responses under 200 words unless asked for more.',
    );
    return sb.toString();
  }

  Future<void> _send(String text, {String? actionType}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loading) return;
    _ctrl.clear();
    FocusScope.of(context).unfocus();

    final userMsg = <String, dynamic>{
      'id': _uuid.v4(),
      'role': 'user',
      'content': trimmed,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'action_type': actionType,
    };

    setState(() {
      _messages = [..._messages, userMsg];
      _loading = true;
    });
    _scrollToBottom();

    AnalysisService.saveCreativeSpace(
      widget.alignmentId,
      List.from(_messages),
    ).ignore();

    final response = await GeminiService.chat(
      systemContext: _buildSystemContext(),
      history: _messages
          .map(
            (m) => {
              'role': m['role'] as String,
              'content': m['content'] as String,
            },
          )
          .toList(),
    );

    if (!mounted) return;

    final assistantMsg = <String, dynamic>{
      'id': _uuid.v4(),
      'role': 'assistant',
      'content':
          response ?? "Sorry, I couldn't get a response. Please try again.",
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'action_type': actionType,
    };

    setState(() {
      _messages = [..._messages, assistantMsg];
      _loading = false;
    });
    _scrollToBottom();

    AnalysisService.saveCreativeSpace(
      widget.alignmentId,
      List.from(_messages),
    ).ignore();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (animated) {
        _scrollCtrl.animateTo(
          max,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(max);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final accent = _palette[0];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF111113),
        body: Column(
          children: [
            // ── Flowing mesh gradient header ───────────────────────────────
            _MeshHeader(
              meshCtrl: _meshCtrl,
              alignment: _alignment,
              palette: _palette,
              elapsed: _elapsed,
              onAction: _send,
            ),

            // ── Chat messages ──────────────────────────────────────────────
            Expanded(
              child: _messages.isEmpty && !_loading
                  ? _EmptyState(accent: accent)
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: EdgeInsets.fromLTRB(
                        20, 16, 20, 16 + mq.padding.bottom,
                      ),
                      itemCount: _messages.length + (_loading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _messages.length) {
                          return _TypingIndicator(color: accent);
                        }
                        return _MessageBubble(
                          message: _messages[i],
                          accentColor: accent,
                        );
                      },
                    ),
            ),

            // ── Input bar ──────────────────────────────────────────────────
            _InputBar(
              ctrl: _ctrl,
              accentColor: accent,
              onSend: _send,
              bottomPad: mq.padding.bottom,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mesh gradient header ──────────────────────────────────────────────────────

class _MeshHeader extends StatelessWidget {
  final MeshGradientController meshCtrl;
  final Map<String, dynamic> alignment;
  final List<Color> palette;
  final ValueNotifier<int> elapsed;
  final Future<void> Function(String, {String? actionType}) onAction;

  const _MeshHeader({
    required this.meshCtrl,
    required this.alignment,
    required this.palette,
    required this.elapsed,
    required this.onAction,
  });

  static String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static (IconData, String) _typeInfo(String type) => switch (type) {
    'youtube' => (CupertinoIcons.play_rectangle_fill, 'YouTube'),
    'reel' => (CupertinoIcons.film_fill, 'Reel'),
    _ => (CupertinoIcons.doc_text_fill, 'Article'),
  };

  Future<void> _confirmEnd(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'End session',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutQuart,
            reverseCurve: Curves.easeOutCubic,
          ),
        ),
        child: child,
      ),
      pageBuilder: (ctx, _, __) => const _EndSessionSheet(),
    );
    if ((confirmed ?? false) && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final title = alignment['title'] as String? ?? 'Creative Space';
    final contentType = alignment['content_type'] as String? ?? 'article';
    final (typeIcon, _) = _typeInfo(contentType);

    return ClipSmoothRect(
      radius: const SmoothBorderRadius.only(
        bottomLeft: SmoothRadius(cornerRadius: 0, cornerSmoothing: 0.6),
        bottomRight: SmoothRadius(cornerRadius: 0, cornerSmoothing: 0.6),
      ),
      child: MeshGradient(
        controller: meshCtrl,
        options: MeshGradientOptions(blend: 3.5, noiseIntensity: 0.05),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Top row: type icon | title + timer | close
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _CircleButton(icon: typeIcon, onTap: null),
                  const SizedBox(width: 12),
                  Text(
                    'Creative Space',
                    style: GoogleFonts.geist(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: elapsed,
                    builder: (_, secs, __) => Text(
                      _formatElapsed(secs),
                      style: GoogleFonts.geist(
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _CircleButton(
                    icon: CupertinoIcons.flag_fill,
                    onTap: () => _confirmEnd(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Alignment title
              Text(
                title,
                style: GoogleFonts.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.82),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 18),

              // Action icon buttons — horizontally scrollable
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    _ActionIconButton(
                      icon: CupertinoIcons.chart_bar_alt_fill,
                      label: 'Infographic',
                      color: const Color(0xFF4A90E2),
                      onTap: () => onAction(
                        'Create a text-based visual summary of this content. '
                        'Use clear sections with emoji headers (📌 Key Points, 🔍 Details, 💡 Insight). '
                        'Make it scannable and visually organized. Under 200 words.',
                        actionType: 'infographic',
                      ),
                    ),
                    const SizedBox(width: 16),
                    _ActionIconButton(
                      icon: CupertinoIcons.arrow_2_squarepath,
                      label: 'Bias Flip',
                      color: const Color(0xFFBF5AF2),
                      onTap: () => onAction(
                        'Re-analyse this content from the opposite perspective. '
                        'What would a strong critic say? Steelman the opposing view. '
                        'Be specific and intellectually honest.',
                        actionType: 'bias_flip',
                      ),
                    ),
                    const SizedBox(width: 16),
                    _ActionIconButton(
                      icon: CupertinoIcons.clock_fill,
                      label: 'Aging',
                      color: const Color(0xFFFF9F0A),
                      onTap: () => onAction(
                        'Look at the claims and predictions in this content. '
                        'How well have they held up over time? '
                        'What proved accurate, what was wrong, what is still uncertain?',
                        actionType: 'aged',
                      ),
                    ),
                    const SizedBox(width: 16),
                    _ActionIconButton(
                      icon: CupertinoIcons.lightbulb_fill,
                      label: 'Key Takeaway',
                      color: const Color(0xFF30D158),
                      onTap: () => onAction(
                        'Distill the entire content into a single powerful sentence. '
                        'No preamble — just the sentence.',
                        actionType: 'takeaway',
                      ),
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

// ── Circle button (header) ────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.30),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

// ── Action icon button ────────────────────────────────────────────────────────

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.28),
                  border: Border.all(
                    color: color.withValues(alpha: 0.50),
                    width: 1.0,
                  ),
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.geist(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final Color accent;
  const _EmptyState({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.sparkles,
              size: 32,
              color: accent.withValues(alpha: 0.40),
            ),
            const SizedBox(height: 14),
            Text(
              'Your creative workspace',
              style: GoogleFonts.geist(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.38),
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Use the actions above or ask anything about this content.',
              style: GoogleFonts.geist(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.22),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Color accentColor;

  const _MessageBubble({required this.message, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    final content = message['content'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.20),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.40),
                  width: 0.7,
                ),
              ),
              child: Icon(
                CupertinoIcons.sparkles,
                size: 12,
                color: accentColor,
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? accentColor.withValues(alpha: 0.80)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: SmoothBorderRadius.only(
                  topLeft: const SmoothRadius(
                    cornerRadius: 16,
                    cornerSmoothing: 0.6,
                  ),
                  topRight: const SmoothRadius(
                    cornerRadius: 16,
                    cornerSmoothing: 0.6,
                  ),
                  bottomLeft: SmoothRadius(
                    cornerRadius: isUser ? 16 : 4,
                    cornerSmoothing: 0.6,
                  ),
                  bottomRight: SmoothRadius(
                    cornerRadius: isUser ? 4 : 16,
                    cornerSmoothing: 0.6,
                  ),
                ),
                border: Border.all(
                  color: isUser
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.10),
                  width: 0.7,
                ),
              ),
              child: Text(
                content,
                style: GoogleFonts.geist(
                  fontSize: 14,
                  color: Colors.white.withValues(
                    alpha: isUser ? 0.95 : 0.82,
                  ),
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final Color color;
  const _TypingIndicator({required this.color});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.20),
              border: Border.all(
                color: widget.color.withValues(alpha: 0.40),
                width: 0.7,
              ),
            ),
            child: Icon(
              CupertinoIcons.sparkles,
              size: 12,
              color: widget.color,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: SmoothBorderRadius.only(
                topLeft: const SmoothRadius(
                  cornerRadius: 16,
                  cornerSmoothing: 0.6,
                ),
                topRight: const SmoothRadius(
                  cornerRadius: 16,
                  cornerSmoothing: 0.6,
                ),
                bottomLeft: const SmoothRadius(
                  cornerRadius: 4,
                  cornerSmoothing: 0.6,
                ),
                bottomRight: const SmoothRadius(
                  cornerRadius: 16,
                  cornerSmoothing: 0.6,
                ),
              ),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i / 3.0;
                    final t = (_ctrl.value - delay).clamp(0.0, 1.0);
                    final bounce = sin(t * pi);
                    return Container(
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                      width: 7,
                      height: 7,
                      transform: Matrix4.translationValues(0, -5 * bounce, 0),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(
                          alpha: 0.35 + 0.45 * bounce,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final Color accentColor;
  final void Function(String) onSend;
  final double bottomPad;

  const _InputBar({
    required this.ctrl,
    required this.accentColor,
    required this.onSend,
    required this.bottomPad,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.11),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: ctrl,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 4,
                style: GoogleFonts.geist(
                  fontSize: 15,
                  color: Colors.white,
                ),
                onSubmitted: onSend,
                decoration: InputDecoration(
                  hintText: 'Ask anything…',
                  hintStyle: GoogleFonts.geist(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: ctrl,
            builder: (_, val, __) {
              final hasText = val.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText
                    ? () {
                        HapticFeedback.lightImpact();
                        onSend(ctrl.text);
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasText
                        ? accentColor
                        : Colors.white.withValues(alpha: 0.09),
                  ),
                  child: Icon(
                    CupertinoIcons.arrow_up,
                    size: 18,
                    color: hasText
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.28),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── End session confirmation sheet ────────────────────────────────────────────

class _EndSessionSheet extends StatelessWidget {
  const _EndSessionSheet();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    const flagColor = Color(0xFFFF9F0A);
    final cardRadius = SmoothBorderRadius(cornerRadius: 26, cornerSmoothing: 0.6);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 4),
        child: ClipSmoothRect(
          radius: cardRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: ShapeDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.92),
                shape: SmoothRectangleBorder(
                  borderRadius: cardRadius,
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flag icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: flagColor.withValues(alpha: isDark ? 0.15 : 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: flagColor.withValues(alpha: 0.30),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.flag_fill,
                      size: 22,
                      color: flagColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'End Creative Session?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      letterSpacing: -0.3,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your conversation is saved and will be here when you return.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SheetButton(
                    label: 'End Session',
                    backgroundColor:
                        flagColor.withValues(alpha: isDark ? 0.28 : 0.16),
                    textColor: flagColor,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop(true);
                    },
                  ),
                  const SizedBox(height: 10),
                  _SheetButton(
                    label: 'Keep Going',
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    textColor: scheme.onSurface,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatefulWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_SheetButton> createState() => _SheetButtonState();
}

class _SheetButtonState extends State<_SheetButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: _pressed ? 0.5 : 1.0,
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: ShapeDecoration(
            color: widget.backgroundColor,
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 14,
                cornerSmoothing: 0.6,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: widget.textColor,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
