import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The check that turns a shared package config into a sentence instead of a compiler opinion.**
///
/// `tool/check_pub_config.py` exists because `.dart_tool/package_config.json` holds eighty-five absolute paths
/// and is shared between this machine's Windows side and its WSL side, so whichever ran `pub get` last owns it
/// -- and the side that did not gets hundreds of "Offset, Paint and Rect are undefined" errors in files that
/// import them. A path problem wearing a source problem's clothes.
///
/// The sibling test parses every Python file, which would catch this script ceasing to be valid Python. It
/// would not catch it answering wrongly, and an answer is the whole of what it does -- so both answers are
/// exercised here, on configs written by the test rather than on this machine's real one.
void main() {
  /// Runs the check against a config the caller wrote, and returns its exit code and output.
  (int, String) runAgainst(String configPath) {
    final result = Process.runSync(
      'python3',
      ['tool/check_pub_config.py'],
      environment: {'PUB_CONFIG': configPath},
    );
    return (result.exitCode, '${result.stdout}${result.stderr}');
  }

  test('a config whose packages exist here is accepted', () {
    final directory = Directory.systemTemp.createTempSync('pub-config-ok');
    addTearDown(() => directory.deleteSync(recursive: true));

    // A real directory, because the check's question is whether the path exists -- not whether it looks like
    // a cache. Anything else would be testing this test's idea of a pub cache.
    final cache = Directory('${directory.path}/pub-cache/hosted')..createSync(recursive: true);
    final config = File('${directory.path}/package_config.json')
      ..writeAsStringSync(jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'example', 'rootUri': 'file://${cache.path}'},
        ],
      }));

    final (code, output) = runAgainst(config.path);
    expect(code, 0, reason: output);
    expect(output, contains('matches this platform'));
  });

  test('**a config whose packages live elsewhere is refused, with the fix named**', () {
    final directory = Directory.systemTemp.createTempSync('pub-config-other');
    addTearDown(() => directory.deleteSync(recursive: true));

    final config = File('${directory.path}/package_config.json')
      ..writeAsStringSync(jsonEncode({
        'configVersion': 2,
        'packages': [
          // The shape of the real problem: an absolute path into the other platform's cache.
          {'name': 'example', 'rootUri': 'file:///home/nyarch/.pub-cache/hosted/pub.dev/analyzer-13.3.0'},
        ],
      }));

    final (code, output) = runAgainst(config.path);
    expect(code, isNot(0), reason: 'a config from the other platform must stop the build');
    expect(output, contains('OTHER platform'));
    // **The instruction is the point.** A check that only says "wrong" leaves the reader where the compiler
    // left them; this one has to name the command that clears it.
    expect(output, contains('flutter pub get'));
  });

  test('a config with relative roots is accepted as portable', () {
    final directory = Directory.systemTemp.createTempSync('pub-config-relative');
    addTearDown(() => directory.deleteSync(recursive: true));

    final config = File('${directory.path}/package_config.json')
      ..writeAsStringSync(jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'example', 'rootUri': '../pub-cache/hosted/pub.dev/analyzer-13.3.0'},
        ],
      }));

    final (code, output) = runAgainst(config.path);
    expect(code, 0, reason: output);
    expect(output, contains('portable by construction'));
  });
}
