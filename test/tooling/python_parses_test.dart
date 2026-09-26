import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Every Python file in this repository parses.**
///
/// This exists because one of them stopped parsing and nobody noticed for a day. A blunt regex deletion -- mine --
/// removed the opening `"""` of a docstring in `art/make_icon.py` while stripping references to a typeface the mark
/// had stopped using, leaving the prose as bare code. `python art/make_icon.py` could no longer regenerate the icon,
/// and nothing failed: no test runs the art scripts, and the icon itself was already committed, so the breakage was
/// invisible until somebody happened to recompile the file.
///
/// A rule of the form "art scripts must keep working" is not a test. `ast.parse` on every tracked `.py` is: it costs
/// a second, it needs no fixtures, and it turns a class of silent breakage into a red test. Regex surgery on source
/// files is exactly the operation that produces this, and it is an operation this repository does perform.
void main() {
  test('**every tracked Python file parses**', () {
    final listed = Process.runSync('git', ['ls-files', '*.py']);
    if (listed.exitCode != 0) {
      fail('git ls-files failed, so this test cannot see the files it is meant to check');
    }
    final files = (listed.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    expect(files, isNotEmpty, reason: 'the repository has Python in it');

    final broken = <String>[];
    for (final path in files) {
      // `ast.parse` rather than `py_compile`: parsing writes nothing, so checking a file cannot change it.
      final result = Process.runSync('python', ['-c', 'import ast,sys;ast.parse(open(sys.argv[1],encoding="utf-8").read())', path]);
      if (result.exitCode != 0) {
        final message = (result.stderr as String).trim().split('\n').last;
        broken.add('$path -- $message');
      }
    }

    expect(
      broken,
      isEmpty,
      reason: 'these files do not parse, and whatever they generate can no longer be regenerated:\n'
          '${broken.join('\n')}',
    );
  });
}
