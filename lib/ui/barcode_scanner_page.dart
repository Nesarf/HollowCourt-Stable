import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/barcode_decoder.dart';
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
  Object? _problem;
  bool _running = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _problem = StateError('no camera'));
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
    } on CameraException catch (error) {
      if (mounted) setState(() => _problem = error);
    } on Exception catch (error) {
      if (mounted) setState(() => _problem = error);
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
              child: _problem != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: DualCopyText(
                        Copy.barcodeScanNoCamera,
                        style: HollowType.body.copyWith(color: HollowPalette.ink),
                      ),
                    )
                  : controller == null || !controller.value.isInitialized
                      ? const CircularProgressIndicator()
                      : AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: CameraPreview(controller),
                        ),
            ),
          ),
          Padding(
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
        ],
      ),
    );
  }
}
