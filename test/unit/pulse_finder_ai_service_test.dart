// Unit tests for PulseFinderAiService — specifically the client-side cap on
// how many conversation turns actually get sent to the `aiPropertyChat`
// callable per request.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_message.dart';
import 'package:property_pulse/features/pulse_finder/services/pulse_finder_ai_service.dart';
import 'package:property_pulse/services/ai/ai_gateway.dart';

// ignore_for_file: subtype_of_sealed_class

class _FakeFirebaseFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAiGateway extends AiGateway {
  _FakeAiGateway() : super(functions: _FakeFirebaseFunctions());

  Map<String, dynamic>? lastData;

  @override
  Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    lastData = data;
    return {'reply': 'ok'};
  }
}

List<PulseFinderMessage> _conversationOf(int length) => [
      for (var i = 0; i < length; i++)
        PulseFinderMessage(
          role: i.isEven ? PulseFinderRole.user : PulseFinderRole.assistant,
          text: 'turn $i',
          timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
    ];

void main() {
  group('PulseFinderAiService.sendTurn message cap', () {
    test('sends every message when the conversation is under the cap', () async {
      final gateway = _FakeAiGateway();
      final service = PulseFinderAiService(gateway);
      final messages = _conversationOf(5);

      await service.sendTurn(messages);

      final sent = gateway.lastData!['messages'] as List;
      expect(sent, hasLength(5));
      expect(sent.first['text'], 'turn 0');
      expect(sent.last['text'], 'turn 4');
    });

    /// Mirrors the server's own MAX_MESSAGES cap
    /// (functions/ai-property-chat-validation.js) — sending the full,
    /// unbounded local history past that point is just wasted upload bytes
    /// every turn for context the server would discard anyway.
    test('caps at the most recent 24 messages, dropping the oldest', () async {
      final gateway = _FakeAiGateway();
      final service = PulseFinderAiService(gateway);
      final messages = _conversationOf(30);

      await service.sendTurn(messages);

      final sent = gateway.lastData!['messages'] as List;
      expect(sent, hasLength(24));
      // Oldest 6 (turn 0..5) dropped; the most recent 24 (turn 6..29) kept,
      // in original order.
      expect(sent.first['text'], 'turn 6');
      expect(sent.last['text'], 'turn 29');
    });

    test('exactly at the cap sends all of them unchanged', () async {
      final gateway = _FakeAiGateway();
      final service = PulseFinderAiService(gateway);
      final messages = _conversationOf(24);

      await service.sendTurn(messages);

      final sent = gateway.lastData!['messages'] as List;
      expect(sent, hasLength(24));
      expect(sent.first['text'], 'turn 0');
    });
  });
}
