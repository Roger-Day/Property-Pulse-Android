import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../constants/app_colors.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/saved_provider.dart';
import '../../repositories/property_repository.dart';
import '../../widgets/property_card.dart';

// Ensure PropertyRepository is read in the build context:
// it's already registered in main.dart via context.read<PropertyRepository>().

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Incrementing this key forces the StreamBuilder to recreate its stream
  // subscription, giving a real pull-to-refresh on a live Firestore stream.
  int _refreshKey = 0;

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    setState(() => _refreshKey++);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  Future<void> _confirmClearAll(
      BuildContext context, SavedProvider saved) async {
    final count = saved.savedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all saved listings?'),
        content: Text(
            'This removes all $count saved listing${count == 1 ? '' : 's'}. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await saved.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final auth = context.watch<AuthProvider>();

    // Guest / not signed in
    if (!auth.isSignedIn || auth.isAnonymous) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved')),
        body: const _SignInPrompt(),
      );
    }

    final userId = auth.user!.uid;
    final repo = context.read<PropertyRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved'),
        actions: [
          // Quick count badge
          Consumer<SavedProvider>(
            builder: (_, saved, __) {
              final count = saved.savedIds.length;
              if (count == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Consumer<SavedProvider>(
            builder: (_, saved, __) {
              if (saved.savedIds.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => _confirmClearAll(context, saved),
                child: const Text('Clear all'),
              );
            },
          ),
        ],
      ),
      body: Consumer<SavedProvider>(
        builder: (context, savedProvider, _) {
          final allSavedIds = savedProvider.savedIds;
          return StreamBuilder<List<PropertyModel>>(
            key: ValueKey(_refreshKey),
            stream: repo.watchSavedListings(userId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ErrorState(message: snapshot.error.toString());
              }
              if (!snapshot.hasData) {
                return const _SavedLoadingSkeleton();
              }
              final available = snapshot.data!;
              // Unavailable = saved IDs that no longer have a matching property doc
              final availableIds = available.map((p) => p.id).toSet();
              final unavailableIds = allSavedIds
                  .where((id) => !availableIds.contains(id))
                  .toList();

              if (available.isEmpty && unavailableIds.isEmpty) {
                return const _EmptyState();
              }
              final screenWidth = MediaQuery.sizeOf(context).width;
              final tablet = screenWidth >= 700;
              final cardMaxWidth = tablet ? 760.0 : 640.0;
              // Saved-property counts can grow into the hundreds for a
              // heavy user — flatten into one list up front so the view
              // below can be lazy instead of eagerly building every card.
              final items = <Widget>[
                    // ── Available listings ─────────────────────────────
                    ...available.asMap().entries.map((e) {
                      final property = e.value;
                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: e.key < available.length - 1 ? 16 : 0),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: cardMaxWidth),
                            child: Dismissible(
                              key: ValueKey(property.id),
                              direction: DismissDirection.endToStart,
                              background: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.error
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.heart_broken_outlined,
                                            color: AppColors.error,
                                            size: 22),
                                        SizedBox(height: 4),
                                        Text('Remove',
                                            style: TextStyle(
                                              color: AppColors.error,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            )),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              onDismissed: (_) {
                                HapticFeedback.mediumImpact();
                                savedProvider.toggle(property);
                              },
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  PropertyCard(
                                    property: property,
                                    onTap: () => context.push(
                                        '/property/${property.id}'),
                                  ),
                                  // Private note chip — mirrors iOS saved property notes
                                  _SavedPropertyNoteRow(
                                    userId: userId,
                                    propertyId: property.id,
                                    repo: context.read<PropertyRepository>(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                    // ── Unavailable / deleted listings ─────────────────
                    if (unavailableIds.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      Text(
                        'No Longer Available',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'These listings were removed or expired.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      ...unavailableIds.map((id) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _UnavailableCard(
                              propertyId: id,
                              onRemove: () => savedProvider
                                  .removeById(id),
                            ),
                          )),
                    ],
                  ];
              return RefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, i) => items[i],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite_border,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Sign in to save properties',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Your saved listings sync across all your devices.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark_border,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Nothing saved yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the heart on any listing to save it here.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Browse Properties'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go('/search'),
                child: const Text('Search Properties'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text('Could not load saved properties',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedLoadingSkeleton extends StatelessWidget {
  const _SavedLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: shine,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) {
          final color = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
          final line = isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);
          return Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    color: line,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 180, height: 16, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5))),
                      const SizedBox(height: 6),
                      Container(width: 130, height: 13, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5))),
                      const SizedBox(height: 8),
                      Container(width: 110, height: 18, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Private note row on saved property ──────────────────────────────────────

class _SavedPropertyNoteRow extends StatelessWidget {
  const _SavedPropertyNoteRow({
    required this.userId,
    required this.propertyId,
    required this.repo,
  });
  final String userId;
  final String propertyId;
  final PropertyRepository repo;

  void _editNote(BuildContext context, String? current) {
    final ctrl = TextEditingController(text: current ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Private Note',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Visible only to you',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add a private note…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await repo.saveSavedPropertyNote(
                    userId: userId,
                    propertyId: propertyId,
                    note: ctrl.text.trim(),
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Save Note'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: repo.watchSavedPropertyNote(
          userId: userId, propertyId: propertyId),
      builder: (context, snap) {
        final note = snap.data;
        if (note == null || note.isEmpty) {
          // Compact "Add note" link
          return GestureDetector(
            onTap: () => _editNote(context, note),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  const Icon(Icons.note_add_outlined,
                      size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text('Add note',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary)),
                ],
              ),
            ),
          );
        }
        // Show note with edit icon
        return GestureDetector(
          onTap: () => _editNote(context, note),
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.sticky_note_2_outlined,
                    size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.edit_outlined,
                    size: 14, color: AppColors.textSecondary),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Unavailable saved property card ─────────────────────────────────────────
// Mirrors iOS UnavailableSavedPropertyItem — grayed out with remove CTA.

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({
    required this.propertyId,
    required this.onRemove,
  });
  final String propertyId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.textTertiary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.home_outlined,
                color: AppColors.textTertiary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listing no longer available',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'ID: ${propertyId.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text('Remove',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
