/// Choosing which address to put in a pairing code, and knowing when the answer is useless.
///
/// **The failure this exists for is the most likely one in the two-device round, and it is invisible on
/// the machine that has it.** `lanAddress()` used to take the first non-loopback IPv4 that
/// `NetworkInterface.list` returned. On a laptop with Wi-Fi, a VPN and WSL installed -- which is this
/// machine -- "the first" is decided by the operating system's enumeration order, and a virtual adapter
/// answers perfectly well while being reachable by nobody else. The code looks right, the other device
/// cannot connect, and every message on both screens is about the *handshake* rather than about the
/// address, because on this side nothing is wrong.
///
/// So the choice is a ranking rather than a scan, and it is a pure function over candidates so that the
/// ranking can be tested without the machine it runs on.
final class LanCandidate {
  const LanCandidate({required this.interfaceName, required this.address});

  /// What the operating system calls the interface: `Wi-Fi`, `Ethernet`, `vEthernet (WSL)`,
  /// `Tailscale`, `Hyper-V Virtual Ethernet Adapter`.
  final String interfaceName;

  /// The IPv4 address on it.
  final String address;
}

/// The address another device on the same network is most likely to reach, or null when there is none.
///
/// **Ranked, not filtered**, because every rule here has a legitimate exception: somebody really does
/// sync over a VPN, and somebody really does run two cellars in one WSL distribution. So a virtual
/// adapter is offered when it is all there is, and never when a real one exists.
String? chooseLanAddress(Iterable<LanCandidate> candidates) {
  final ranked = candidates.where((c) => _usable(c.address)).toList()
    ..sort((a, b) => _score(b).compareTo(_score(a)));
  return ranked.isEmpty ? null : ranked.first.address;
}

/// Every interface worth offering, best first, for a screen that lets a person choose.
///
/// **The owner asked for wired networks and real VPNs on 2026-09-22, and that is what makes this
/// necessary.** Red Alert 2 stored a `NetCard=0` index beside its port numbers for exactly this reason:
/// a machine with Wi-Fi, an Ethernet port, a container bridge and a VPN adapter has several addresses,
/// the automatic answer is right most of the time, and the times it is wrong are precisely the times a
/// person has deliberately plugged something in. So the ranking becomes a *default* and the reader gets
/// the list.
///
/// Returned as candidates rather than strings because a reader choosing between two addresses needs to
/// know which adapter each belongs to -- `Wi-Fi 192.168.31.157` and `Ethernet 169.254.10.20` are a
/// decision, and two bare addresses are a puzzle.
List<LanCandidate> rankedLanCandidates(Iterable<LanCandidate> candidates) =>
    candidates.where((c) => _usable(c.address)).toList()
      ..sort((a, b) => _score(b).compareTo(_score(a)));

/// True when [host] is an address **another device could plausibly reach**.
///
/// Used by the screen rather than by the chooser: a ticket whose host fails this is a ticket that will
/// not work, and saying so before somebody types it into a phone is worth a sentence.
bool looksReachableFromAnotherDevice(String host) {
  if (host.isEmpty) return false;
  if (host == '0.0.0.0' || host == '::') return false;
  if (host.startsWith('127.')) return false;
  // Link-local is reachable *by the device on the other end of the wire* and by nobody else, which for a
  // direct cable connection is the whole point rather than a problem. Warning about it would be crying
  // wolf at exactly the setup the owner asked for.
  return true;
}

/// Whether an address is worth offering at all.
///
/// **Loopback is not; link-local is.** The first version of this dropped `169.254.` along with `127.`,
/// which was wrong for a reason the owner found: *"没有无线网络的时候，有网线接口的设备可以直接有线连接"*.
/// Two machines joined by one cable and no router are **exactly** the machines whose only addresses are
/// link-local (`169.254.x.x`), and a rule that refused to advertise one would make a direct cable
/// connection impossible while looking like it worked -- the ticket would name a real address that the
/// other end had never heard of.
///
/// Loopback stays out because it is not a claim about reachability, it is the absence of one.
bool _usable(String address) {
  if (address.isEmpty) return false;
  if (address.startsWith('127.')) return false;
  return true;
}

/// Higher is better. The bands are deliberately far apart so a rule can be added without re-tuning the
/// others.
int _score(LanCandidate candidate) {
  var score = 0;

  // ---- what the address itself says ------------------------------------------------
  //
  // The three private ranges are equally good in principle, and the order between them is taste: 192.168
  // is what a home router hands out, 10. is what an office does, and 172.16-31 is where WSL and Docker
  // live -- so it scores lowest of the three without being excluded, because a private 172 address that
  // is *not* a container is perfectly reachable.
  if (candidate.address.startsWith('192.168.')) score += 300;
  if (candidate.address.startsWith('10.')) score += 200;
  if (_isCarrierGradeOrContainer(candidate.address)) score += 50;

  // **Link-local is not penalised, and the reason is that the ranking cannot know what somebody
  // intended.** A `169.254.` address means "no router answered, so we agreed on something", which is
  // exactly what a direct cable looks like: reachable by the device on the other end of that cable and by
  // nobody else. So are a VPN overlay's addresses and a container bridge's. The rule this file settles on
  // is therefore stated once, here:
  //
  //   The ranking answers *"which address would a device I have arranged nothing with be able to reach?"*
  //   A private LAN address wins, because that is the network the whole building shares. Everything else
  //   is a **deliberate arrangement**, and a deliberate arrangement is a choice rather than a default --
  //   offered in a stable order, and picked by the reader (`rankedLanCandidates`).
  //
  // Left unpenalised, the interface *name* still orders these sensibly: an Ethernet port with a
  // link-local address is the cable in the wall, while a VPN adapter is reachable only while its overlay
  // is up.

  // ---- and what the interface is called --------------------------------------------
  //
  // **Names are checked because addresses cannot tell them apart.** WSL's virtual adapter is a private
  // 172 address, a VPN's is usually private too, and both are indistinguishable from a real LAN by
  // their numbers alone.
  final name = candidate.interfaceName.toLowerCase();
  if (_realLanNames.any(name.contains)) score += 100;
  if (_virtualNames.any(name.contains)) score -= 100;

  return score;
}

/// 172.16.0.0 through 172.31.255.255 -- where containers and WSL live.
bool _isCarrierGradeOrContainer(String address) {
  if (!address.startsWith('172.')) return false;
  final second = int.tryParse(address.split('.').elementAt(1));
  return second != null && second >= 16 && second <= 31;
}

/// Interface names that mean a physical network a peer is likely to share.
const List<String> _realLanNames = [
  'wi-fi',
  'wifi',
  'wlan',
  'wireless',
  'ethernet',
  'eth',
  'en0',
  'en1',
];

/// Interface names that mean something only this machine can reach.
///
/// Not exhaustive and not meant to be: it is a penalty, so an unknown adapter still loses to a known
/// good one and still wins over nothing.
const List<String> _virtualNames = [
  'wsl',
  'hyper-v',
  'vethernet',
  'docker',
  'vmware',
  'virtualbox',
  'vbox',
  'tailscale',
  'zerotier',
  'wireguard',
  'openvpn',
  'tap',
  'tun',
  'vpn',
  'loopback',
];
