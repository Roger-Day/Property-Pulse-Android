import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';

enum _VerificationStep {
  overview,
  levelSelection,
  documentUpload,
  review,
  processing,
  complete;

  String get title {
    switch (this) {
      case _VerificationStep.overview:
        return 'Get Started';
      case _VerificationStep.levelSelection:
        return 'Choose Level';
      case _VerificationStep.documentUpload:
        return 'Upload Documents';
      case _VerificationStep.review:
        return 'Review & Submit';
      case _VerificationStep.processing:
        return 'Processing';
      case _VerificationStep.complete:
        return 'Complete';
    }
  }
}

enum VerificationLevel {
  basic,
  standard,
  professional,
  elite;

  String get displayName {
    switch (this) {
      case VerificationLevel.basic:
        return 'Basic';
      case VerificationLevel.standard:
        return 'Standard';
      case VerificationLevel.professional:
        return 'Professional';
      case VerificationLevel.elite:
        return 'Elite';
    }
  }

  String get description {
    switch (this) {
      case VerificationLevel.basic:
        return 'Email verified, phone confirmed';
      case VerificationLevel.standard:
        return 'Government ID verified';
      case VerificationLevel.professional:
        return 'License + ID verified';
      case VerificationLevel.elite:
        return 'Full background + professional credentials';
    }
  }

  IconData get icon {
    switch (this) {
      case VerificationLevel.basic:
        return Icons.verified_user;
      case VerificationLevel.standard:
        return Icons.badge;
      case VerificationLevel.professional:
        return Icons.workspace_premium;
      case VerificationLevel.elite:
        return Icons.star;
    }
  }

  Color get color {
    switch (this) {
      case VerificationLevel.basic:
        return Colors.blue;
      case VerificationLevel.standard:
        return Colors.green;
      case VerificationLevel.professional:
        return Colors.purple;
      case VerificationLevel.elite:
        return Colors.orange;
    }
  }

  List<String> get requirements {
    switch (this) {
      case VerificationLevel.basic:
        return ['Email verification', 'Phone number'];
      case VerificationLevel.standard:
        return ['Government-issued photo ID', 'Selfie with ID'];
      case VerificationLevel.professional:
        return [
          'Government-issued photo ID',
          'Professional license',
          'Proof of business address',
        ];
      case VerificationLevel.elite:
        return [
          'Government-issued photo ID',
          'Professional license',
          'Business registration',
          'Background check consent',
        ];
    }
  }
}

/// Multi-step verification flow matching iOS `EnhancedVerificationFlowView`.
class EnhancedVerificationScreen extends StatefulWidget {
  const EnhancedVerificationScreen({super.key, required this.userId});

  final String userId;

  @override
  State<EnhancedVerificationScreen> createState() =>
      _EnhancedVerificationScreenState();
}

