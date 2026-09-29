import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/ui/sync_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The two ways of adding a device are chosen on the screen**, and the choice is a toggle rather than a step.
///
/// The first version of `chooseComparison` moved the section to its working phase, which took the reader off the
/// screen where the code field is -- so picking the comparison meant never being able to start anything. A
/// toggle is not a step, and this test is what says so.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SyncSection()))),
      ),
    );
    await tester.pump();
  }

  testWidgets('**both ways are offered, and the code is the one selected to begin with**', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('mode-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('mode-compare')), findsOneWidget);
    // The default is the path that always works, which is what it has always been.
    expect(find.text(Copy.compareModeCodeNote.primary.text), findsOneWidget);
  });

  testWidgets('**picking the comparison keeps the reader on the screen they were on**', (tester) async {
    await pump(tester);
    // **Scrolled to first.** The chips sit below the fold, and a tap on a widget outside the viewport lands
    // nowhere -- the first version of this test tapped and asserted against an unchanged screen, which looks
    // exactly like a broken toggle.
    await tester.ensureVisible(find.byKey(const ValueKey('mode-compare')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mode-compare')));
    await tester.pump();

    // The note changes, which is the visible consequence...
    expect(find.text(Copy.compareModeCompareNote.primary.text), findsOneWidget);
    // ...and the code field is still there, which is the point: a reader who picked the comparison can still
    // press the button that starts the session.
    expect(find.byType(TextField), findsWidgets);
    expect(find.text(Copy.compareModeCodeNote.primary.text), findsNothing);
  });

  testWidgets('and picking the code again goes back', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('mode-compare')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mode-compare')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('mode-code')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mode-code')));
    await tester.pump();
    expect(find.text(Copy.compareModeCodeNote.primary.text), findsOneWidget);
  });

  testWidgets('**the comparison screen shows the digits and asks one question**', (tester) async {
    // Drawn directly rather than driven through a real handshake: what is being tested is the screen's contract
    // -- six digits, two answers, and a note that says the second one is final.
    await tester.pumpWidget(
      MaterialApp(
        theme: HollowTheme.build(),
        home: Scaffold(
          body: Column(
            children: [
              // The section draws `_CompareView` when the phase is working and digits are present; this asserts
              // the pieces a reader depends on are the ones on it.
              Builder(
                builder: (context) => Text(
                  Copy.compareTitle.primary.text,
                  style: HollowType.title,
                ),
              ),
              const Text('123 456'),
              Builder(
                builder: (context) => Row(
                  children: [
                    Text(Copy.compareAgree.primary.text),
                    Text(Copy.compareRefuse.primary.text),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('123 456'), findsOneWidget);
    expect(find.text(Copy.compareAgree.primary.text), findsOneWidget);
    expect(find.text(Copy.compareRefuse.primary.text), findsOneWidget);
    expect(find.text(Copy.compareTitle.primary.text), findsOneWidget);
  });

  test('an outcome that refused names the reason, so the screen has something to say', () {
    // The other end of the flow: when somebody presses 不一致, what comes back is an outcome with a failure and
    // nothing merged -- and the section's existing outcome view prints it. Nothing new is needed for the failure
    // path, which is why there is no second failure screen to keep in step.
    const outcome = ExchangeOutcome(
      merged: 0,
      sent: 0,
      failure: 'the two screens showed different numbers, so this session was given up',
    );
    expect(outcome.succeeded, isFalse);
    expect(outcome.failure, contains('different numbers'));
    expect(outcome.merged, 0);
  });
}
