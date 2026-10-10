import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../services/verification_service.dart';

/// Sends the evidence for one verification step: the government ID ("identity") or the role's
/// professional credential ("professional"). What is needed, and how many photos each
/// document may have, comes from the backend (`getVerificationRequirements`), not from this
/// file. Submitting only creates a request for review - nothing here grants a badge.
class EnhancedVerificationScreen extends StatefulWidget {
  const EnhancedVerificationScreen({
    super.key,
    required this.userId,
    this.requestType = 'identity',
    this.service,
  });

  final String userId;

  /// 'identity' or 'professional'
  final String requestType;
  final VerificationService? service;

  @override
  State<EnhancedVerificationScreen> createState() => _EnhancedVerificationScreenState();
}

class _EnhancedVerificationScreenState extends State<EnhancedVerificationScreen> {
  late final VerificationService _service = widget.service ?? VerificationService();
  final _picker = ImagePicker();
  final _note = TextEditingController();

  VerificationRequirements _requirements = VerificationRequirements.fallback;
  VerificationRecord _record = const VerificationRecord();
  final Map<String, List<File>> _photos = {};
  bool _submitting = false;
  bool _submitted = false;

  bool get _isProfessional => widget.requestType == 'professional';
  String get _levelId => _isProfessional ? 'professional' : 'standard';
  List<VerificationDocSpec> get _specs => _requirements.level(_levelId)?.documents ?? const [];
  VerificationSection get _section => _isProfessional ? _record.professional : _record.identity;

  @override
  void initState() {
    super.initState();
    _service.requirements().then((r) {
      if (mounted) setState(() => _requirements = r);
    });
    _service.watch(widget.userId).listen((r) {
      if (mounted) setState(() => _record = r);
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? get _blocker {
    if (!_record.contactVerified) return 'Verify your email and phone number first.';
    if (_isProfessional && _record.identity.status != VerificationSectionStatus.approved) {
      return 'Your identity must be verified first.';
    }
    if (!_section.status.canSubmit) {
      return _section.status == VerificationSectionStatus.pending
          ? 'Your request is under review.'
          : 'This verification is already complete.';
    }
    return null;
  }

  bool get _complete =>
      _specs.isNotEmpty && _specs.every((s) => (_photos[s.type]?.length ?? 0) >= s.minFiles);

  Future<void> _add(VerificationDocSpec spec, ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 2048, maxHeight: 2048);
    if (picked == null || !mounted) return;
    final list = _photos.putIfAbsent(spec.type, () => []);
    if (list.length >= spec.maxFiles) return;
    final file = File(picked.path);
    if (await file.length() > _requirements.maxFileBytes) {
      _toast('That photo is too large. Try a smaller one.');
      return;
    }
    setState(() => list.add(file));
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final documents = <Map<String, dynamic>>[];
      for (final spec in _specs) {
        final paths = <String>[];
        final files = _photos[spec.type] ?? const <File>[];
        for (var i = 0; i < files.length; i++) {
          paths.add(await _service.uploadPhoto(widget.userId, files[i], i));
        }
        documents.add({'type': spec.type, 'files': paths});
      }
      await _service.submit(type: widget.requestType, documents: documents, note: _note.text);
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      _toast(verificationErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    return Scaffold(
      appBar: AppBar(title: Text(_isProfessional ? 'Professional verification' : 'Identity verification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_submitted)
            _submittedView()
          else if (blocker != null)
            _banner(blocker, Colors.blue)
          else ...[
            if ((_section.note ?? '').isNotEmpty &&
                (_section.status == VerificationSectionStatus.rejected ||
                    _section.status == VerificationSectionStatus.requiresResubmission))
              _banner('Feedback from our team: ${_section.note}', Colors.orange),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Your photos are stored securely and only reviewed by our team. Submitting does not '
                'verify you; a reviewer approves or declines each request.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            for (final spec in _specs) _documentCard(spec),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note for the reviewer (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _complete && !_submitting ? _submit : null,
              child: _submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit for review'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _banner(String text, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(text),
      );

  Widget _documentCard(VerificationDocSpec spec) {
    final picked = _photos[spec.type] ?? const <File>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (spec.filesHint.isNotEmpty)
              Text(spec.filesHint, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (picked.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < picked.length; i++)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(picked[i], width: 96, height: 96, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            tooltip: 'Remove photo',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.cancel, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                            onPressed: _submitting ? null : () => setState(() => picked.removeAt(i)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
            if (picked.length < spec.maxFiles) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : () => _add(spec, ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : () => _add(spec, ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Library'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _submittedView() => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            const Icon(Icons.hourglass_empty_rounded, size: 48, color: Colors.orange),
            const SizedBox(height: 12),
            const Text('Submitted for review', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              "You'll get a notification when a reviewer decides. You are not verified until then.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Done')),
          ],
        ),
      );
}
