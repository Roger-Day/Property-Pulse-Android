import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

/// Firebase Phone Auth: request SMS → enter code → signed in.
class PhoneSignInScreen extends StatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    AuthService.instance.clearPhoneVerificationId();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter a phone number with country code (e.g. +15551234567)');
      return;
    }
    final e164 = raw.startsWith('+') ? raw : '+$raw';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().startPhoneVerification(
            phoneNumber: e164,
            onCodeSent: (_) {
              if (mounted) {
                setState(() {
                  _codeSent = true;
                  _busy = false;
                });
              }
            },
          );
    } on FirebaseAuthException catch (ex) {
      if (mounted) {
        setState(() {
          _error = ex.message ?? ex.code;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().submitPhoneSmsCode(_codeCtrl.text);
      if (!mounted) return;
      context.go('/home');
    } on FirebaseAuthException catch (ex) {
      setState(() {
        _error = ex.message ?? ex.code;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in with phone')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Use your phone number in international format (include country code, e.g. +1…). '
                'Phone sign-in must be enabled in Firebase Console → Authentication → Sign-in method.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction:
                    _codeSent ? TextInputAction.done : TextInputAction.next,
                enabled: !_codeSent && !_busy,
                onSubmitted: (_) {
                  if (!_codeSent && !_busy) _sendCode();
                },
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+15551234567',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (!_codeSent) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _sendCode,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send SMS code'),
                ),
              ],
              if (_codeSent) ...[
                const SizedBox(height: 20),
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _verifyCode(),
                  decoration: const InputDecoration(
                    labelText: 'SMS code',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _verifyCode,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify and sign in'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          context.read<AuthProvider>().clearPhoneVerification();
                          setState(() {
                            _codeSent = false;
                            _codeCtrl.clear();
                          });
                        },
                  child: const Text('Use a different number'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.go('/auth'),
                child: const Text('Back to email sign in'),
              ),
            ],
          ),        // Column
        ),          // SingleChildScrollView
      ),            // SafeArea
    ),              // GestureDetector
  );                // Scaffold
  }
}
