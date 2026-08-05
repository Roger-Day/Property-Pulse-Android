import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import 'host_dashboard_screen.dart';
import 'my_listings_screen.dart';

/// Combined workspace for realtors, property owners, and admins who have at
/// least one managed short-stay (Airbnb) listing — mirrors iOS
/// `RealtorWorkspaceView`. Shown in the bottom nav's middle "Manage" slot
/// once [HomeShell] determines the signed-in user qualifies (see
/// `home_shell.dart`'s `_hasManagedShortStayListing` check); everyone else
/// still sees the plain "Add" tab routing straight to Create Listing.
///
/// A segmented control switches between:
///   • My Listings   — traditional sales/rental listing management
///   • Host Dashboard — short-stay bookings, calendar, and earnings
///
/// Both segments are kept alive in an [IndexedStack] (not rebuilt on
/// switch) so neither loses its scroll position or re-fetches on every
/// toggle — the same "one shared stack, root content switches in place"
/// idea as iOS's single NavigationStack with an if/else segment switch.
class RealtorWorkspaceScreen extends StatefulWidget {
  const RealtorWorkspaceScreen({super.key, required this.userId});

  final String userId;

  @override
  State<RealtorWorkspaceScreen> createState() => _RealtorWorkspaceScreenState();
}

class _RealtorWorkspaceScreenState extends State<RealtorWorkspaceScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _WorkspaceSegmentedControl(
              selectedIndex: _segment,
              onChanged: (i) => setState(() => _segment = i),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: [
              MyListingsScreen(userId: widget.userId),
              const HostDashboardScreen(),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkspaceSegmentedControl extends StatelessWidget {
  const _WorkspaceSegmentedControl({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  static const _labels = ['My Listings', 'Host Dashboard'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_labels.length, (i) {
        final selected = i == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: i < _labels.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _labels[i],
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
