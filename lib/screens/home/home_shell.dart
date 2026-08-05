import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../router/navigate_admin_dashboard.dart';
import '../../services/messaging_service.dart';
import '../../widgets/ios_style_bottom_nav_bar.dart';
import '../../widgets/offline_banner.dart';

/// Main shell — parity with iOS `MainTabView`.
/// Middle tab slot mirrors iOS `compactMiddleTab`:
///   Realtor / PropertyOwner / Admin, no managed short-stay listing → Add listing
///   Realtor / PropertyOwner / Admin, ≥1 managed short-stay listing → Manage (My Listings + Host Dashboard)
///   Developer                                                      → Developer dashboard
///   AirbnbHost                                                     → Host dashboard
///   Everyone else                                                  → Map
///
/// Layout:
///   < 600dp  → NavigationBar (bottom)         — phones
///   ≥ 600dp  → NavigationRail (left sidebar)  — tablets / foldables / landscape
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Mirrors iOS MainTabView's `managedAirbnbListings` — a session-stable,
  // one-time load (not a live stream) so the middle tab doesn't flip out
  // from under the user mid-session when the global discovery feed
  // refreshes. Re-fetched only when the signed-in uid actually changes.
  String? _fetchedForUid;
  Future<bool>? _hasManagedShortStayListingFuture;

  Future<bool> _fetchHasManagedShortStayListing(String uid) async {
    final listings =
        await context.read<UserProfileRepository>().getMyListings(uid);
    return listings.any((p) => p.isShortStayHostListing);
  }

  /// Number of conversations with an unread message — mirrors iOS
  /// `MessageViewModel.totalUnreadMessagesCount`, which sums each
  /// conversation's 0/1 `unreadCount` flag rather than a running message
  /// tally. Same computation as the home-screen bell badge, reused here for
  /// the Messages tab badge and the OS app-icon badge.
  Stream<int> _unreadMessagesStream(String uid) {
    return context.read<PropertyRepository>().watchConversations(uid).map((convs) {
      return convs
          .where((t) => MessagingService.isConversationUnread(t, uid))
          .length;
    });
  }

  int? _lastSyncedBadgeCount;

  /// Best-effort — badge support varies by platform/launcher and this must
  /// never disrupt navigation if it fails or is unsupported.
  void _syncAppBadge(int count) {
    if (_lastSyncedBadgeCount == count) return;
    _lastSyncedBadgeCount = count;
    AppBadgePlus.updateBadge(count).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        context.select<UserRoleProvider, bool>((p) => p.isAdmin);
    final uid = context.select<AuthProvider, String?>(
        (a) => a.isSignedIn && !a.isAnonymous ? a.user?.uid : null);

    return StreamBuilder<int>(
      stream: uid != null ? _unreadMessagesStream(uid) : const Stream.empty(),
      builder: (context, unreadSnap) {
        final unreadMessageCount = unreadSnap.data ?? 0;
        _syncAppBadge(unreadMessageCount);
        return _buildProfileAware(context, uid, isAdmin, unreadMessageCount);
      },
    );
  }

  Widget _buildProfileAware(
    BuildContext context,
    String? uid,
    bool isAdmin,
    int unreadMessageCount,
  ) {
    return StreamBuilder(
      stream: uid != null
          ? context.read<UserProfileRepository>().watchUserProfile(uid)
          : const Stream.empty(),
      builder: (context, snap) {
        final role = snap.data?.role?.toLowerCase().trim() ?? '';
        final normRole = role.replaceAll(' ', '').replaceAll('_', '');

        final isListerRole = normRole == 'realtor' ||
            normRole == 'owner' ||
            normRole == 'propertyowner' ||
            isAdmin;

        if (isListerRole && uid != null) {
          if (_fetchedForUid != uid) {
            _fetchedForUid = uid;
            _hasManagedShortStayListingFuture =
                _fetchHasManagedShortStayListing(uid);
          }
        } else {
          _fetchedForUid = null;
          _hasManagedShortStayListingFuture = null;
        }

        return FutureBuilder<bool>(
          future: _hasManagedShortStayListingFuture,
          builder: (context, listingsSnap) {
            final hasManagedShortStayListing = listingsSnap.data ?? false;

            // Mirror iOS MainTabView.compactMiddleTab exactly.
            final _MiddleTab middleTab;
            if (normRole == 'developer') {
              middleTab = _MiddleTab.developer;
            } else if (normRole == 'airbnbhost') {
              middleTab = _MiddleTab.host;
            } else if (isListerRole) {
              middleTab = hasManagedShortStayListing
                  ? _MiddleTab.manage
                  : _MiddleTab.add;
            } else {
              middleTab = _MiddleTab.map;
            }

            final items = _buildItems(middleTab, unreadMessageCount);
            final screenWidth = MediaQuery.sizeOf(context).width;

            if (screenWidth >= 600) {
              return _TabletShell(
                navigationShell: widget.navigationShell,
                items: items,
                middleTab: middleTab,
                isAdmin: isAdmin,
              );
            }

            return _PhoneShell(
              navigationShell: widget.navigationShell,
              items: items,
              middleTab: middleTab,
            );
          },
        );
      },
    );
  }

  static List<IosNavBarItem> _buildItems(
    _MiddleTab middleTab,
    int unreadMessageCount,
  ) =>
      [
        const IosNavBarItem(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          label: 'Home',
          semanticLabel: 'Home tab',
        ),
        const IosNavBarItem(
          icon: Icons.search_outlined,
          selectedIcon: Icons.search_rounded,
          label: 'Search',
          semanticLabel: 'Search properties',
        ),
        switch (middleTab) {
          _MiddleTab.add => const IosNavBarItem(
              icon: Icons.add_circle_outline_rounded,
              selectedIcon: Icons.add_circle_rounded,
              label: 'Add',
              semanticLabel: 'Add a listing',
            ),
          _MiddleTab.manage => const IosNavBarItem(
              icon: Icons.cottage_outlined,
              selectedIcon: Icons.cottage_rounded,
              label: 'Manage',
              semanticLabel: 'Manage your listings',
            ),
          _MiddleTab.developer => const IosNavBarItem(
              icon: Icons.apartment_outlined,
              selectedIcon: Icons.apartment_rounded,
              label: 'Projects',
              semanticLabel: 'Developer dashboard',
            ),
          _MiddleTab.host => const IosNavBarItem(
              icon: Icons.house_siding_outlined,
              selectedIcon: Icons.house_siding_rounded,
              label: 'Host',
              semanticLabel: 'Host dashboard',
            ),
          _MiddleTab.map => const IosNavBarItem(
              icon: Icons.map_outlined,
              selectedIcon: Icons.map_rounded,
              label: 'Map',
              semanticLabel: 'Map view',
            ),
        },
        IosNavBarItem(
          icon: Icons.chat_bubble_outline_rounded,
          selectedIcon: Icons.chat_bubble_rounded,
          label: 'Messages',
          semanticLabel: 'Messages',
          badgeCount: unreadMessageCount,
        ),
        const IosNavBarItem(
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          label: 'Profile',
          semanticLabel: 'Your profile',
        ),
      ];
}

