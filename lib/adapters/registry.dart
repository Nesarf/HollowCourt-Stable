/// Section 11's adapter layer: the seams, and the fact that all of them start shut.
///
/// **What this file is.** Section 13 gives adapters their own directory and names three
/// -- DeepSeek / price / barcode -- and P5 puts the network layer at the end of the
/// roadmap with "switched per item, off by default". This is the part of that which can
/// be built before any of them exists: the interface, the disclosure, and a registry
/// whose initial state is **every adapter disabled**.
///
/// **No adapter is implemented, and that is the point rather than an omission.** An
/// interface with no implementation cannot leak a request, and the thing worth having
/// today is the shape a caller has to go through -- so that the day one is written, the
/// only way to reach it is a path that already asks for permission.
///
/// **The disclosure is facts, not prose.** A reader-visible sentence is a `CopyLine`
/// under section 12.4 and belongs in the UI layer; an adapter that wrote its own warning
/// would put display text in a layer section 3 keeps it out of, and would need
/// translating in fourteen locales. So an adapter declares *hosts*, *payload keys* and a
/// boolean, and the screen composes the sentence -- which also means the sentence cannot
/// drift away from what the code actually does, because it is built from the code's own
/// declaration.
///
/// **Two rules from section 18 are encoded here rather than trusted.** Native libraries
/// are rejected outright, so [AdapterTransport] has no `dlopen` member and no integer
/// handle to pass; and an adapter that is not [Adapter.isAvailable] cannot be enabled at
/// all, so a missing key produces a closed door rather than a request that fails at the
/// worst moment.
library;

/// The three seams section 13 names, plus the one section 11.2 does.
enum AdapterKind {
  /// Section 7's source two: a price looked up rather than typed in.
  priceComparison,

  /// A barcode read into an ingredient id.
  barcode,

  /// **Section 11.2's peripherals**: a scale, a refractometer, a thermometer, a density
  /// meter. A reading taken from a device instead of a number typed in.
  ///
  /// The instruction that makes this concrete is a milk: 全脂牛奶/低脂牛奶/甜牛奶/鲜牛奶, each
  /// brand measurably different, so a density is a *measured per-SKU* fact rather than a
  /// constant anyone can look up. `Densities` already says as much -- "a catalogue that
  /// carries a measured figure should use that instead" -- and this is the seam where such a
  /// figure would come from.
  ///
  /// **It is the one kind whose disclosure is empty by construction rather than by
  /// omission.** A peripheral has no host because there is nowhere to go, and the
  /// disclosure's whole purpose is to answer "what leaves this device" -- here the answer is
  /// that a reading *arrives* and nothing leaves, which is why the boolean is false for a
  /// reason rather than by default.
  measurement,
}

/// How an adapter reaches the world.
///
/// **Two members, and the split is section 18's argument rather than a technicality.**
/// Section 18 rejects `dlopen` on all three platforms -- *"fetch a piece of executable code
/// from the internet and run it on the user's machine"* -- and that is a statement about
/// **where code comes from**, not about which wire it crosses. A network adapter sends data
/// and receives data; a scale is a device on the other end of Bluetooth whose driver is
/// compiled into this application rather than fetched into it. Neither is a code path, and
/// there is deliberately no member that is.
///
/// **This enum had one member and a test asserting it had exactly one**, which was wrong
/// about this project's own design: section 11 is titled "network - peripherals - render
/// tiers" and section 11.2 is called "Peripheral adapters", with a Bluetooth scale named in
/// its table. The test was enforcing a claim nobody had made. What it enforces now is the
/// claim section 18 actually makes.
enum AdapterTransport {
  /// An HTTPS request to a host.
  https,

  /// A local peripheral: Bluetooth, USB, or the device's own sensors.
  ///
  /// No host and no payload, because a reading arrives rather than a request leaving.
  peripheral,
}

/// What an adapter would do, as facts a screen can build a sentence out of.
///
/// Every field is a list or a boolean rather than a string, because a string here would
/// be display copy in the wrong layer. The UI is expected to say, in its own language,
/// something of the form "contacting `hosts` and sending `payloadKeys`".
final class AdapterDisclosure {
  const AdapterDisclosure({
    required this.hosts,
    required this.payloadKeys,
    required this.sendsAnythingAboutTheCellar,
    this.needsCamera = false,
    this.needsNetwork = false,
  });

