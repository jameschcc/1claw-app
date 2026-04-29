import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/ws_message.dart';
import '../services/websocket_service.dart';

const int _maxMessagesPerProfile = 200;
const String _cacheKey = 'chat_history_v1';

/// Manages chat messages for the active profile.
/// Persists history via SharedPreferences, auto-restores on init.
/// Supports server-side conversation sync for cross-device usage.
class ChatProvider extends ChangeNotifier {
  final WebSocketService _wsService;
  final Map<String, List<ChatMessage>> _conversations = {};
  final Map<String, int> _unreadCounts = {};
  String _currentProfileId = '';
  bool _isThinking = false;
  String _reasoningText = '';
  ChatMessage? _replyTarget;
  bool _loaded = false;

  ChatProvider(this._wsService) {
    _wsService.addMessageListener(_handleMessage);
    _loadHistory();
  }

  List<ChatMessage> get messages =>
      _conversations[_currentProfileId] ?? [];
  String get currentProfileId => _currentProfileId;
  bool get isThinking => _isThinking;
  String get reasoningText => _reasoningText;
  ChatMessage? get replyTarget => _replyTarget;
  bool get isLoaded => _loaded;

  int unreadCount(String profileId) => _unreadCounts[profileId] ?? 0;

  void switchProfile(String profileId) {
    _currentProfileId = profileId;
    _conversations.putIfAbsent(profileId, () => []);
    _unreadCounts[profileId] = 0; // clear unread
    _isThinking = false;
    _reasoningText = '';
    _replyTarget = null;
    notifyListeners();
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty || _currentProfileId.isEmpty) return;

    _replyTarget = null;
    _reasoningText = '';
    final msgId = _generateId();
    final userMsg = ChatMessage(
      id: msgId,
      profileId: _currentProfileId,
      content: content.trim(),
      role: 'user',
    );

    _getConversation().add(userMsg);
    _isThinking = true;
    _saveHistory();
    notifyListeners();

    _wsService.sendChat(_currentProfileId, content.trim(), messageId: msgId);
  }

  void setReplyTarget(ChatMessage msg) {
    _replyTarget = msg;
    notifyListeners();
  }

  void clearReplyTarget() {
    _replyTarget = null;
    notifyListeners();
  }

  void _handleMessage(WsMessage msg) {
    switch (msg.type) {
      case 'conversation':
        debugPrint('[chat] Server assigned conversation: ${msg.conversationId}');
        break;

      case 'history':
        // Server sent conversation history — merge into local conversations
        if (msg.messages != null && msg.messages!.isNotEmpty) {
          _mergeServerHistory(msg.messages!);
        }
        break;

      case 'reasoning':
        // Intermediate reasoning text from the AI
        if (msg.content != null && msg.profileId == _currentProfileId) {
          final nextReasoning = msg.content!.trim();
          if (nextReasoning.isEmpty) {
            break;
          }

          if (_reasoningText.isEmpty || nextReasoning.startsWith(_reasoningText)) {
            _reasoningText = nextReasoning;
          } else if (!_reasoningText.contains(nextReasoning)) {
            _reasoningText = '$_reasoningText\n$nextReasoning';
          }
          _isThinking = true;
          notifyListeners();
        }

      case 'chat':
        if (msg.content != null && msg.profileId != null) {
          final agentMsg = ChatMessage(
            id: msg.id ?? _generateId(),
            profileId: msg.profileId!,
            content: msg.content!,
            role: 'agent',
          );
          _getConversationFor(msg.profileId!).add(agentMsg);
          // Increment unread if not the currently viewed profile
          if (msg.profileId != _currentProfileId) {
            _unreadCounts[msg.profileId!] =
                (_unreadCounts[msg.profileId!] ?? 0) + 1;
          }
          _isThinking = false;
          _saveHistory();
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
          _reasoningText = '';
          _saveHistory();
          notifyListeners();
        }

      case 'status':
      case 'pong':
        break;
    }
  }

  /// Merge server history into local conversations.
  /// Prevents duplicates by checking message IDs, prefers server messages
  /// over local (SharedPreferences) for consistency across devices.
  void _mergeServerHistory(List<ChatMessage> serverMessages) {
    bool changed = false;

    for (final serverMsg in serverMessages) {
      final pid = serverMsg.profileId;
      final conv = _getConversationFor(pid);

      // Skip if we already have this message by ID
      if (conv.any((m) => m.id == serverMsg.id)) continue;

      // Find insertion point by timestamp
      int insertAt = conv.length;
      for (int i = 0; i < conv.length; i++) {
        if (conv[i].timestamp.isAfter(serverMsg.timestamp)) {
          insertAt = i;
          break;
        }
      }
      conv.insert(insertAt, serverMsg);
      changed = true;
    }

    if (changed) {
      _saveHistory();
      notifyListeners();
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

  // --- Persistence ---

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = <String, List<Map<String, dynamic>>>{};
      for (final e in _conversations.entries) {
        if (e.value.isEmpty) continue;
        // Trim old messages
        final kept = e.value.length > _maxMessagesPerProfile
            ? e.value.sublist(e.value.length - _maxMessagesPerProfile)
            : e.value;
        all[e.key] = kept.map((m) => m.toJson()).toList();
      }
      await prefs.setString(_cacheKey, jsonEncode(all));
    } catch (e) {
      debugPrint('[chat] save error: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;

      final all = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in all.entries) {
        final list = (e.value as List)
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          _conversations[e.key] = list;
        }
      }
      _loaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[chat] load error: $e');
    }
  }

  void clearConversation() {
    _conversations[_currentProfileId] = [];
    _isThinking = false;
    _reasoningText = '';
    _replyTarget = null;
    _saveHistory();
    notifyListeners();
  }

  void clearAll() {
    _conversations.clear();
    _isThinking = false;
    _reasoningText = '';
    _replyTarget = null;
    _saveHistory();
    notifyListeners();
  }

  /// Get the last message preview for a given profile (for sidebar).
  /// Returns empty string if no messages. Trims newlines for single-line preview.
  String getLastMessageForProfile(String profileId) {
    final msgs = _conversations[profileId];
    if (msgs == null || msgs.isEmpty) return '';
    final lastMsg = msgs.last;
    final prefix = lastMsg.isUser ? 'You: ' : '';
    final content = lastMsg.content.replaceAll('\n', ' ').trim();
    if (content.length > 60) return '$prefix${content.substring(0, 60)}...';
    return '$prefix$content';
  }
}
