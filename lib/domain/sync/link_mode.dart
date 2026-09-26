import 'lan_address.dart';

/// Which *kind* of link sync is allowed to use.
///
/// The owner's design, 2026-09-22: *"把有线和无线分成两种模式（不可同时选择），有线模式下无法使用无线网络进行
/// 同步，反之亦然"*.
///
/// **Two modes and not a list of adapters, and the difference is what the setting promises.** A list says
/// "prefer this one"; a mode says "**only** this kind, and the other kind is not a fallback". That is a
/// stronger and more useful statement for the case this feature exists for: on a cabled hospital intranet,
/// "wired" has to mean that nothing leaves through the building's Wi-Fi, and a mode that quietly fell back
/// to Wi-Fi when the cable was unplugged would be worse than useless -- it would be a promise that was kept
/// until it mattered.
enum SyncLink {
  /// Copper or fibre: an Ethernet port, a cable between two machines.
  wired,

  /// Radio: Wi-Fi, and the wireless bridge a building provides.
  wireless,

  /// **A network carried over a USB cable**, which on Android is USB tethering: the phone hands the other
  /// device an address on a link that exists only while that cable is plugged into that device.
  ///
  /// The owner asked for this to be its own mode rather than folded into wired -- *"而安卓端可以使用usb——所以
  /// 干脆统一再加一个USB连接模式算了"* -- and it earns the separate place for reasons a reader can act on:
  /// the link appears and disappears with a cable and a toggle, its address is the phone's to hand out
  /// (`192.168.42.x` on Android's tethering), and a machine may have both this and a real Ethernet port at
  /// the same time with no way to tell them apart by address alone.
  usb,

  /// **A routed tunnel**: WireGuard, an overlay, a site-to-site VPN.
  ///
  /// The owner's decision, 2026-09-22, after the question was put to them: a tunnel is none of the three
  /// physical links, so it becomes a fourth mode rather than being folded into one of them or left out.
  ///
  /// **Two things about it that the others do not have, and both belong on the screen.** A tunnel is the
  /// only mode that can reach a device that is *not* on this network -- which is the point -- and it is the
  /// only mode where **discovery cannot be relied on**: a broadcast does not cross a router, a tunnel has no
  /// broadcast domain, and two devices on one are found by the pairing code or by having met before
  /// (§10.2.0.3). A reader who chooses this mode and sees an empty list needs to be told that, rather than
  /// concluding that nobody is there.
  tunnel;

  static SyncLink? byName(String? name) => switch (name) {
    'wired' => SyncLink.wired,
    'wireless' => SyncLink.wireless,
    'usb' => SyncLink.usb,
    'tunnel' => SyncLink.tunnel,
    _ => null,
  };

  String get wire => name;
}

