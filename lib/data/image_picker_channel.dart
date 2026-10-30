import 'dart:io';

import 'package:flutter/services.dart';

/// **A picture from the reader's own library, taken through a channel rather than a plugin.**
///
/// The obvious answer was `image_picker`, and it was refused for the same reason `permission_handler` was refused on
/// 2026-10-22: the Android side of that package wants a newer `compileSdk` than this project builds against, and
/// upgrading a whole toolchain to pick a photograph is a poor trade. The channel below is the alternative the owner
/// asked for -- thirty lines of Kotlin on the other side, no new dependency, and the same `MethodChannel` pattern the
/// camera permission and the browser already use.
///
/// **Android only, and honestly so.** Windows and Linux have no `OpenDocument` contract, and inventing one with
/// another plugin would repeat the trade this file exists to avoid. The button that calls this is drawn only where
/// this answers, which is the rule of 2026-09-25: a screen does not offer what the build cannot do.
const MethodChannel _channel = MethodChannel('com.nesarf.hollow_court/picker');

/// True where a picture can be chosen from the system picker.
bool get canPickFromLibrary => Platform.isAndroid;

/// The bytes of the chosen picture, or null when the reader closed the picker.
///
/// **Null for "closed" and null for "failed"**, because the screen says the same thing either way: nothing was
/// attached. Distinguishing them would add a message nobody can act on -- the reader who cancelled knows they
/// cancelled, and the reader whose picker failed can only try again.
Future<Uint8List?> pickPictureFromLibrary() async {
  if (!canPickFromLibrary) return null;
  try {
    return await _channel.invokeMethod<Uint8List>('pickImage');
  } on MissingPluginException {
    // A build without the seam -- a plain `flutter test`, or a platform this file did not reach.
    return null;
  } on PlatformException {
    return null;
  }
}