/// Which destination the middle tab routes to — mirrors iOS `compactMiddleTab`.
enum _MiddleTab { add, manage, developer, host, map }

// ── Phone layout ───────────────────────────────────────────────────────────────

class _PhoneShell extends StatelessWidget {
  const _PhoneShell({
    required this.navigationShell,
    required this.items,
    required this.middleTab,
  });

  final StatefulNavigationShell navigationShell;
  final List<IosNavBarItem> items;
  final _MiddleTab middleTab;

  @override
  Widget build(BuildContext context) {
    final selected =
        navigationShell.currentIndex.clamp(0, items.length - 1);
    return Scaffold(
      body: OfflineBanner(child: navigationShell),
      bottomNavigationBar: IosStyleBottomNavBar(
        items: items,
        selectedIndex: selected,
        onDestinationSelected: (i) =>
            _onTap(context, i, items.length, middleTab, navigationShell),
      ),
    );
  }
}

// ── Tablet / foldable layout ───────────────────────────────────────────────────

class _TabletShell extends StatelessWidget {
  const _TabletShell({
    required this.navigationShell,
    required this.items,
    required this.middleTab,
    required this.isAdmin,
  });

  final StatefulNavigationShell navigationShell;
  final List<IosNavBarItem> items;
  final _MiddleTab middleTab;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    // Wide tablets (≥720dp) get an extended rail with visible labels
    final extended = MediaQuery.sizeOf(context).width >= 720;

