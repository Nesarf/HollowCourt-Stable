import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/domain/events/overlay.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/overlay/overlay_key.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

/// Section 8's headline promise, with evidence rather than reasoning: **the seed is
/// replaced wholesale on update and the overlay never is.**
///
/// These go through the real file, because the promise is about what is on disk and
/// not about what a fold makes of a list in memory. They also check the other half
/// of "one storage location": an overlay entry is an ordinary event in the same log
/// as the stock, so reopening a cellar brings back the shelf and the notes together,
/// from one file, with one clock, and a note needs no special case to sync.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('hollow_court_overlay'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File fileFor(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name.ndjson');

  /// Opens a device whose wall clock starts at [startMillis].
  Future<EventLog> device(String name, {int startMillis = 1000}) {
    final now = startMillis;
    return EventLog.open(
      file: fileFor(name),
      nodeId: name,
      nowMillis: () => now,
    );
  }

  final note = OverlayKey.recipe('negroni12345');

  test('a note written today is still there after a restart', () async {
    final first = await device('phone');
    await first.record(
      (hlc) => OverlayEvents.fieldSet(hlc: hlc, key: note, value: '糖浆减半'),
    );

    // The reopen is the only thing that makes this a claim about storage rather
    // than about a variable that happened to still be in scope.
    final second = await device('phone');
    expect(second.overlay.recipeNote('negroni12345'), '糖浆减半');
  });

  test('and it is still there when the recipe it was written about is gone', () async {
    // The seed is not in this file at all, which is the point: an overlay entry
    // names a key and a value and nothing else, so there is no reference to the
    // library that a rebuilt library could invalidate. This is the worst case -- a
    // fresh build whose seed no longer ships the recipe -- and the user's words
    // survive it because there was never anything to lose.
    final first = await device('phone');
    await first.record(
      (hlc) => OverlayEvents.fieldSet(
        hlc: hlc,
        key: OverlayKey.recipe('a_recipe_that_no_longer_ships'),
        value: '这杯别再做第二次',
      ),
    );

    final second = await device('phone');
    expect(
      second.overlay.recipeNote('a_recipe_that_no_longer_ships'),
      '这杯别再做第二次',
    );
  });

  test('a removal survives the restart too, and does not come back', () async {
    // The failure this guards against looks like a ghost: a clear that was never
    // written down, read back as though nothing had happened.
    final first = await device('phone');
    await first.record(
      (hlc) => OverlayEvents.fieldSet(hlc: hlc, key: note, value: '糖浆减半'),
    );
    await first.record((hlc) => OverlayEvents.fieldCleared(hlc: hlc, key: note));

    final second = await device('phone');
    expect(second.overlay.recipeNote('negroni12345'), isNull);
    expect(second.overlay.has(note), isFalse);
  });

  test('a note and a bottle come back from one file, in one reopen', () async {
    // Section 8's dividend stated as a test: the two folds are of one log, so a
    // reopened cellar is a shelf and its notes together rather than two stores that
    // have to be kept in step with each other.
    final first = await device('phone');
    await first.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'b1',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      ),
    );
    await first.record(
      (hlc) => OverlayEvents.fieldSet(hlc: hlc, key: note, value: '糖浆减半'),
    );

    final second = await device('phone');
    expect(second.stock.bottleCount, 1);
    expect(second.stock.remainingOf('gin').microlitres, 700000);
    expect(second.overlay.recipeNote('negroni12345'), '糖浆减半');
  });

  test('a note travels between two devices as events, with no diff layer', () async {
    // Section 10.4 reduces a sync to exchanging the events the other side is
    // missing. A note needs no special case, which is what "the event log is
    // inherently an overlay layer" buys -- and the second half of the test is the
    // part that matters, because it is where a naive implementation resolves by who
    // spoke last instead of by the clock.
    final phone = await device('phone');
    await phone.record(
      (hlc) => OverlayEvents.fieldSet(hlc: hlc, key: note, value: '糖浆减半'),
    );

    final desktop = await device('desktop', startMillis: 2000);
    expect(await desktop.merge(phone.events), hasLength(1));
    expect(desktop.overlay.recipeNote('negroni12345'), '糖浆减半');

    await desktop.record(
      (hlc) => OverlayEvents.fieldSet(hlc: hlc, key: note, value: '还是别减'),
    );
    await phone.merge(desktop.events);
    expect(phone.overlay.recipeNote('negroni12345'), '还是别减');
  });
}