/// Which kind of link an interface is, as far as its name can say.
///
/// **Names are the only evidence available, and they are not always enough.** `dart:io` reports an
/// interface's name and its addresses; it does not report whether the hardware is a radio. So this is a
/// list of what the four platforms actually call things, and **anything unrecognised returns null** rather
/// than being guessed into a mode -- see [candidatesFor] for what null means.
///
/// The names, by platform, from what these systems report:
///
/// | | wired | wireless |
/// | --- | --- | --- |
/// | Windows | `Ethernet`, `以太网`, `本地连接` | `Wi-Fi`, `WLAN`, `无线网络连接` |
/// | Linux | `eth0`, `enp3s0`, `eno1` | `wlan0`, `wlp2s0`, `wlx…` |
/// | Android | `eth0` | `wlan0` (and `usb0`/`rndis0` are [SyncLink.usb]) |
/// | macOS | `en…` when it is an adapter | `en0`, `en1` (which is why `en` alone is not conclusive) |
///
/// macOS is the reason `en` is checked for **wired only when nothing else claims it**, and the reason this
/// function has a documented "unknown" answer instead of a default: `en0` is Wi-Fi on almost every Mac and
/// Ethernet on some, and a coin toss presented as a classification is worse than an honest null.
SyncLink? classifyLink(String interfaceName) {
  final name = interfaceName.toLowerCase().trim();

  // **The exclusion list is checked first, and that order is the whole correctness of this function.**
  // `vEthernet (WSL)` contains `eth`, and `Hyper-V Virtual Ethernet Adapter` contains `ethernet`: a naive
  // substring test classifies both as a cable, and the first version of this did exactly that -- which the
  // tests caught, and which would have put a container bridge into 有线 mode and then announced its
  // address to a network that cannot reach it.
  //
  // Then the tunnels, which are their own mode by the owner's decision rather than holes in the
  // classification: a WireGuard or Tailscale adapter is a real way to reach another device, and the only
  // way to reach one that is not on this network.
  if (_tunnelNames.any(name.contains)) return SyncLink.tunnel;

  // And what is left of the virtual names is neither a link nor a tunnel: container bridges, virtual
  // switches, Bluetooth personal-area networks. A mode that promised "only this kind of link" must not
  // quietly use one of these either.
  if (_virtualNames.any(name.contains)) return null;

  if (_wirelessNames.any(name.contains)) return SyncLink.wireless;

  // **USB is checked before wired, because on Android it is the same cable and a different mode.** A
  // tethered phone presents `rndis0` or `usb0`; an Ethernet adapter presents `eth0` on the same device. The
  // owner asked for USB to be selectable on its own, so these names belong to [SyncLink.usb] and not to
  // [SyncLink.wired] -- otherwise choosing 有线 on a phone would silently mean "tethering".
  for (final prefix in const ['usb', 'rndis']) {
    if (name.startsWith(prefix)) return SyncLink.usb;
  }

  // Short Linux names are matched as **prefixes**, because `eth` inside a longer word is a different word:
  // `eth0` and `enp3s0` are interfaces, while a name that merely contains `eth` is not (see the exclusion
  // list above, which is where `vEthernet` is caught).
  for (final prefix in const ['eth', 'enp', 'eno', 'enx']) {
    if (name.startsWith(prefix)) return SyncLink.wired;
  }
  for (final word in const ['ethernet', '以太网', '本地连接']) {
    if (name.contains(word)) return SyncLink.wired;
  }
  if (name == 'lan' || name.startsWith('lan')) return SyncLink.wired;

  // **Everything else is neither.** A name from a platform nobody has taught this function yet is not
  // promoted into whichever mode happens to be selected: an honest null is a screen that says "no cable
  // found", and a guess is a promise broken later.
  return null;
}

/// Names of things that carry a route rather than a link: every VPN and overlay adapter worth naming.
///
/// **A name list is a guess and is treated as one**, which is why an unrecognised interface belongs to no
/// mode rather than to a default: a machine running an overlay this list has never heard of will show that
/// interface to nobody, and the reader can see that it is missing rather than wonder why the wrong address
/// is being advertised.
const List<String> _tunnelNames = [
  'tailscale',
  'zerotier',
  'wireguard',
  'nordlynx',
  'openvpn',
  'proton',
  'hamachi',
  'radmin',
  'softether',
  'tap',
  'tun',
  'wg',
  'vpn',
];

/// Names of things that are neither a link nor a tunnel: container bridges, virtual switches, Bluetooth.
const List<String> _virtualNames = [
  'virtual',
  'vethernet',
  'hyper-v',
  'wsl',
  'docker',
  'vmware',
  'virtualbox',
  'vbox',
  'loopback',
  'bridge',
  'bluetooth',
];

const List<String> _wirelessNames = [
  'wi-fi',
  'wifi',
  'wlan',
  'wireless',
  'wlp',
  'wlo',
  'wlx',
  '无线',
];


/// The interfaces a mode may use, best first.
///
/// **This is where the mutual exclusion lives, and it is total**: an interface classified as the other
/// kind is not returned, and neither is one that could not be classified at all. An unclassified interface
/// is not silently promoted into the mode that happens to be selected -- a container bridge or a VPN
/// overlay is neither wired nor wireless, and using one under a mode that promises "only this kind" would
/// be exactly the quiet fallback the mode exists to prevent.
///
/// The consequence is deliberate and has to be said on screen rather than here: **a mode with nothing in it
/// finds nothing and syncs nothing**, and a reader who chose 有线 on a laptop with no cable is told that,
/// instead of being quietly served by the radio.
List<LanCandidate> candidatesFor(
  SyncLink mode,
  Iterable<LanCandidate> all,
) => rankedLanCandidates(
  all.where((candidate) => classifyLink(candidate.interfaceName) == mode),
);
