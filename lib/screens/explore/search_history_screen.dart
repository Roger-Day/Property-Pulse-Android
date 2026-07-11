import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';

/// Mirrors iOS `SearchHistoryView` — displays and manages recent searches.
class SearchHistoryScreen extends StatefulWidget {
  const SearchHistoryScreen({
    super.key,
    required this.onSelectQuery,
  });

  /// Called when user taps a history item — passes the search text back.
  final void Function(String query) onSelectQuery;

  @override
  State<SearchHistoryScreen> createState() => _SearchHistoryScreenState();
}

class _SearchHistoryScreenState extends State<SearchHistoryScreen> {
  Future<List<_HistoryEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final uid =
        context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    setState(() {
      _future = _fetch(uid);
    });
  }

  Future<List<_HistoryEntry>> _fetch(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('searchHistory')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((doc) {
      final m = doc.data();
      final ts = m['timestamp'];
      final date = ts is Timestamp ? ts.toDate() : DateTime.now();
      return _HistoryEntry(
        id: doc.id,
        query: m['query'] as String? ?? '',
        resultCount: (m['resultCount'] as num?)?.toInt() ?? 0,
        timestamp: date,
      );
    }).toList();
  }

  Future<void> _clearAll(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('searchHistory')
          .where('userId', isEqualTo: uid)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteEntry(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection('searchHistory')
          .doc(id)
          .delete();
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search History'),
        actions: [
          TextButton(
            onPressed: () => _clearAll(uid),
            child: const Text('Clear All',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: FutureBuilder<List<_HistoryEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data ?? [];
          if (entries.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No Search History',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('Your recent searches will appear here',
                      style: TextStyle(
                          color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final e = entries[i];
              return Dismissible(
                key: ValueKey(e.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => _deleteEntry(e.id),
                child: ListTile(
                  leading: const Icon(Icons.search,
                      color: AppColors.textSecondary),
                  title: Text(e.query,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${DateFormat('MMM d, h:mm a').format(e.timestamp)} · ${e.resultCount} results',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSelectQuery(e.query);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry({
    required this.id,
    required this.query,
    required this.resultCount,
    required this.timestamp,
  });
  final String id;
  final String query;
  final int resultCount;
  final DateTime timestamp;
}

/// Helper to save a search to history.
Future<void> saveSearchHistory({
  required String userId,
  required String query,
  required int resultCount,
}) async {
  if (query.trim().isEmpty || userId.isEmpty) return;
  try {
    await FirebaseFirestore.instance.collection('searchHistory').add({
      'userId': userId,
      'query': query.trim(),
      'resultCount': resultCount,
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}
