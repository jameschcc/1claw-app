import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/ws_message.dart';
import '../services/websocket_service.dart';

const int _maxMessagesPerProfile = 200;
const String _cacheKey = 'chat_history_v1';
const String _sessionCacheKey = 'chat_session_ids_v1';
const int _bootstrapMessageLimit = 20;
const int _bootstrapContentLimit = 500;

/// Manages chat messages for the active profile.
/// Persists history via SharedPreferences, auto-restores on init.
class ChatProvider extends ChangeNotifier {
  final WebSocketService _wsService;
  final Map<String, List<ChatMessage>> _conversations = {};
  final Map<String, int> _unreadCounts = {};
  final Map<String, String> _sessionIds = {};
  String _currentProfileId = '';
  bool _isThinking = false;
  String _reasoningText = '';
  String? _activeMessageId;
  ChatMessage? _replyTarget;
  bool _loaded = false;

  ChatProvider(this._wsService) {
    _wsService.addMessageListener(_handleMessage);
    _loadHistory();
  }

  List<ChatMessage> get messages => _conversations[_currentProfileId] ?? [];
  String get currentProfileId => _currentProfileId;
  bool get isThinking => _isThinking;
  String get reasoningText => _reasoningText;
  ChatMessage? get replyTarget => _replyTarget;
  bool get isLoaded => _loaded;
  String? get activeMessageId => _activeMessageId;

  int unreadCount(String profileId) => _unreadCounts[profileId] ?? 0;
  String sessionIdForProfile(String profileId) => _sessionIds[profileId] ?? '';

  void switchProfile(String profileId) {
    _currentProfileId = profileId;
    _conversations.putIfAbsent(profileId, () => []);
    _unreadCounts[profileId] = 0; // clear unread
    _isThinking = false;
    _reasoningText = '';
    _activeMessageId = null;
    _replyTarget = null;
    notifyListeners();
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty || _currentProfileId.isEmpty) return;

    final profileId = _currentProfileId;
    final conversation = _getConversation();
    final hadSessionId = sessionIdForProfile(profileId).isNotEmpty;
    final sessionId = _ensureSessionId(profileId);
    final bootstrapHistory = hadSessionId
        ? null
        : _buildBootstrapHistory(conversation);

    _replyTarget = null;
    _reasoningText = '';
    final msgId = _generateId();
    final userMsg = ChatMessage(
      id: msgId,
      profileId: profileId,
      content: content.trim(),
      role: 'user',
    );

    conversation.add(userMsg);
    _isThinking = true;
    _activeMessageId = msgId;
    _saveHistory();
    notifyListeners();

    _wsService.sendChat(
      profileId,
      content.trim(),
      messageId: msgId,
      sessionId: sessionId,
      history: bootstrapHistory,
    );
  }

  void cancelActiveResponse() {
    if (!_isThinking || _currentProfileId.isEmpty) return;

    _wsService.cancelChat(
      _currentProfileId,
      messageId: _activeMessageId,
      sessionId: sessionIdForProfile(_currentProfileId),
    );
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
      case 'reasoning':
        // Intermediate reasoning text from the AI
        if (msg.profileId != null && msg.sessionId != null) {
          _sessionIds[msg.profileId!] = msg.sessionId!;
        }
        if (msg.content != null && msg.profileId == _currentProfileId) {
          final nextReasoning = msg.content!.trim();
          if (nextReasoning.isEmpty) {
            break;
          }

          if (_reasoningText.isEmpty ||
              nextReasoning.startsWith(_reasoningText)) {
            _reasoningText = nextReasoning;
          } else if (!_reasoningText.contains(nextReasoning)) {
            _reasoningText = '$_reasoningText\n$nextReasoning';
          }
          _isThinking = true;
          notifyListeners();
        }

      case 'chat':
        if (msg.content != null && msg.profileId != null) {
          if (msg.sessionId != null && msg.sessionId!.isNotEmpty) {
            _sessionIds[msg.profileId!] = msg.sessionId!;
          }
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
          _activeMessageId = null;
          _saveHistory();
          notifyListeners();
        }

      case 'cancelled':
        if (msg.profileId != null && msg.sessionId != null) {
          _sessionIds[msg.profileId!] = msg.sessionId!;
        }
        if (msg.profileId == _currentProfileId) {
          _isThinking = false;
          _reasoningText = '';
          _activeMessageId = null;
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
          _activeMessageId = null;
          _saveHistory();
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
      await prefs.setString(_sessionCacheKey, jsonEncode(_sessionIds));
    } catch (e) {
      debugPrint('[chat] save error: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final all = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in all.entries) {
          final list = (e.value as List)
              .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
              .toList();
          if (list.isNotEmpty) {
            _conversations[e.key] = list;
          }
        }
      }

      final rawSessions = prefs.getString(_sessionCacheKey);
      if (rawSessions != null && rawSessions.isNotEmpty) {
        final decoded = jsonDecode(rawSessions) as Map<String, dynamic>;
        for (final e in decoded.entries) {
          final value = e.value?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            _sessionIds[e.key] = value;
          }
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
    _sessionIds.remove(_currentProfileId);
    _isThinking = false;
    _reasoningText = '';
    _activeMessageId = null;
    _replyTarget = null;
    _saveHistory();
    notifyListeners();
  }

  void clearAll() {
    _conversations.clear();
    _sessionIds.clear();
    _isThinking = false;
    _reasoningText = '';
    _activeMessageId = null;
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

  String _ensureSessionId(String profileId) {
    final existing = sessionIdForProfile(profileId);
    if (existing.isNotEmpty) return existing;

    final sessionId =
        'sess_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
    _sessionIds[profileId] = sessionId;
    return sessionId;
  }

  List<Map<String, String>>? _buildBootstrapHistory(
    List<ChatMessage> messages,
  ) {
    if (messages.isEmpty) return null;

    final start = messages.length > _bootstrapMessageLimit
        ? messages.length - _bootstrapMessageLimit
        : 0;
    final recent = messages.sublist(start);
    return recent
        .map(
          (msg) => {
            'role': msg.role,
            'content': _trimBootstrapContent(msg.content),
          },
        )
        .toList();
  }

  String _trimBootstrapContent(String content) {
    final trimmed = content.trim();
    if (trimmed.length <= _bootstrapContentLimit) {
      return trimmed;
    }
    return '${trimmed.substring(0, _bootstrapContentLimit)}...';
  }
}
