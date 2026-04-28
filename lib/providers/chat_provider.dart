import 'dart:math';

import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';
import '../models/ws_message.dart';
import '../services/websocket_service.dart';

/// Manages chat messages for the active profile.
/// Stores messages in memory and sends/receives via WebSocket.
class ChatProvider extends ChangeNotifier {
  final WebSocketService _wsService;
  final Map<String, List<ChatMessage>> _conversations = {};
  String _currentProfileId = '';

  ChatProvider(this._wsService) {
    _wsService.addMessageListener(_handleMessage);
  }

  List<ChatMessage> get messages {
    return _conversations[_currentProfileId] ?? [];
  }

  String get currentProfileId => _currentProfileId;

  /// Switch to a different profile's conversation.
  void switchProfile(String profileId) {
    _currentProfileId = profileId;
    if (!_conversations.containsKey(profileId)) {
      _conversations[profileId] = [];
    }
    notifyListeners();
  }

  /// Send a chat message to the current profile.
  void sendMessage(String content) {
    if (content.trim().isEmpty || _currentProfileId.isEmpty) return;

    final msgId = _generateId();
    final userMsg = ChatMessage(
      id: msgId,
      profileId: _currentProfileId,
      content: content.trim(),
      role: 'user',
    );

    _getConversation().add(userMsg);
    notifyListeners();

    _wsService.sendChat(_currentProfileId, content.trim(), messageId: msgId);
  }

  /// Handle incoming WebSocket messages.
  void _handleMessage(WsMessage msg) {
    switch (msg.type) {
      case 'chat':
        if (msg.content != null && msg.profileId != null) {
          final agentMsg = ChatMessage(
            id: msg.id ?? _generateId(),
            profileId: msg.profileId!,
            content: msg.content!,
            role: 'agent',
          );
          _getConversationFor(msg.profileId!).add(agentMsg);
          notifyListeners();
        }

      case 'error':
        debugPrint('[chat] Error: ${msg.code}: ${msg.message}');
        if (msg.profileId != null) {
          final errorMsg = ChatMessage(
            id: _generateId(),
            profileId: msg.profileId!,
            content: '⚠️ Error: ${msg.message ?? "Unknown error"}',
            role: 'agent',
          );
          _getConversationFor(msg.profileId!).add(errorMsg);
          notifyListeners();
        }

      case 'status':
        // Profile status update — handled by ProfilesProvider
        break;

      case 'pong':
        break;
    }
  }

  List<ChatMessage> _getConversation() {
    _conversations.putIfAbsent(_currentProfileId, () => []);
    return _conversations[_currentProfileId]!;
  }

  List<ChatMessage> _getConversationFor(String profileId) {
    _conversations.putIfAbsent(profileId, () => []);
    return _conversations[profileId]!;
  }

  String _generateId() {
    final r = Random();
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(9999)}';
  }

  /// Clear all messages for the current profile.
  void clearConversation() {
    _conversations[_currentProfileId] = [];
    notifyListeners();
  }

  /// Clear all conversations.
  void clearAll() {
    _conversations.clear();
    notifyListeners();
  }
}
