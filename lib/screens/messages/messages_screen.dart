import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import '../../services/messaging_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Resolves the peer UID from either `participantIds` (Android) or
/// `participants` plain-array (iOS).
String _otherUid(Map<String, dynamic> thread, String me) {
  for (final key in ['participantIds', 'participants']) {
    final v = thread[key];
    if (v is List) {
      final ids = v.map((e) => e.toString()).toList();
      final other = ids.firstWhere((id) => id != me, orElse: () => '');
      if (other.isNotEmpty) return other;
    }
  }
  return '';
}

String _formatTime(dynamic ts) {
  DateTime? dt;
  if (ts is Timestamp) dt = ts.toDate();
  if (ts is DateTime) dt = ts;
  if (dt == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(dt.year, dt.month, dt.day);
  if (d == today) return DateFormat.jm().format(dt);          // 8:16 PM
  if (now.difference(dt).inDays < 7) return DateFormat.E().format(dt); // Mon
  return DateFormat.MMMd().format(dt);                        // Mar 17
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _refreshKey = 0;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // ── Cross-thread message search (mirrors iOS MessageCenterView) ──────────
  Timer? _searchDebounce;
  bool _searchingMessages = false;
  List<MessageSearchResult> _messageResults = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshKey++);
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _messageResults = [];
        _searchingMessages = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _runMessageSearch(value);
    });
  }

  Future<void> _runMessageSearch(String query) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.user == null) return;
    setState(() => _searchingMessages = true);
    try {
      final results = await MessagingService.searchMessages(
        db: FirebaseFirestore.instance,
        currentUserId: auth.user!.uid,
        query: query,
      );
      if (!mounted || query != _searchQuery) return;
      setState(() {
        _messageResults = results;
        _searchingMessages = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageResults = [];
        _searchingMessages = false;
      });
    }
  }

  Future<void> _deleteThread(String threadId, String me) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
            'This removes it from your list. The other person can still see their copy.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.conversationsCollection)
          .doc(threadId)
          .update({'deletedFor.$me': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (!auth.isSignedIn || auth.isAnonymous) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              _Header(onCompose: () => context.push('/messages/new')),
              const Expanded(child: _SignInPrompt()),
            ],
          ),
        ),
      );
    }

    final me = auth.user!.uid;
    final repo = context.read<PropertyRepository>();
    final isSearchActive = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          key: ValueKey(_refreshKey),
          stream: repo.watchConversations(me),
          builder: (context, snap) {
            final threads = snap.data ?? [];
            final hasError = snap.hasError;
            final loading = !snap.hasData && !hasError;

            return RefreshIndicator(
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Large title + compose ─────────────────────────────
                  SliverToBoxAdapter(
                    child: _Header(
                        onCompose: () => context.push('/messages/new')),
                  ),

                  // ── Inline search bar (always visible, like iOS) ──────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: _SearchField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),

                  // ── Body ─────────────────────────────────────────────
                  if (isSearchActive)
                    SliverFillRemaining(
                      child: _MessageSearchResultsView(
                        loading: _searchingMessages,
                        results: _messageResults,
                        query: _searchQuery,
                        currentUserId: me,
                      ),
                    )
                  else if (hasError)
                    SliverFillRemaining(
                      child: _ErrorState(snap.error.toString()),
                    )
                  else if (loading)
                    const SliverFillRemaining(child: _Skeleton())
                  else if (threads.isEmpty)
                    const SliverFillRemaining(child: _Empty())
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final t = threads[i];
                          final tid = t['id'] as String? ?? '';
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Dismissible(
                                key: ValueKey(tid),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) async {
                                  await _deleteThread(tid, me);
                                  return false;
                                },
                                background: ColoredBox(
                                  color: AppColors.error,
                                  child: const Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                      padding: EdgeInsets.only(right: 20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.delete_outline,
                                              color: Colors.white, size: 24),
                                          SizedBox(height: 4),
                                          Text('Delete',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                child: _ThreadTile(
                                  thread: t,
                                  currentUserId: me,
                                  searchQuery: _searchQuery,
                                ),
                              ),
                              if (i < threads.length - 1)
                                const Divider(
                                    height: 1, indent: 80, endIndent: 0),
                            ],
                          );
                        },
                        childCount: threads.length,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — large title + compose button, mirrors iOS NavigationStack header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onCompose});
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Messages',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          // iOS: square.and.pencil icon, top-trailing
          IconButton(
            icon: const Icon(Icons.edit_square, size: 24),
            tooltip: 'New message',
            onPressed: onCompose,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search field — always visible, matches iOS .searchable modifier appearance
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search messages',
          hintStyle: TextStyle(
              color: scheme.onSurfaceVariant, fontSize: 16),
          prefixIcon: Icon(Icons.search_rounded,
              color: scheme.onSurfaceVariant, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cross-thread message search results — mirrors iOS
// MessageCenterView.searchResultsView (loading → empty → tappable list)
// ─────────────────────────────────────────────────────────────────────────────

class _MessageSearchResultsView extends StatelessWidget {
  const _MessageSearchResultsView({
    required this.loading,
    required this.results,
    required this.query,
    required this.currentUserId,
  });

  final bool loading;
  final List<MessageSearchResult> results;
  final String query;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    if (loading && results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      return _NoResults(query);
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, i) => _SearchResultTile(
        result: results[i],
        query: query,
        currentUserId: currentUserId,
      ),
    );
  }
}

