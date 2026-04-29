import 'package:claw_app/models/ws_message.dart';
import 'package:claw_app/providers/profiles_provider.dart';
import 'package:claw_app/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProfilesProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('ignores websocket callbacks after dispose', () async {
      final wsService = _FakeWebSocketService();
      final provider = ProfilesProvider(wsService);

      await Future<void>.delayed(Duration.zero);
      provider.dispose();

      expect(() => wsService.onConnectionChange?.call(true), returnsNormally);
      expect(
        () => wsService.emit(
          WsMessage(
            type: 'status',
            profiles: const [
              {
                'id': 'assistant',
                'name': 'Assistant',
                'emoji': '🤖',
                'description': 'General assistant',
                'color': '#0078D7',
                'online': true,
              },
            ],
          ),
        ),
        returnsNormally,
      );
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

  void emit(WsMessage message) {
    for (final listener in List<void Function(WsMessage)>.from(_listeners)) {
      listener(message);
    }
  }
}