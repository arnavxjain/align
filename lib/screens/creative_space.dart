import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:simple_ripple_animation/simple_ripple_animation.dart';
import 'package:uuid/uuid.dart';

import '../providers/theme_notifier.dart';
import '../services/analysis_service.dart';
import '../services/gemini_service.dart';
import '../utils/transitions.dart' show AppRoute, PillExpandRoute;

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

void openCreativeSpace(
  BuildContext context,
  String alignmentId, {
  int initialElapsed = 0,
  Rect? fromRect,
}) {
  final screen = CreativeSpaceScreen(
    alignmentId: alignmentId,
    initialElapsed: initialElapsed,
  );
  Navigator.of(context).push(
    fromRect != null
        ? PillExpandRoute(fromRect: fromRect, builder: (_) => screen)
        : AppRoute.transparentModal(screen),
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CreativeSpaceScreen extends StatefulWidget {
  final String alignmentId;
  final int initialElapsed;
  const CreativeSpaceScreen({
    super.key,
    required this.alignmentId,
    this.initialElapsed = 0,
  });

  @override
  State<CreativeSpaceScreen> createState() => _CreativeSpaceScreenState();
}

class _CreativeSpaceScreenState extends State<CreativeSpaceScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Drag-to-dismiss state.
  Offset _drag = Offset.zero;
  // Set when the dismiss commit animation begins; used to interpolate the clip rect.
  Rect _dismissStartRect = Rect.zero;
  double _dismissStartCornerRadius = 36.0;
  // 0→1 during the dismiss commit animation.
  double _dismissT = 0.0;
  late final AnimationController _snapCtrl;

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

// Session timer (starts from initialElapsed when re-opening a dismissed session).
  late final _elapsed = ValueNotifier<int>(widget.initialElapsed);
  Timer? _timer;

  Map<String, dynamic> get _alignment =>
      alignmentsNotifier.value.firstWhere(
        (e) => e['id'] == widget.alignmentId,
        orElse: () => <String, dynamic>{},
      );

  @override
  void initState() {
    super.initState();

    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      detailBlurNotifier.value = 1.0;
    });

    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(animated: false),
    );
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!mounted) return;
    setState(() => _drag += d.delta);
    final screenH = MediaQuery.of(context).size.height;
    final dragFraction = (_drag.dy / screenH).clamp(0.0, 1.0);
    detailBlurNotifier.value = (1.0 - dragFraction * 1.4).clamp(0.0, 1.0);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!mounted) return;
    final screenH = MediaQuery.of(context).size.height;
    final vy = d.velocity.pixelsPerSecond.dy;
    final start = _drag;

    final shouldDismiss = start.dy > screenH * 0.5 || vy > 800;

    _snapCtrl.stop();
    _snapCtrl.reset();

    if (shouldDismiss) {
      _snapCtrl.duration = const Duration(milliseconds: 380);

      // Capture the exact visual rect of the screen at this moment so the
      // dismiss clip starts seamlessly from the current drag state.
      final screenW = MediaQuery.of(context).size.width;
      final dragFrac = (start.dy / screenH).clamp(0.0, 1.0);
      final scale = 1.0 - dragFrac * 0.12;
      _dismissStartCornerRadius = 36.0 + dragFrac * 10.0;
      _dismissStartRect = Rect.fromLTWH(
        start.dx + screenW * (1 - scale) / 2,
        start.dy,
        screenW * scale,
        screenH * scale,
      );

      final blurStart = detailBlurNotifier.value;
      void listener() {
        if (!mounted) return;
        setState(() => _dismissT = _snapCtrl.value);
        detailBlurNotifier.value = (blurStart * (1.0 - _snapCtrl.value)).clamp(0.0, 1.0);
      }

      _snapCtrl.addListener(listener);
      _snapCtrl.forward().then((_) async {
        _snapCtrl.removeListener(listener);
        if (!mounted) return;
        // Activate the floating pill before popping.
        activeCreativeSessionNotifier.value = {
          'alignmentId': widget.alignmentId,
          'title': _alignment['title'],
          'contentType': _alignment['content_type'],
          'elapsedSeconds': _elapsed.value,
        };
        Navigator.maybePop(context);
      });
    } else {
      final dist = start.distance;
      final ms = (dist * 0.55).clamp(180.0, 340.0);
      _snapCtrl.duration = Duration(milliseconds: ms.round());

      final blurStart = detailBlurNotifier.value;
      void listener() {
        if (!mounted) return;
        final t = Curves.easeOutCubic.transform(_snapCtrl.value);
        setState(() => _drag = start * (1.0 - t));
        detailBlurNotifier.value = blurStart + (1.0 - blurStart) * t;
      }

      _snapCtrl.addListener(listener);
      _snapCtrl.forward().then((_) {
        _snapCtrl.removeListener(listener);
        if (mounted) setState(() => _dismissT = 0.0);
      });
    }
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
    _snapCtrl.dispose();
    _meshAnimCtrl
      ..removeListener(_onMeshTick)
      ..removeStatusListener(_onMeshStatus)
      ..dispose();
    _meshCtrl.dispose();
    _timer?.cancel();
    _elapsed.dispose();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    detailBlurNotifier.value = 0.0;
    // If the screen is disposed without drag-dismiss or end-session (rare),
    // don't leave a stale pill showing.
    // Only clear if this session's ID matches (avoids clearing a re-opened session).
    final active = activeCreativeSessionNotifier.value;
    if (active != null && active['alignmentId'] == widget.alignmentId) {
      // Check if this was NOT a drag-dismiss (pill would already be set).
      // We only clear if the pill was NOT just activated by our dismiss path.
      // Since the dismiss path sets it and then pops, dispose runs after the
      // pill is visible — so we must NOT clear it here in the drag-dismiss case.
      // We detect this by checking if the dispose is from a normal pop (no drag).
      // Simple heuristic: if _drag.dy is near zero, this is an accidental dispose.
      if (_drag.dy < 10) activeCreativeSessionNotifier.value = null;
    }
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

  // The pill widget uses: left/right: 16px, height: 62px, bottom: padding.bottom + 88.
  // This must match creative_session_pill.dart's positioning exactly.
  Rect _pillTargetRect(MediaQueryData mq) {
    const hPad = 16.0;
    const pillH = 60.0;
    const baseBottomOffset = 88.0;
    return Rect.fromLTWH(
      hPad,
      mq.size.height - mq.padding.bottom - baseBottomOffset - pillH,
      mq.size.width - hPad * 2,
      pillH,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final accent = _palette[0];
    final screenH = mq.size.height;
    final dragFraction = (_drag.dy / screenH).clamp(0.0, 1.0);
    final sheetScale = 1.0 - dragFraction * 0.12;
    final cornerRadius = 36.0 + dragFraction * 10.0;

    final content = _buildContent(context, mq, accent, screenH, cornerRadius);

    Widget body;

    if (_dismissT > 0) {
      // Dismiss commit: clip rect morphs from screen's current visual rect → pill rect.
      final t = Curves.easeInCubic.transform(_dismissT);
      final pillRect = _pillTargetRect(mq);
      final rect = Rect.lerp(_dismissStartRect, pillRect, t)!;
      final radius = lerpDouble(_dismissStartCornerRadius, 20.0, t)!;
      // Content fades out in the first 40% so only the dark bg shows as clip shrinks.
      final contentOpacity = (1.0 - _dismissT / 0.4).clamp(0.0, 1.0);

      body = Stack(
        children: [
          Positioned.fromRect(
            rect: rect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: mq.size.width,
                maxWidth: mq.size.width,
                minHeight: screenH,
                maxHeight: screenH,
                child: Opacity(opacity: contentOpacity, child: content),
              ),
            ),
          ),
        ],
      );
    } else {
      // Normal / in-progress drag: existing transform-based feel.
      body = Transform.translate(
        offset: _drag,
        child: Transform.scale(
          scale: sheetScale,
          alignment: Alignment.topCenter,
          child: content,
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(backgroundColor: Colors.transparent, body: body),
    );
  }

  Widget _buildContent(
    BuildContext context,
    MediaQueryData mq,
    Color accent,
    double screenH,
    double cornerRadius,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cornerRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 40,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipSmoothRect(
        radius: SmoothBorderRadius(
          cornerRadius: cornerRadius,
          cornerSmoothing: 0.9,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF080808)),
            Column(
              children: [
                SizedBox(height: mq.padding.top + 15),
                Expanded(
                  child: _messages.isEmpty && !_loading
                      ? Padding(
                          padding: const EdgeInsets.only(top: 280),
                          child: _EmptyState(accent: accent),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: EdgeInsets.fromLTRB(
                            20, mq.padding.top + 360, 20, 90 + mq.padding.bottom,
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
              ],
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _InputBar(
                ctrl: _ctrl,
                accentColor: accent,
                onSend: _send,
                bottomPad: mq.padding.bottom,
              ),
            ),
            Positioned(
              top: 0, left: 0, right: 0,
              child: _MeshHeader(
                meshCtrl: _meshCtrl,
                alignment: _alignment,
                palette: _palette,
                elapsed: _elapsed,
                onAction: _send,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mesh gradient header ──────────────────────────────────────────────────────

class _MeshHeader extends StatefulWidget {
  final MeshGradientController meshCtrl;
  final Map<String, dynamic> alignment;
  final List<Color> palette;
  final ValueNotifier<int> elapsed;
  final Future<void> Function(String, {String? actionType}) onAction;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  const _MeshHeader({
    required this.meshCtrl,
    required this.alignment,
    required this.palette,
    required this.elapsed,
    required this.onAction,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  State<_MeshHeader> createState() => _MeshHeaderState();
}

class _MeshHeaderState extends State<_MeshHeader>
    with SingleTickerProviderStateMixin {
  // 0.0 = fully expanded, 1.0 = fully collapsed
  double _collapseProgress = 0.0;

  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  // Single persistent listener — avoids accumulation on repeated drags.
  late final VoidCallback _snapListener = () {
    if (mounted) setState(() => _collapseProgress = _snapCtrl.value);
  };

  // Approximate drag distance to go fully collapsed (px).
  static const double _collapsibleHeight = 180.0;

  @override
  void initState() {
    super.initState();
    _snapCtrl.addListener(_snapListener);
  }

  @override
  void dispose() {
    _snapCtrl.removeListener(_snapListener);
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onChevronDragUpdate(DragUpdateDetails d) {
    _snapCtrl.stop();
    setState(() {
      _collapseProgress =
          (_collapseProgress - d.delta.dy / _collapsibleHeight).clamp(0.0, 1.0);
      // Sync controller so snap continues from current position.
      _snapCtrl.value = _collapseProgress;
    });
  }

  void _onChevronDragEnd(DragEndDetails d) {
    final vy = d.velocity.pixelsPerSecond.dy;
    final target = (vy < -150 || _collapseProgress >= 0.5) ? 1.0 : 0.0;
    _snapCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    ).then((_) => HapticFeedback.lightImpact());
  }

  void _onChevronTap() {
    final target = _collapseProgress < 0.5 ? 1.0 : 0.0;
    _snapCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    ).then((_) => HapticFeedback.lightImpact());
  }

  static String _formatElapsed(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static (IconData, Color) _typeInfo(String type) => switch (type) {
    'youtube' => (CupertinoIcons.play_rectangle_fill, Color(0xFFFF3B30)),
    'reel'    => (CupertinoIcons.film_fill, Color(0xFFBF5AF2)),
    _         => (CupertinoIcons.doc_text_fill, Color(0xFF0A84FF)),
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
      activeCreativeSessionNotifier.value = null;
      detailBlurNotifier.value = 0.0;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final title = widget.alignment['title'] as String? ?? 'Creative Space';
    final contentType = widget.alignment['content_type'] as String? ?? 'article';
    final (typeIcon, typeColor) = _typeInfo(contentType);
    final accent = widget.palette[0];

    return Padding(
      padding: EdgeInsets.fromLTRB(14, topPad, 14, 0),
      child: ClipSmoothRect(
        radius: SmoothBorderRadius(cornerRadius: 34, cornerSmoothing: 0.9),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
          decoration: ShapeDecoration(
            color: Colors.black.withValues(alpha: 0.15),
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(cornerRadius: 34, cornerSmoothing: 0.9),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.8,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Gradient image panel ──────────────────────────────────
              SizedBox(
                height: 100,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MeshGradient(
                      controller: widget.meshCtrl,
                      options: MeshGradientOptions(blend: 3.5, noiseIntensity: 0.05),
                    ),
                    // Drag handle
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      height: 20,
                      child: GestureDetector(
                        onPanUpdate: widget.onPanUpdate,
                        onPanEnd: widget.onPanEnd,
                        behavior: HitTestBehavior.translucent,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // End session button — top right
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _CircleButton(
                        icon: CupertinoIcons.stop_fill,
                        onTap: () => _confirmEnd(context),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Info area ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 18),
                child: Stack(
                  children: [
                    // Column drives the Stack height; bottom padding reserves
                    // space so the chevron never overlaps content.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row + ripple bubble
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  'Creative Session',
                                  style: GoogleFonts.geist(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: -0.6,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              RippleAnimation(
                                color: accent.withValues(alpha: 0.3),
                                minRadius: 18,
                                maxRadius: 30,
                                ripplesCount: 3,
                                repeat: true,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Timer pill + content type icon
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: ValueListenableBuilder<int>(
                                  valueListenable: widget.elapsed,
                                  builder: (_, secs, __) {
                                    final hasHours = secs >= 3600;
                                    return SizedBox(
                                      width: hasHours ? 80 : 58,
                                      child: Text(
                                        _formatElapsed(secs),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.geist(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: typeColor,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: typeColor.withValues(alpha: 0.18),
                                  ),
                                  child: Icon(typeIcon, size: 14, color: typeColor),
                                ),
                              ),
                            ],
                          ),
                          ),
                        ),
                        // Collapsible: content title + action pills
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: 1.0 - _collapseProgress,
                            child: Opacity(
                              opacity: (1.0 - _collapseProgress * 2).clamp(0.0, 1.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.07),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.09),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        title,
                                        style: GoogleFonts.geist(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withValues(alpha: 0.82),
                                          height: 1.45,
                                          letterSpacing: -0.1,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    scrollDirection: Axis.horizontal,
                                    clipBehavior: Clip.none,
                                    child: Row(
                                      children: [
                                        _ActionPillButton(
                                          label: 'Create Infographic',
                                          onTap: () => widget.onAction(
                                            'Create a text-based visual summary of this content. '
                                            'Use clear sections with emoji headers (📌 Key Points, 🔍 Details, 💡 Insight). '
                                            'Make it scannable and visually organized. Under 200 words.',
                                            actionType: 'infographic',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _ActionPillButton(
                                          label: 'Bias Flip',
                                          onTap: () => widget.onAction(
                                            'Re-analyse this content from the opposite perspective. '
                                            'What would a strong critic say? Steelman the opposing view. '
                                            'Be specific and intellectually honest.',
                                            actionType: 'bias_flip',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _ActionPillButton(
                                          label: 'Aging Check',
                                          onTap: () => widget.onAction(
                                            'Look at the claims and predictions in this content. '
                                            'How well have they held up over time? '
                                            'What proved accurate, what was wrong, what is still uncertain?',
                                            actionType: 'aged',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _ActionPillButton(
                                          label: 'Key Takeaway',
                                          onTap: () => widget.onAction(
                                            'Distill the entire content into a single powerful sentence. '
                                            'No preamble — just the sentence.',
                                            actionType: 'takeaway',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Spacer that shrinks as modal collapses
                        SizedBox(height: lerpDouble(30.0, 3.0, _collapseProgress)),
                      ],
                    ),

                    // Chevron always at bottom-right; animates up as
                    // AnimatedSize shrinks the Stack's height.
                    Positioned(
                      bottom: 0,
                      right: 24,
                      child: _ChevronButton(
                        collapseProgress: _collapseProgress,
                        onTap: _onChevronTap,
                        onDragUpdate: _onChevronDragUpdate,
                        onDragEnd: _onChevronDragEnd,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}


// ── Circle button (header) ────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData? icon;
  final String? emoji;
  final VoidCallback? onTap;

  const _CircleButton({this.icon, this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Widget child = emoji != null
        ? Text(emoji!, style: const TextStyle(fontSize: 15))
        : Icon(icon!, size: 16, color: Colors.white);

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
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

// ── Chevron collapse button ───────────────────────────────────────────────────

class _ChevronButton extends StatelessWidget {
  final double collapseProgress;
  final VoidCallback onTap;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;

  const _ChevronButton({
    required this.collapseProgress,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onVerticalDragUpdate: onDragUpdate,
      onVerticalDragEnd: onDragEnd,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Transform.rotate(
          angle: collapseProgress * pi,
          child: Icon(
            CupertinoIcons.chevron_compact_up,
            size: 30,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

// ── Action pill button ────────────────────────────────────────────────────────

class _ActionPillButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionPillButton({required this.label, required this.onTap});

  @override
  State<_ActionPillButton> createState() => _ActionPillButtonState();
}

class _ActionPillButtonState extends State<_ActionPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 80),
        opacity: _pressed ? 0.55 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.geist(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.88),
              letterSpacing: -0.1,
            ),
          ),
        ),
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

String _stripMarkdown(String text) {
  String s = text;
  // Bold (**text** or __text__)
  s = s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*', dotAll: true), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'__(.+?)__', dotAll: true), (m) => m[1]!);
  // Italic (*text* or _text_)
  s = s.replaceAllMapped(RegExp(r'\*(.+?)\*', dotAll: true), (m) => m[1]!);
  s = s.replaceAllMapped(RegExp(r'_(.+?)_', dotAll: true), (m) => m[1]!);
  // Inline code
  s = s.replaceAllMapped(RegExp(r'`(.+?)`', dotAll: true), (m) => m[1]!);
  // Bullet points: lines starting with "* " or "- " or "+ "
  s = s.replaceAll(RegExp(r'^\s*[*\-+]\s+', multiLine: true), '');
  // Numbered lists
  s = s.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
  // Headers
  s = s.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  // Blockquotes
  s = s.replaceAll(RegExp(r'^>\s*', multiLine: true), '');
  // Strip leading whitespace/tabs from each line
  s = s.replaceAll(RegExp(r'^\s+', multiLine: true), '');
  // Collapse 3+ newlines to 2
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Color accentColor;

  const _MessageBubble({required this.message, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    final raw = message['content'] as String? ?? '';
    final content = isUser ? raw : _stripMarkdown(raw);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? Colors.white : Colors.black;
    final textColor = isUser
        ? primary
        : primary.withValues(alpha: 0.45);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (context, constraints) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isUser ? double.infinity : constraints.maxWidth * 0.86,
                  ),
                  child: IntrinsicWidth(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: isUser
                    ? ShapeDecoration(
                        color: Colors.transparent,
                        shape: SmoothRectangleBorder(
                          borderRadius: SmoothBorderRadius.only(
                            topLeft: const SmoothRadius(cornerRadius: 14, cornerSmoothing: 0.9),
                            topRight: const SmoothRadius(cornerRadius: 14, cornerSmoothing: 0.9),
                            bottomLeft: const SmoothRadius(cornerRadius: 14, cornerSmoothing: 0.9),
                            bottomRight: const SmoothRadius(cornerRadius: 4, cornerSmoothing: 0.9),
                          ),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                        ),
                      )
                    : const BoxDecoration(color: Colors.transparent),
                child: Text(
                  content,
                  textAlign: isUser ? TextAlign.right : TextAlign.left,
                  style: GoogleFonts.geist(
                    fontSize: 14,
                    color: textColor,
                    height: 1.55,
                  ),
                ),
              ),
              ),
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
            child: ClipSmoothRect(
              radius: SmoothBorderRadius(cornerRadius: 17, cornerSmoothing: 0.9),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: ShapeDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(cornerRadius: 17, cornerSmoothing: 0.9),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.11),
                    width: 0.8,
                  ),
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
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasText
                            ? accentColor
                            : Colors.white.withValues(alpha: 0.12),
                        border: hasText
                            ? null
                            : Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 0.8,
                              ),
                      ),
                      child: Icon(
                        CupertinoIcons.arrow_up,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
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
    const flagColor = Color(0xFFFF3B30);
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
                    child: const Icon(CupertinoIcons.stop_circle),
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
