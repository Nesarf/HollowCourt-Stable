import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/declared.dart';
import '../adapters/registry.dart';

/// Which adapters are switched on, as state a screen can change and rebuild from.
///
/// **Why this is a notifier when `adapters_section.dart` said it would not be.** That comment reasoned that
/// `AdapterRegistry` is itself the mutable state, and wrapping it would mean two objects holding the same
/// truth. That reasoning was right about the truth and wrong about the screen: a switch whose callback cannot
/// make anything rebuild is a switch that moves and does nothing, which is the exact failure the same file
/// warns about. The registry is still the only thing that knows what is enabled; the notifier holds *which
/// instance of it* is current, and hands out a copy on every change.
final adapterRegistryProvider = NotifierProvider<AdapterRegistryNotifier, AdapterRegistry>(
  AdapterRegistryNotifier.new,
);

class AdapterRegistryNotifier extends Notifier<AdapterRegistry> {
  @override
  AdapterRegistry build() => AdapterRegistry(declaredAdapters);

  /// Opens or shuts one door. Enabling an unavailable adapter still throws -- the screen asks
  /// `isAvailable` before offering the control, so reaching that throw is a bug rather than a state.
  void setEnabled(AdapterKind kind, bool on) {
    final next = state.copy();
    if (on) {
      next.enable(kind);
    } else {
      next.disable(kind);
    }
    state = next;
  }
}
