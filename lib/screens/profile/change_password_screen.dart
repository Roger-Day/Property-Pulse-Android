import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import 'profile_subscreen_widgets.dart';

/// Material parity with iOS `ChangePasswordView`: hero, three fields, live requirement
/// checklist, inline error, loading, unavailable / signed-out states, success alert then pop.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  static const double _horizontalPadding = 20;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentCtrl.addListener(_onFieldsChanged);
    _newCtrl.addListener(_onFieldsChanged);
    _confirmCtrl.addListener(_onFieldsChanged);
  }

  void _onFieldsChanged() {
    if (mounted && _errorMessage != null) {
      setState(() => _errorMessage = null);
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _currentCtrl.removeListener(_onFieldsChanged);
    _newCtrl.removeListener(_onFieldsChanged);
    _confirmCtrl.removeListener(_onFieldsChanged);
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  fb_auth.User? get _user => fb_auth.FirebaseAuth.instance.currentUser;

  bool get _signedOut => _user == null;

  bool get _supportsEmailPassword {
    final u = _user;
    if (u == null) return false;
    return u.providerData
        .any((p) => p.providerId == fb_auth.EmailAuthProvider.PROVIDER_ID);
  }

  bool get _hasMinLength => _newCtrl.text.length >= 8;

  bool get _hasUpper =>
      RegExp(r'[A-Z]').hasMatch(_newCtrl.text);

  bool get _hasLower =>
      RegExp(r'[a-z]').hasMatch(_newCtrl.text);

  bool get _hasDigit =>
      RegExp(r'[0-9]').hasMatch(_newCtrl.text);

  bool get _passwordRulesOk =>
      _hasMinLength && _hasUpper && _hasLower && _hasDigit;

  bool get _isFormValid {
    final cur = _currentCtrl.text;
    final neu = _newCtrl.text;
    final conf = _confirmCtrl.text;
    return cur.isNotEmpty &&
        neu.isNotEmpty &&
        conf.isNotEmpty &&
        neu == conf &&
        _passwordRulesOk;
  }

  Future<void> _submit() async {
    if (!_isFormValid || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await context.read<AuthProvider>().changePassword(
            currentPassword: _currentCtrl.text,
            newPassword: _newCtrl.text,
          );
      if (!mounted) return;
      setState(() => _loading = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Success'),
            content: const Text(
              'Your password has been changed successfully.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = _messageForAuthException(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  String _messageForAuthException(fb_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'The current password is incorrect.';
      case 'weak-password':
        return 'The new password is too weak. Meet all requirements below.';
      case 'requires-recent-login':
        return 'Please sign in again, then change your password.';
      case 'no-email':
        return 'This account has no email address for password sign-in.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Could not change password.';
    }
  }

  void _pop() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ProfileGroupedScaffold(
      title: 'Change Password',
      actions: [
        TextButton(
          onPressed: _loading ? null : _pop,
          child: const Text('Cancel'),
        ),
      ],
      child: _signedOut
          ? _signedOutBody(context)
          : !_supportsEmailPassword
              ? _unavailableBody(context)
              : _mainScrollContent(context, theme),
    );
  }

  Widget _signedOutBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ProfileEmptyState(
          icon: Icons.lock_outline,
          title: 'Sign in required',
          subtitle:
              'Sign in with email and password to change your password.',
        ),
      ),
    );
  }

  Widget _unavailableBody(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ProfileEmptyState(
          icon: Icons.link_off_outlined,
          title: 'Email password not set up',
          subtitle:
              'Password change applies to accounts that use email & password. '
              'If you use Google or another sign-in method, use your provider’s '
              'account security settings or reset password from the sign-in screen.',
        ),
      ),
    );
  }

  Widget _mainScrollContent(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileSheetHeroHeader(
            icon: Icons.lock_person_outlined,
            iconColor: AppColors.primary,
            title: 'Change Password',
            subtitle:
                'Enter your current password and choose a new one',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ChangePasswordScreen._horizontalPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _passwordField(
                  context,
                  label: 'Current Password',
                  hint: 'Enter current password',
                  controller: _currentCtrl,
                  obscure: _obscureCurrent,
                  onToggleObscure: () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  allowWhitespace: true,
                ),
                const SizedBox(height: 20),
                _passwordField(
                  context,
                  label: 'New Password',
                  hint: 'Enter new password',
                  controller: _newCtrl,
                  obscure: _obscureNew,
                  onToggleObscure: () =>
                      setState(() => _obscureNew = !_obscureNew),
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 20),
                _passwordField(
                  context,
                  label: 'Confirm New Password',
                  hint: 'Confirm new password',
                  controller: _confirmCtrl,
                  obscure: _obscureConfirm,
                  onToggleObscure: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20),
                _requirementsCard(context, theme),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed:
                      (!_isFormValid || _loading) ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_loading) ...[
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else ...[
                        Icon(
                          Icons.vpn_key_rounded,
                          size: 20,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _loading ? 'Changing Password...' : 'Change Password',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _loading ? null : _pop,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField(
    BuildContext context, {
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
    TextInputAction textInputAction = TextInputAction.next,
    List<String>? autofillHints,
    void Function(String)? onFieldSubmitted,
    bool allowWhitespace = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          keyboardType: TextInputType.visiblePassword,
          // The CURRENT password must accept whitespace: sign-in does, so an
          // existing password containing a space could otherwise never be
          // entered here and re-authentication always failed.
          inputFormatters: allowWhitespace
              ? const []
              : [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          onSubmitted: onFieldSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              ),
              onPressed: onToggleObscure,
            ),
          ),
        ),
      ],
    );
  }

  Widget _requirementsCard(BuildContext context, ThemeData theme) {
    final bg = theme.colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password Requirements:',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _requirementRow(
            context,
            'At least 8 characters',
            _hasMinLength,
          ),
          _requirementRow(
            context,
            'Contains uppercase letter',
            _hasUpper,
          ),
          _requirementRow(
            context,
            'Contains lowercase letter',
            _hasLower,
          ),
          _requirementRow(
            context,
            'Contains number',
            _hasDigit,
          ),
        ],
      ),
    );
  }

  Widget _requirementRow(
    BuildContext context,
    String text,
    bool isValid,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.circle_outlined,
            size: 18,
            color: isValid ? AppColors.success : AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isValid
                    ? theme.colorScheme.onSurface
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
