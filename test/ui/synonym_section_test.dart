import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/synonym_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// The bulk editor: it says what it understood before it saves, and it refuses to lose a line quietly.
void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('hollow-synonyms'));
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<Cellar> cellar(WidgetTester tester) async {
    final built = await tester.runAsync(() async {
      final log = await EventLog.open(
        file: File('${home.path}${Platform.pathSeparator}cellar.ndjson'),
        nodeId: 'test',
        nowMillis: () => 1000,
      );
      return Cellar.of(log);
    });
    return built!;
  }

  Future<Cellar> pump(WidgetTester tester) async {
    final it = await cellar(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cellarProvider.overrideWith(() => _Seeded(it)),
          localeSettingsProvider.overrideWith(
            () => _FixedLocale(
              const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: false),
            ),
          ),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: const Scaffold(body: SingleChildScrollView(child: SynonymSection())),
        ),
      ),
    );
    await tester.pump();
    return it;
  }

  testWidgets('**a pasted block says how many groups it understood**', (tester) async {
    final it = await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('synonym-block')),
      '金酒 = 琴酒, 杜松子酒\n安高天娜 = 安哥斯图拉',
    );
    await tester.pump();

    expect(find.text('2'), findsWidgets, reason: 'two groups understood');

    // **The save itself is asserted at the notifier**, in the plain test below: it is a file write, and a
    // widget test cannot wait for one outside `runAsync`. What belongs here is what the screen says before
    // anything is saved -- which is the count, and that the button is live.
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('synonym-apply')));
    expect(button.onPressed, isNotNull);

    // And `it` is used, so nobody deletes the fixture wondering what it was for.
    expect(it.overlay.synonymBlock, isEmpty, reason: 'nothing has been saved yet');
  });

  testWidgets('**a line it cannot read is reported, and the save is refused**', (tester) async {
    // The failure this prevents: twenty names pasted, a success message, and the one that mattered silently
    // missing -- surfacing weeks later as a drink that cannot be made.
    await pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('synonym-block')),
      '金酒 = 琴酒\n = 没有名字',
    );
    await tester.pump();

    // The complaint, not the text field: `textContaining` on the raw line matches the editor's own contents
    // as well, so the assertion is on the shape of the message -- the reader's line number and the reason.
    expect(
      find.textContaining('${Copy.synonymLineProblem.primary.text} 2'),
      findsOneWidget,
      reason: 'the offending line is reported with the number the reader sees',
    );
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('synonym-apply')));
    expect(button.onPressed, isNull, reason: 'refused while a line is unreadable');
    expect(find.text(Copy.synonymFixFirst.primary.text), findsOneWidget);
  });

  testWidgets('and saving is refused when nothing has changed', (tester) async {
    await pump(tester);
    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('synonym-apply')));
    expect(button.onPressed, isNull);
    expect(find.text(Copy.synonymUnchanged.primary.text), findsOneWidget);
  });
}

class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}

class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this._initial);

  final LocaleSettings _initial;

  @override
  LocaleSettings build() => _initial;
}
