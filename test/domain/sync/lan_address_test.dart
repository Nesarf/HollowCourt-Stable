import 'package:hollow_court/domain/sync/lan_address.dart';
import 'package:test/test.dart';

/// Choosing the address that goes into a pairing code.
///
/// **This is the failure that cannot be seen from the machine that has it.** A laptop with Wi-Fi, a VPN
/// and WSL has three private addresses; the operating system returns them in whatever order it keeps;
/// a virtual one answers perfectly and is reachable by nobody else. The code looks right, the phone
/// cannot connect, and both screens talk about the handshake -- so the ranking is a pure function over
/// candidates and this file is the machine that would otherwise hide the bug.
void main() {
  LanCandidate c(String name, String address) =>
      LanCandidate(interfaceName: name, address: address);

  group('a real network beats a virtual one, whatever order they arrive in', () {
    test('Wi-Fi wins over WSL, Hyper-V and a VPN on the same machine', () {
      // The list is in the order this machine would plausibly produce: the virtual adapters first,
      // which is exactly why taking the first was wrong.
      final candidates = [
        c('vEthernet (WSL (Hyper-V firewall))', '172.30.96.1'),
        c('vEthernet (Default Switch)', '172.20.144.1'),
        c('Tailscale', '100.101.102.103'),
        c('Wi-Fi', '192.168.1.24'),
      ];

      expect(chooseLanAddress(candidates), '192.168.1.24');
    });

    test('and the order of the list does not change the answer', () {
      final reversed = [
        c('Wi-Fi', '192.168.1.24'),
        c('vEthernet (Default Switch)', '172.20.144.1'),
      ];
      expect(chooseLanAddress(reversed), '192.168.1.24');
      expect(
        chooseLanAddress(reversed.reversed),
        '192.168.1.24',
        reason: 'the same machine, enumerated the other way round',
      );
    });

    test('Ethernet and a WLAN name both count as real', () {
      expect(chooseLanAddress([c('wlan0', '10.0.0.5'), c('docker0', '172.17.0.1')]), '10.0.0.5');
      expect(chooseLanAddress([c('en0', '192.168.0.9'), c('utun3', '10.8.0.2')]), '192.168.0.9');
    });
  });

  group('a virtual address is still offered when it is all there is', () {
    test('somebody really does sync over a VPN', () {
      // Every rule above has a legitimate exception, which is why this is a ranking and not a filter.
      expect(chooseLanAddress([c('Tailscale', '100.101.102.103')]), '100.101.102.103');
      expect(chooseLanAddress([c('vEthernet (WSL)', '172.28.0.1')]), '172.28.0.1');
    });

    test('and a 172 address that is not a container is fine', () {
      // 172.16-31 is where containers live, and it is also a private range a real network may use. The
      // penalty is a penalty, not a ban.
      expect(chooseLanAddress([c('Ethernet', '172.20.5.5')]), '172.20.5.5');
    });
  });

  group('addresses nobody can reach are not offered at all', () {
    test('loopback is dropped, because it is not a claim about reachability', () {
      expect(chooseLanAddress([c('lo', '127.0.0.1')]), isNull);
      expect(chooseLanAddress([c('lo', '127.0.0.1'), c('Ethernet', '192.168.1.7')]), '192.168.1.7');
    });

    test('**but link-local is kept, because that is what a direct cable looks like**', () {
      // The owner's requirement: *"没有无线网络的时候，有网线接口的设备可以直接有线连接"*. Two machines joined by
      // one cable and no router are exactly the machines whose only addresses are `169.254.x.x` -- and the
      // first version of this dropped them along with loopback, which would have made a direct cable
      // connection impossible while looking like it worked: the ticket would name a real address the other
      // end had never heard of.
      expect(chooseLanAddress([c('Ethernet', '169.254.10.20')]), '169.254.10.20');
      expect(
        chooseLanAddress([c('Ethernet', '169.254.10.20'), c('Wi-Fi', '192.168.1.7')]),
        '192.168.1.7',
        reason: 'and it ranks below a routable address, because the network at large cannot use it',
      );
    });

    test('every candidate is offered in order, for a screen that lets a person choose', () {
      // The `NetCard` lesson from the study: a machine with Wi-Fi, Ethernet and a VPN adapter has several
      // addresses, and the times the automatic answer is wrong are exactly the times somebody deliberately
      // plugged something in.
      final ranked = rankedLanCandidates([
        c('vEthernet (WSL)', '172.30.96.1'),
        c('Ethernet', '169.254.10.20'),
        c('Wi-Fi', '192.168.31.157'),
        c('Tailscale', '100.101.102.103'),
        c('lo', '127.0.0.1'),
      ]);
      expect(ranked.first.address, '192.168.31.157');
      expect(
        ranked.map((c) => c.address),
        containsAll(['169.254.10.20', '100.101.102.103', '172.30.96.1']),
        reason: 'a VPN address is offered, it is just not the default: over a VPN is a real way to sync',
      );
      expect(ranked.map((c) => c.address), isNot(contains('127.0.0.1')));
      expect(
        ranked.map((c) => c.address).toList().indexOf('169.254.10.20'),
        lessThan(ranked.map((c) => c.address).toList().indexOf('100.101.102.103')),
        reason: 'the cable in the wall beats the overlay that has to be up, and both are offered',
      );
    });

    test('no candidates means no answer rather than a wrong one', () {
      expect(chooseLanAddress(const []), isNull);
      expect(chooseLanAddress([c('Wi-Fi', '')]), isNull);
    });
  });

  group('the screen can ask whether a code is worth showing', () {
    test('a loopback host is one that cannot work', () {
      expect(looksReachableFromAnotherDevice('127.0.0.1'), isFalse);
      expect(looksReachableFromAnotherDevice('127.1.2.3'), isFalse);
      expect(looksReachableFromAnotherDevice(''), isFalse);
      expect(looksReachableFromAnotherDevice('0.0.0.0'), isFalse);
    });

    test('**and a link-local address is not a thing to warn about either**', () {
      // A direct cable connection is a legitimate setup, and warning about it would be crying wolf at
      // exactly the case the owner asked for.
      expect(looksReachableFromAnotherDevice('169.254.1.1'), isTrue);
    });

    test('and everything plausible is allowed, including things this file cannot judge', () {
      // A hostname, a public address, a private one: the check is about the addresses that are
      // *definitely* wrong, because warning about a name would be crying wolf.
      expect(looksReachableFromAnotherDevice('192.168.1.24'), isTrue);
      expect(looksReachableFromAnotherDevice('10.0.0.5'), isTrue);
      expect(looksReachableFromAnotherDevice('172.28.0.1'), isTrue);
      expect(looksReachableFromAnotherDevice('laptop.local'), isTrue);
    });
  });
}
