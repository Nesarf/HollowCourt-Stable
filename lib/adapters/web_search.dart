import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chat_client.dart';

/// **What the model asked the application to look up, before it answers.**
///
/// DeepSeek's Search API is a separate endpoint from the conversation (`/v1/tools/search`), so a model that wants to
/// know today's gin prices has to *ask* -- and this is the asking. The alternative would be searching before every
/// message, which costs money on questions that are not about the world, or searching on a keyword list, which is a
/// guess about what the reader meant.
class WebSearchResult {
  const WebSearchResult({required this.title, required this.url, this.summary = '', this.date});

  final String title;
  final String url;
  final String summary;
  final String? date;

  factory WebSearchResult.fromJson(Map<String, Object?> json) => WebSearchResult(
        title: '${json['title'] ?? ''}',
        url: '${json['url'] ?? ''}',
        summary: '${json['summary'] ?? json['snippet'] ?? ''}',
        date: json['date'] as String?,
      );

  /// One line per result, in the shape a model reads best: what it is, where it came from, when, and what it says.
  String get asContext => '[$title]($url)${date == null ? '' : ' · $date'}\n$summary';
}

/// **The tool the model is given, and the two ends of it.**
///
/// One tool only. A wine cellar assistant needs the web and nothing else; handing it six tools would make it slower to
/// answer and harder to predict, and every extra tool is a surface the prompt has to describe.
const Map<String, Object?> webSearchTool = <String, Object?>{
  'type': 'function',
  'function': <String, Object?>{
    'name': 'web_search',
    'description': 'Search the live web. Use it for anything about the present day: prices, releases, news, '
        'opening hours, whether a distillery still exists. Do not use it for the reader\'s own cellar.',
    'parameters': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'query': <String, Object?>{
          'type': 'string',
          'description': 'The search query, 1 to 128 characters. Supports site:, lang:, after: and quotes.',
        },
      },
      'required': <String>['query'],
    },
  },
};

/// Runs one search and answers with text the model can read.
typedef WebSearchRunner = Future<String> Function(String query);

/// **The real search, against DeepSeek's own endpoint.**
///
/// Billed per successful request rather than per token (0.75 USD per thousand as of 2026-10-22), which is why it is
/// called only when the model says it needs it.
class DeepSeekSearch {
  const DeepSeekSearch({this.timeout = const Duration(seconds: 15), SearchFetch? fetch}) : _fetch = fetch; // ignore: prefer_initializing_formals

  final Duration timeout;
  final SearchFetch? _fetch;

  static const String host = 'deepseek.com';
  static const int defaultCount = 5;

  Uri uriFor(ChatEndpoint endpoint) {
    // **The address is taken from the reader's endpoint, not hard-coded.** Somebody who pointed the conversation at a
    // proxy or a compatible server is not necessarily pointed at DeepSeek's search, and guessing otherwise would send
    // their key somewhere they did not choose.
    final base = Uri.parse(endpoint.baseUrl.replaceFirst(RegExp(r'/+$'), ''));
    final root = base.host.isEmpty ? Uri.https('api.deepseek.com', '/') : Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null);
    return root.replace(path: '/v1/tools/search');
  }

  Future<String> search(ChatEndpoint endpoint, String query) async {
    final body = <String, Object?>{'query': query, 'count': defaultCount, 'need_content': false};
    final ({int status, String body}) response;
    try {
      response = await (_fetch ?? _httpFetch)(uriFor(endpoint), endpoint.apiKey, body).timeout(timeout);
    } on TimeoutException {
      return 'The search did not answer in time.';
    } on Exception catch (error) {
      return 'The search could not be run: $error';
    }
    if (response.status != 200) {
      return 'The search answered HTTP ${response.status}.';
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return 'The search answered something that is not JSON.';
    }
    if (decoded is! Map<String, Object?>) return 'The search answered something unexpected.';
    final results = decoded['results'];
    if (results is! List || results.isEmpty) return 'No results.';
    final lines = <String>[
      for (final item in results.take(defaultCount))
        if (item is Map<String, Object?>) WebSearchResult.fromJson(item).asContext,
    ];
    return lines.isEmpty ? 'No results.' : lines.join('\n\n');
  }

  static Future<({int status, String body})> _httpFetch(Uri uri, String apiKey, Map<String, Object?> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set(HttpHeaders.userAgentHeader, 'HollowCourt/1.0 (github.com/Nesarf/HollowCourt-Stable)');
      request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (status: response.statusCode, body: text);
    } finally {
      client.close();
    }
  }
}

/// Fetches a search URL with a body and answers with status and text. Injectable so the tests never touch the network.
typedef SearchFetch = Future<({int status, String body})> Function(
  Uri uri,
  String apiKey,
  Map<String, Object?> body,
);