    // Rows beyond the 5 branch tabs — mirrors iOS `IPadSidebarView`, which
    // has room (unlike the phone tab bar) for Projects (always visible,
    // iOS's "Browse" section), Appointments (always visible, iOS's
    // "Account" section), Analytics (role-gated, iOS's "Manage" section —
    // any lister-adjacent role, same set already used for the middle tab
    // slot), Support (always visible), and Admin (admins only). Each is a
    // plain pushed route, not a branch, so it doesn't affect
    // [navigationShell.currentIndex]/tab highlighting.
    final isLister = middleTab != _MiddleTab.map;
    final extras = [
      const _TabletExtra(
        icon: Icons.apartment_outlined,
        selectedIcon: Icons.apartment_rounded,
        label: 'Projects',
        route: '/home/developments',
      ),
      const _TabletExtra(
        icon: Icons.calendar_today_outlined,
        selectedIcon: Icons.calendar_today_rounded,
        label: 'Appointments',
        route: '/profile/appointments',
      ),
      if (isLister)
        const _TabletExtra(
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart_rounded,
          label: 'Analytics',
          route: '/profile/analytics',
        ),
      const _TabletExtra(
        icon: Icons.help_outline_rounded,
        selectedIcon: Icons.help_rounded,
        label: 'Support',
        route: '/profile/support',
      ),
      if (isAdmin)
        const _TabletExtra(
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings_rounded,
          label: 'Admin',
          isAdminDashboard: true,
        ),
    ];
    final adminIndex =
        isAdmin ? items.length + extras.indexWhere((e) => e.isAdminDashboard) : null;

    final selected = navigationShell.currentIndex == adminShellBranchIndex &&
            adminIndex != null
        ? adminIndex
        : navigationShell.currentIndex.clamp(0, items.length - 1);

    return Scaffold(
      body: OfflineBanner(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              extended: extended,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.selected,
              onDestinationSelected: (i) async {
                if (i >= items.length) {
                  final extra = extras[i - items.length];
                  if (extra.isAdminDashboard) {
                    await navigateToAdminDashboard(context);
                  } else {
                    context.push(extra.route!);
                  }
                  return;
                }
                _onTap(context, i, items.length, middleTab, navigationShell);
              },
              destinations: [
                ...items.map((d) => NavigationRailDestination(
                      icon: Semantics(
                          label: d.semanticLabel, child: Icon(d.icon)),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    )),
                ...extras.map((e) => NavigationRailDestination(
                      icon: Semantics(
                          label: e.label, child: Icon(e.icon)),
                      selectedIcon: Icon(e.selectedIcon),
                      label: Text(e.label),
                    )),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
}

/// A tablet-rail row that pushes a plain route rather than switching
/// [StatefulNavigationShell] branches — see [_TabletShell].
class _TabletExtra {
  const _TabletExtra({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.route,
    this.isAdminDashboard = false,
  }) : assert(route != null || isAdminDashboard);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? route;
  final bool isAdminDashboard;
}

// ── Shared tap handler ─────────────────────────────────────────────────────────

void _onTap(
  BuildContext context,
  int index,
  int count,
  _MiddleTab middleTab,
  StatefulNavigationShell shell,
) {
  final clamped = index.clamp(0, count - 1);
  // Middle tab (index 2) routes per role — mirrors iOS compactMiddleTab.
  if (clamped == 2) {
    switch (middleTab) {
      case _MiddleTab.add:
        context.push('/profile/add-listing');
        return;
      case _MiddleTab.manage:
        context.push('/profile/manage-workspace');
        return;
      case _MiddleTab.developer:
        context.push('/profile/developer-dashboard');
        return;
      case _MiddleTab.host:
        context.push('/profile/host-dashboard');
        return;
      case _MiddleTab.map:
        break; // fall through to normal branch navigation (Map tab)
    }
  }
  shell.goBranch(clamped, initialLocation: clamped == shell.currentIndex);
}
