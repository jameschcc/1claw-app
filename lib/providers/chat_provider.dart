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
/// Supports server-side conversation sync for cross-device usage.
class ChatProvider extends ChangeNotifier {
  final WebSocketService _wsService;
  final Map<String, List<ChatMessage>> _conversations = {};
  final Map<String, int> _unreadCounts = {};
  final Map<String, String> _sessionIds = {};
  final Map<String, bool> _thinkingStates = {};
  final Map<String, String> _reasoningTexts = {};
  final Map<String, String?> _activeMessageIds = {};
  String _currentProfileId = '';
  ChatMessage? _replyTarget;
  bool _loaded = false;

  ChatProvider(this._wsService) {
    _wsService.addMessageListener(_handleMessage);
    _loadHistory();
  }

  List<ChatMessage> get messages => _conversations[_currentProfileId] ?? [];
  String get currentProfileId => _currentProfileId;
  bool get isThinking => _thinkingStates[_currentProfileId] ?? false;
  String get reasoningText => _reasoningTexts[_currentProfileId] ?? '';
  ChatMessage? get replyTarget => _replyTarget;
  bool get isLoaded => _loaded;
  String? get activeMessageId => _activeMessageIds[_currentProfileId];

  int unreadCount(String profileId) => _unreadCounts[profileId] ?? 0;
  String sessionIdForProfile(String profileId) => _sessionIds[profileId] ?? '';

  void switchProfile(String profileId) {
    _currentProfileId = profileId;
    _conversations.putIfAbsent(profileId, () => []);
    _unreadCounts[profileId] = 0; // clear unread
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
    _reasoningTexts[profileId] = '';
    final msgId = _generateId();
    final userMsg = ChatMessage(
      id: msgId,
      profileId: profileId,
      content: content.trim(),
      role: 'user',
    );

    conversation.add(userMsg);
    _thinkingStates[profileId] = false;
    _activeMessageIds[profileId] = msgId;
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
    if (!isThinking || _currentProfileId.isEmpty) return;

    _wsService.cancelChat(
      _currentProfileId,
      messageId: activeMessageId,
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
    final profileId = msg.profileId;

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
        if (profileId != null && msg.sessionId != null) {
          _sessionIds[profileId] = msg.sessionId!;
        }
        if (profileId != null && msg.content != null) {
          if (msg.id != null && msg.id!.isNotEmpty) {
            _activeMessageIds[profileId] = msg.id;
          }
          final nextReasoning = msg.content!.trim();
          if (nextReasoning.isEmpty) {
            break;
          }

          final currentReasoning = _reasoningTexts[profileId] ?? '';
          if (currentReasoning.isEmpty ||
              nextReasoning.startsWith(currentReasoning)) {
            _reasoningTexts[profileId] = nextReasoning;
          } else if (!currentReasoning.contains(nextReasoning)) {
            _reasoningTexts[profileId] = '$currentReasoning\n$nextReasoning';
          }
          _thinkingStates[profileId] = true;
          notifyListeners();
        }

      case 'chat':
        if (msg.content != null && profileId != null) {
          if (msg.sessionId != null && msg.sessionId!.isNotEmpty) {
            _sessionIds[profileId] = msg.sessionId!;
          }
          final agentMsg = ChatMessage(
            id: msg.id ?? _generateId(),
            profileId: profileId,
            content: msg.content!,
            role: 'agent',
          );
          _getConversationFor(profileId).add(agentMsg);
          // Increment unread if not the currently viewed profile
          if (profileId != _currentProfileId) {
            _unreadCounts[profileId] = (_unreadCounts[profileId] ?? 0) + 1;
          }
          _thinkingStates[profileId] = false;
          _activeMessageIds[profileId] = null;
          _saveHistory();
          notifyListeners();
        }

      case 'cancelled':
        if (profileId != null && msg.sessionId != null) {
          _sessionIds[profileId] = msg.sessionId!;
        }
        if (profileId != null) {
          _thinkingStates[profileId] = false;
          _reasoningTexts[profileId] = '';
          _activeMessageIds[profileId] = null;
          notifyListeners();
        }

      case 'error':
        debugPrint('[chat] Error: ${msg.code}: ${msg.message}');
        if (profileId != null) {
          final errorMsg = ChatMessage(
            id: _generateId(),
            profileId: profileId,
            content: '⚠️ Error: ${msg.message ?? "Unknown error"}',
            role: 'agent',
          );
          _getConversationFor(profileId).add(errorMsg);
          _thinkingStates[profileId] = false;
          _reasoningTexts[profileId] = '';
          _activeMessageIds[profileId] = null;
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
    _thinkingStates[_currentProfileId] = false;
    _reasoningTexts[_currentProfileId] = '';
    _activeMessageIds[_currentProfileId] = null;
    _replyTarget = null;
    _saveHistory();
    notifyListeners();
  }

  void clearAll() {
    _conversations.clear();
    _sessionIds.clear();
    _thinkingStates.clear();
    _reasoningTexts.clear();
    _activeMessageIds.clear();
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
