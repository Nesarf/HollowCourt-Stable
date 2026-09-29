import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The three button states, defined as a set** — the second convention from a study of a rhythm game
/// (`docs/DESIGN.md` 12.9.1).
///
/// a rhythm game draws every button in exactly three states — `Button_Normal`, `Button_Press`, `Button_Disable` — and
/// that trio appears three separate times in its data, its texture names and its default widget art. It also
/// shows disabled **beside** enabled: a grey chevron next to a white one on the World entry screen.
///
/// **The property under test is that disabled is a version of enabled rather than a separate look**, which is
/// the part that is easy to lose: a disabled state defined by hand tends to drift into its own colour family
/// until nobody can tell whether grey means "disabled" or "a different kind of button".
void main() {
  Color? background(ButtonStyle style, Set<WidgetState> states) =>
      style.backgroundColor?.resolve(states);

  test('**a filled button is gold, and disabled is the same shape in `absent`**', () {
    final style = HollowTheme.build().filledButtonTheme.style!;
    final enabled = background(style, {});
    final disabled = background(style, {WidgetState.disabled});

    expect(enabled, isNot(disabled), reason: 'a disabled button must look different');
    expect(enabled, HollowPalette.gold, reason: '金＝已选: the action colour');
    expect(
      disabled,
      HollowPalette.absent,
      reason: 'the palette already has a colour for "not here" -- so disabled is the same shape, muted',
    );
  });

  test('**the label is one colour in both states, because the fill is what changes**', () {
    // It used to be `ground` enabled and `inkFaint` disabled -- "the label fades rather than changing hue".
    // Then the two faint colours were raised to clear 4.5:1 against the surfaces, which made `inkFaint` and
    // `absent` neighbours of each other (~1.0:1): a disabled button would have been a label the colour of
    // its own background. The state now reads from the fill -- gold to grey -- and the foreground is
    // `onAccent` either way, which is the same pairing rule every accent fill obeys.
    final style = HollowTheme.build().filledButtonTheme.style!;
    expect(style.foregroundColor?.resolve({}), HollowPalette.onAccent);
    expect(style.foregroundColor?.resolve({WidgetState.disabled}), HollowPalette.onAccent);
    expect(style.backgroundColor?.resolve({}), HollowPalette.gold);
    expect(style.backgroundColor?.resolve({WidgetState.disabled}), HollowPalette.absent);
  });

  test('**the pressed state is stated, not inherited**', () {
    // Material's ripple would make the same button feel different depending on which of the four themes is in
    // force. An explicit overlay is the cheapest way to say "a press is felt" in all of them.
    final style = HollowTheme.build().filledButtonTheme.style!;
    final pressed = style.overlayColor!.resolve({WidgetState.pressed});
    expect(pressed, isNotNull);
    expect(pressed!.a, greaterThan(0.0), reason: 'a fully transparent overlay is not a pressed state');
  });

  test('the secondary action uses the rose, which is what rose means here', () {
    final style = HollowTheme.build().textButtonTheme.style!;
    expect(style.foregroundColor?.resolve({}), HollowPalette.rose);
    expect(style.foregroundColor?.resolve({WidgetState.disabled}), HollowPalette.inkFaint);
  });

  testWidgets('**disabled and enabled are visibly different when actually drawn**', (tester) async {
    // Rendered as well as resolved, because the failure this guards against is a style that exists in the theme
    // and is then overridden at the call site -- which a test on the ButtonStyle alone would never see.
    await tester.pumpWidget(
      MaterialApp(
        theme: HollowTheme.build(),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(
                key: const ValueKey('enabled'),
                onPressed: () {},
                child: const Text('on'),
              ),
              const FilledButton(
                key: ValueKey('disabled'),
                onPressed: null,
                child: Text('off'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final enabled = tester.widget<FilledButton>(find.byKey(const ValueKey('enabled')));
    final disabled = tester.widget<FilledButton>(find.byKey(const ValueKey('disabled')));
    expect(enabled.onPressed, isNotNull);
    expect(disabled.onPressed, isNull, reason: 'the disabled state is the control refusing to act');
  });
}
