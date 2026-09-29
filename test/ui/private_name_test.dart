import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The rule the design document states and nothing enforced.**
///
/// `docs/DESIGN.md` says, two pages in, that no string a person reads carries the project's private full name --
/// the project has a
/// formal internal full name and a public name, and a reader sees only the second. That was written down after
/// the first version put the internal name on the title bar and a test was written asserting it had to be
/// there, so both the copy and the test were wrong in the same direction.
///
/// **It was a claim without a check, and on 2026-09-24 it was found broken**: the cellar-name hint in
/// `lib/ui/theme.dart` used the internal name as its example, in all four languages. The suite was green,
/// because nothing was looking.
///
/// This checks the shipped sources as *text* rather than through an API, and that is the stronger form: it
/// covers strings that do not come from `CopyLine` at all, and it covers a line somebody adds tomorrow. What it
/// deliberately does not cover is `test/`, where the internal name appears in fixtures on purpose -- a cellar
/// in a sync test is allowed to be called anything, because it is not on a screen.
///
/// **Two-character sequences, not single characters.** The private name and the public name share 庭, so a
/// one-character check would have to reject the project's own name to catch the private one. The last test here
/// fails if somebody widens it that way.
void main() {
  // **Built from code points rather than written out, so this file carries none of the characters it is looking
  // for.** Spelled literally, the sanitiser that prepares the public mirror would rewrite the guard, which is
  // both a broken guard and a large diff in a file whose whole purpose is to be clean.
  final forbidden = <String>[
    String.fromCharCodes(const [0x5E7D, 0x7A74]),
    String.fromCharCodes(const [0x871C, 0x5EAD]),
    // **The G edition's own marks, because Stable must not carry them.** Section 12.10 of `DESIGN.md` splits the
    // work: animation, feel and particle work belong to the Galactic edition and are not used here, and that
    // edition has a title of its own. If any of it makes it into what ships -- a stray title in a string table, an
    // animation smuggled in with a screen -- the stable build is describing a product it is not.
    'Galactic',
    String.fromCharCodes(const [0x6C89, 0x6CA6, 0x4E8E, 0x67D4, 0x6DA6]),
    String.fromCharCodes(const [0x67D4, 0x6F64, 0x306E, 0x6CC9]),
  ];

  /// The private name's own tail, named rather than assumed to be the last entry.
  ///
  /// **The first version of this file leaned on `forbidden.last`**, and the moment three G-edition words were
  /// appended the check below failed -- correctly, and for the wrong reason: it was testing the list's *order*
  /// instead of its aim. Position was never the point.
  final privateTail = String.fromCharCodes(const [0x871C, 0x5EAD]);
  final privateFull = String.fromCharCodes(const [0x5E7D, 0x7A74]);

  /// Directories whose contents ship. `docs/` is not among them: the design document discusses the private
  /// name as part of its own reasoning, and the public mirror is sanitised separately.
  const shippedRoots = <String>['lib', 'data', 'assets', 'android/app/src', 'windows/runner', 'linux'];

  test('**the private name appears nowhere in what ships**', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final root in shippedRoots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (!_isText(path)) continue;
        final text = entity.readAsStringSync();
        scanned++;
        for (final needle in forbidden) {
          if (text.contains(needle)) offenders.add('$path contains $needle');
        }
      }
    }
    expect(scanned, greaterThan(50), reason: 'the scan has to be looking at something');
    expect(
      offenders,
      isEmpty,
      reason: 'the internal full name must not ship:\n${offenders.join('\n')}',
    );
  });

  test('and the check is aimed at the private name, not at the project\'s own', () {
    // If somebody widens the guard to 庭 -- the character the two names share -- the project's own name stops
    // passing and this fails first. That is the mistake the design document explains, made checkable.
    expect('空庭'.contains(privateFull), isFalse);
    expect('空庭'.contains(privateTail), isFalse);
    expect(privateTail.contains(privateTail), isTrue, reason: 'the guard has to catch the private one');
    expect(forbidden, contains(privateFull));
    expect(forbidden, contains(privateTail));
  });
}

/// Text formats worth reading. A match inside a compiled artefact is a copy of a source file the scan already
/// reads, and decoding a binary as UTF-8 is how a test starts failing for the wrong reason.
bool _isText(String path) {
  const extensions = <String>[
    '.dart', '.json', '.yaml', '.yml', '.md', '.txt', '.xml', '.kt', '.java', '.gradle',
    '.kts', '.properties', '.sh', '.cmd', '.ps1', '.py', '.svg', '.html', '.h', '.cpp',
    '.rc', '.manifest', '.wxs', '.wxi', '.cmake', '.plist',
  ];
  return extensions.any(path.endsWith);
}
