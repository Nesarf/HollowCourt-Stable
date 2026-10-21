import 'dart:io';

import 'package:flutter/services.dart';

/// **The camera permission, asked for at the moment the scanner opens.**
///
/// Only Android has a runtime permission to ask for. Windows and Linux have none, so this answers true there
/// without touching a channel -- and that is not a shortcut, it is the platform's own arrangement: on the desktop
/// the operating system asks the reader once, in its own settings, and an application that prompted anyway would
/// be inventing a step.
const MethodChannel _channel = MethodChannel('com.nesarf.hollow_court/camera_permission');

/// True when the camera may be used: already granted, granted just now, or there is nothing to ask.
Future<bool> requestCameraPermission() async {
  if (!Platform.isAndroid) return true;
  try {
    return await _channel.invokeMethod<bool>('request') ?? false;
  } on MissingPluginException {
    // A build without the seam -- a plain `flutter test`, or a platform this file did not reach. The camera plugin
    // will complain by itself if it truly cannot open; reporting "denied" here would hide that behind the wrong
    // sentence.
    return true;
  } on PlatformException {
    return false;
  }
}
