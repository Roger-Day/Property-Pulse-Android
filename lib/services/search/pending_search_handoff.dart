import 'package:flutter/foundation.dart';

import '../../repositories/property_repository.dart';

/// Pulse Finder (Phase 3.1) — carries a [PropertyFilter] from Pulse Finder's
/// "View All Matching Properties" action into the existing Explore/Search
/// screen.
///
/// `ExploreScreen` lives inside a `StatefulShellRoute.indexedStack` branch
/// (see `app_router.dart`), so its widget instance is kept alive across tab
/// switches — a plain `context.go('/search', extra: filter)` cannot rely on
/// `initState` re-running to pick up a new filter if the user has already
/// visited that tab once this session. This singleton sidesteps that: it
/// works identically whether `ExploreScreen` is being built for the first
/// time or is already alive and merely being switched back into view.
///
/// Registered app-wide in `main.dart` (a route-scoped provider wouldn't be
/// visible to both the Pulse Finder route and the Explore tab at once).
class PendingSearchHandoff extends ChangeNotifier {
  PropertyFilter? _pending;

  void set(PropertyFilter filter) {
    _pending = filter;
    notifyListeners();
  }

  /// Returns the pending filter (if any) and clears it — a second call
  /// without an intervening [set] returns null, so the handoff never
  /// re-applies a stale filter on an unrelated later visit to Explore.
  PropertyFilter? consume() {
    final filter = _pending;
    _pending = null;
    return filter;
  }
}
