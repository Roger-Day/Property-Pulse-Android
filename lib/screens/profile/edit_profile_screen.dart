import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/user_profile_doc.dart';
import '../../widgets/role_switcher.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/auth_service.dart';
import 'profile_subscreen_widgets.dart';

/// Canonical role strings — matches iOS `UserRole` raw values.
abstract final class ProfileRoleLabels {
  static const seeker = 'Property Seeker';
  static const owner = 'Property Owner';
  static const realtor = 'Realtor';
  static const developer = 'Developer';
  static const airbnbHost = 'Airbnb Host';
  static const admin = 'Admin';

  static const selectable = [seeker, owner, realtor, developer, airbnbHost];

  /// Maps any stored role variant to its display label.
  /// Returns null for unrecognised values — callers must NOT write a role
  /// back to Firestore in that case (writing a fallback silently downgraded
  /// realtors to seekers).
  static String? normalizeOrNull(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();
    for (final k in const [admin, developer, realtor, owner, airbnbHost, seeker]) {
      if (k.toLowerCase() == s.toLowerCase()) return k;
    }
    final n = s.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    switch (n) {
      case 'admin':
        return admin;
      case 'developer':
        return developer;
      case 'realtor':
        return realtor;
      case 'owner':
      case 'propertyowner':
        return owner;
      case 'airbnbhost':
        return airbnbHost;
      case 'seeker':
      case 'propertyseeker':
        return seeker;
      default:
        return null;
    }
  }

  /// UI-only normalisation (dropdown needs a valid value). Never use the
  /// result of this for a Firestore write when the input was unrecognised.
  static String normalize(String? raw) => normalizeOrNull(raw) ?? seeker;
}

