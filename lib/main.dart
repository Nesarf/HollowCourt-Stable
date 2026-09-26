import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app.dart';

/// Hollow Court -- 空庭
///
/// **The formal full name is deliberately not written here or anywhere a person
/// can see it.** Section 0 makes 空庭 / Hollow Court the public copy and the full
/// name an internal identifier and an easter egg, and the first version of the
/// interface got that wrong: the title on screen was the internal name, and a
/// test asserted the internal name had to be there. Both were wrong the same way,
/// so neither caught the other. `test/ui/theme_and_swatch_test.dart` now asserts
/// the direction that cannot be got wrong twice.
///
/// The entry point is deliberately three lines. Everything the application
/// actually is lives below: `lib/domain/` holds the arithmetic and imports no
/// Flutter at all, `lib/data/` holds the seed and the event log, and `lib/ui/`
/// is the only layer that knows what a screen is.
///
/// A `ProviderScope` is the whole of the wiring. The drink library and the event
/// log are both asynchronous -- one is an asset, the other a file -- and every
/// screen renders the state it is actually in rather than a spinner over a lie.
void main() {
  runApp(const ProviderScope(child: HollowCourtApp()));
}
