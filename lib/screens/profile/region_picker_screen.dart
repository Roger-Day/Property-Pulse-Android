import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_colors.dart';
import '../../models/app_region.dart';
import '../../repositories/user_profile_repository.dart';
import 'profile_subscreen_widgets.dart';

/// Mirrors iOS `RegionPickerView`: searchable list of `AppRegion.supportedRegions`,
/// persists `SharedPreferences` + Firestore `users.region`.
class RegionPickerScreen extends StatefulWidget {
  const RegionPickerScreen({super.key, required this.userId});

  final String userId;

  @override
  State<RegionPickerScreen> createState() => _RegionPickerScreenState();
}

class _RegionPickerScreenState extends State<RegionPickerScreen> {
  final TextEditingController _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AppRegion> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return AppRegion.supportedRegions;
    return AppRegion.supportedRegions.where((r) {
      return r.displayName.toLowerCase().contains(q) ||
          r.currencyCode.toLowerCase().contains(q) ||
          r.id.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _select(AppRegion region) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<UserProfileRepository>().setUserRegion(
            userId: widget.userId,
            regionId: region.id,
          );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppRegionPrefsKeys.selectedRegionId, region.id);
      await prefs.setBool(AppRegionPrefsKeys.hasCompletedRegionSelection, true);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save region: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ProfileGroupedScaffold(
      title: 'Region',
      actions: [
        TextButton(
          onPressed: _busy ? null : () => context.pop(false),
          child: const Text('Done'),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search regions…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_busy)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: AbsorbPointer(
              absorbing: _busy,
              child: ListView.separated(
                padding: ProfileLayout.pagePadding.copyWith(top: 0),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
                itemBuilder: (context, i) {
                  final r = _filtered[i];
                  final emoji = AppRegion.flagEmojiForId(r.id);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Text(emoji, style: const TextStyle(fontSize: 28)),
                    title: Text(
                      r.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${r.currencyCode} • ${r.sampleListingPriceFormatted}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textTertiary,
                    ),
                    onTap: () => _select(r),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
