import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/barcode_catalog.dart';

/// **The catalogue, tested against answers rather than against the network.**
///
/// A test that called Open Food Facts would need the internet, would change its mind when a product was edited, and
/// would fail on a train. So the transport is injected and the fixtures are the shapes this class has to tell apart:
/// a product, a miss, a blank product, and four kinds of trouble. The one thing this cannot prove is whether the
/// service answers what its documentation says -- that is checked by hand, once, with a real barcode.
void main() {
  BarcodeCatalog catalogAnswering(int status, String body) => BarcodeCatalog(
        fetch: (uri) async => (status: status, body: body),
      );

  const found = '{"status":1,"product":{"code":"6902944880059","product_name":"二锅头",'
      '"brands":"红星","quantity":"500 ml"}}';

  test('**a product comes back with its name, brand and size**', () async {
    final answer = await catalogAnswering(200, found).lookUp('6902944880059');
    expect(answer, isA<CatalogFound>());
    final product = (answer as CatalogFound).product;
    expect(product.name, '二锅头');
    expect(product.brand, '红星');
    expect(product.quantity, '500 ml');
    expect(product.title, '二锅头 · 红星 · 500 ml');
  });

  test('**status 0 means no such product, which is not a failure**', () async {
    final answer = await catalogAnswering(200, '{"status":0,"status_verbose":"no code found"}').lookUp('1');
    expect(answer, isA<CatalogMissing>());
  });

  test('**a product with nothing in it counts as missing**', () async {
    // A real shape: the code exists in the service but nobody has filled anything in. Reporting it as found would put
    // an empty line on the screen and leave the reader believing something had gone wrong.
    final answer = await catalogAnswering(200, '{"status":1,"product":{"code":"1","product_name":""}}').lookUp('1');
    expect(answer, isA<CatalogMissing>());
  });

  test('**a 404 is the catalogue saying it has no such code**', () async {
    // Measured against the real service on 2026-10-22: an unknown code answers 404, and some others answer 200 with
    // status 0. Both are misses; neither means the network is down.
    final answer = await catalogAnswering(404, '').lookUp('6902944880059');
    expect(answer, isA<CatalogMissing>());
  });

  test('**trouble is told apart from a miss**', () async {
    expect(await catalogAnswering(503, '').lookUp('1'), isA<CatalogUnreachable>());
    expect(await catalogAnswering(200, 'not json').lookUp('1'), isA<CatalogUnreachable>());
    expect(await catalogAnswering(200, '[]').lookUp('1'), isA<CatalogUnreachable>());
    // And one that throws rather than answering.
    final throws = BarcodeCatalog(fetch: (uri) async => throw const SocketExceptionLike());
    expect(await throws.lookUp('1'), isA<CatalogUnreachable>());
  });

  test('**the request asks for the fields this class reads**', () {
    final uri = const BarcodeCatalog().uriFor('6902944880059');
    expect(uri.host, BarcodeCatalog.host);
    expect(uri.path, '/api/v2/product/6902944880059.json');
    expect(uri.queryParameters['fields'], 'code,product_name,brands,quantity');
  });

  test('**a timeout is an answer, not a hang**', () async {
    final slow = BarcodeCatalog(
      timeout: const Duration(milliseconds: 30),
      fetch: (uri) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return (status: 200, body: found);
      },
    );
    final answer = await slow.lookUp('1');
    expect(answer, isA<CatalogUnreachable>());
    expect((answer as CatalogUnreachable).reason, 'timeout');
  });
}

/// A stand-in for a transport that fails. `SocketException` cannot be constructed without a message, and this test
/// only needs something that throws.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
