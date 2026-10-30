import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// **What the newest release calls itself, and whether it is newer than this build.**
///
/// "Newer" is decided by the build number, not by the tag's shape: `1.0.0.51531` and `v1.0.0.51531` are the same
/// release said two ways, and a string comparison would put `v1.0.0.9999` after `v1.0.0.51531`. So the digits are
/// pulled out and compared as one number, and a tag with no digits in it is treated as unreadable rather than as
/// newer.
class UpdateInfo {
  const UpdateInfo({required this.tag, required this.url, required this.newer, this.notes = ''});

  /// The tag exactly as the repository spells it, so the screen can show what it will be called.
  final String tag;
  final String url;

  /// True when the release's build number is greater than this build's.
  final bool newer;

  /// The release notes, trimmed: enough to say what changed, not enough to fill a screen.
  final String notes;
}

/// What asking GitHub produced.
///
/// Four answers again, and for the same reason: this build's own version being unreadable is a different fact from
/// the network being down, and the screen has to be able to say which.
sealed class UpdateAnswer {
  const UpdateAnswer();
}

final class UpdateAvailable extends UpdateAnswer {
  const UpdateAvailable(this.info);
  final UpdateInfo info;
}

final class UpdateCurrent extends UpdateAnswer {
  const UpdateCurrent(this.tag);
  final String tag;
}

final class UpdateUnreadable extends UpdateAnswer {
  const UpdateUnreadable(this.reason);
  final String reason;
}

/// Fetches a URL and answers with status and body. Injectable so the tests never touch the network.
typedef UpdateFetch = Future<({int status, String body})> Function(Uri uri);

/// **Asks the public mirror what the latest release is.**
///
/// GitHub's unauthenticated API allows sixty requests an hour per address, which is far more than a reader pressing a
/// button can spend -- and pressing a button is the only way this is ever called. Nothing here runs on launch and
/// nothing here phones home on its own.
class UpdateChecker {
  const UpdateChecker({this.timeout = const Duration(seconds: 12), UpdateFetch? fetch}) : _fetch = fetch; // ignore: prefer_initializing_formals

  final Duration timeout;
  final UpdateFetch? _fetch;

  /// The API address for a repository URL. Accepts `https://github.com/owner/name` with or without a trailing slash
  /// or `.git`.
  static Uri apiFor(String repositoryUrl) {
    var path = Uri.parse(repositoryUrl).path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length < 2) return Uri.https('api.github.com', '/repos');
    return Uri.https('api.github.com', '/repos/${parts[0]}/${parts[1]}/releases/latest');
  }

  Future<UpdateAnswer> check({required String repositoryUrl, required String currentVersion}) async {
    final mine = buildNumberOf(currentVersion);
    if (mine == null) {
      // **A build that cannot say which build it is cannot be told it is out of date.** The version comes from a
      // `--dart-define` the packaging scripts pass; a local `flutter run` has none, and answering "there is an update"
      // to a developer running from source would be a false alarm every single time.
      return UpdateUnreadable('this build has no version to compare (${currentVersion.isEmpty ? 'empty' : currentVersion})');
    }
    final ({int status, String body}) response;
    try {
      response = await (_fetch ?? _httpFetch)(apiFor(repositoryUrl)).timeout(timeout);
    } on TimeoutException {
      return const UpdateUnreadable('timeout');
    } on SocketException catch (error) {
      return UpdateUnreadable(error.message);
    } on Exception catch (error) {
      return UpdateUnreadable('$error');
    }
    if (response.status == 404) return const UpdateUnreadable('no releases published');
    if (response.status != 200) return UpdateUnreadable('HTTP ${response.status}');

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const UpdateUnreadable('not JSON');
    }
    if (decoded is! Map<String, Object?>) return const UpdateUnreadable('not an object');
    final tag = '${decoded['tag_name'] ?? ''}'.trim();
    final url = '${decoded['html_url'] ?? ''}'.trim();
    if (tag.isEmpty) return const UpdateUnreadable('the release has no tag');
    final theirs = buildNumberOf(tag);
    if (theirs == null) return UpdateUnreadable('unreadable tag: $tag');
    final notes = '${decoded['body'] ?? ''}'.trim();
    final info = UpdateInfo(
      tag: tag,
      url: url.isEmpty ? repositoryUrl : url,
      newer: theirs > mine,
      notes: notes.length > 600 ? '${notes.substring(0, 600)}…' : notes,
    );
    return info.newer ? UpdateAvailable(info) : UpdateCurrent(tag);
  }

  /// The build number in a version string, or null.
  ///
  /// **The last run of digits after the last dot**, which is what `1.0.0.51531`, `v1.0.0.51531` and
  /// `1.0.0+51531` all share. A `-J1407b-FFF8E7` suffix is a theme and commit marker on the About screen and carries
  /// no order, so it is ignored.
  static int? buildNumberOf(String version) {
    final withoutBuild = version.split('+').last;
    final match = RegExp(r'(\d+)(?![^.]*\d)').allMatches(withoutBuild).lastOrNull;
    final digits = RegExp(r'(\d+)\.(\d+)\.(\d+)\.(\d+)').firstMatch(withoutBuild);
    if (digits != null) return int.tryParse(digits.group(4)!);
    final tail = RegExp(r'[.\-](\d+)$').firstMatch(withoutBuild);
    if (tail != null) return int.tryParse(tail.group(1)!);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static Future<({int status, String body})> _httpFetch(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri);
      // GitHub refuses a request with no User-Agent. Naming this application is also the honest thing to send.
      request.headers.set(HttpHeaders.userAgentHeader, 'HollowCourt/1.0 (github.com/Nesarf/HollowCourt-Stable)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return (status: response.statusCode, body: body);
    } finally {
      client.close();
    }
  }
}
