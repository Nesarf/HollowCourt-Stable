import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The two principles the owner asked for on 2026-09-25, as checks rather than as intentions.**
///
/// * *中立性原则* -- 所有对他人项目的引用的痕迹都不能推到公开仓库.
/// * *自主化原则* -- 提高工程内的自制比例, which is the same instinct seen from the other side: a project that
///   does not name other products as its sources is a project whose work is its own.
///
/// **Both were applied by hand this round, and both could regress tomorrow.** That is what this file is for: the
/// sweep that removed the references was a one-off, and a one-off is not a principle. A test is.
void main() {
  /// The roots whose text is published. `tools/` and an earlier survey are the private probing kit and the study
  /// notes -- they exist to name other products, which is exactly why they are not published.
  const publishedRoots = <String>[
    'lib', 'test', 'docs', 'tool', 'packaging', 'data', 'assets', 'art', 'audio', 'android', 'windows', 'linux',
  ];
  const privateRoots = <String>['tools', 'docs/reverse', 'audio/wwise'];

  /// Names of other people's products. **A coupe is not on this list and must never be**: it is a glass, the same
  /// way a highball is, and `Glass.coupe` is glassware rather than a citation. The list is of *products*, and
  /// adding a general noun to it would rename the vocabulary of drink-making.
  const otherProducts = <String>[
    'Arcaea', 'Blue Archive', 'a mobile game', 'a mobile game', 'Potion Craft', 'VRChat', 'osu!',
    'Zenless', 'Inscryption', 'Buckshot', 'Hollow Knight', 'Mixel', 'Monotype', 'UnifrakturMaguntia',
  ];

  bool isText(String path) => const [
    '.dart', '.md', '.json', '.sh', '.py', '.ps1', '.yaml', '.yml', '.txt', '.html', '.xml', '.kt', '.gradle',
    '.properties', '.wxs', '.svg', '.plist', '.cmake',
  ].any(path.endsWith);

  Iterable<File> publishedFiles() sync* {
    for (final root in publishedRoots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (privateRoots.any(path.startsWith)) continue;
        if (!isText(path)) continue;
        // The two scripts that do the sanitising necessarily name what they remove; they are excluded from the
        // mirror themselves, which the publish script enforces.
        if (path == 'tool/sanitise_public.py' || path == 'tool/push_public.sh') continue;
        if (path == 'tool/publish_public.sh') continue;
        // This file names the products on purpose, in the list above. Asking it not to would mean writing the
        // list from code points, which hides from a reader what the rule is about.
        if (path == 'test/data/principles_test.dart') continue;
        // The sweep tool names the products in order to remove them, exactly as this file does in order to
        // forbid them. It was added to the sanitiser's skip list first and forgotten here, which is what the
        // sixth round of this mistake looked like.
        if (path == 'tool/strip_references.py') continue;
        yield entity;
      }
    }
  }

  test('**中立性: no published text names another product**', () {
    final offenders = <String>[];
    for (final file in publishedFiles()) {
      // **Internal blocks are not published.** `` is stripped by the
      // sanitiser before anything leaves the machine -- its own verification proves that on every push -- so the
      // design document may keep the full citations where they are useful, inside that boundary.
      final text = file
          .readAsStringSync()
          .replaceAll(RegExp(r'', dotAll: true), '');
      for (final product in otherProducts) {
        if (text.contains(product)) offenders.add('${file.path} names $product');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'the published set must not cite other projects:\n${offenders.join('\n')}\n\n'
          '(If the hit is a glass or another general noun, take it off the list above rather than renaming it.)',
    );
  });

  test('**自主化: nothing of ours came from somebody else**', () {
    // **The owner's clarification, 2026-09-25: 自主化只针对我们工程内的东西.** Flutter's engine, the Dart SDK,
    // its packages and its 39 platform host files are what this application is built *with* -- they are the
    // platform, not our material, and replacing them would raise a count without removing a dependency. The
    // question worth answering is whether anything **of ours** came from somewhere else, and the answer must be
    // no. The platform is counted and printed separately so the framing hides nothing.
    final source = File('tool/provenance.json').readAsStringSync();
    final rules = (jsonDecode(source) as Map<String, Object?>)['rules']! as List<Object?>;

    String classOf(String path) {
      for (final entry in rules) {
        final rule = entry! as Map<String, Object?>;
        if (_matches(rule['glob']! as String, path)) return rule['class']! as String;
      }
      return 'unclassified';
    }

    final tracked = _trackedFiles();
    expect(tracked, isNotEmpty, reason: 'the repository has files, and they were not found');

    final counted = tracked.where((path) => classOf(path) != 'excluded').toList();
    final unclassified = counted.where((path) => classOf(path) == 'unclassified').toList();
    expect(
      unclassified,
      isEmpty,
      reason: 'every file needs a provenance rule, or nobody has decided where it came from: '
          '${unclassified.join(', ')}',
    );

    final ours = counted
        .where((path) => const ['self', 'generated'].contains(classOf(path)))
        .length;
    final theirs = counted.where((path) => classOf(path) == 'thirdParty').toList();
    final platform = counted.where((path) => classOf(path) == 'platform').toList();

    expect(
      theirs,
      isEmpty,
      reason: 'nothing of ours may come from somebody else: ${theirs.join(', ')}',
    );
    expect(ours, greaterThan(0), reason: 'and there must be something of ours');
    // Printed rather than asserted: the platform's size is a fact to report, not a threshold to cross.
    // ignore: avoid_print
    print("自主化: $ours of our own files, ${theirs.length} of anybody else's, "
        "${platform.length} platform files (${(ours * 100 / (ours + theirs.length)).toStringAsFixed(1)}% "
        "of ours are ours)");
  });
}

/// `**` matches across directories, `*` within one, which is all the rules in the file need.
bool _matches(String glob, String path) {
  final pattern = RegExp(
    '^${glob.split('**').map((part) => part.split('*').map(RegExp.escape).join('[^/]*')).join('.*')}\$',
  );
  return pattern.hasMatch(path);
}

/// The tracked files, asked of git because the working tree holds build output that does not ship.
List<String> _trackedFiles() {
  try {
    final result = Process.runSync('git', ['ls-files']);
    if (result.exitCode != 0) return const [];
    return (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  } on ProcessException {
    return const [];
  }
}
