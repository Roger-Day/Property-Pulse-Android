import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import 'enhanced_verification_screen.dart';

/// Shows user's current verification status with detailed breakdown.
/// Mirrors iOS `VerificationDetailsView`.
class VerificationDetailsScreen extends StatelessWidget {
  const VerificationDetailsScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Status')),
      body: FutureBuilder<DocumentSnapshot>(
        // `verificationRequests` queries (list) are admin-only per Firestore
        // rules — the owner's current status lives on `userVerifications/{uid}`,
        // a single-doc get any authenticated user may read for their own uid
        // (mirrors iOS `VerificationManager.loadUserVerification`).
        future: FirebaseFirestore.instance
            .collection('userVerifications')
            .doc(userId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!(snap.data?.exists ?? false)) {
            return _NoVerificationView(userId: userId);
          }
          final data = snap.data!.data() as Map<String, dynamic>;
          return _VerificationStatusView(data: data, userId: userId);
        },
      ),
    );
  }
}

class _NoVerificationView extends StatelessWidget {
  const _NoVerificationView({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 72, color: AppColors.textSecondary),
          const SizedBox(height: 20),
          const Text(
            'Not Yet Verified',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Get verified to build trust and unlock premium features.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EnhancedVerificationScreen(userId: userId),
            )),
            icon: const Icon(Icons.verified),
            label: const Text('Start Verification'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const VerificationBenefitsScreen(),
            )),
            child: const Text('Learn about benefits →'),
          ),
        ],
      ),
    );
  }
}

class _VerificationStatusView extends StatelessWidget {
  const _VerificationStatusView(
      {required this.data, required this.userId});
  final Map<String, dynamic> data;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final level = data['level'] as String? ?? 'standard';
    final docs = (data['documentUrls'] as List?)?.cast<String>() ?? [];
    final ts = data['createdAt'];
    DateTime? createdAt;
    if (ts is Timestamp) createdAt = ts.toDate();

    final isApproved = status == 'approved';
    final isPending = status == 'pending';
    final color = isApproved
        ? Colors.green
        : isPending
            ? Colors.orange
            : Colors.red;
    final statusLabel = isApproved
        ? 'Verified'
        : isPending
            ? 'Under Review'
            : 'Not Approved';
    final statusIcon = isApproved
        ? Icons.verified
        : isPending
            ? Icons.hourglass_empty
            : Icons.cancel;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status hero
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: color, size: 40),
                ),
                const SizedBox(height: 12),
                Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
                if (createdAt != null)
                  Text(
                    'Submitted ${_formatDate(createdAt)}',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Details
          _DetailRow(label: 'Level', value: _capitalise(level)),
          _DetailRow(label: 'Status', value: statusLabel),
          _DetailRow(
              label: 'Documents', value: '${docs.length} uploaded'),
          if (isPending)
            _DetailRow(
                label: 'Processing Time', value: '1–3 business days'),
          const SizedBox(height: 24),
          if (status == 'rejected') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your verification was not approved. You may resubmit with additional documents.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EnhancedVerificationScreen(userId: userId),
                  ),
                ),
                child: const Text('Resubmit Verification'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Verification Benefits screen ─────────────────────────────────────────────

/// Mirrors iOS `VerificationBenefitsView`.
class VerificationBenefitsScreen extends StatelessWidget {
  const VerificationBenefitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Benefits')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.verified,
                      size: 64, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'Why Get Verified?',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Verified accounts get more trust, visibility, and features',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _BenefitSection(
              title: 'Trust & Credibility',
              benefits: [
                _Benefit(Icons.verified, Colors.blue, 'Verified Badge',
                    'Blue checkmark shown on your profile and listings'),
                _Benefit(Icons.people, Colors.teal, 'User Confidence',
                    'Buyers and renters prefer verified sellers'),
              ],
            ),
            const SizedBox(height: 20),
            _BenefitSection(
              title: 'Search & Visibility',
              benefits: [
                _Benefit(Icons.trending_up, Colors.green,
                    'Priority Ranking',
                    'Verified listings rank higher in search results'),
                _Benefit(Icons.star, Colors.amber, 'Featured Eligibility',
                    'Access to featured placement on the home screen'),
              ],
            ),
            const SizedBox(height: 20),
            _BenefitSection(
              title: 'Tools & Features',
              benefits: [
                _Benefit(Icons.message, Colors.purple,
                    'Enhanced Messaging',
                    'Priority inbox and quick-reply templates'),
                _Benefit(Icons.bar_chart, Colors.indigo, 'Advanced Analytics',
                    'Deeper insights into listing performance'),
              ],
            ),
            const SizedBox(height: 28),
            // Level comparison
            const Text(
              'Verification Levels',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...VerificationLevel.values.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: l.color.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(l.icon, color: l.color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.displayName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          Text(l.description,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit {
  const _Benefit(this.icon, this.color, this.title, this.description);
  final IconData icon;
  final Color color;
  final String title;
  final String description;
}

class _BenefitSection extends StatelessWidget {
  const _BenefitSection(
      {required this.title, required this.benefits});
  final String title;
  final List<_Benefit> benefits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
              ),
            ],
          ),
          child: Column(
            children: benefits
                .map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: b.color.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(b.icon, color: b.color, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(b.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              Text(b.description,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
