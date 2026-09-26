/// A hybrid logical clock reading.
///
/// Section 10.4 is blunt that a wall clock will not do: two devices whose
/// clocks disagree by half a minute would produce a last-write-wins verdict
/// that is simply wrong, and the losing write would be discarded as stale.
/// An HLC fixes that without giving up the usefulness of real time -- the
/// physical field still tracks the wall clock, so the ordering reads like time
/// and stays sortable by eye, while the counter and node id break ties in a way
/// every device agrees on.
///
/// The reading is also the event's identity. It is globally unique because the
/// node id is inside it, and totally ordered because the comparison below is
/// total -- so there is no separate id to mint, and no tie-break to invent
/// later when two devices turn out to have written in the same millisecond.
final class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.physicalMillis,
    required this.counter,
    required this.nodeId,
  }) : assert(nodeId != '', 'a clock reading without a node id cannot break ties');

  /// Milliseconds since the Unix epoch, as the *logical* clock sees them.
  ///
  /// Never behind any reading this device has already issued or observed, which
  /// is the whole point: it may run ahead of the machine's own wall clock.
  final int physicalMillis;

  /// Distinguishes readings that share a physical millisecond.
  final int counter;

  /// Which device issued the reading. The final tie-break, and the reason two
  /// devices can never mint the same reading.
  final String nodeId;

  @override
  int compareTo(Hlc other) {
    final byPhysical = physicalMillis.compareTo(other.physicalMillis);
    if (byPhysical != 0) return byPhysical;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;
  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;

  Map<String, Object?> toJson() => {
    'physical': physicalMillis,
    'counter': counter,
    'node': nodeId,
  };

  /// Reads a reading back, keeping the field names the log uses.
  ///
  /// Throws [FormatException] rather than guessing: a log line whose clock
  /// cannot be read is a line whose position in the order is unknown, and
  /// quietly substituting a default would silently reorder history.
  factory Hlc.fromJson(Map<String, Object?> json) {
    final physical = json['physical'];
    final counter = json['counter'];
    final node = json['node'];
    if (physical is! int || counter is! int || node is! String) {
      throw FormatException('not an HLC reading: $json');
    }
    if (node.isEmpty) {
      throw FormatException('HLC reading with an empty node id: $json');
    }
    return Hlc(physicalMillis: physical, counter: counter, nodeId: node);
  }

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.physicalMillis == physicalMillis &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(physicalMillis, counter, nodeId);

  @override
  String toString() => '$physicalMillis.$counter@$nodeId';
}

/// Issues [Hlc] readings for one device, and keeps them in step with the
/// readings it has seen from other devices.
///
/// The clock is deliberately *not* a singleton and does not read the system
/// clock itself: [nowMillis] is injected, so a test can drive time forward,
/// hold it still, or run it backwards -- the three cases the algorithm exists
/// to survive.
final class HlcClock {
  HlcClock({required this.nodeId, required this.nowMillis, Hlc? last})
    : assert(nodeId != '', 'a clock without a node id cannot break ties'),
      _last = last ?? Hlc(physicalMillis: 0, counter: 0, nodeId: nodeId);

  final String nodeId;

  /// How this clock reads the machine's wall clock.
  ///
  /// Injected rather than called directly, so a test can drive time forward,
  /// hold it still, or run it backwards -- the three cases the algorithm exists
  /// to survive.
  final int Function() nowMillis;

  Hlc _last;

  /// The most recent reading this clock has issued or observed.
  Hlc get last => _last;

  /// Issues a reading for a locally created event.
  ///
  /// When the wall clock has moved forward the physical field follows it and
  /// the counter resets; when it has not -- because two events landed in the
  /// same millisecond, or because the clock was moved backwards -- the counter
  /// carries the ordering instead. That second branch is why a device whose
  /// clock is corrected backwards does not start handing out readings that look
  /// older than events it has already written.
  Hlc next() => _issue(nowMillis());

  /// Folds in a reading received from elsewhere, and returns a new local one
  /// that is strictly after both.
  ///
  /// Replaying the log through this at startup is what restores the clock: the
  /// device resumes issuing readings past everything it has already seen, even
  /// if its own wall clock has since gone backwards.
  Hlc observe(Hlc remote) => _issue(nowMillis(), remote: remote);

  Hlc _issue(int wallMillis, {Hlc? remote}) {
    final last = _last;

    // The physical field is the maximum of everything in play. Taking the max
    // rather than the wall clock is what keeps the reading monotonic when the
    // machine's clock is behind, or has been moved backwards since the last
    // reading was written.
    var physical = wallMillis;
    if (last.physicalMillis > physical) physical = last.physicalMillis;
    final remotePhysical = remote?.physicalMillis;
    if (remotePhysical != null && remotePhysical > physical) {
      physical = remotePhysical;
    }

    final int counter;
    if (physical == last.physicalMillis && physical == remotePhysical) {
      // Both sides already used this millisecond, so the counter has to clear
      // both of them -- not just the local one.
      counter = (last.counter > remote!.counter ? last.counter : remote.counter) + 1;
    } else if (physical == last.physicalMillis) {
      counter = last.counter + 1;
    } else if (remotePhysical != null && physical == remotePhysical) {
      counter = remote!.counter + 1;
    } else {
      counter = 0;
    }

    return _last = Hlc(
      physicalMillis: physical,
      counter: counter,
      nodeId: nodeId,
    );
  }
}
