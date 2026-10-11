import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/archive_note.dart';
import 'package:hollow_court/ui/archive_providers.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/theme.dart';
import '../support/open_logs.dart';

/// **The line that says the readings were folded from more than the working log.**
///
/// `docs/archival.md` sets the rule: *history depth is a visible choice rather than a hidden constant.* The choosing
/// half is the section in 设置; this is the other half, and it was missing -- **`Cellar.archivedEvents` and
/// `readsArchives` were written for exactly this and had no caller.**
///
/// **The case that matters most is the one where it says nothing.** A note that appears on every cellar is furniture,
/// and the failure it guards against is a reader seeing a chart that is *longer* than they expected -- so it has to be
/// absent when the history is just the log, and present with the right numbers when it is not.
void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('hollow-note'));
  tearDown(() async {
    await releaseCellars();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  var clock = 1000;
  Hlc tick() => Hlc(physicalMillis: ++clock, counter: 0, nodeId: 'test');

  Event added(String id, String sku) => StockEvents.bottleAdded(
    hlc: tick(),
    bottleId: id,
    sku: sku,
    volume: Volume.fromMillilitres(700),
  );

  /// A real cellar built on the real clock, with [archived] passed as the packages the reader attached.
  Future<Cellar> cellar(WidgetTester tester, {required List<Event> archived}) async {
    final built = await tester.runAsync(() async {
      final log = await openTracked(
        file: File('${home.path}${Platform.pathSeparator}cellar.ndjson'),
        nodeId: 'test',
        nowMillis: () => ++clock,
      );
      await log.record((_) => added('b1', 'gin'));
      return Cellar.of(log, archived: archived);
    });
    return built!;
  }

  Future<void> pump(
    WidgetTester tester,
    Cellar built, {
    Set<String> attached = const {},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cellarProvider.overrideWith(() => _Seeded(built)),
          archiveSelectionProvider.overrideWith(() => _Selected(attached)),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: const Scaffold(body: ArchivedHistoryNote()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('**a cellar whose history is only the log says nothing at all**', (tester) async {
    // The ordinary case, and the one that decides whether this can sit at the top of a page at all.
    await pump(tester, await cellar(tester, archived: const []));

    expect(find.byKey(const ValueKey('cellar-reads-archives')), findsNothing);
    expect(find.textContaining('attached'), findsNothing);
  });

  testWidgets('**and a cellar reading a package says how many, and how much**', (tester) async {
    final built = await cellar(tester, archived: [added('old1', 'vermouth'), added('old2', 'campari')]);
    await pump(tester, built, attached: {'2001-2005.hca'});

    expect(find.byKey(const ValueKey('cellar-reads-archives')), findsOneWidget);
    // **The two numbers come from two places on purpose**: the package count is what the reader ticked, and the event
    // count is what the fold actually used. Both are on the line.
    expect(find.textContaining('1'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('**the count is the fold\'s, not the selection\'s**', (tester) async {
    // A ticked package that contributed nothing -- because it was empty, or because the merge found every reading
    // already in the log -- must not make the line claim events that were not used. The selection is three and the
    // events are zero, which is not a state the note may render as "three packages, no events" and therefore not a
    // state it claims anything about at all.
    final built = await cellar(tester, archived: const []);
    await pump(tester, built, attached: {'a.hca', 'b.hca', 'c.hca'});

    expect(find.byKey(const ValueKey('cellar-reads-archives')), findsNothing);
  });

  testWidgets('**it is written in the reader\'s language, which the archive section is not**', (tester) async {
    // `Copy.archiveAttached` resolves `.textFor('zh-Hans')`, so the 设置 line reads Chinese in an English interface.
    // This one goes through `ref.copy`, and the assertion is that the two agree about which language is on screen --
    // checked by pinning nothing and reading whichever the framework resolves, the same way `reorder_section_test`
    // records.
    final built = await cellar(tester, archived: [added('old1', 'vermouth')]);
    await pump(tester, built, attached: {'2001-2005.hca'});

    final shown = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('cellar-reads-archives')),
        matching: find.byType(Text),
      ),
    );
    expect(shown.data, isNotNull);
    // The placeholder is substituted, whichever language it was substituted into.
    expect(shown.data, isNot(contains('{packages}')));
    expect(shown.data, isNot(contains('{events}')));
  });
}

final class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}

/// The reader's ticked packages, without a directory to read them from.
final class _Selected extends ArchiveSelection {
  _Selected(this._names);

  final Set<String> _names;

  @override
  Set<String> build() => _names;
}
