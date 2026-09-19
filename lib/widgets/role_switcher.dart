import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/user_profile_doc.dart';
import '../services/role_switch_service.dart';

/// Mirrors iOS `RoleChip` grid + cooldown banner in `UserProfileEditView`.
/// Presents all 5 selectable roles, locks current + cooldown/previous, shows
/// confirmation dialog before switching, calls [onRoleChanged] on success.
class RoleSwitcher extends StatefulWidget {
  const RoleSwitcher({
    super.key,
    required this.doc,
    required this.userId,
    required this.onRoleChanged,
  });

  final UserProfileDoc doc;
  final String userId;
  final void Function(String newRole) onRoleChanged;

  @override
  State<RoleSwitcher> createState() => _RoleSwitcherState();
}

class _RoleSwitcherState extends State<RoleSwitcher> {
  bool _switching = false;

  String get _currentRole => widget.doc.normalizedRole;
  String get _previousRole =>
      widget.doc.previousRole?.toLowerCase().trim() ?? '';
  int get _daysLeft =>
      RoleSwitchService.daysRemainingInCooldown(
          widget.doc.lastRoleSwitchDate);
  bool get _cooldownActive => _daysLeft > 0;

  Future<void> _onTapRole(String role) async {
    if (role == _currentRole) return;

    // Previous-role block
    if (_previousRole.isNotEmpty &&
        role.toLowerCase() == _previousRole) {
      _showAlert(
        title: 'Role Unavailable',
        message:
            'You cannot return to the ${RoleSwitchService.displayName(role)} role after switching away.',
      );
      return;
    }

    // Cooldown block
    if (_cooldownActive) {
      final expiry = RoleSwitchService.cooldownExpiryString(
          widget.doc.lastRoleSwitchDate);
      _showAlert(
        title: 'Switch Not Available',
        message:
            'You can switch roles again in $_daysLeft day${_daysLeft == 1 ? '' : 's'} (after $expiry).',
      );
      return;
    }

    // Confirmation dialog
    final confirmed = await _showConfirmDialog(role);
    if (confirmed != true || !mounted) return;

    setState(() => _switching = true);
    final error = await RoleSwitchService.switchRole(
      userId: widget.userId,
      currentRole: _currentRole,
      previousRole: _previousRole,
      newRole: role,
      lastRoleSwitchDate: widget.doc.lastRoleSwitchDate,
      roleSwitchCount: widget.doc.roleSwitchCount,
    );
    if (!mounted) return;
    setState(() => _switching = false);

    if (error != null) {
      _showAlert(title: 'Role Switch Failed', message: error);
    } else {
      // Callers (EditProfileScreen) compare this against display-string
      // role labels (e.g. ProfileRoleLabels.owner == "Property Owner"),
      // matching what RoleSwitchService.switchRole just wrote to Firestore
      // — passing the raw short code ("owner") desynced the two, hiding
      // the role-specific section and making the next Save silently fail
      // Firestore's role-string allowlist.
      widget.onRoleChanged(RoleSwitchService.displayName(role));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Role changed to ${RoleSwitchService.displayName(role)}'),
        ),
      );
    }
  }

  void _showAlert({required String title, required String message}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String newRole) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Role?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Switch from ${RoleSwitchService.displayName(_currentRole)} to ${RoleSwitchService.displayName(newRole)}?'),
            const SizedBox(height: 8),
            Text(
              'You can switch roles again in ${RoleSwitchService.cooldownDays} days after this change.',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Role',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            if (_cooldownActive)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 11, color: Colors.orange),
                    const SizedBox(width: 3),
                    Text(
                      '${_daysLeft}d cooldown',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_switching)
          const Center(child: CircularProgressIndicator())
        else
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 3.2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: RoleSwitchService.selectableRoles.map((role) {
              // `_currentRole` keeps its camelCase form ('airbnbHost'), so
              // lower-casing only the chip's side made that chip never match.
              final isCurrent =
                  role.toLowerCase() == _currentRole.toLowerCase();
              final isPrev = _previousRole.isNotEmpty &&
                  role.toLowerCase() == _previousRole &&
                  !isCurrent;
              final isLocked = _cooldownActive && !isCurrent;

              return _RoleChip(
                role: role,
                isCurrent: isCurrent,
                isPreviousRole: isPrev,
                isLocked: isLocked,
                onTap: () => _onTapRole(role),
              );
            }).toList(),
          ),
        if (_cooldownActive) ...[
          const SizedBox(height: 6),
          Text(
            'Role switching locked until ${RoleSwitchService.cooldownExpiryString(widget.doc.lastRoleSwitchDate)}.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.role,
    required this.isCurrent,
    required this.isPreviousRole,
    required this.isLocked,
    required this.onTap,
  });

  final String role;
  final bool isCurrent;
  final bool isPreviousRole;
  final bool isLocked;
  final VoidCallback onTap;

  IconData get _icon {
    switch (role) {
      case 'seeker':
        return Icons.search;
      case 'owner':
        return Icons.home;
      case 'realtor':
        return Icons.business_center;
      case 'developer':
        return Icons.apartment;
      case 'airbnbHost':
        return Icons.cottage;
      default:
        return Icons.person;
    }
  }

  Color get _color {
    if (isPreviousRole) return AppColors.textSecondary;
    if (isLocked) return AppColors.textTertiary;
    switch (role) {
      case 'seeker':
        return Colors.blue;
      case 'owner':
        return Colors.teal;
      case 'realtor':
        return Colors.purple;
      case 'developer':
        return Colors.indigo;
      case 'airbnbHost':
        return const Color(0xFFFF5A5F);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isCurrent
              ? _color.withOpacity(0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isCurrent
                ? _color
                : isPreviousRole
                    ? AppColors.border.withOpacity(0.4)
                    : AppColors.border,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPreviousRole)
              const Icon(Icons.block, size: 14,
                  color: AppColors.textSecondary)
            else if (isLocked && !isCurrent)
              const Icon(Icons.lock, size: 14,
                  color: AppColors.textTertiary)
            else
              Icon(_icon, size: 14, color: _color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                RoleSwitchService.displayName(role),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent
                      ? FontWeight.bold
                      : FontWeight.w500,
                  color: isCurrent
                      ? _color
                      : isPreviousRole || isLocked
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCurrent)
              Icon(Icons.check_circle, size: 14, color: _color),
          ],
        ),
      ),
    );
  }
}
