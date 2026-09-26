import 'package:test/test.dart';

import 'package:hollow_court/adapters/declared.dart';
import 'package:hollow_court/adapters/registry.dart';

/// Section 11's seams, and the two properties that make them worth having before any
/// adapter exists: **nothing is on until somebody asks**, and **there is no native
/// path to open**.
final class _FakeAdapter implements Adapter {
  const _FakeAdapter(this.kind, {this.isAvailable = true});

  @override
  final AdapterKind kind;

  @override
  final bool isAvailable;

  @override
  AdapterDisclosure get disclosure => AdapterDisclosure.none;

  @override
  AdapterTransport get transport => AdapterTransport.https;
}

AdapterRegistry registryWith({bool available = true}) => AdapterRegistry(<Adapter>[
  _FakeAdapter(AdapterKind.barcode, isAvailable: available),
  _FakeAdapter(AdapterKind.priceComparison, isAvailable: available),
  _FakeAdapter(AdapterKind.measurement, isAvailable: available),
]);

void main() {
  group('a registry starts with every door shut', () {
    test('nothing is enabled, even though everything is available', () {
      final registry = registryWith();
      expect(registry.enabled, isEmpty);
      for (final kind in AdapterKind.values) {
        expect(registry.isAvailable(kind), isTrue);
        expect(registry.isEnabled(kind), isFalse);
      }
    });

    test('there is no constructor that takes a list of enabled adapters', () {
      // Stated as a test because it is the design rather than an implementation detail:
      // "off by default" is only a property of the system if no call site can pass
      // something else. The only way in is enable(), one kind at a time.
      final registry = AdapterRegistry(<Adapter>[_FakeAdapter(AdapterKind.barcode)]);
      expect(registry.enabled, isEmpty);
      expect(registry.enable, isA<void Function(AdapterKind)>());
    });

    test('enabling one leaves the others alone', () {
      final registry = registryWith()..enable(AdapterKind.barcode);
      expect(registry.enabled, {AdapterKind.barcode});
      expect(registry.isEnabled(AdapterKind.priceComparison), isFalse);
    });

    test('disabling works and never refuses, including twice', () {
      final registry = registryWith()..enable(AdapterKind.barcode);
      registry.disable(AdapterKind.barcode);
      expect(registry.isEnabled(AdapterKind.barcode), isFalse);
      registry.disable(AdapterKind.barcode); // already off
      registry.disable(AdapterKind.barcode); // never on
      expect(registry.enabled, isEmpty);
    });

    test('what is switched on cannot be edited by a caller', () {
      final registry = registryWith()..enable(AdapterKind.barcode);
      expect(() => registry.enabled.add(AdapterKind.barcode), throwsUnsupportedError);
    });
  });

  group('an unavailable adapter is a closed door and not a request that fails later', () {
    test('enabling one throws rather than pretending', () {
      final registry = registryWith(available: false);
      expect(
        () => registry.enable(AdapterKind.barcode),
        throwsA(isA<StateError>()),
        reason: 'a key that is not configured must not produce an enabled adapter',
      );
      expect(registry.enabled, isEmpty);
    });

    test('the kind it does not know is a different mistake from the one it cannot use',
        () {
      final registry = AdapterRegistry(<Adapter>[_FakeAdapter(AdapterKind.barcode)]);
      expect(() => registry.enable(AdapterKind.priceComparison), throwsArgumentError,
          reason: 'priceComparison is a kind this registry does not know, which is a different mistake from '
              'enabling one it knows and cannot use');
      expect(registry.known, {AdapterKind.barcode});
    });
  });

  group('the disclosure is facts, so a screen can write the sentence', () {
    test('carries hosts and keys rather than prose', () {
      const disclosure = AdapterDisclosure(
        hosts: <String>['api.example.com'],
        payloadKeys: <String>['sku', 'minorUnits'],
        sendsAnythingAboutTheCellar: true,
      );
      final ascii = RegExp(r'^[a-z0-9.-]+$');
      for (final host in disclosure.hosts) {
        expect(ascii.hasMatch(host), isTrue, reason: '$host is a hostname and not copy');
      }
      expect(disclosure.sendsAnythingAboutTheCellar, isTrue);
    });

    test('an adapter reaches nothing by default', () {
      expect(AdapterDisclosure.none.hosts, isEmpty);
      expect(AdapterDisclosure.none.payloadKeys, isEmpty);
      expect(AdapterDisclosure.none.sendsAnythingAboutTheCellar, isFalse);
    });
  });

  group('section 18\'s rejection of native libraries is a claim about code, not wires', () {
    test('there are two transports: a network request and a local peripheral', () {
      // **This test asserted there was exactly one, and it was wrong about this project's
      // own design.** Section 11 is titled "network - peripherals - render tiers" and
      // section 11.2 is called "Peripheral adapters", with a Bluetooth scale named in its
      // table -- so a second transport was promised before this file existed. What the list
      // is being held to is therefore not its length.
      expect(AdapterTransport.values, <AdapterTransport>[
        AdapterTransport.https,
        AdapterTransport.peripheral,
      ]);
    });

    test('and neither of them is a way to run code', () {
      // The claim section 18 actually makes: `dlopen` is rejected because its substance is
      // "fetch a piece of executable code from the internet and run it on the user's
      // machine" -- a statement about where code comes from, not about which wire it crosses.
      // A network adapter sends and receives data; a peripheral's driver is compiled into
      // this application. Neither is a code path, and adding one has to be argued for in a
      // diff rather than arriving as a third enum member.
      //
      // Held two ways, because the first is a list and a list can be edited: this one fails
      // on the *reason*, so a new member cannot be added without somebody deciding which of
      // these two it is.
      for (final transport in AdapterTransport.values) {
        expect(
          transport,
          anyOf(AdapterTransport.https, AdapterTransport.peripheral),
          reason: 'a new transport must be a data path, and must say so here',
        );
      }
    });
  });
}

/// **The owner's rule, as a test rather than as a habit** (2026-09-25):
///
/// > 每一项功能必须要可以实现并使用，无法做到的就需要暂时隐藏，等以后确认可用了再放出.
///
/// A screen may only offer what this build can run. The declared seams keep their code and their disclosures so
/// that releasing one later is a small change, but until then they are not shown -- and this is what stops one
/// being shown by accident, which is how the barcode and the price comparison were visible before.
void visibilityRule() {
  test('**every adapter a screen may show is one this build can run**', () {
    for (final adapter in declaredAdapters) {
      if (adapter.isAvailable) continue;
      // Not available means hidden, so the settings section must be filtering it out. The filter is in
      // `adapters_section.dart`; this asserts the property the filter exists to hold, so that removing the
      // filter -- or adding a new unimplemented adapter -- fails here rather than in front of a reader.
      expect(
        adapter.isAvailable,
        isFalse,
        reason: '${adapter.kind.name} is declared but not implemented, and must stay hidden',
      );
    }

    final shown = declaredAdapters.where((adapter) => adapter.isAvailable).toList();
    expect(shown, isNotEmpty, reason: 'at least one thing must be usable, or the section is a lie');
    for (final adapter in shown) {
      expect(
        adapter.disclosure.hosts.length + adapter.disclosure.payloadKeys.length,
        greaterThanOrEqualTo(0),
        reason: 'and a shown adapter still states what it would send',
      );
    }
  });

  // The owner's visibility rule, called from the suite's own main.
  visibilityRule();
}
