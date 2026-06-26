import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SplineOrb extends StatefulWidget {
  final double width;
  final double height;
  final Color backgroundColor;

  const SplineOrb({
    super.key,
    this.width = 300,
    this.height = 300,
    this.backgroundColor = Colors.black,
  });

  @override
  State<SplineOrb> createState() => _SplineOrbState();
}

class _SplineOrbState extends State<SplineOrb> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  Timer? _loadingTimeout;

  static const _url = 'https://my.spline.design/pixelcube-da466e0166035b957fc956d32659af33/';

  void _hideLoader() {
    _loadingTimeout?.cancel();
    if (mounted && _isLoading) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _loadingTimeout?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  static const double _internalSize = 320.0;

  @override
  Widget build(BuildContext context) {
    final scale = widget.width / _internalSize;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipOval(
        child: ColoredBox(
          color: widget.backgroundColor,
          child: Stack(
            children: [
              Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: OverflowBox(
                  maxWidth: _internalSize,
                  maxHeight: _internalSize,
                  child: SizedBox(
                    width: _internalSize,
                    height: _internalSize,
                    child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_url)),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  disableHorizontalScroll: true,
                  disableVerticalScroll: true,
                  supportZoom: false,
                  disallowOverScroll: true,
                  javaScriptEnabled: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                  javaScriptCanOpenWindowsAutomatically: true,
                ),
                onWebViewCreated: (controller) => _controller = controller,
                onLoadStart: (controller, url) {
                  _loadingTimeout?.cancel();
                  if (mounted) setState(() => _isLoading = true);
                  // Spline loads WebGL content after HTML — hide loader after 8s max
                  _loadingTimeout = Timer(const Duration(seconds: 8), _hideLoader);
                },
                onLoadStop: (controller, url) async {
                  await controller.evaluateJavascript(source: '''
                    var canvas = document.querySelector('canvas');
                    if (canvas) canvas.style.background = 'transparent';
                    var logo = document.querySelector('#logo');
                    if (logo) logo.style.display = 'none';
                  ''');
                  // Give WebGL a moment to render before hiding the loader
                  Future.delayed(const Duration(milliseconds: 800), _hideLoader);
                },
                onReceivedError: (controller, request, error) => _hideLoader(),
                onReceivedHttpError: (controller, request, response) => _hideLoader(),
              ),
                  ),
                ),
              ),
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
