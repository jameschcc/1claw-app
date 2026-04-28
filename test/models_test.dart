import 'package:flutter_test/flutter_test.dart';
import 'package:claw_app/models/agent_profile.dart';
import 'package:claw_app/models/chat_message.dart';

void main() {
  group('AgentProfile', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'test',
        'name': 'Test Agent',
        'emoji': '🧪',
        'description': 'A test agent',
        'color': '#FF0000',
        'online': true,
      };

      final profile = AgentProfile.fromJson(json);

      expect(profile.id, 'test');
      expect(profile.name, 'Test Agent');
      expect(profile.emoji, '🧪');
      expect(profile.description, 'A test agent');
      expect(profile.color, '#FF0000');
      expect(profile.online, true);
    });

    test('toJson produces correct output', () {
      final profile = AgentProfile(
        id: 'test',
        name: 'Test',
        emoji: '🧪',
        description: 'Test desc',
        color: '#00FF00',
        online: true,
      );

      final json = profile.toJson();

      expect(json['id'], 'test');
      expect(json['name'], 'Test');
      expect(json['color'], '#00FF00');
      expect(json['online'], true);
    });

    test('colorValue parses hex correctly', () {
      final profile = AgentProfile(
        id: 'test',
        name: 'Test',
        emoji: '🧪',
        description: 'Test',
        color: '#FF0000',
      );
      // FF0000 → ARGB: 0xFFFF0000
      expect(profile.colorValue, 0xFFFF0000);
    });

    test('default color when no color provided', () {
      final profile = AgentProfile(
        id: 'test',
        name: 'Test',
        emoji: '🧪',
        description: 'Test',
      );
      expect(profile.colorValue, 0xFF0078D7);
    });
  });

  group('ChatMessage', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'msg_001',
        'profile_id': 'assistant',
        'content': 'Hello!',
        'role': 'agent',
        'timestamp': '2026-04-28T12:00:00.000',
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.id, 'msg_001');
      expect(msg.profileId, 'assistant');
      expect(msg.content, 'Hello!');
      expect(msg.role, 'agent');
      expect(msg.isAgent, true);
      expect(msg.isUser, false);
    });

    test('toJson produces correct output', () {
      final msg = ChatMessage(
        id: 'msg_001',
        profileId: 'user',
        content: 'Hi',
        role: 'user',
      );

      final json = msg.toJson();

      expect(json['id'], 'msg_001');
      expect(json['profile_id'], 'user');
      expect(json['content'], 'Hi');
      expect(json['role'], 'user');
    });

    test('isUser and isAgent correct', () {
      final userMsg = ChatMessage(
        id: '1',
        profileId: 'test',
        content: 'Hello',
        role: 'user',
      );
      final agentMsg = ChatMessage(
        id: '2',
        profileId: 'test',
        content: 'Hi',
        role: 'agent',
      );

      expect(userMsg.isUser, true);
      expect(userMsg.isAgent, false);
      expect(agentMsg.isAgent, true);
      expect(agentMsg.isUser, false);
    });
  });
}
