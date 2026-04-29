import 'package:claw_app/models/ws_message.dart';
import 'package:claw_app/providers/chat_provider.dart';
import 'package:claw_app/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ChatProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('enters thinking only after server reasoning event', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('Hello');

      expect(provider.isThinking, isFalse);
      expect(provider.reasoningText, isEmpty);
      expect(provider.activeMessageId, isNotNull);

      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-1',
          content: 'Drafting a response',
        ),
      );

      expect(provider.isThinking, isTrue);
      expect(provider.reasoningText, 'Drafting a response');
      expect(provider.activeMessageId, 'srv-1');
    });

    test('preserves thinking state when switching profiles', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('Hello');
      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-2',
          content: 'Drafting a response',
        ),
      );

      expect(provider.isThinking, isTrue);
      expect(provider.reasoningText, 'Drafting a response');
      expect(provider.activeMessageId, isNotNull);

      provider.switchProfile('beta');

      expect(provider.isThinking, isFalse);
      expect(provider.reasoningText, isEmpty);
      expect(provider.activeMessageId, isNull);

      provider.switchProfile('alpha');

      expect(provider.isThinking, isTrue);
      expect(provider.reasoningText, 'Drafting a response');
      expect(provider.activeMessageId, 'srv-2');
    });

    test('leaves thinking when server sends final chat while inactive', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('Hello');
      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-3',
          content: 'Drafting a response',
        ),
      );

      provider.switchProfile('beta');
      wsService.emit(
        WsMessage(
          type: 'chat',
          profileId: 'alpha',
          id: 'srv-3',
          content: 'Done',
        ),
      );

      provider.switchProfile('alpha');

      expect(provider.isThinking, isFalse);
      expect(provider.reasoningText, isEmpty);
      expect(provider.activeMessageId, isNull);
    });

    test('clears thinking bubble state when final chat arrives', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('Hello');
      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-4',
          content: 'Drafting a response',
        ),
      );

      expect(provider.isThinking, isTrue);
      expect(provider.reasoningText, isNotEmpty);

      wsService.emit(
        WsMessage(
          type: 'chat',
          profileId: 'alpha',
          id: 'srv-4',
          content: 'Done',
        ),
      );

      expect(provider.isThinking, isFalse);
      expect(provider.reasoningText, isEmpty);
      expect(provider.messages.last.content, 'Done');
    });
  });
}

class _FakeWebSocketService extends WebSocketService {
  final List<void Function(WsMessage)> _listeners = [];

  @override
  void addMessageListener(void Function(WsMessage) listener) {
    _listeners.add(listener);
  }

  @override
  void removeMessageListener(void Function(WsMessage) listener) {
    _listeners.remove(listener);
  }

  @override
  void sendChat(
    String profileId,
    String content, {
    String? messageId,
    String? sessionId,
    List<Map<String, String>>? history,
  }) {}

  @override
  void cancelChat(String profileId, {String? messageId, String? sessionId}) {}

  void emit(WsMessage message) {
    for (final listener in List<void Function(WsMessage)>.from(_listeners)) {
      listener(message);
    }
  }
}