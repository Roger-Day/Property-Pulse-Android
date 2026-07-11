import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/user_profile_repository.dart';
import '../../widgets/ios_style_bottom_nav_bar.dart';
import '../../widgets/offline_banner.dart';

/// Main shell — parity with iOS `MainTabView`.
/// Middle tab slot mirrors iOS `compactMiddleTab`:
///   Realtor / PropertyOwner / Developer → Add listing
///   AirbnbHost                          → Host dashboard
///   Everyone else                       → Map
///
/// Layout:
///   < 600dp  → NavigationBar (bottom)         — phones
///   ≥ 600dp  → NavigationRail (left sidebar)  — tablets / foldables / landscape
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        context.select<UserRoleProvider, bool>((p) => p.isAdmin);
    final uid = context.select<AuthProvider, String?>(
        (a) => a.isSignedIn && !a.isAnonymous ? a.user?.uid : null);

    return StreamBuilder(
      stream: uid != null
          ? context.read<UserProfileRepository>().watchUserProfile(uid)
          : const Stream.empty(),
      builder: (context, snap) {
        final role = snap.data?.role?.toLowerCase().trim() ?? '';
        final normRole = role.replaceAll(' ', '').replaceAll('_', '');

        // Mirror iOS MainTabView.compactMiddleTab exactly:
        //   Realtor / PropertyOwner / Admin → Add (Create Listing)
        //   Developer                       → Developer Dashboard
        //   AirbnbHost                      → Host Dashboard
        //   Everyone else                   → Map
        final _MiddleTab middleTab;
        if (normRole == 'developer') {
          middleTab = _MiddleTab.developer;
        } else if (normRole == 'airbnbhost') {
          middleTab = _MiddleTab.host;
        } else if (normRole == 'realtor' ||
            normRole == 'owner' ||
            normRole == 'propertyowner' ||
            isAdmin) {
          middleTab = _MiddleTab.add;
        } else {
          middleTab = _MiddleTab.map;
        }

        final items = _buildItems(middleTab, isAdmin);
        final screenWidth = MediaQuery.sizeOf(context).width;

        if (screenWidth >= 600) {
          return _TabletShell(
            navigationShell: navigationShell,
            items: items,
            middleTab: middleTab,
          );
        }

        return _PhoneShell(
          navigationShell: navigationShell,
          items: items,
          middleTab: middleTab,
        );
      },
    );
  }

  static List<IosNavBarItem> _buildItems(_MiddleTab middleTab, bool isAdmin) => [
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
        const IosNavBarItem(
          icon: Icons.chat_bubble_outline_rounded,
          selectedIcon: Icons.chat_bubble_rounded,
          label: 'Messages',
          semanticLabel: 'Messages',
        ),
        const IosNavBarItem(
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
          label: 'Profile',
          semanticLabel: 'Your profile',
        ),
        if (isAdmin)
          const IosNavBarItem(
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings_rounded,
            label: 'Admin',
            semanticLabel: 'Admin panel',
          ),
      ];
}

/// Which destination the middle tab routes to — mirrors iOS `compactMiddleTab`.
enum _MiddleTab { add, developer, host, map }

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
  });

  final StatefulNavigationShell navigationShell;
  final List<IosNavBarItem> items;
  final _MiddleTab middleTab;

  @override
  Widget build(BuildContext context) {
    final selected =
        navigationShell.currentIndex.clamp(0, items.length - 1);
    // Wide tablets (≥720dp) get an extended rail with visible labels
    final extended = MediaQuery.sizeOf(context).width >= 720;

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
              onDestinationSelected: (i) =>
                  _onTap(context, i, items.length, middleTab, navigationShell),
              destinations: items
                  .map((d) => NavigationRailDestination(
                        icon: Semantics(
                            label: d.semanticLabel, child: Icon(d.icon)),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: navigationShell),
          ],
        ),
      ),
    );
  }
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