  /// **What the device has to be able to do for this adapter to work at all.**
  ///
  /// Separate from [hosts], which says what it would *send*, because these are the questions a person answers
  /// before switching it on: a barcode lookup cannot run without a camera and a network, and telling them so after
  /// they have enabled it and watched it fail is not a disclosure. [needsNetwork] is not derived from `hosts`
  /// being non-empty either -- an adapter could reach a device on the loopback, with no network at all.
  final bool needsCamera;
  final bool needsNetwork;

  /// ASCII hostnames it would connect to. Empty for an adapter that reaches nothing.
  final List<String> hosts;

  /// The event or model keys it would put in a request. Named so that "what leaves this
  /// device" is answerable without reading the adapter's source.
  final List<String> payloadKeys;

  /// Whether anything derived from the user's own log would be sent.
  ///
  /// A separate flag from [payloadKeys] because it is the question a person actually
  /// asks: a barcode lookup sends a number off a bottle, and a price comparison sends
  /// what you paid. Treating those as the same thing would make the disclosure useless.
  final bool sendsAnythingAboutTheCellar;

  static const AdapterDisclosure none = AdapterDisclosure(
    hosts: <String>[],
    payloadKeys: <String>[],
    sendsAnythingAboutTheCellar: false,
  );
}

/// One seam.
///
/// An interface rather than a base class, so an implementation cannot inherit a default
/// [isAvailable] or a default [disclosure] and accidentally ship one that says nothing.
abstract interface class Adapter {
  AdapterKind get kind;

  AdapterTransport get transport;

  /// Whether this build is in a position to run it at all.
  ///
  /// False for an adapter whose key is not configured, and **a registry refuses to
  /// enable an unavailable adapter** rather than enabling it and letting the request
  /// fail later. Section 18's position on half-open doors is the same argument: a door
  /// that looks open and is not is worse than one that is plainly shut.
  bool get isAvailable;

  /// What it would send and where, for the screen to say out loud.
  AdapterDisclosure get disclosure;
}

/// Which adapters are switched on, and they all start switched off.
///
/// **Off by default is the initial state of this object and not a setting a caller
/// passes**, which is what makes it a property of the design rather than of one call
/// site. There is no constructor that takes an "enabled" list: the only way in is
/// [enable], one kind at a time, after checking availability.
final class AdapterRegistry {
  AdapterRegistry(Iterable<Adapter> adapters)
    : _adapters = <AdapterKind, Adapter>{
        for (final adapter in adapters) adapter.kind: adapter,
      },
      _enabled = <AdapterKind>{};

  final Map<AdapterKind, Adapter> _adapters;
  final Set<AdapterKind> _enabled;

  /// Every kind this build knows about, whether or not it is available.
  Iterable<AdapterKind> get known => _adapters.keys;

  bool isEnabled(AdapterKind kind) => _enabled.contains(kind);

  bool isAvailable(AdapterKind kind) => _adapters[kind]?.isAvailable ?? false;

  Adapter? adapterFor(AdapterKind kind) => _adapters[kind];

  /// Switches one on, or refuses.
  ///
  /// Throws rather than returning false, because every path that reaches here has
  /// already asked a person whether they want it -- so a refusal means the screen was
  /// wrong about availability, which is a bug to surface and not a state to handle.
  void enable(AdapterKind kind) {
    final adapter = _adapters[kind];
    if (adapter == null) {
      throw ArgumentError.value(kind, 'kind', 'no adapter of that kind is installed');
    }
    if (!adapter.isAvailable) {
      throw StateError(
        '${kind.name} is not available in this build, so it cannot be switched on',
      );
    }
    _enabled.add(kind);
  }

  /// Switches one off. Never refuses: shutting a door is always allowed.
  void disable(AdapterKind kind) => _enabled.remove(kind);

  /// What is currently switched on, for a screen to show and a test to assert.
  Set<AdapterKind> get enabled => Set<AdapterKind>.unmodifiable(_enabled);

  /// **A second object carrying the same switches, for the one caller that needs a new identity.**
  ///
  /// A screen that toggles a switch has to rebuild, and a widget rebuilding needs a value that is not `==` to
  /// the last one. This registry is *itself* the mutable state -- the note at the top of this file says so, and
  /// that is why it is not wrapped in a notifier that would hold a second copy of the truth. The compromise is
  /// here: the truth stays in one object, and the object is replaced by a copy when something has to notice.
  AdapterRegistry copy() {
    final next = AdapterRegistry(_adapters.values);
    next._enabled.addAll(_enabled);
    return next;
  }
}