class _EnhancedVerificationScreenState
    extends State<EnhancedVerificationScreen> {
  _VerificationStep _step = _VerificationStep.overview;
  VerificationLevel? _selectedLevel;
  final List<String> _uploadedDocUrls = [];
  bool _submitting = false;
  String? _existingStatus;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadExistingStatus();
  }

  Future<void> _loadExistingStatus() async {
    try {
      // `verificationRequests` queries (list) are admin-only per Firestore
      // rules — the owner's current status lives on `userVerifications/{uid}`,
      // a single-doc get any authenticated user may read for their own uid.
      final doc = await FirebaseFirestore.instance
          .collection('userVerifications')
          .doc(widget.userId)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        setState(() {
          _existingStatus = doc.data()?['status'] as String? ?? 'pending';
        });
      }
    } catch (_) {}
  }

  void _advance() {
    final steps = _VerificationStep.values;
    final i = steps.indexOf(_step);
    if (i < steps.length - 1) {
      setState(() => _step = steps[i + 1]);
    }
  }

  void _back() {
    final steps = _VerificationStep.values;
    final i = steps.indexOf(_step);
    if (i > 0) setState(() => _step = steps[i - 1]);
  }

  bool get _canAdvance {
    switch (_step) {
      case _VerificationStep.overview:
        return true;
      case _VerificationStep.levelSelection:
        return _selectedLevel != null;
      case _VerificationStep.documentUpload:
        return _uploadedDocUrls.isNotEmpty;
      case _VerificationStep.review:
        return true;
      case _VerificationStep.processing:
      case _VerificationStep.complete:
        return false;
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final requestData = {
        'userId': widget.userId,
        'level': _selectedLevel?.name ?? 'standard',
        'documentUrls': _uploadedDocUrls,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      final db = FirebaseFirestore.instance;
      // Firestore rules restrict *querying* (list) `verificationRequests` to
      // admins — only `get` on a known doc id is allowed for the owner. So
      // status checks read `userVerifications/{userId}` instead (mirrors iOS
      // `VerificationManager.saveUserVerification`); this create is the
      // admin-reviewable request record.
      await db.collection('verificationRequests').add(requestData);
      await db.collection('userVerifications').doc(widget.userId).set(
        {
          ...requestData,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      setState(() {
        _step = _VerificationStep.complete;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Submission failed: $e')));
    }
  }

  Future<void> _pickAndUpload() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;

    try {
      final uid = widget.userId;
      final ref = FirebaseStorage.instance
          .ref()
          .child('${AppConstants.storageVerificationDocs}/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      if (!mounted) return;
      setState(() => _uploadedDocUrls.add(url));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepIndex = _VerificationStep.values.indexOf(_step);
    final totalSteps = _VerificationStep.values.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification'),
        leading: _step == _VerificationStep.overview ||
                _step == _VerificationStep.complete
            ? null
            : BackButton(onPressed: _back),
      ),
      body: Column(
        children: [
          // Progress bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: (stepIndex) / (totalSteps - 1),
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primary),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    totalSteps,
                    (i) => Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= stepIndex
                            ? AppColors.primary
                            : Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _step.title,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStepContent(),
            ),
          ),
          // Navigation buttons
          if (_step != _VerificationStep.complete)
            _buildNavigationBar(),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    // Show existing status banner if already submitted
    if (_existingStatus != null &&
        _step == _VerificationStep.overview) {
      return Column(
        children: [
          _ExistingStatusBanner(status: _existingStatus!),
          const SizedBox(height: 20),
          _buildOverview(),
        ],
      );
    }

    switch (_step) {
      case _VerificationStep.overview:
        return _buildOverview();
      case _VerificationStep.levelSelection:
        return _buildLevelSelection();
      case _VerificationStep.documentUpload:
        return _buildDocumentUpload();
      case _VerificationStep.review:
        return _buildReview();
      case _VerificationStep.processing:
        return _buildProcessing();
      case _VerificationStep.complete:
        return _buildComplete();
    }
  }

  Widget _buildOverview() {
    return Column(
      children: [
        const Icon(Icons.verified, size: 72, color: AppColors.primary),
        const SizedBox(height: 16),
        const Text(
          'Get Verified',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Build trust and unlock premium features with verified credentials',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        _BenefitsCard(),
        const SizedBox(height: 16),
        _VerificationLevelsPreviewCard(),
      ],
    );
  }

  Widget _buildLevelSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Your Verification Level',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Select the level that best matches your needs',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        ...VerificationLevel.values.map(
          (level) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _VerificationLevelCard(
              level: level,
              isSelected: _selectedLevel == level,
              onTap: () => setState(() => _selectedLevel = level),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentUpload() {
    final level = _selectedLevel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload Required Documents',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (level != null) ...[
          const SizedBox(height: 8),
          Text(
            'For ${level.displayName} verification, please upload:',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ...level.requirements.map(
            (req) => _DocumentRequirementTile(
              requirement: req,
              isUploaded: _uploadedDocUrls.length >
                  level.requirements.indexOf(req),
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickAndUpload,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload Document'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await _picker.pickImage(
                source: ImageSource.camera, imageQuality: 85);
            if (picked == null || !mounted) return;
            try {
              final ref = FirebaseStorage.instance
                  .ref()
                  .child('${AppConstants.storageVerificationDocs}/${widget.userId}/${DateTime.now().millisecondsSinceEpoch}.jpg');
              await ref.putFile(File(picked.path));
              final url = await ref.getDownloadURL();
              if (!mounted) return;
              setState(() => _uploadedDocUrls.add(url));
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          },
          icon: const Icon(Icons.camera_alt),
          label: const Text('Take Photo'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_uploadedDocUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${_uploadedDocUrls.length} document(s) uploaded',
            style: const TextStyle(
                color: Colors.green, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  Widget _buildReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Review Your Information',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Please review before submitting',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        _ReviewCard(
          title: 'Verification Level',
          value: _selectedLevel?.displayName ?? '—',
          icon: _selectedLevel?.icon ?? Icons.verified,
          color: _selectedLevel?.color ?? AppColors.primary,
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Documents Uploaded',
          value:
              '${_uploadedDocUrls.length} of ${_selectedLevel?.requirements.length ?? 0}',
          icon: Icons.description,
          color: Colors.blue,
        ),
        const SizedBox(height: 12),
        _ReviewCard(
          title: 'Processing Time',
          value: '1–3 business days',
          icon: Icons.access_time,
          color: Colors.teal,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'By submitting, you confirm that all documents are genuine and accurate.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProcessing() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Submitting your verification request…',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildComplete() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 48, color: Colors.green),
          ),
          const SizedBox(height: 20),
          const Text(
            'Request Submitted!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Your verification request has been submitted. You\'ll receive updates via notifications.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    final isLastActionStep = _step == _VerificationStep.review;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (_step != _VerificationStep.overview) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _back,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _canAdvance && !_submitting
                    ? isLastActionStep
                        ? _submit
                        : _advance
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isLastActionStep ? 'Submit' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Supporting widgets ───────────────────────────────────────────────────────

class _ExistingStatusBanner extends StatelessWidget {
  const _ExistingStatusBanner({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    // Admin approvals write status: 'verified' (see AdminRepository); iOS's
    // own banner checks both spellings for exactly this reason — matching
    // only 'approved' here made every actually-approved user see "Rejected".
    final isApproved = status == 'approved' || status == 'verified';
    final color = isApproved
        ? Colors.green
        : isPending
            ? Colors.orange
            : Colors.red;
    final label = isApproved
        ? 'Verified'
        : isPending
            ? 'Under Review'
            : 'Rejected';
    final icon = isApproved
        ? Icons.verified
        : isPending
            ? Icons.hourglass_empty
            : Icons.cancel;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color)),
                Text(
                  isPending
                      ? 'Your verification request is being reviewed.'
                      : isApproved
                          ? 'Your account is verified.'
                          : 'Your verification was not approved. You may resubmit.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final benefits = [
      (Icons.star, Colors.amber, 'Verified Badge',
          'Show your verified status to build trust'),
      (Icons.trending_up, Colors.blue, 'Higher Visibility',
          'Get priority in search results'),
      (Icons.message, Colors.green, 'Enhanced Messaging',
          'Access to premium messaging features'),
      (Icons.workspace_premium, Colors.purple, 'Premium Features',
          'Unlock exclusive tools and analytics'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verification Benefits',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          ...benefits.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: b.$2.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(b.$1, color: b.$2, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.$3,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        Text(b.$4,
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
    );
  }
}

class _VerificationLevelsPreviewCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('4 Verification Levels',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          ...VerificationLevel.values.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(l.icon, color: l.color, size: 16),
                  const SizedBox(width: 8),
                  Text(l.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text(l.description,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                      textAlign: TextAlign.right),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationLevelCard extends StatelessWidget {
  const _VerificationLevelCard({
    required this.level,
    required this.isSelected,
    required this.onTap,
  });

  final VerificationLevel level;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? level.color.withOpacity(0.08)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? level.color
                : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: level.color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(level.icon, color: level.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(level.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(level.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    '${level.requirements.length} document(s) required',
                    style: TextStyle(
                        fontSize: 11,
                        color: level.color,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: level.color),
          ],
        ),
      ),
    );
  }
}

class _DocumentRequirementTile extends StatelessWidget {
  const _DocumentRequirementTile({
    required this.requirement,
    required this.isUploaded,
  });

  final String requirement;
  final bool isUploaded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            isUploaded
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: isUploaded ? Colors.green : AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(requirement,
                style: TextStyle(
                    color: isUploaded
                        ? AppColors.textPrimary
                        : AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }
}
