import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/listing_permission_service.dart';
import '../host/airbnb_listing_wizard_screen.dart';
import 'add_property_screen.dart';

/// Mirrors iOS `CreateListingEntryView` — capability-gated entry point for all
/// listing creation flows. Shows the category picker for multi-role users.
///
/// Routes:
///   Realtor / Owner  → Property Listing + Short-Stay Listing
///   AirbnbHost       → Short-Stay (primary) + Property Listing
///   Developer        → New Project only (direct)
///   Seeker           → Blocked view
class CreateListingEntryScreen extends StatefulWidget {
  const CreateListingEntryScreen({super.key, required this.userId});

  final String userId;

  @override
  State<CreateListingEntryScreen> createState() =>
      _CreateListingEntryScreenState();
}

class _CreateListingEntryScreenState
    extends State<CreateListingEntryScreen> {
  String _role = 'seeker';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final doc = await context
          .read<UserProfileRepository>()
          .watchUserProfile(widget.userId)
          .first;
      if (!mounted) return;
      setState(() {
        _role = doc?.normalizedRole ?? 'seeker';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleCategoryTap(ListingCategory category) {
    final result = ListingPermissionService.check(_role, category);

    if (result is PermissionAllowed) {
      _navigateTo(category);
    } else if (result is PermissionSoftRestricted) {
      _showWarningModal(
        category: category,
        title: result.warningTitle,
        message: result.warningMessage,
      );
    } else if (result is PermissionBlocked) {
      _showBlockedAlert(result.reason);
    }
  }

  void _navigateTo(ListingCategory category) {
    switch (category) {
      case ListingCategory.general:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AddPropertyScreen(userId: widget.userId),
        ));
        break;
      case ListingCategory.airbnb:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AirbnbListingWizardScreen(),
        ));
        break;
      case ListingCategory.development:
        context.push('/profile/my-developments');
        break;
    }
  }

  void _showBlockedAlert(String reason) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listing Not Available'),
        content: Text(reason),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showWarningModal({
    required ListingCategory category,
    required String title,
    required String message,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ListingTypeWarningSheet(
        category: category,
        warningTitle: title,
        warningMessage: message,
        onContinue: () {
          Navigator.of(context).pop();
          _navigateTo(category);
        },
        onCancel: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final available =
        ListingPermissionService.availableCategories(_role);
    final primary = ListingPermissionService.defaultCategory(_role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Listing'),
        centerTitle: true,
      ),
      body: available.isEmpty
          ? _BlockedView(role: _role)
          : available.length == 1
              ? _SingleCategoryNavigator(
                  category: available.first,
                  onNavigate: _navigateTo,
                )
              : _CategoryPicker(
                  categories: available,
                  primaryCategory: primary,
                  role: _role,
                  onTap: _handleCategoryTap,
                ),
    );
  }
}

// ─── Blocked view ─────────────────────────────────────────────────────────────

class _BlockedView extends StatelessWidget {
  const _BlockedView({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 20),
            const Text(
              'Listing Creation Unavailable',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Property Seekers cannot create listings. Switch to a listing role in your profile to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go to Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Single-category auto-navigator ──────────────────────────────────────────

class _SingleCategoryNavigator extends StatefulWidget {
  const _SingleCategoryNavigator({
    required this.category,
    required this.onNavigate,
  });
  final ListingCategory category;
  final void Function(ListingCategory) onNavigate;

  @override
  State<_SingleCategoryNavigator> createState() =>
      _SingleCategoryNavigatorState();
}

class _SingleCategoryNavigatorState
    extends State<_SingleCategoryNavigator> {
  @override
  void initState() {
    super.initState();
    // Navigate immediately on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onNavigate(widget.category);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

// ─── Category picker ──────────────────────────────────────────────────────────

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.primaryCategory,
    required this.role,
    required this.onTap,
  });
  final List<ListingCategory> categories;
  final ListingCategory primaryCategory;
  final String role;
  final void Function(ListingCategory) onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What would you like to list?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Select the type of listing you want to create.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ...categories.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CategoryCard(
                category: cat,
                result: ListingPermissionService.check(role, cat),
                isPrimary: cat == primaryCategory,
                onTap: () => onTap(cat),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.result,
    required this.isPrimary,
    required this.onTap,
  });
  final ListingCategory category;
  final PermissionResult result;
  final bool isPrimary;
  final VoidCallback onTap;

  Color get _iconColor {
    switch (category) {
      case ListingCategory.general:
        return AppColors.primary;
      case ListingCategory.development:
        return Colors.indigo;
      case ListingCategory.airbnb:
        return const Color(0xFFFF5A5F);
    }
  }

  IconData get _icon {
    switch (category) {
      case ListingCategory.general:
        return Icons.home;
      case ListingCategory.development:
        return Icons.apartment;
      case ListingCategory.airbnb:
        return Icons.cottage;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPrimary
                ? AppColors.primary.withOpacity(0.4)
                : AppColors.border,
            width: isPrimary ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _iconColor.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(_icon, color: _iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        category.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      if (isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Primary',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      if (result is PermissionSoftRestricted) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.warning_amber,
                            color: Colors.orange, size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    category.subtitle,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─── Soft-restriction warning sheet ──────────────────────────────────────────

class _ListingTypeWarningSheet extends StatelessWidget {
  const _ListingTypeWarningSheet({
    required this.category,
    required this.warningTitle,
    required this.warningMessage,
    required this.onContinue,
    required this.onCancel,
  });
  final ListingCategory category;
  final String warningTitle;
  final String warningMessage;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final limited =
        ListingPermissionService.limitedFeatures(category);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Limited Access'),
        leading: CloseButton(onPressed: onCancel),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          children: [
            const Icon(Icons.warning_amber,
                size: 52, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              warningTitle,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              warningMessage,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            // Limited features box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.orange.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What may be limited',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 10),
                  ...limited.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.remove_circle,
                              color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(item,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors
                                        .textSecondary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                child: const Text('Continue Anyway'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onCancel,
              child: Text('Go Back',
                  style: TextStyle(
                      color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}
