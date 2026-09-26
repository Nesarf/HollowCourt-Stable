import '../overlay/overlay_key.dart';
import 'event.dart';
import 'hlc.dart';

/// The overlay events, and the payload keys they use.
///
/// **They live in the same log as everything else, and section 8 says so**:
/// "the event log is inherently an overlay layer -- another dividend of this
/// architecture". A second file for the overlay would be a second clock, a second
/// sync story and a second thing to get wrong, for a layer whose whole purpose is
/// to be the thing that survives when something else is replaced. So an overlay
/// entry is an ordinary event, and it merges, dedupes and travels by the
/// machinery section 10 already asks for.
///
/// The keys are written down once, here, because they are a wire format: two
/// devices agree about a note only because they spell the field the same way.
abstract final class OverlayEvent {
  /// Somebody set a field to a value.
  static const fieldSet = 'overlay.field.set';

  /// Somebody removed a field.
  ///
  /// **Not the same as never having set it**, and the difference is the whole
  /// reason this event exists rather than the UI simply forgetting the value. A
  /// removal that left no trace would be undone by the next sync: a peer that
  /// still holds the older `set` would hand it back, and the value the user threw
  /// away would reappear. A clear is an operation, so it wins on its clock like
  /// anything else.
  static const fieldCleared = 'overlay.field.cleared';

  /// Every type this build knows how to reduce.
  static const all = {fieldSet, fieldCleared};
}

/// Builders for the overlay events.
///
/// Each takes the clock reading the caller obtained from an `HlcClock`. Nothing
/// here reads the system clock, so an event's contents can be asserted exactly in
/// a test.
abstract final class OverlayEvents {
  /// Sets [key] to [value].
  ///
  /// **[value] may not be empty, and the refusal is deliberate.** "Set to nothing"
  /// and "removed" are the same state to a reader and different operations to a
  /// log, and a layer that allowed both would leave every screen guessing which
  /// one it was looking at. So an empty string is refused here and the caller is
  /// pointed at [fieldCleared], which is the operation they actually meant. The
  /// value is otherwise the user's own text and is not trimmed, normalised or
  /// inspected: the words belong to them.
  static Event fieldSet({
    required Hlc hlc,
    required OverlayKey key,
    required String value,
  }) {
    if (value.isEmpty) {
      throw ArgumentError.value(
        value,
        'value',
        'an empty value is a removal; use OverlayEvents.fieldCleared($key)',
      );
    }
    return Event(
      hlc: hlc,
      type: OverlayEvent.fieldSet,
      data: {..._partsOf(key), 'value': value},
    );
  }

  /// Removes whatever [key] held.
  ///
  /// Clearing a key that was never set is a no-op rather than an error: the two
  /// devices in a sync disagree about what has been set all the time, and an
  /// operation that errored on a legitimate race would be an operation nobody
  /// could send.
  static Event fieldCleared({required Hlc hlc, required OverlayKey key}) => Event(
    hlc: hlc,
    type: OverlayEvent.fieldCleared,
    data: _partsOf(key),
  );

  /// The key, spread across three payload fields.
  ///
  /// Three fields rather than the packed `kind:id.field` form, because the packed
  /// one has to be parsed and a wire format that needs parsing is a wire format
  /// with a failure mode. `OverlayKey.toString` exists for humans and for a
  /// settings key; this is the form that is read back.
  static Map<String, Object?> _partsOf(OverlayKey key) => {
    'kind': key.kind,
    'id': key.id,
    'field': key.field,
  };
}

/// An overlay event, read back as a typed operation.
///
/// [tryParse] returns null for any other event type rather than throwing: the log
/// is shared, and a device will routinely meet events written by a build that
/// knows more than it does. Refusing to read the line would be refusing to carry
/// it, and an op-log that drops what it does not understand loses operations on
/// sync -- here, somebody's note.
///
/// **A malformed overlay payload does throw**, through `Event.require`, and that
/// is not inconsistent with the paragraph above. An event whose *type* this build
/// does not know is a peer from the future and is carried untouched; an event of
/// this build's own type whose payload is wrong is drift, and drift worth
/// surfacing is exactly what `require`'s strictness is for.
sealed class OverlayOp {
  const OverlayOp(this.hlc, this.key);

  final Hlc hlc;

  /// What the operation is about.
  final OverlayKey key;

  static OverlayOp? tryParse(Event event) {
    if (!OverlayEvent.all.contains(event.type)) return null;
    final key = OverlayKey(
      event.require<String>('kind'),
      event.require<String>('id'),
      event.require<String>('field'),
    );
    return switch (event.type) {
      OverlayEvent.fieldSet => OverlayFieldSet(
        hlc: event.hlc,
        key: key,
        value: event.require<String>('value'),
      ),
      OverlayEvent.fieldCleared => OverlayFieldCleared(hlc: event.hlc, key: key),
      _ => null,
    };
  }
}

/// A field was set to something.
final class OverlayFieldSet extends OverlayOp {
  const OverlayFieldSet({
    required Hlc hlc,
    required OverlayKey key,
    required this.value,
  }) : super(hlc, key);

  final String value;
}

/// A field was removed.
final class OverlayFieldCleared extends OverlayOp {
  const OverlayFieldCleared({required Hlc hlc, required OverlayKey key})
    : super(hlc, key);
}
