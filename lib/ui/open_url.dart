/// Opens a URL in whatever browser the reader already uses — without a third-party package.
///
/// **Flutter has no in-tree way to do this, and the project's answer to that is not a package.** The case for
/// one is real: `url_launcher` is maintained by the Flutter team and would take four lines. The case against is
/// the one this project keeps making — Hollow Court has its own development platform and its own tools, and a
/// capability this small is a poor reason to hand a platform seam to somebody else.
///
/// So it is done with what the framework already provides:
///
///   * **Desktop** uses `dart:io` and the launcher the system already ships — `explorer` on Windows, `xdg-open`
///     on Linux, `open` on macOS. No native code at all, and nothing to keep in step with a plugin.
///   * **Android** cannot be reached from Dart, so it goes through a `MethodChannel` — the framework's own
///     mechanism — and a few lines of Kotlin in `MainActivity` that start an `ACTION_VIEW` intent.
///
/// **The return value is honest rather than decorative.** A build that cannot open a browser says so, and the
/// screen shows the address instead of pretending a tap worked; a link that silently does nothing is the same
/// class of thing as a switch that moves and leads nowhere.
library;

import 'dart:io' show Platform, Process, ProcessException;

import 'package:flutter/services.dart' show MethodChannel, PlatformException;

/// The channel the Android side answers on. Named for the application, not for the feature, because it is the
/// application that owns the seam.
const MethodChannel _channel = MethodChannel('com.nesarf.hollow_court/open_url');

/// Whether this build has any way to open a browser at all.
///
/// Asked separately from [openInBrowser] because a screen may want to know before drawing a control, and
/// because "this platform is not one of the three" is a fact rather than an error.
bool get canOpenInBrowser =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid;

/// Opens [url] in the reader's own browser. False when this build cannot, which the caller is expected to show.
Future<bool> openInBrowser(String url) async {
  final uri = Uri.tryParse(url);
  // Only ever hand a browser something that is plainly a web address. A caller passing a file path or a
  // `javascript:` string would otherwise be handing the system a command, and this function exists to open a
  // repository rather than to run things.
  if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return false;
  }

  try {
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('open', uri.toString());
      return true;
    }
    if (Platform.isWindows) {
      // `start` needs a shell; `explorer` takes the address directly and is always present.
      await Process.run('explorer', <String>[uri.toString()], runInShell: false);
      return true;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', <String>[uri.toString()]);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.run('open', <String>[uri.toString()]);
      return true;
    }
  } on PlatformException {
    // **One clause, not two, because `MissingPluginException` extends `PlatformException`.** Written the other
    // way round the second clause was unreachable dead code -- and the analyzer said so, which is the only
    // reason this comment exists rather than a silent bug: a desktop build that answers no channel at all
    // arrives here as a `MissingPluginException`, which is the case this is for.
    return false;
  } on ProcessException {
    // No launcher on the PATH, which on a minimal Linux image is a real possibility rather than a bug.
    return false;
  }
  return false;
}