class _SearchResultTile extends StatefulWidget {
  const _SearchResultTile({
    required this.result,
    required this.query,
    required this.currentUserId,
  });

  final MessageSearchResult result;
  final String query;
  final String currentUserId;

  @override
  State<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<_SearchResultTile> {
  String _name = '';
  String? _photo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = widget.result.otherParticipantId;
    if (uid.isEmpty) {
      if (mounted) setState(() => _name = 'Unknown');
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_public')
          .doc(uid)
          .get();
      if (!mounted) return;
      final d = doc.data() ?? {};
      setState(() {
        _name = d['displayName'] as String? ??
            d['name'] as String? ??
            d['fullName'] as String? ??
            'User';
        _photo = d['photoURL'] as String? ?? d['photoUrl'] as String?;
      });
    } catch (_) {
      if (mounted) setState(() => _name = 'User');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = widget.result;
    return InkWell(
      onTap: () =>
          context.push('/messages/thread/${r.conversationId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(name: _name, photoUrl: _photo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _name.isEmpty ? '…' : _name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(r.createdAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  _Highlight(
                    text: r.text,
                    query: widget.query,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thread tile — mirrors iOS ConversationRowView
// ─────────────────────────────────────────────────────────────────────────────

class _ThreadTile extends StatefulWidget {
  const _ThreadTile({
    required this.thread,
    required this.currentUserId,
    this.searchQuery = '',
  });

  final Map<String, dynamic> thread;
  final String currentUserId;
  final String searchQuery;

  @override
  State<_ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<_ThreadTile> {
  String _name = '';
  String? _photo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ThreadTile old) {
    super.didUpdateWidget(old);
    if (old.thread['id'] != widget.thread['id']) _load();
  }

  Future<void> _load() async {
    final uid = _otherUid(widget.thread, widget.currentUserId);
    if (uid.isEmpty) {
      if (mounted) setState(() => _name = 'Unknown');
      return;
    }

    // 1. Embedded profile in thread doc (Android writes participantProfiles)
    final rawProfiles = widget.thread['participantProfiles'];
    if (rawProfiles is Map) {
      final p = rawProfiles[uid];
      if (p is Map) {
        final n = p['displayName'] as String? ?? p['name'] as String?;
        final ph = p['photoURL'] as String? ?? p['photoUrl'] as String?;
        if (n != null && n.isNotEmpty) {
          if (mounted) setState(() { _name = n; _photo = ph; });
          return;
        }
      }
    }

    // 2. Fetch from user_public (iOS-created threads — no embedded profile)
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_public')
          .doc(uid)
          .get();
      if (!mounted) return;
      final d = doc.data() ?? {};
      setState(() {
        _name = d['displayName'] as String? ??
            d['name'] as String? ??
            d['fullName'] as String? ??
            'User';
        _photo = d['photoURL'] as String? ?? d['photoUrl'] as String?;
      });
    } catch (_) {
      if (mounted) setState(() => _name = 'User');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.thread;
    final me = widget.currentUserId;
    final scheme = Theme.of(context).colorScheme;

    final lastMessage = t['lastMessage'] as String? ?? '';
    final lastAt = t['lastMessageAt'];
    final propertyTitle = t['propertyTitle'] as String? ?? '';
    final hasProperty = propertyTitle.isNotEmpty;
    final isUnread = MessagingService.isConversationUnread(t, me);

    return InkWell(
      onTap: () {
        final id = t['id'] as String?;
        if (id != null) context.push('/messages/thread/$id');
      },
      child: Padding(
        // iOS: 12pt vertical, 16pt horizontal
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar: 50pt diameter with thin border, mirrors iOS ProfileImageView
            _Avatar(name: _name, photoUrl: _photo),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Name · house icon (if has property) · Time
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _name.isEmpty ? '…' : _name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // house.fill icon when there is a linked property
                            if (hasProperty) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.house_rounded,
                                size: 13,
                                color: AppColors.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(lastAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: isUnread
                              ? AppColors.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),

                  // Row 2: Property title in primary (caption, matches iOS)
                  if (hasProperty) ...[
                    const SizedBox(height: 2),
                    Text(
                      propertyTitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // Row 3: Last message preview + unread dot
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: _Highlight(
                          text: lastMessage.isEmpty
                              ? 'No messages yet'
                              : lastMessage,
                          query: widget.searchQuery,
                          maxLines: hasProperty ? 1 : 2,
                          style: TextStyle(
                            fontSize: 15,
                            color: isUnread
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontWeight: isUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        const _UnreadDot(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar — 50pt diameter, thin primary border, matches iOS ProfileImageView
// ─────────────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl});
  final String name;
  final String? photoUrl;

  static const double _r = 25; // 50pt diameter

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _r * 2,
      height: _r * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                width: _r * 2,
                height: _r * 2,
                fit: BoxFit.cover,
                memCacheWidth: 100,
                memCacheHeight: 100,
                errorWidget: (_, __, ___) => _Initials(name: name, r: _r),
                placeholder: (_, __) => _Initials(name: name, r: _r),
              )
            : _Initials(name: name, r: _r),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.r});
  final String name;
  final double r;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    return ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
            fontSize: r * 0.48,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unread dot — iOS only tracks a 0/1 unread flag per conversation (see
// MessagingService.isConversationUnread), not a message count, so there is
// no real number to show here.
// ─────────────────────────────────────────────────────────────────────────────

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Highlighted text (search match)
// ─────────────────────────────────────────────────────────────────────────────

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.text,
    required this.query,
    required this.style,
    this.maxLines,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) {
      return Text(text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style);
    }
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final i = lower.indexOf(q, start);
      if (i == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (i > start) spans.add(TextSpan(text: text.substring(start, i)));
      spans.add(TextSpan(
        text: text.substring(i, i + q.length),
        style: TextStyle(
          backgroundColor: AppColors.primary.withValues(alpha: 0.2),
          fontWeight: FontWeight.w700,
        ),
      ));
      start = i + q.length;
    }
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// States
// ─────────────────────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => _StateView(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No messages yet',
        body: 'Start a conversation from any property listing.',
      );
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();
  @override
  Widget build(BuildContext context) => _StateView(
        icon: Icons.lock_outline_rounded,
        title: 'Sign in to view messages',
        body: 'Your conversations are private and linked to your account.',
      );
}

class _NoResults extends StatelessWidget {
  const _NoResults(this.query);
  final String query;
  @override
  Widget build(BuildContext context) => _StateView(
        icon: Icons.search_off_rounded,
        title: 'No results for "$query"',
        body: 'Try searching a name, property, or message preview.',
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => _StateView(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load messages',
        body: message,
      );
}

class _StateView extends StatelessWidget {
  const _StateView(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton loader
// ─────────────────────────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
      highlightColor:
          isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: 6,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 80),
        itemBuilder: (_, __) => const _SkeletonRow(),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE5E7EB);

    Widget box(double w, double h, {double r = 6}) => Container(
          width: w,
          height: h,
          decoration:
              BoxDecoration(color: c, borderRadius: BorderRadius.circular(r)),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  box(120, 15),
                  const Spacer(),
                  box(36, 12),
                ]),
                const SizedBox(height: 6),
                box(90, 12),
                const SizedBox(height: 6),
                box(double.infinity, 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
