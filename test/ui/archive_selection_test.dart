import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/archive_providers.dart';

/// **Which packages a reader has attached.**
///
/// `docs/archival.md`: no archive is read unless it was chosen, and that is what makes the consequences safe -- a
/// package the reader deletes is simply not in the list, so nothing has to notice and no history changes behind their
/// back. **These are the three operations the owner asked for by name**: select, select-all, and invert.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  // **Functions rather than getters**, because Dart does not allow a getter inside a function body -- and a getter was
  // the first version, which does not compile.
  ArchiveSelection selection() => container.read(archiveSelectionProvider.notifier);
  Set<String> state() => container.read(archiveSelectionProvider);

  const three = ['a.courtarchive', 'b.courtarchive', 'c.courtarchive'];

  test('nothing is attached until something is chosen', () {
    expect(state(), isEmpty, reason: 'the default has to be "read only the working log"');
  });

  test('a name toggles in and out', () {
    selection().toggle('a.courtarchive');
    expect(state(), {'a.courtarchive'});
    selection().toggle('a.courtarchive');
    expect(state(), isEmpty);
  });

  test('**select-all takes everything it is offered**', () {
    selection().selectAll(three);
    expect(state(), three.toSet());
  });

  test('select-all replaces rather than adds, so it is not an accumulating mess', () {
    selection().toggle('a.courtarchive');
    selection().selectAll(three);
    expect(state(), three.toSet());
  });

  test('**invert is the inverse of what is selected, not of everything**', () {
    // The operation the owner asked for, and the one worth testing hardest: a reader with twenty packages who wants all
    // but one should not have to tick nineteen.
    selection().toggle('a.courtarchive');
    selection().invert(three);
    expect(state(), {'b.courtarchive', 'c.courtarchive'});
  });

  test('inverting twice returns to where it started', () {
    selection().toggle('b.courtarchive');
    final before = {...state()};
    selection().invert(three);
    selection().invert(three);
    expect(state(), before);
  });

  test('invert against everything selects nothing', () {
    selection().selectAll(three);
    selection().invert(three);
    expect(state(), isEmpty);
  });

  test('invert against nothing selects everything', () {
    selection().invert(three);
    expect(state(), three.toSet());
  });

  test('**names outside the offered list are inverted away, not kept**', () {
    // A package that has since been deleted is not in the list a screen offers, so it must not survive an invert --
    // otherwise a reader who selected it, deleted the file, and pressed invert would still have a selection naming a
    // file that is not there.
    selection().toggle('gone.courtarchive');
    selection().toggle('a.courtarchive');
    selection().invert(three);
    expect(state(), {'b.courtarchive', 'c.courtarchive'});
  });

  test('clear empties it', () {
    selection().selectAll(three);
    selection().clear();
    expect(state(), isEmpty);
  });

  test('**the state() is replaced rather than mutated, so a watcher rebuilds**', () {
    // A Riverpod notifier that mutated its own set in place would notify nobody, and the screen would draw the old
    // selection -- which is the failure mode the whole class of "state() that is a collection" invites.
    final before = state();
    selection().toggle('a.courtarchive');
    expect(identical(state(), before), isFalse);
  });
}
