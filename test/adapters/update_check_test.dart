import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/update_check.dart';

/// **The update check, against answers rather than against GitHub.**
///
/// The part worth testing is the comparison: a repository tag and a build's own version are written in three different
/// shapes, and getting the order wrong means telling a reader they are up to date when they are not (or, worse,
/// telling them every launch that a beta is available). The transport is injected for the usual reasons.
void main() {
  UpdateChecker answering(int status, String body) => UpdateChecker(fetch: (uri) async => (status: status, body: body));

  const release = '{"tag_name":"v1.0.0.51540","html_url":"https://github.com/Nesarf/HollowCourt-Stable/releases/tag/v1.0.0.51540",'
      '"body":"Fixed the thing."}';

  test('**the build number is read out of all three spellings**', () {
    expect(UpdateChecker.buildNumberOf('1.0.0.51531'), 51531);
    expect(UpdateChecker.buildNumberOf('v1.0.0.51531'), 51531);
    expect(UpdateChecker.buildNumberOf('1.0.0+51531'), 51531);
    // The screen appends a theme and commit marker; it carries no order and must not confuse the comparison.
    expect(UpdateChecker.buildNumberOf('1.0.0.51531-J1407b-FFF8E7'), 51531);
    expect(UpdateChecker.buildNumberOf('unknown'), isNull);
  });

  test('**a newer tag is an update, and the notes come with it**', () async {
    final answer = await answering(200, release).check(
      repositoryUrl: 'https://github.com/Nesarf/HollowCourt-Stable',
      currentVersion: '1.0.0.51531-J1407b-FFF8E7',
    );
    expect(answer, isA<UpdateAvailable>());
    final info = (answer as UpdateAvailable).info;
    expect(info.tag, 'v1.0.0.51540');
    expect(info.newer, isTrue);
    expect(info.notes, 'Fixed the thing.');
    expect(info.url, contains('/releases/tag/'));
  });

  test('**the same build is not an update, and an older one is not either**', () async {
    for (final tag in <String>['v1.0.0.51531', 'v1.0.0.5000']) {
      final answer = await answering(200, '{"tag_name":"$tag","html_url":"u"}').check(
        repositoryUrl: 'https://github.com/Nesarf/HollowCourt-Stable',
        currentVersion: '1.0.0.51531',
      );
      expect(answer, isA<UpdateCurrent>(), reason: '$tag should not look newer');
    }
  });

  test('**a build with no version says so rather than crying update**', () async {
    // A developer running from source has no `--dart-define`; telling them there is an update every launch would be a
    // false alarm that trains them to ignore the button.
    var called = false;
    final checker = UpdateChecker(fetch: (uri) async {
      called = true;
      return (status: 200, body: release);
    });
    final answer = await checker.check(repositoryUrl: 'https://github.com/a/b', currentVersion: 'unknown');
    expect(answer, isA<UpdateUnreadable>());
    expect(called, isFalse, reason: 'nothing should be asked when the question cannot be answered');
  });

  test('**the repository address becomes the API address**', () {
    expect(UpdateChecker.apiFor('https://github.com/Nesarf/HollowCourt-Stable').toString(),
        'https://api.github.com/repos/Nesarf/HollowCourt-Stable/releases/latest');
    // The same repository said with a trailing slash or a `.git` is the same repository.
    expect(UpdateChecker.apiFor('https://github.com/Nesarf/HollowCourt-Stable/').toString(),
        'https://api.github.com/repos/Nesarf/HollowCourt-Stable/releases/latest');
    expect(UpdateChecker.apiFor('https://github.com/Nesarf/HollowCourt-Stable.git').toString(),
        'https://api.github.com/repos/Nesarf/HollowCourt-Stable/releases/latest');
  });

  test('**trouble is told apart from "up to date"**', () async {
    expect(
      await answering(404, '').check(repositoryUrl: 'https://github.com/a/b', currentVersion: '1.0.0.1'),
      isA<UpdateUnreadable>(),
    );
    expect(
      await answering(500, '').check(repositoryUrl: 'https://github.com/a/b', currentVersion: '1.0.0.1'),
      isA<UpdateUnreadable>(),
    );
    expect(
      await answering(200, '{"tag_name":"nightly","html_url":"u"}').check(
        repositoryUrl: 'https://github.com/a/b',
        currentVersion: '1.0.0.1',
      ),
      isA<UpdateUnreadable>(),
      reason: 'a tag with no number cannot be ordered against anything',
    );
  });
}
