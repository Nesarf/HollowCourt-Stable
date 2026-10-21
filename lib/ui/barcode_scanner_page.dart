import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/barcode_decoder.dart';
import '../data/camera_permission.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// Opens the scanner and answers with the digits it read, or null when the reader closed it.
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(builder: (_) => const BarcodeScannerPage()),
  );
}

/// **The camera, pointed at a bottle.**
///
/// **This takes a picture rather than reading a stream, and that is a platform fact rather than a preference.**
/// `camera_windows` still does not implement image streaming (issue 97542), and the desktop is where a reader is
/// most likely to be entering stock. Taking a picture every so often works everywhere; a stream would work on the
/// phone only and would be a second code path to keep alive.
///
/// **The shape is a self-scheduling loop rather than a timer, and that is the first of the three traps.** A
/// `Timer.periodic` firing into an `async` body starts a second picture while the first is still being written and
/// decoded; on a slow camera the queue grows until the driver reports the device as busy. Here the next attempt is
/// scheduled by the attempt that just finished, so there is never more than one in flight.
class BarcodeScannerPage extends ConsumerStatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  ConsumerState<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends ConsumerState<BarcodeScannerPage> {
  CameraController? _controller;
  /// The sentence to show instead of a preview, when there is nothing to preview.
  CopyLine? _problemLine;
  bool _running = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    // **Asked here rather than at launch.** A prompt on first run, with no explanation beside it, is how a reader
    // decides an application is nosy; asked at the moment the scanner opens, the reason is on the screen.
    final granted = await requestCameraPermission();
    if (!granted) {
      if (mounted) setState(() => _problemLine = Copy.barcodeScanDenied);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _problemLine = Copy.barcodeScanNoCamera);
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _running = true;
      unawaited(_loop());
    } on CameraException {
      if (mounted) setState(() => _problemLine = Copy.barcodeScanNoCamera);
    } on Exception {
      if (mounted) setState(() => _problemLine = Copy.barcodeScanNoCamera);
    }
  }

  /// One attempt after another, never two at once.
  Future<void> _loop() async {
    while (_running && mounted) {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) break;
      try {
        final shot = await controller.takePicture();
        final bytes = await shot.readAsBytes();
        // **The file is deleted before it is decoded, and not after.** It has already been read into memory; leaving
        // it until the decoder returns would accumulate a file per attempt in the temporary directory, which on a
        // long scan is hundreds of photographs.
        try {
          await File(shot.path).delete();
        } on FileSystemException {
          // The camera wrote it; somebody else may have removed it. Either way it is not this loop's to insist on.
        }
        final scanned = decodeBarcodeBytes(bytes);
        if (scanned != null) {
          _finish(scanned.text);
          break;
        }
      } on CameraException {
        // One frame that could not be taken is not a reason to stop looking.
      } on Exception {
        // Same.
      }
      if (!_running) break;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  void _finish(String code) {
    if (_finished) return;
    _finished = true;
    _running = false;
    if (mounted) Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    _running = false;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: DualCopyText(Copy.barcodeScan, style: HollowType.title),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _problemLine != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: DualCopyText(
                        _problemLine!,
                        style: HollowType.body.copyWith(color: HollowPalette.ink),
                      ),
                    )
                  : controller == null || !controller.value.isInitialized
                      ? const CircularProgressIndicator()
                      : _preview(controller),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              children: [
                DualCopyText(
                  Copy.barcodeScanHint,
                  style: HollowType.caption.copyWith(color: HollowPalette.inkSoft),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: DualCopyText(
                    Copy.barcodeScanClose,
                    style: HollowType.body.copyWith(color: HollowPalette.gold),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

  /// **The preview, with its ratio turned the right way up.**
  ///
  /// `previewSize` is what the sensor delivers, and a sensor delivers a landscape picture -- 1920 by 1080 -- even
  /// when the phone is held upright. Passing that ratio straight to `AspectRatio` on a portrait screen produces a
  /// letterbox slot about a third of the height, which is exactly what the handset showed on 2026-10-22: the bottle
  /// was in a band across the middle with black above and below. The ratio is therefore height over width.
  ///
  /// `CameraPreview` then scales to fit that box, which keeps the picture undistorted rather than stretched to fill
  /// the screen. A `BoxFit.cover` would fill more of the screen and crop instead; both are honest, and this one is
  /// chosen because the whole frame is what a reader aims with.
  Widget _preview(CameraController controller) {
    final size = controller.value.previewSize;
    final ratio = size == null ? 3 / 4 : size.height / size.width;
    return AspectRatio(
      aspectRatio: ratio,
      child: CameraPreview(controller),
    );
  }
}
