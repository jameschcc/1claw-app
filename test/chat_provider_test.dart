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

    test('tracks active thinking state for the pending response', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('Hello');

      expect(provider.isThinking, isTrue);
      expect(provider.reasoningText, isEmpty);
      expect(provider.activeMessageId, isNotNull);
      expect(wsService.lastSessionId, isNull);

      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-1',
          sessionId: 'sess-server-1',
          content: 'Drafting a response',
        ),
      );

      await _settleAsyncWork();

      expect(provider.isThinking, isTrue);
      expect(provider.reasoningText, 'Drafting a response');
      expect(provider.activeMessageId, 'srv-1');
      expect(provider.sessionIdForProfile('alpha'), 'sess-server-1');
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
          sessionId: 'sess-server-2',
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
          sessionId: 'sess-server-3',
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
          sessionId: 'sess-server-4',
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

    test('joins incremental reasoning chunks inline instead of new lines', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('Hello');

      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-inline-1',
          content: 'Thinking',
        ),
      );
      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-inline-1',
          content: 'about',
        ),
      );
      wsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-inline-1',
          content: 'this',
        ),
      );

      expect(provider.reasoningText, 'Thinking about this');
    });

    test('maps agent history entries to assistant for bootstrap context', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('First question');

      wsService.emit(
        WsMessage(
          type: 'chat',
          profileId: 'alpha',
          id: 'srv-7',
          sessionId: 'sess-server-history',
          content: 'First answer',
        ),
      );

      await _settleAsyncWork();
      provider.sendMessage('Second question');

      expect(wsService.lastHistory, isNotNull);
      expect(wsService.lastHistory, hasLength(2));
      _expectHistoryEntry(wsService.lastHistory![0], 'user', 'First question');
      _expectHistoryEntry(wsService.lastHistory![1], 'agent', 'First answer');
    });

    test('reuses server-provided session id after provider restart', () async {
      final firstWsService = _FakeWebSocketService();
      final firstProvider = ChatProvider(firstWsService);

      firstProvider.switchProfile('alpha');
      firstProvider.sendMessage('Hello');

      expect(firstWsService.lastSessionId, isNull);

      firstWsService.emit(
        WsMessage(
          type: 'reasoning',
          profileId: 'alpha',
          id: 'srv-5',
          sessionId: 'sess-server-persisted',
          content: 'Working on it',
        ),
      );

      await _settleAsyncWork();
      firstProvider.dispose();

      final secondWsService = _FakeWebSocketService();
      final secondProvider = ChatProvider(secondWsService);
      await _settleAsyncWork();

      secondProvider.switchProfile('alpha');
      secondProvider.sendMessage('Continue');

      expect(secondWsService.lastSessionId, 'sess-server-persisted');
    });

    test('sends recent history with follow-up messages', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('First question');

      wsService.emit(
        WsMessage(
          type: 'chat',
          profileId: 'alpha',
          id: 'srv-6',
          sessionId: 'sess-server-history',
          content: 'First answer',
        ),
      );

      await _settleAsyncWork();
      provider.sendMessage('Second question');

      expect(wsService.lastSessionId, 'sess-server-history');
      expect(wsService.lastHistory, isNotNull);
      expect(wsService.lastHistory, hasLength(2));
      _expectHistoryEntry(wsService.lastHistory![0], 'user', 'First question');
      _expectHistoryEntry(wsService.lastHistory![1], 'agent', 'First answer');
    });

    test('stores reply session and original request session for debug display', () async {
      final wsService = _FakeWebSocketService();
      final provider = ChatProvider(wsService);

      provider.switchProfile('alpha');
      provider.sendMessage('First question');

      final sentUserMessage = provider.messages.last;
      expect(sentUserMessage.isUser, isTrue);
      expect(sentUserMessage.sessionId, isNull);
      expect(sentUserMessage.requestSessionId, isNull);

      wsService.emit(
        WsMessage(
          type: 'chat',
          profileId: 'alpha',
          id: sentUserMessage.id,
          sessionId: 'sess-server-debug',
          content: 'First answer',
        ),
      );

      final updatedUserMessage = provider.messages.firstWhere(
        (message) => message.id == sentUserMessage.id,
      );
      final replyMessage = provider.messages.last;

      expect(updatedUserMessage.sessionId, 'sess-server-debug');
      expect(updatedUserMessage.requestSessionId, isNull);
      expect(replyMessage.isAgent, isTrue);
      expect(replyMessage.sessionId, 'sess-server-debug');
      expect(replyMessage.requestSessionId, isNull);
    });
  });
}

Future<void> _settleAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

class _FakeWebSocketService extends WebSocketService {
  final List<void Function(WsMessage)> _listeners = [];
  String? lastProfileId;
  String? lastContent;
  String? lastMessageId;
  String? lastSessionId;
  List<Map<String, String>>? lastHistory;

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
  }) {
    lastProfileId = profileId;
    lastContent = content;
    lastMessageId = messageId;
    lastSessionId = sessionId;
    lastHistory = history;
  }

  @override
  void cancelChat(String profileId, {String? messageId, String? sessionId}) {}

  void emit(WsMessage message) {
    for (final listener in List<void Function(WsMessage)>.from(_listeners)) {
      listener(message);
    }
  }
}

void _expectHistoryEntry(
  Map<String, String> entry,
  String role,
  String content,
) {
  expect(entry['role'], role);
  expect(entry['content'], content);
}