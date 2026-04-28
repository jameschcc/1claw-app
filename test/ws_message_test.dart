import 'package:flutter_test/flutter_test.dart';
import 'package:claw_app/models/ws_message.dart';

void main() {
  group('WsMessage', () {
    test('fromJson parses chat message', () {
      final json = {
        'type': 'chat',
        'profile_id': 'assistant',
        'content': 'Hello world',
        'id': 'msg_001',
        'timestamp': '2026-04-28T12:00:00Z',
      };

      final msg = WsMessage.fromJson(json);

      expect(msg.type, 'chat');
      expect(msg.profileId, 'assistant');
      expect(msg.content, 'Hello world');
      expect(msg.id, 'msg_001');
      expect(msg.timestamp, '2026-04-28T12:00:00Z');
    });

    test('fromJson parses status message', () {
      final json = {
        'type': 'status',
        'message': 'ok',
      };

      final msg = WsMessage.fromJson(json);

      expect(msg.type, 'status');
      expect(msg.message, 'ok');
    });

    test('fromJson parses error message', () {
      final json = {
        'type': 'error',
        'code': 'PROFILE_NOT_FOUND',
        'message': 'Profile not found',
      };

      final msg = WsMessage.fromJson(json);

      expect(msg.type, 'error');
      expect(msg.code, 'PROFILE_NOT_FOUND');
      expect(msg.message, 'Profile not found');
    });

    test('fromJson handles missing fields gracefully', () {
      final msg = WsMessage.fromJson({'type': 'ping'});

      expect(msg.type, 'ping');
      expect(msg.profileId, isNull);
      expect(msg.content, isNull);
    });

    test('toJson produces correct format', () {
      final msg = WsMessage(
        type: 'chat',
        profileId: 'assistant',
        content: 'Hello',
        id: 'msg_001',
      );

      final json = msg.toJson();

      expect(json['type'], 'chat');
      expect(json['profile_id'], 'assistant');
      expect(json['content'], 'Hello');
      expect(json['id'], 'msg_001');
    });
  });
}
