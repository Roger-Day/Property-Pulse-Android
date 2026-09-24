import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/property_model.dart';
import '../../repositories/property_repository.dart';

/// Mirrors iOS `ListingExpirationView` — shows expiring/expired listings with renewal CTAs.
class ListingExpirationScreen extends StatefulWidget {
  const ListingExpirationScreen({super.key, required this.userId});

  final String userId;

  @override
  State<ListingExpirationScreen> createState() =>
      _ListingExpirationScreenState();
}

class _ListingExpirationScreenState extends State<ListingExpirationScreen> {
  Future<_ExpirationData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ExpirationData> _load() async {
    final uid = widget.userId;
    final col = FirebaseFirestore.instance
        .collection(AppConstants.propertiesCollection);

    // Mirror iOS ListingExpirationViewModel: run parallel queries for
    // ownerId, realtorId, and hostUserId so all listing roles are covered.
    // Firestore doesn't support OR, so we run three queries and deduplicate.
    //
    // No server-side `deleted` filter — `isEqualTo: false` silently drops
    // any doc missing the field entirely (legacy listings predating it),
    // which would hide them from this screen and make them unrenewable.
    // Filtered out client-side below instead.
    final results = await Future.wait([
      col.where('ownerId', isEqualTo: uid).get(),
      col.where('realtorId', isEqualTo: uid).get(),
      col.where('hostUserId', isEqualTo: uid).get(),
    ]);

    // Deduplicate by doc id
    final seen = <String>{};
    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final snap in results) {
      for (final doc in snap.docs) {
        if (doc.data()['deleted'] == true) continue;
        if (seen.add(doc.id)) allDocs.add(doc);
      }
    }

    final expiringSoon = <PropertyModel>[];
    final expired = <PropertyModel>[];

    for (final doc in allDocs) {
      final p = PropertyModel.fromFirestore(doc);
      // Use PropertyModel.isExpired / isExpiringSoon which mirror iOS logic:
      // expired   → status=='expired' OR expirationDate has passed
      // expiringSoon → expirationDate within 7 days (matches iOS 7-day window)
      if (p.isExpired) {
        expired.add(p);
      } else if (p.isExpiringSoon) {
        expiringSoon.add(p);
      }
    }

    // Sort each list: most recently expired / soonest expiry first
    expired.sort((a, b) {
      final da = a.expirationDate, db = b.expirationDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da); // newest expiry first
    });
    expiringSoon.sort((a, b) {
      final da = a.expirationDate, db = b.expirationDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db); // soonest first
    });

    return _ExpirationData(expiringSoon: expiringSoon, expired: expired);
  }

  Future<void> _renew(PropertyModel property) async {
    try {
      // Delegate to PropertyRepository.renewListing — it also resets `status`
      // back to 'available' (this screen's own inline update used to only
      // touch expirationDate, so `isExpired`/isDiscoverable — which check
      // `status` first — kept treating the listing as expired even after
      // "renewal") and grants the correct rent-vs-sale renewal duration.
      await context.read<PropertyRepository>().renewListing(property);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing renewed')),
      );
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Renewal failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listing Expiration')),
      body: FutureBuilder<_ExpirationData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null || (data.expiringSoon.isEmpty && data.expired.isEmpty)) {
            return _AllCurrentView();
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (data.expiringSoon.isNotEmpty) ...[
                  _SectionLabel(
                      label: 'Expiring Soon',
                      icon: Icons.warning_amber,
                      color: Colors.orange),
                  const SizedBox(height: 8),
                  ...data.expiringSoon.map(
                    (p) => _ExpiringCard(
                        property: p,
                        onRenew: () => _renew(p),
                        isExpired: false),
                  ),
                  const SizedBox(height: 20),
                ],
                if (data.expired.isNotEmpty) ...[
                  _SectionLabel(
                      label: 'Expired',
                      icon: Icons.schedule,
                      color: Colors.red),
                  const SizedBox(height: 8),
                  ...data.expired.map(
                    (p) => _ExpiringCard(
                        property: p,
                        onRenew: () => _renew(p),
                        isExpired: true),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AllCurrentView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'All Listings Are Current',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'No properties are expiring soon or have expired.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
      {required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: color)),
      ],
    );
  }
}

class _ExpiringCard extends StatelessWidget {
  const _ExpiringCard({
    required this.property,
    required this.onRenew,
    required this.isExpired,
  });
  final PropertyModel property;
  final VoidCallback onRenew;
  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    final color = isExpired ? Colors.red : Colors.orange;
    final expDate = property.expirationDate;
    final fmtDate = expDate != null
        ? DateFormat.yMMMd().format(expDate)
        : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(property.title,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  isExpired ? 'Expired' : 'Expiring Soon',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${property.city}, ${property.state}',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.event, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                isExpired
                    ? 'Expired on $fmtDate'
                    : 'Expires on $fmtDate',
                style: TextStyle(fontSize: 12, color: color),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onRenew,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                child: const Text('Renew'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpirationData {
  const _ExpirationData(
      {required this.expiringSoon, required this.expired});
  final List<PropertyModel> expiringSoon;
  final List<PropertyModel> expired;
}
