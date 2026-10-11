import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/domain/archive/archive_manifest.dart';
import 'package:hollow_court/domain/sync/wire.dart';

/// **The segment announcement, and the two compatibility claims it rests on.**
///
/// `docs/archival.md` asks for *"a new frame in the sync protocol"* and requires that **an older peer "must degrade
/// to 'I do not have that' rather than to an error"**. Those two cannot both be met by a frame kind, and measuring
/// the exchange is what shows it: `WireFrame.parse` returns null for a kind this build does not know, and the reader
/// of that null calls `_end('the other end sent something unreadable')`. **An old peer has no path that says "I do
/// not have that"; the only thing it can do with a frame it cannot read is hang up.**
///
/// So the announcement rides an optional field on `hello`, which every build already parses and whose unknown keys
/// are ignored. The tests below are the two halves of that claim -- **a hello without the field still parses** (what
/// this build must do with an old peer) and **a hello with a field it does not know still parses** (what an old peer
/// does with this one) -- plus the rules for a field that is present and wrong.
void main() {
  ArchiveManifest claim(
    String digest, {
    int count = 3,
    String first = 'a',
    String last = 'b',
    String nodeId = 'test',
    int createdMillis = 1000,
  }) => ArchiveManifest(
    format: ArchiveManifest.formatVersion,
    createdMillis: createdMillis,
    firstClock: first,
    lastClock: last,
    count: count,
    nodeId: nodeId,
    digest: digest,
  );

  HelloFrame hello({Iterable<ArchiveManifest> segments = const []}) => HelloFrame(
    name: 'cellar',
    digest: ClockDigest.fromSummary(count: 0, digest: 0),
    segments: segments,
  );

  group('the field travels', () {
    test('**a hello with segments survives the wire and says the same thing**', () {
      final sent = hello(segments: [claim('abc', count: 12), claim('def', count: 1)]);

      final read = WireFrame.parse(sent.encode());

      expect(read, isA<HelloFrame>());
      final got = read! as HelloFrame;
      expect(got.segments, hasLength(2));
      expect(got.segments.first.digest, 'abc');
      expect(got.segments.first.count, 12);
      expect(got.segments.last.firstClock, 'a');
      expect(got.segments.last.lastClock, 'b');
    });

    test('**and a hello with none is byte-for-byte the hello that came before this feature**', () {
      // Not a tautology: it is what an old peer receives, and the reason it never has to notice. If this build sent
      // an empty `segments` array the frame would still parse over there -- but the omission is what keeps a hello
      // identical to the one the previous release sent, and that is the property worth holding.
      expect(hello().encode(), isNot(contains('segments')));
      expect(hello().encode(), contains('"kind":"hello"'));
    });
  });

  group('the two compatibility directions', () {
    test('**a hello from a build that has never heard of segments parses**', () {
      // What this build must do with an older peer. The frame is exactly the one this project has always sent.
      const line = '{"kind":"hello","name":"old","count":4,"digest":99}';

      final read = WireFrame.parse(line);

      expect(read, isA<HelloFrame>());
      expect((read! as HelloFrame).segments, isEmpty);
      expect((read as HelloFrame).name, 'old');
    });

    test('**a hello carrying a field this build does not know parses**', () {
      // The other direction, simulated: a *future* build's hello, with a key this one has no idea about. It has to
      // be readable -- an old peer that hung up on an unknown JSON key would break every forward-compatible change,
      // and the whole point of putting the announcement here is that it does not.
      const line =
          '{"kind":"hello","name":"new","count":1,"digest":2,"somethingLater":{"a":1},"segments":[]}';

      final read = WireFrame.parse(line);

      expect(read, isA<HelloFrame>());
      expect((read! as HelloFrame).name, 'new');
    });

    test('and a segment entry carrying a field this build does not know keeps its readable fields', () {
      // **The whole manifest now, and that is the correction this round is about.** The first version announced
      // `{digest, count, first, last}` -- enough to identify a package and not enough to receive one, because a
      // receiver writes the file it is given and needs *when* it was made and *which device* made it.
      const line = '{"kind":"hello","name":"n","count":0,"digest":0,"segments":['
          '{"version":1,"createdMillis":7,"firstClock":"a","lastClock":"b","count":2,'
          '"nodeId":"them","digest":"abc","later":"x"}]}';

      final read = WireFrame.parse(line)! as HelloFrame;

      expect(read.segments.single, claim('abc', count: 2, nodeId: 'them', createdMillis: 7));
      expect(read.segments.single.createdMillis, 7);
    });
  });

  group('and the rules for a field that is present and wrong', () {
    test('**a field of the wrong type is refused, because that is a peer contradicting the protocol**', () {
      // `segments` that is not a list is not "a peer with one odd entry"; it is a frame whose shape is not this
      // protocol's, and refusing it here is the rule `HelloFrame` already applies to every other field.
      const line = '{"kind":"hello","name":"n","count":0,"digest":0,"segments":"two"}';

      expect(WireFrame.parse(line), isNull);
    });

    test('**one unreadable entry is dropped and the others are kept**', () {
      // The asymmetry, and it is deliberate: an entry is a *claim about somebody's files*, so a claim this build
      // cannot read costs that claim and not the four beside it. A peer that announced five segments and garbled one
      // is announcing four, which is a true statement about it -- where refusing the whole hello would end a sync
      // over a field that does nothing but describe.
      String entry(String digest, int count) =>
          '{"version":1,"createdMillis":1,"firstClock":"a","lastClock":"b",'
          '"count":$count,"nodeId":"them","digest":"$digest"}';
      final line = '{"kind":"hello","name":"n","count":0,"digest":0,"segments":['
          '${entry('good', 1)},'
          '${entry('', 1)},'
          '{"count":1,"first":"a","last":"b"},'
          '"not an object",'
          '${entry('also', 2)}]}';

      final read = WireFrame.parse(line)! as HelloFrame;

      expect(read.segments, hasLength(2));
      expect([for (final s in read.segments) s.digest], ['good', 'also']);
    });

    test('a negative count is refused, and a zero one is not', () {
      // A count is what a receiver sizes itself against, and a negative one is the same class of defect the
      // `digest.count` field already refuses: a claim that would make a loop complete immediately.
      Map<String, Object?> claimJson(String digest, int count) => {
        'version': ArchiveManifest.formatVersion,
        'createdMillis': 1,
        'firstClock': 'a',
        'lastClock': 'b',
        'count': count,
        'nodeId': 'them',
        'digest': digest,
      };

      expect(readSegmentClaim(claimJson('d', -1)), isNull);
      expect(readSegmentClaim(claimJson('d', 0)), isNotNull);
    });

    test('an empty digest names nothing, and is dropped', () {
      // The digest **is** the identity: a segment with no digest cannot be asked for, and keeping it would put a
      // claim on the outcome that names nothing a reader could act on.
      Map<String, Object?> claimJson(String digest) => {
        'version': ArchiveManifest.formatVersion,
        'createdMillis': 1,
        'firstClock': 'a',
        'lastClock': 'b',
        'count': 1,
        'nodeId': 'them',
        'digest': digest,
      };

      expect(readSegmentClaim(claimJson('')), isNull);
      expect(readSegmentClaim(claimJson('abc')), isNotNull);
    });
  });
}