/// Mirrors iOS `UserProfileEditView`: grouped cards (photo, personal info, bio,
/// contact, role-specific, preferences), inline title, Cancel leading.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.userId,
    required this.email,
  });

  final String userId;
  final String email;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _agencyCtrl = TextEditingController();
  final _yearsCtrl = TextEditingController();

  bool _profileSynced = false;
  bool _saving = false;
  bool _uploadingAvatar = false;

  String _roleSelection = ProfileRoleLabels.seeker;
  // Role as loaded from Firestore — role is only written on save when the
  // user actively changed the dropdown AFTER the profile synced. This is the
  // guard against the realtor→seeker downgrade race (saving before the async
  // profile sync used to write the dropdown's default 'seeker' value).
  String? _loadedRole;
  bool _notificationsEnabled = true;

  static const int _maxBio = 500;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    _licenseCtrl.dispose();
    _agencyCtrl.dispose();
    _yearsCtrl.dispose();
    super.dispose();
  }

  void _syncFromDoc(UserProfileDoc doc) {
    _fullNameCtrl.text = doc.fullName ?? '';
    _phoneCtrl.text = doc.phoneNumber ?? '';
    _bioCtrl.text = doc.bio ?? '';
    _licenseCtrl.text = doc.realtorLicenseNumber ?? '';
    _agencyCtrl.text = doc.realtorAgency ?? '';
    _yearsCtrl.text = doc.realtorYearsExperience != null
        ? '${doc.realtorYearsExperience}'
        : '';
    _roleSelection = ProfileRoleLabels.normalize(doc.role);
    _loadedRole = _roleSelection;
    _notificationsEnabled = doc.notificationsEnabled;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Never save before the profile has loaded — the form still holds
    // defaults ('Property Seeker' role) that would overwrite real data.
    if (!_profileSynced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile is still loading — try again.')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    try {
      final repo = context.read<UserProfileRepository>();
      final isAdmin = UserProfileDoc.isAdminRole(_roleSelection);

      final yearsParsed = int.tryParse(_yearsCtrl.text.trim());

      // Only write the role when the user actively changed the dropdown.
      // An unchanged role is omitted, so a stale/defaulted selection can
      // never downgrade the account (the realtor→seeker bug).
      final roleChanged = _roleSelection != _loadedRole;

      await repo.updateProfile(
        userId: widget.userId,
        fullName: _fullNameCtrl.text,
        phoneNumber: _phoneCtrl.text,
        bio: _bioCtrl.text,
        role: roleChanged
            ? (isAdmin ? ProfileRoleLabels.admin : _roleSelection)
            : null,
        notificationsEnabled: _notificationsEnabled,
        realtorLicenseNumber:
            _roleSelection == ProfileRoleLabels.realtor ? _licenseCtrl.text : null,
        realtorAgency:
            _roleSelection == ProfileRoleLabels.realtor ? _agencyCtrl.text : null,
        realtorYearsExperience:
            _roleSelection == ProfileRoleLabels.realtor ? yearsParsed : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;
    final repo = context.read<UserProfileRepository>();
    setState(() => _uploadingAvatar = true);
    try {
      // iOS: user_uploads/{uid}/profile_photos/{uid}_profile.jpg
      // Source: UserProfileService.swift line 154
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_uploads')
          .child(widget.userId)
          .child('profile_photos')
          .child('${widget.userId}_profile.jpg');
      await ref.putFile(File(x.path));
      final url = await ref.getDownloadURL();
      await repo.updateProfilePhotoUrl(
        userId: widget.userId,
        downloadUrl: url,
      );
      await AuthService.instance.updatePhotoUrl(url);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();

    return ProfileGroupedScaffold(
      title: 'Edit Profile',
      leading: TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        child: const Text('Cancel'),
      ),
      child: StreamBuilder<UserProfileDoc?>(
        stream: repo.watchUserProfile(widget.userId),
        builder: (context, snap) {
          if (snap.hasError) {
            return ProfileErrorState(
              message: snap.error.toString(),
              onRetry: () => setState(() {}),
            );
          }

          final doc = snap.data;
          // Sync before the next frame / user taps so Firestore role does not
          // overwrite the role dropdown after the user changes it (post-frame
          // was too late). Mark synced synchronously so only one microtask runs.
          if (doc != null && !_profileSynced) {
            _profileSynced = true;
            final d = doc;
            scheduleMicrotask(() {
              if (!mounted) return;
              setState(() => _syncFromDoc(d));
            });
          }

          final bioLen = _bioCtrl.text.length;

          return Form(
            key: _formKey,
            child: ListView(
              padding: ProfileLayout.pagePadding,
              children: [
                _PhotoSection(
                  doc: doc,
                  fullNameForInitials: _fullNameCtrl.text,
                  uploadingAvatar: _uploadingAvatar,
                  onPickPhoto: _pickAndUploadAvatar,
                ),
                const SizedBox(height: ProfileLayout.sectionGap),
                _PersonalInfoCard(
                  email: widget.email,
                  fullNameCtrl: _fullNameCtrl,
                  roleSelection: _roleSelection,
                  lockedAdmin: doc != null &&
                      UserProfileDoc.isAdminRole(doc.role),
                  onRoleChanged: (v) => setState(() => _roleSelection = v),
                  doc: doc,
                  userId: widget.userId,
                ),
                const SizedBox(height: ProfileLayout.sectionGap),
                _BioCard(
                  bioCtrl: _bioCtrl,
                  bioLen: bioLen,
                  maxBio: _maxBio,
                  onBioChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: ProfileLayout.sectionGap),
                _ContactCard(phoneCtrl: _phoneCtrl),
                if (_roleSelection == ProfileRoleLabels.realtor) ...[
                  const SizedBox(height: ProfileLayout.sectionGap),
                  _RealtorInfoCard(
                    licenseCtrl: _licenseCtrl,
                    agencyCtrl: _agencyCtrl,
                    yearsCtrl: _yearsCtrl,
                  ),
                ],
                if (_roleSelection == ProfileRoleLabels.owner) ...[
                  const SizedBox(height: ProfileLayout.sectionGap),
                  _PlaceholderRoleCard(
                    title: 'Property Management',
                    body:
                        'Manage your owned properties and rental history from '
                        'your listings and dashboard.',
                  ),
                ],
                if (_roleSelection == ProfileRoleLabels.seeker) ...[
                  const SizedBox(height: ProfileLayout.sectionGap),
                  _PlaceholderRoleCard(
                    title: 'Search Preferences',
                    body:
                        'Saved searches and viewing preferences are available '
                        'from Explore and Saved.',
                  ),
                ],
                const SizedBox(height: ProfileLayout.sectionGap),
                _PreferencesCard(
                  notificationsEnabled: _notificationsEnabled,
                  onNotificationsChanged: (v) =>
                      setState(() => _notificationsEnabled = v),
                ),
                SizedBox(height: ProfileLayout.actionGap),
                _SaveButton(onPressed: _saving ? null : _save, busy: _saving),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Section cards (iOS grouped `systemBackground` + corner radius + light shadow)
// ─────────────────────────────────────────────────────────────────────────────

class _IosSectionCard extends StatelessWidget {
  const _IosSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        boxShadow: ProfileShadows.card(),
      ),
      child: child,
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.doc,
    required this.fullNameForInitials,
    required this.uploadingAvatar,
    required this.onPickPhoto,
  });

  final UserProfileDoc? doc;
  final String fullNameForInitials;
  final bool uploadingAvatar;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final url = doc?.profileImageUrl;
    final hasUrl = url != null && url.isNotEmpty;

    return _IosSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile Photo',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  GestureDetector(
                    onTap: uploadingAvatar ? null : onPickPhoto,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.surfaceVariant,
                        backgroundImage:
                            hasUrl ? CachedNetworkImageProvider(url) : null,
                        child: !hasUrl
                            ? Text(
                                _initials(fullNameForInitials),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (uploadingAvatar)
                    const SizedBox(
                      width: 88,
                      height: 88,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Tap the photo to change your profile image.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _PersonalInfoCard extends StatelessWidget {
  const _PersonalInfoCard({
    required this.email,
    required this.fullNameCtrl,
    required this.roleSelection,
    required this.lockedAdmin,
    required this.onRoleChanged,
    this.doc,
    this.userId,
  });

  final String email;
  final TextEditingController fullNameCtrl;
  final String roleSelection;
  final bool lockedAdmin;
  final ValueChanged<String> onRoleChanged;
  final UserProfileDoc? doc;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return _IosSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Personal Information',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 14),
          _ProfileFieldLabel(label: 'Full Name'),
          TextFormField(
            controller: fullNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Enter your full name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
          ),
          const SizedBox(height: 14),
          _ProfileFieldLabel(label: 'Email'),
          TextFormField(
            initialValue: email,
            readOnly: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Color(0xFFF3F4F6),
            ),
          ),
          const SizedBox(height: 14),
          if (lockedAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                ProfileRoleLabels.admin,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          else if (doc != null && userId != null)
            RoleSwitcher(
              doc: doc!,
              userId: userId!,
              onRoleChanged: onRoleChanged,
            )
          else
            InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey<String>(roleSelection),
                  isExpanded: true,
                  value: roleSelection,
                  items: [
                    for (final r in ProfileRoleLabels.selectable)
                      DropdownMenuItem(value: r, child: Text(r)),
                  ],
                  onChanged: (v) {
                    if (v != null) onRoleChanged(v);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BioCard extends StatelessWidget {
  const _BioCard({
    required this.bioCtrl,
    required this.bioLen,
    required this.maxBio,
    required this.onBioChanged,
  });

  final TextEditingController bioCtrl;
  final int bioLen;
  final int maxBio;
  final ValueChanged<String> onBioChanged;

  @override
  Widget build(BuildContext context) {
    return _IosSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Bio',
                style: ProfileTextStyles.cardSectionTitle(context),
              ),
              const Spacer(),
              Text(
                '${bioLen.clamp(0, maxBio)}/$maxBio',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A short intro shown on your public profile.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: bioCtrl,
            maxLines: 5,
            maxLength: maxBio,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            onChanged: onBioChanged,
            decoration: const InputDecoration(
              hintText:
                  'Tell others about your focus, markets, or experience…',
              filled: true,
              fillColor: Color(0xFFEFEFF4),
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.phoneCtrl});

  final TextEditingController phoneCtrl;

  @override
  Widget build(BuildContext context) {
    return _IosSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Contact Information',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 14),
          _ProfileFieldLabel(label: 'Phone Number'),
          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Enter your phone number',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _RealtorInfoCard extends StatelessWidget {
  const _RealtorInfoCard({
    required this.licenseCtrl,
    required this.agencyCtrl,
    required this.yearsCtrl,
  });

  final TextEditingController licenseCtrl;
  final TextEditingController agencyCtrl;
  final TextEditingController yearsCtrl;

  @override
  Widget build(BuildContext context) {
    return _IosSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Realtor Information',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 14),
          _ProfileFieldLabel(label: 'License Number'),
          TextFormField(
            controller: licenseCtrl,
            decoration: const InputDecoration(
              hintText: 'Enter your license number',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          _ProfileFieldLabel(label: 'Agency'),
          TextFormField(
            controller: agencyCtrl,
            decoration: const InputDecoration(
              hintText: 'Enter your agency name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          _ProfileFieldLabel(label: 'Years of Experience'),
          TextFormField(
            controller: yearsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Enter years of experience',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderRoleCard extends StatelessWidget {
  const _PlaceholderRoleCard({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _IosSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({
    required this.notificationsEnabled,
    required this.onNotificationsChanged,
  });

  final bool notificationsEnabled;
  final ValueChanged<bool> onNotificationsChanged;

  @override
  Widget build(BuildContext context) {
    return _IosSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Preferences',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Notifications'),
            value: notificationsEnabled,
            onChanged: onNotificationsChanged,
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF007AFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: busy
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProfileFieldLabel extends StatelessWidget {
  const _ProfileFieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }
}
