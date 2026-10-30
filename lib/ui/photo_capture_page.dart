import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/camera_permission.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// Takes one photograph and answers with its bytes, or null when the reader closed the page.
///
/// **One shutter, not a stream.** The scanner next door loops because it is looking for something it has to find
/// unaided; here the reader decides when the bottle is framed, and the only thing the page owes them is a preview with
/// the right proportions.
Future<Uint8List?> takePhoto(BuildContext context) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute<Uint8List>(builder: (_) => const PhotoCapturePage()),
  );
}

class PhotoCapturePage extends ConsumerStatefulWidget {
  const PhotoCapturePage({super.key});

  @override
  ConsumerState<PhotoCapturePage> createState() => _PhotoCapturePageState();
}

class _PhotoCapturePageState extends ConsumerState<PhotoCapturePage> {
  CameraController? _controller;
  bool _problem = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final granted = await requestCameraPermission();
    if (!granted) {
      if (mounted) setState(() => _problem = true);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _problem = true);
        return;
      }
      // `medium` rather than `high`: the model downscales to about 1300 by 1300 before inference, so a bigger picture
      // costs the reader upload time and buys the answer nothing.
      final controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException {
      if (mounted) setState(() => _problem = true);
    } on Exception {
      if (mounted) setState(() => _problem = true);
    }
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      try {
        await File(shot.path).delete();
      } on FileSystemException {
        // The bytes are already in memory; the file is the camera's business.
      }
      if (mounted) Navigator.of(context).pop(bytes);
    } on CameraException {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
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
        title: DualCopyText(Copy.chatTakePhoto, style: HollowType.title),
        backgroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _problem
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
                          // The same correction as the scanner: a sensor hands over a landscape picture, so on a
                          // portrait screen the ratio goes height over width.
                          aspectRatio: controller.value.previewSize == null
                              ? 3 / 4
                              : controller.value.previewSize!.height / controller.value.previewSize!.width,
                          child: CameraPreview(controller),
                        ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: IconButton.filled(
                key: const ValueKey('chat-shutter'),
                iconSize: 34,
                onPressed: _busy || _problem || controller == null ? null : _shoot,
                icon: const Icon(Icons.camera_alt),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
