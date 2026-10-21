import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// **What a public catalogue says a barcode is.**
///
/// Only three fields, and that is a decision rather than a first cut. A bottle is identified to the reader by a name,
/// a brand and a size; anything more -- ingredients, allergens, a photograph -- is information the reader did not ask
/// this application for, arriving from a database whose accuracy this application cannot vouch for. The screen says
/// where it came from, and what it says is what the catalogue says.
class CatalogProduct {
  const CatalogProduct({required this.code, this.name, this.brand, this.quantity});

  final String code;
  final String? name;
  final String? brand;
  final String? quantity;

  /// True when the catalogue knows the code but has nothing to say about it -- a real answer, and a different one
  /// from "no such code".
  bool get isBlank =>
      (name ?? '').trim().isEmpty && (brand ?? '').trim().isEmpty && (quantity ?? '').trim().isEmpty;

  /// The one line a reader would read: the name, with the size after it when the catalogue gave one.
  String get title {
    final parts = <String>[
      if ((name ?? '').trim().isNotEmpty) name!.trim(),
      if ((brand ?? '').trim().isNotEmpty) brand!.trim(),
      if ((quantity ?? '').trim().isNotEmpty) quantity!.trim(),
    ];
    return parts.isEmpty ? code : parts.join(' · ');
  }

  @override
  String toString() => '$code ($title)';
}

/// What asking the catalogue produced.
///
/// **Four answers rather than an optional product**, because the screen says something different for each and one
/// of them is not a failure: a code the catalogue has never heard of is an ordinary outcome for a small distillery,
/// and telling the reader "the network is down" about it would be a lie that repeats on every bottle.
sealed class CatalogAnswer {
  const CatalogAnswer();
}

final class CatalogFound extends CatalogAnswer {
  const CatalogFound(this.product);
  final CatalogProduct product;
}

/// The catalogue answered, and has no such code.
final class CatalogMissing extends CatalogAnswer {
  const CatalogMissing();
}

/// The catalogue could not be reached: no network, a timeout, a refusal, or an answer that was not JSON.
final class CatalogUnreachable extends CatalogAnswer {
  const CatalogUnreachable(this.reason);
  final String reason;
}

/// Fetches a URL and answers with the status and the body. Injectable so the tests never touch the network.
typedef CatalogFetch = Future<({int status, String body})> Function(Uri uri);

/// **The catalogue, asked about one barcode.**
///
/// The service is Open Food Facts, chosen on 2026-09-25 and unchanged: open, free, no key, no account, and a licence
/// (ODbL) that permits this use. Its coverage of spirits is uneven -- a small distillery is often not in it -- which
/// is why `CatalogMissing` is a normal answer rather than an error.
///
/// **What leaves the machine is the digits on the bottle and nothing else.** That is the disclosure the barcode
/// adapter already carried before this class existed (`hosts`, `payloadKeys: ['barcode']`,
/// `sendsAnythingAboutTheCellar: false`), and it is the reason a barcode is worth distinguishing from the reader's
/// own data: a number printed on a bottle says nothing about what is in the cellar.
class BarcodeCatalog {
  const BarcodeCatalog({
    this.timeout = const Duration(seconds: 8),
    CatalogFetch? fetch,
  }) : _fetch = fetch; // ignore: prefer_initializing_formals

  final Duration timeout;
  final CatalogFetch? _fetch;

  /// The fields asked for, and no others -- the service returns a great deal more, and asking for less is both
  /// faster and a smaller surface to misread.
  static const String _fields = 'code,product_name,brands,quantity';

  /// The host in the adapter's disclosure. Kept here rather than passed in, because a catalogue is one place and a
  /// reader is entitled to know which.
  static const String host = 'world.openfoodfacts.org';

  Uri uriFor(String code) => Uri.https(host, '/api/v2/product/$code.json', {'fields': _fields});

  Future<CatalogAnswer> lookUp(String code) async {
    final Uri uri = uriFor(code);
    final ({int status, String body}) response;
    try {
      response = await (_fetch ?? _httpFetch)(uri).timeout(timeout);
    } on TimeoutException {
      return const CatalogUnreachable('timeout');
    } on SocketException {
      return const CatalogUnreachable('no network');
    } on HttpException catch (error) {
      return CatalogUnreachable(error.message);
    } on Exception catch (error) {
      return CatalogUnreachable('$error');
    }

    // **404 is the service saying "no such product", and it is a miss rather than a failure.** Measured on
    // 2026-10-22: a real code the service does not hold answers 404, while some others answer 200 with status 0. Both
    // mean the same thing, and treating the first as "could not reach the catalogue" told the reader the network was
    // down about a bottle that simply is not in the database.
    if (response.status == 404) return const CatalogMissing();
    if (response.status != 200) return CatalogUnreachable('HTTP ${response.status}');

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const CatalogUnreachable('not JSON');
    }
    if (decoded is! Map<String, Object?>) return const CatalogUnreachable('not an object');

    // **`status` is a number in this API, and zero means "no such product" rather than an error.** A service that
    // answered 200 with an empty product would be indistinguishable from a miss otherwise.
    final status = decoded['status'];
    if (status == 0) return const CatalogMissing();

    final product = decoded['product'];
    if (product is! Map<String, Object?>) return const CatalogMissing();

    final found = CatalogProduct(
      code: '${product['code'] ?? code}',
      name: product['product_name'] as String?,
      brand: product['brands'] as String?,
      quantity: product['quantity'] as String?,
    );
    if (found.isBlank) return const CatalogMissing();
    return CatalogFound(found);
  }

  /// The real transport: one request, no redirects followed into other hosts, and a User-Agent that names this
  /// application -- the service asks for one, and an anonymous client is a client the service has no reason to keep
  /// answering.
  static Future<({int status, String body})> _httpFetch(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'HollowCourt/1.0 (github.com/Nesarf/HollowCourt-Stable)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return (status: response.statusCode, body: body);
    } finally {
      client.close();
    }
  }
}
