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
  bool _isThinking = false;
  ChatMessage? _replyTarget;

  ChatProvider(this._wsService) {
    _wsService.addMessageListener(_handleMessage);
  }

  List<ChatMessage> get messages =>
      _conversations[_currentProfileId] ?? [];
  String get currentProfileId => _currentProfileId;
  bool get isThinking => _isThinking;
  ChatMessage? get replyTarget => _replyTarget;

  /// Switch to a different profile's conversation.
  void switchProfile(String profileId) {
    _currentProfileId = profileId;
    _conversations.putIfAbsent(profileId, () => []);
    _isThinking = false;
    _replyTarget = null;
    notifyListeners();
  }

  /// Send a chat message to the current profile.
  void sendMessage(String content) {
    if (content.trim().isEmpty || _currentProfileId.isEmpty) return;

    _replyTarget = null;
    final msgId = _generateId();
    final userMsg = ChatMessage(
      id: msgId,
      profileId: _currentProfileId,
      content: content.trim(),
      role: 'user',
    );

    _getConversation().add(userMsg);
    _isThinking = true;
    notifyListeners();

    _wsService.sendChat(_currentProfileId, content.trim(), messageId: msgId);
  }

  /// Set a message to reply to (highlight it in chat).
  void setReplyTarget(ChatMessage msg) {
    _replyTarget = msg;
    notifyListeners();
  }

  /// Clear reply target.
  void clearReplyTarget() {
    _replyTarget = null;
    notifyListeners();
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
          _isThinking = false;
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
          _isThinking = false;
          notifyListeners();
        }

      case 'status':
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

  void clearConversation() {
    _conversations[_currentProfileId] = [];
    _isThinking = false;
    _replyTarget = null;
    notifyListeners();
  }

  void clearAll() {
    _conversations.clear();
    _isThinking = false;
    _replyTarget = null;
    notifyListeners();
  }
}
