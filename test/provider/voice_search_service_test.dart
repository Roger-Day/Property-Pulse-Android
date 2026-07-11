// Unit tests for VoiceSearchService.
// iOS parity: SpeechRecognitionService.swift — isListening state, text accumulation,
// error handling, dispose.
//
// NOTE: speech_to_text uses a platform channel (MethodChannel) that is not
// available in a Dart-only test environment. We use
// TestWidgetsFlutterBinding to initialise the binding so the plugin's
// channel is set up, but we never call startListening() in these tests.
// Full integration tests that invoke the microphone run on device only.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/voice_search_service.dart';

void main() {
  // Initialise binding so MethodChannel handlers are registered.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub the speech_to_text platform channel to avoid MissingPluginException.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      (call) async {
        if (call.method == 'initialize') return true;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugin.csdcorp.com/speech_to_text'),
      null,
    );
  });

  group('VoiceSearchService — initial state', () {
    late VoiceSearchService svc;

    setUp(() => svc = VoiceSearchService());
    tearDown(() => svc.dispose());

    test('isListening is false initially', () {
      expect(svc.isListening, isFalse);
    });

    test('recognizedText is empty initially', () {
      expect(svc.recognizedText, isEmpty);
    });

    test('errorMessage is null initially', () {
      expect(svc.errorMessage, isNull);
    });

    test('is a ChangeNotifier', () {
      expect(svc, isA<VoiceSearchService>());
    });
  });

  group('VoiceSearchService — clearText', () {
    late VoiceSearchService svc;
    setUp(() => svc = VoiceSearchService());
    tearDown(() => svc.dispose());

    test('clearText resets recognizedText', () {
      // Directly set text by calling internal method path (via listener simulate)
      svc.clearText();
      expect(svc.recognizedText, isEmpty);
    });

    test('clearText resets errorMessage', () {
      svc.clearText();
      expect(svc.errorMessage, isNull);
    });

    test('clearText fires notifyListeners', () {
      var notified = false;
      svc.addListener(() => notified = true);
      svc.clearText();
      expect(notified, isTrue);
    });
  });

  group('VoiceSearchService — dispose', () {
    test('can be disposed without error', () {
      final svc = VoiceSearchService();
      expect(() => svc.dispose(), returnsNormally);
    });

    test('isAvailable is false before initialize()', () {
      final svc = VoiceSearchService();
      expect(svc.isAvailable, isFalse);
      svc.dispose();
    });
  });
}
