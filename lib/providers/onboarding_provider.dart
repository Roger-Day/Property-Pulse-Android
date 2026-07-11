import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists onboarding state using the same keys/semantics as iOS `OnboardingManager`.
class OnboardingProvider extends ChangeNotifier {
  OnboardingProvider();

  static const _version = '1.0';

  bool _ready = false;
  bool _isComplete = false;
  String _state = 'notStarted';
  String _userType = 'unknown';
  String _displayName = '';

  bool get ready => _ready;

  /// Mirrors iOS `shouldShowOnboardingFlow()`.
  bool get shouldShowOnboardingFlow {
    if (_isComplete) return false;
    if (_state == 'skipped') return false;
    if (_state == 'notStarted' || _state == 'inProgress') return true;
    return false;
  }

  String get userType => _userType;

  /// Name the user entered during the profile step. May be empty.
  String get displayName => _displayName;

  /// Call from `main()` before `runApp` so the first router redirect is correct.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString('onboardingVersion');
    if (savedVersion != _version) {
      await prefs.setString('onboardingVersion', _version);
      await _clearOnboardingKeys(prefs);
    }
    _isComplete = prefs.getBool('isOnboardingComplete') ?? false;
    _state = prefs.getString('onboardingState') ?? 'notStarted';
    _userType = prefs.getString('userType') ?? 'unknown';
    _displayName = prefs.getString('displayName') ?? '';
    _ready = true;
    notifyListeners();
  }

  Future<void> _persistUserType() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userType', _userType);
    notifyListeners();
  }

  Future<void> setUserType(String type) async {
    _userType = type;
    await _persistUserType();
  }

  Future<void> setDisplayName(String name) async {
    _displayName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('displayName', name);
    notifyListeners();
  }

  Future<void> markInProgress() async {
    if (_state == 'completed' || _state == 'skipped') return;
    _state = 'inProgress';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onboardingState', _state);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _state = 'completed';
    _isComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onboardingState', _state);
    await prefs.setBool('isOnboardingComplete', true);
    notifyListeners();
  }

  Future<void> skipOnboarding() async {
    _state = 'skipped';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onboardingState', _state);
    await prefs.setBool('isOnboardingComplete', false);
    notifyListeners();
  }

  Future<void> _clearOnboardingKeys(SharedPreferences prefs) async {
    await prefs.remove('onboardingState');
    await prefs.remove('completedSteps');
    await prefs.setBool('isOnboardingComplete', false);
    await prefs.remove('shouldShowOnboarding');
    await prefs.remove('userType');
    await prefs.remove('displayName');
    _isComplete = false;
    _state = 'notStarted';
    _userType = 'unknown';
    _displayName = '';
  }
}
