import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../repositories/pulse_finder_session_repository.dart';
import '../../../services/analytics_service.dart';
import '../../../widgets/pp_widgets.dart';
import '../models/pulse_finder_session.dart';

/// Pulse Finder (Phase 4) — the consultation history screen.
///
/// These are *consultations*, not chat logs: each row reads like a saved
/// engagement with an advisor ("Montego Bay Anniversary Trip"), showing the
/// category, when it was last worked on, what was understood, and how many
/// recommendations came out of it. Tapping resumes it exactly where it was
/// left (see `PulseFinderConversationController.resume`).
///
/// Retention follows the Recent + Saved model: the list shows recent
/// consultations, and pinned/saved ones are kept and always sorted first.
class PulseFinderHistoryScreen extends StatefulWidget {
  const PulseFinderHistoryScreen({super.key});

  @override
  State<PulseFinderHistoryScreen> createState() => _PulseFinderHistoryScreenState();
}

class _PulseFinderHistoryScreenState extends State<PulseFinderHistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Client-side search over the fields the spec calls out — title, summary,
  /// category and location. Runs on the already-streamed list, so typing
  /// never costs an extra read.
  List<PulseFinderSession> _filter(List<PulseFinderSession> sessions) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return sessions;
    return sessions.where((s) {
      final haystack = [
        s.title,
        s.profileSummary,
        s.messagePreview,
        s.intent?.displayLabel ?? '',
        s.filter.city,
        s.filter.state,
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthProvider>().user?.uid;
    final repo = context.read<PulseFinderSessionRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your consultations'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'New search',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => context.pushReplacement('/pulse-finder'),
          ),
        ],
      ),
      body: SafeArea(
        child: uid == null
            ? const PPEmptyState(
                icon: Icons.lock_outline,
                title: 'Sign in to see your consultations',
                message: 'Your Pulse Finder consultations are saved to your account.',
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search consultations…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<PulseFinderSession>>(
                      stream: repo.watchSessions(uid),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const PPLoadingView(message: 'Loading your consultations…');
                        }
                        final all = snapshot.data ?? const <PulseFinderSession>[];
                        final sessions = _filter(all);

                        if (all.isEmpty) {
                          return const PPEmptyState(
                            icon: Icons.chat_bubble_outline,
                            title: 'No consultations yet',
                            message:
                                'Start a search with Pulse Finder and it will be saved here so you can pick up where you left off.',
                          );
                        }
                        if (sessions.isEmpty) {
                          return const PPEmptyState(
                            icon: Icons.search_off,
                            title: 'No matches',
                            message: 'No consultation matches that search.',
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: sessions.length,
                          itemBuilder: (context, i) => _ConsultationCard(
                            session: sessions[i],
                            onResume: () => _resume(sessions[i]),
                            onRename: () => _rename(repo, uid, sessions[i]),
                            onTogglePin: () => _togglePin(repo, uid, sessions[i]),
                            onArchive: () => _archive(repo, uid, sessions[i]),
                            onDuplicate: () => _duplicate(repo, uid, sessions[i]),
                            onDelete: () => _delete(repo, uid, sessions[i]),
                            confirmDelete: () => _confirmDelete(sessions[i]),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _resume(PulseFinderSession session) {
    // Replaces history with a fresh Pulse Finder route that resumes this
    // consultation, so the back stack stays one entry deep.
    context.pushReplacement('/pulse-finder?sessionId=${session.id}');
  }

  Future<void> _rename(
    PulseFinderSessionRepository repo,
    String uid,
    PulseFinderSession session,
  ) async {
    final controller = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename consultation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = newTitle?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await repo.renameSession(uid, session.id, trimmed);
    AnalyticsService.logEvent('pulse_finder_conversation_renamed');
  }

  Future<void> _togglePin(
    PulseFinderSessionRepository repo,
    String uid,
    PulseFinderSession session,
  ) async {
    await repo.setPinned(uid, session.id, !session.pinned);
    AnalyticsService.logEvent(
      session.pinned ? 'pulse_finder_conversation_unpinned' : 'pulse_finder_conversation_pinned',
    );
  }

  Future<void> _archive(
    PulseFinderSessionRepository repo,
    String uid,
    PulseFinderSession session,
  ) async {
    await repo.archiveSession(uid, session.id);
    AnalyticsService.logEvent('pulse_finder_conversation_archived');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Consultation archived')),
    );
  }

  Future<void> _duplicate(
    PulseFinderSessionRepository repo,
    String uid,
    PulseFinderSession session,
  ) async {
    await repo.duplicateSession(uid, session);
    AnalyticsService.logEvent('pulse_finder_conversation_duplicated');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Started a copy of this search')),
    );
  }

  Future<bool> _confirmDelete(PulseFinderSession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete consultation?'),
        content: Text('"${session.title}" and its messages will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _delete(
    PulseFinderSessionRepository repo,
    String uid,
    PulseFinderSession session,
  ) async {
    await repo.deleteSession(uid, session.id);
    AnalyticsService.logEvent('pulse_finder_conversation_deleted');
  }
}

/// One consultation row. Swipe left to delete (confirmed), swipe right to
/// archive; rename / duplicate / pin live in the overflow menu — all four
/// actions the spec asks for, without adding a swipe-library dependency.
class _ConsultationCard extends StatelessWidget {
  const _ConsultationCard({
    required this.session,
    required this.onResume,
    required this.onRename,
    required this.onTogglePin,
    required this.onArchive,
    required this.onDuplicate,
    required this.onDelete,
    required this.confirmDelete,
  });

  final PulseFinderSession session;
  final VoidCallback onResume;
  final VoidCallback onRename;
  final VoidCallback onTogglePin;
  final VoidCallback onArchive;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final Future<bool> Function() confirmDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = session.profileSummary.isNotEmpty
        ? session.profileSummary
        : session.messagePreview;

    return Dismissible(
      key: ValueKey(session.id),
      background: _swipeBackground(
        color: Colors.blueGrey,
        icon: Icons.archive_outlined,
        label: 'Archive',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _swipeBackground(
        color: Colors.red,
        icon: Icons.delete_outline,
        label: 'Delete',
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) return confirmDelete();
        onArchive();
        return false; // archive updates the stream; don't remove locally
      },
      onDismissed: (_) => onDelete(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: PPCard(
          child: InkWell(
            onTap: onResume,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (session.pinned)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.push_pin, size: 16, color: AppColors.primary),
                        ),
                      Expanded(
                        child: Text(
                          session.title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (value) {
                          switch (value) {
                            case 'rename':
                              onRename();
                            case 'pin':
                              onTogglePin();
                            case 'duplicate':
                              onDuplicate();
                            case 'archive':
                              onArchive();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(
                            value: 'pin',
                            child: Text(session.pinned ? 'Unpin' : 'Pin to top'),
                          ),
                          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                          const PopupMenuItem(value: 'archive', child: Text('Archive')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (session.intent != null) ...[
                        _Chip(label: session.intent!.displayLabel),
                        const SizedBox(width: 6),
                      ],
                      if (session.status != PulseFinderSessionStatus.active)
                        _Chip(label: session.status.displayLabel, muted: true),
                      const Spacer(),
                      Text(
                        _relativeTime(session.updatedAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      preview,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (session.recommendationCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.recommend_outlined, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          session.recommendationCount == 1
                              ? '1 recommendation'
                              : '${session.recommendationCount} recommendations',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground({
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? AppColors.textSecondary.withValues(alpha: 0.12) : AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: muted ? AppColors.textSecondary : AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
