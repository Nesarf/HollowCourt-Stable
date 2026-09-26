/// The three seams section 11 names, declared and shut.
///
/// **These are not adapters and they say so.** Nothing here contacts anything: there is
/// no HTTP client, no key, no request code. What exists is the *declaration* -- which
/// kind, which transport, and what it would be allowed to send -- so that the registry has
/// something to hold, a screen has something to list, and the first implementation has a
/// shape to fill in rather than a shape to invent.
///
/// **The disclosure is empty, and that emptiness is not a placeholder value.** No host is
/// named because no host has been chosen, and inventing one -- a plausible-looking
/// `api.example.com` -- would put a fact in the interface that nobody decided. The field
/// exists so that the first real adapter is *forced* to fill it in: an adapter that
/// inherits an empty disclosure is a door whose sign says nothing, which is the thing a
/// screen would not be able to warn about.
///
/// **`isAvailable` is false for all three**, so the registry refuses to enable any of
/// them. That is section 18's position on half-open doors encoded as a fact rather than as
/// a policy: a switch that turns on and then fails at the moment of use is worse than one
/// that will not turn on.
library;

import 'registry.dart';

/// A named seam with nothing behind it.
///
/// One class and not three, because the three differ only in [kind] -- and three
/// identical classes would suggest three implementations were planned differently, which
/// is not what has been decided. The day one of them is real it becomes its own class and
/// this one keeps the other two.
final class UnimplementedAdapter implements Adapter {
  const UnimplementedAdapter(this.kind);

  @override
  final AdapterKind kind;

  /// False, and it is the whole reason this class exists rather than a null.
  ///
  /// A missing adapter and an unavailable one are different states, and only the second
  /// belongs on a screen: "this build cannot do that" is a thing to tell a person, while
  /// "there is no such feature" is not.
  @override
  bool get isAvailable => false;

  /// Empty because nobody has chosen a host, a key or a payload.
  ///
  /// Deliberately not `AdapterDisclosure.none` spelled as a default on the constructor:
  /// an implementation must state what it sends, and a default would let it not.
  @override
  AdapterDisclosure get disclosure => const AdapterDisclosure(
    hosts: <String>[],
    payloadKeys: <String>[],
    sendsAnythingAboutTheCellar: false,
  );

  /// A network request, which is what all three of section 13's seams are.
  @override
  AdapterTransport get transport => AdapterTransport.https;
}

/// **The barcode seam: a camera and a network, both of which the reader has to agree to.**
///
/// The owner's instruction on 2026-09-25: *把条码功能设置为需要联网与调用摄像头* -- so this is a declared adapter
/// that states those two requirements rather than an entry saying it cannot be built. What it does is narrow and
/// worth being precise about, because it is the one adapter that turns the camera on:
///
///   * it reads an **EAN-13** off a bottle with the camera, and that is the only thing it takes from the device;
///   * the number is matched against a catalogue. **Open Food Facts** is the intended one: open, non-commercial,
///     and run by a foundation, which is the same shape of organisation as S.M.Y.T. rather than a shop;
///   * [AdapterDisclosure.sendsAnythingAboutTheCellar] is **false**, and that is the whole point of the flag
///     existing: what leaves this device is a number printed by a distillery. Nothing about the shelf, the log,
///     what was paid, or how much is left goes anywhere;
///   * and the lookup is **optional**. The reader's own registry answers first -- a bottle scanned once is
///     remembered by its own code -- so the feature keeps working on a plane, and gets better with use.
///
/// `isAvailable` is **false**, and it says something true: no implementation ships in this build. The seam and
/// its terms are declared; the camera plugin, the permission and the lookup are not written. Section 11.1's rule
/// applies as it does to the others -- off by default, and the screen says what switching it on would cost.
final class BarcodeAdapter implements Adapter {
  const BarcodeAdapter();

  @override
  AdapterKind get kind => AdapterKind.barcode;

  @override
  AdapterTransport get transport => AdapterTransport.https;

  /// False: no implementation in this build. Not the same question as whether a catalogue exists.
  @override
  bool get isAvailable => false;

  @override
  AdapterDisclosure get disclosure => const AdapterDisclosure(
    hosts: ['world.openfoodfacts.org'],
    payloadKeys: ['barcode'],
    // **A number off a bottle is not the reader's data.** This is the distinction the flag was introduced for,
    // and the barcode is the case it was written about.
    sendsAnythingAboutTheCellar: false,
    needsCamera: true,
    needsNetwork: true,
  );
}

/// Every seam this build knows about, all of them shut.
///
/// The order is section 13's, then section 11.2's: the price comparison
/// section 7 lists as its second source, the barcode, and the peripheral that would take a
/// reading instead of a typed number.
const List<Adapter> declaredAdapters = <Adapter>[
  UnimplementedAdapter(AdapterKind.priceComparison),
  BarcodeAdapter(),
  InstrumentAdapter(),
];

/// **The peripheral seam, which is the one that is safe by construction.**
///
/// It is not an implementation and does not pretend to be: no Bluetooth stack, no protocol,
/// no reading. What it states is the shape a real one would have, and that shape is worth
/// writing down early because it differs from the other three in a way that is easy to get
/// wrong later.
///
/// **A measuring instrument contacts nothing.** Its disclosure is empty because there is
/// nowhere to go -- a scale is on the other end of a local link, and what it produces is a
/// reading *arriving* rather than anything leaving. So it is the one kind whose privacy
/// question answers itself, and the disclosure mechanism earns its place by being able to say
/// that rather than by being bypassed for it.
///
/// The instruction that made this concrete: 全脂牛奶/低脂牛奶/甜牛奶/鲜牛奶, each brand measurably
/// different, so a density is a per-SKU measurement rather than a constant. `Densities`
/// already says which way to go -- "a catalogue that carries a measured figure should use that
/// instead" -- and this is the seam such a figure would arrive through.
final class InstrumentAdapter implements Adapter {
  const InstrumentAdapter();

  @override
  AdapterKind get kind => AdapterKind.measurement;

  /// False, like the others and for a different reason worth naming: they are false because
  /// nothing is built, this one because a peripheral needs a device on the other end and this
  /// build has no driver to talk to one. Both mean the same thing to a reader.
  @override
  bool get isAvailable => false;

  /// Empty, and here it is a **fact rather than an omission**. The other three are empty
  /// because nobody has chosen a host yet; this one is empty because there is no host.
  @override
  AdapterDisclosure get disclosure => const AdapterDisclosure(
    hosts: <String>[],
    payloadKeys: <String>[],
    sendsAnythingAboutTheCellar: false,
  );

  /// **The one place the transport differs**, and the reason section 11.2 exists: a scale is
  /// not a web service. Section 18 forbids fetching executable code, and a driver compiled
  /// into this application is not that.
  @override
  AdapterTransport get transport => AdapterTransport.peripheral;
}
