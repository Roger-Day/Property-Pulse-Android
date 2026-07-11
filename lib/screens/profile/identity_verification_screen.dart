import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_profile_repository.dart';
import 'profile_subscreen_widgets.dart';

/// Upload ID / license for admin review (`verificationRequests` collection).
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key, required this.userId});

  final String userId;

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  final _noteCtrl = TextEditingController();
  final _picker = ImagePicker();
  XFile? _picked;
  bool _uploading = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (x != null && mounted) setState(() => _picked = x);
  }

  /// Mirrors iOS `jpegDataUnderLimit`: resize long edge to 2048px, then JPEG
  /// encode from quality 88 down by 10 until ≤ [AppConstants.maxImageUploadBytes].
  Future<Uint8List?> _compressUnderLimit(File file) async {
    final raw = await file.readAsBytes();
    var image = img.decodeImage(raw);
    if (image == null) return null;

    const maxDim = 2048;
    final w = image.width;
    final h = image.height;
    final longest = w > h ? w : h;
    if (longest > maxDim) {
      final scale = maxDim / longest;
      image = img.copyResize(
        image,
        width: (w * scale).round(),
        height: (h * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    Uint8List? last;
    for (var quality = 88; quality >= 12; quality -= 10) {
      final encoded =
          Uint8List.fromList(img.encodeJpg(image, quality: quality));
      last = encoded;
      if (encoded.length <= AppConstants.maxImageUploadBytes) {
        return encoded;
      }
    }
    return last;
  }

  Future<void> _submit() async {
    if (_picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a photo of your ID or license.')),
      );
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Use the Android or iOS app to upload documents.')),
      );
      return;
    }

    setState(() => _uploading = true);
    final repo = context.read<UserProfileRepository>();
    try {
      final file = File(_picked!.path);

      // ── Compress (mirrors iOS jpegDataUnderLimit) ──────────────────────────
      final bytes = await _compressUnderLimit(file);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not read the selected image. Try another.')),
        );
        return;
      }
      if (bytes.length > AppConstants.maxImageUploadBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Image is too large even after compression (max 5 MB). '
                      'Please use a smaller image.')),
        );
        return;
      }
      // ── Upload compressed bytes ────────────────────────────────────────────

      final uid = widget.userId;
      final name = 'kyc_${DateTime.now().millisecondsSinceEpoch}.jpg';
      // Must match storage.rules: verification_documents/{userId}/{fileName}
      final ref = FirebaseStorage.instance
          .ref()
          .child(AppConstants.storageVerificationDocs)
          .child(uid)
          .child(name);

      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();

      await repo.submitVerificationRequest(
        userId: uid,
        documentDownloadUrl: url,
        note: _noteCtrl.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Request submitted. We will review your documents.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.user?.uid != widget.userId) {
      return const Scaffold(
        body: Center(
            child:
                Text('You can only submit verification for your own account.')),
      );
    }

    return ProfileGroupedScaffold(
      title: 'Identity verification',
      child: ListView(
        padding: ProfileLayout.pagePadding,
        children: [
          Text(
            'Upload a clear photo of a government-issued ID or real estate license. '
            'Your document is stored securely and reviewed by our team.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 20),
          if (_picked != null && !kIsWeb)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_picked!.path),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _uploading ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. license number on file',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ProfilePrimaryButton(
            onPressed: _uploading ? null : _submit,
            busy: _uploading,
            icon: Icons.upload_file,
            label: _uploading ? 'Submitting…' : 'Submit for review',
          ),
        ],
      ),
    );
  }
}
