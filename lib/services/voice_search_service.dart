import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Mirrors iOS `SpeechRecognitionService` (SFSpeechRecognizer).
///
/// Usage:
///   final svc = VoiceSearchService();
///   await svc.initialize();
///   svc.addListener(() { field.text = svc.recognizedText; });
///   await svc.toggle();
class VoiceSearchService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();

  bool _initialized = false;
  bool _isListening = false;
  String _recognizedText = '';
  String? _errorMessage;

  bool get isListening => _isListening;
  String get recognizedText => _recognizedText;
  String? get errorMessage => _errorMessage;
  bool get isAvailable => _initialized;

  /// Call once before first use. Safe to call multiple times.
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _stt.initialize(
      onStatus: _onStatus,
      onError: _onError,
    );
    notifyListeners();
    return _initialized;
  }

  /// Start listening and stream partial results back via [recognizedText].
  Future<void> startListening() async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) {
        _errorMessage = 'Speech recognition not available on this device';
        notifyListeners();
        return;
      }
    }
    if (_isListening) return;

    _recognizedText = '';
    _errorMessage = null;
    _isListening = true;
    notifyListeners();

    await _stt.listen(
      onResult: _onResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: 'en_US',
      listenMode: ListenMode.search,
    );
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    await _stt.stop();
    _isListening = false;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  void clearText() {
    _recognizedText = '';
    _errorMessage = null;
    notifyListeners();
  }

  // ── Callbacks ──────────────────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    _recognizedText = result.recognizedWords;
    if (result.finalResult) {
      _isListening = false;
    }
    notifyListeners();
  }

  void _onStatus(String status) {
    // 'done' or 'notListening' means recognition ended
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
      notifyListeners();
    }
  }

  void _onError(SpeechRecognitionError error) {
    // Code 'error_speech_timeout' is normal (silence timeout) — not shown to user
    if (error.errorMsg != 'error_speech_timeout') {
      _errorMessage = error.errorMsg;
    }
    _isListening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }
}
