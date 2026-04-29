import 'dart:async';
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

  /// Maps server-provided msg IDs → local agent response IDs.
  /// Server reuses the user's message ID for agent responses (chat_chunk/chat),
  /// so we need our own IDs to avoid overwriting user messages with agent content.
  final Map<String, String> _agentResponseIds = {};

  Timer? _historyRequestTimeout;
  String _currentProfileId = '';
  ChatMessage? _replyTarget;
  bool _isRequestingHistory = false;
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
  bool get isRequestingHistory => _isRequestingHistory;
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
    unawaited(requestHistory());
  }

  Future<void> requestHistory({bool force = false}) async {
    if (_currentProfileId.isEmpty || !_wsService.isConnected || _isRequestingHistory) {
      return;
    }

    final currentMessages = _conversations[_currentProfileId] ?? const <ChatMessage>[];
    if (!force && currentMessages.isNotEmpty) {
      return;
    }

    _setRequestingHistory(true);
    _historyRequestTimeout?.cancel();
    _historyRequestTimeout = Timer(const Duration(seconds: 4), () {
      _setRequestingHistory(false);
    });
    _wsService.requestHistory();
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty || _currentProfileId.isEmpty) return;

    final profileId = _currentProfileId;
    final conversation = _getConversation();
    final sessionId = _sessionIdForOutgoingMessage(profileId);
    final bootstrapHistory = _buildBootstrapHistory(conversation);

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
    _thinkingStates[profileId] = true;
    _reasoningTexts[profileId] = '';
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

    final sessionId = _sessionIdForOutgoingMessage(_currentProfileId);

    _wsService.cancelChat(
      _currentProfileId,
      messageId: activeMessageId,
      sessionId: sessionId,
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
        _finishHistoryRequest();
        // Server sent conversation history — merge into local conversations
        if (msg.messages != null && msg.messages!.isNotEmpty) {
          _mergeServerHistory(msg.messages!);
        }
        break;

      case 'thinking':
        // Agent received the message and started processing — show thinking indicator
        if (profileId != null) {
          if (msg.id != null && msg.id!.isNotEmpty) {
            _activeMessageIds[profileId] = msg.id;
          }
          _thinkingStates[profileId] = true;
          _reasoningTexts[profileId] = '';
          notifyListeners();
        }
        break;

      case 'chat_chunk':
        // Streaming text chunk — update agent response in-place without clearing thinking
        if (msg.content != null && profileId != null) {
          _updateSessionId(profileId, msg.sessionId);
          final conv = _getConversationFor(profileId);
          final serverId = msg.id ?? '';

          if (serverId.isNotEmpty) {
            // Look up our local agent response ID for this server-provided ID
            final localId = _agentResponseIds[serverId];
            if (localId != null) {
              // Update existing streaming agent response
              final idx = conv.indexWhere((m) => m.id == localId);
              if (idx >= 0) {
                conv[idx] = ChatMessage(
                  id: localId,
                  profileId: profileId,
                  content: msg.content!,
                  role: 'agent',
                );
              }
            } else {
              // First chunk — create new agent response with its own ID
              final newId = _generateId();
              _agentResponseIds[serverId] = newId;
              conv.add(ChatMessage(
                id: newId,
                profileId: profileId,
                content: msg.content!,
                role: 'agent',
              ));
            }
          } else {
            // No server ID — treat as one-shot non-streaming update
            conv.add(ChatMessage(
              id: _generateId(),
              profileId: profileId,
              content: msg.content!,
              role: 'agent',
            ));
          }
          // Keep thinking state — streaming is still in progress
          notifyListeners();
        }
        break;

      case 'reasoning':
        // Intermediate reasoning text from the AI
        if (profileId != null) {
          if (_updateSessionId(profileId, msg.sessionId)) {
            unawaited(_saveHistory());
          }
          if (msg.id != null && msg.id!.isNotEmpty) {
            _activeMessageIds[profileId] = msg.id;
          }

          final nextReasoning = msg.content?.trim() ?? '';
          if (nextReasoning.isNotEmpty) {
            final currentReasoning = _reasoningTexts[profileId] ?? '';
            _reasoningTexts[profileId] = _mergeReasoningText(
              currentReasoning,
              nextReasoning,
            );
          }

          _thinkingStates[profileId] = true;
          notifyListeners();
        }
        break;

      case 'chat':
        if (msg.content != null && profileId != null) {
          _updateSessionId(profileId, msg.sessionId);
          final conv = _getConversationFor(profileId);
          final serverId = msg.id ?? '';

          if (serverId.isNotEmpty) {
            final localId = _agentResponseIds.remove(serverId);
            if (localId != null) {
              // Update streaming agent response with final content
              final idx = conv.indexWhere((m) => m.id == localId);
              if (idx >= 0) {
                conv[idx] = ChatMessage(
                  id: localId,
                  profileId: profileId,
                  content: msg.content!,
                  role: 'agent',
                );
              }
            } else {
              // Batch response (no prior streaming) — add with new ID
              conv.add(ChatMessage(
                id: _generateId(),
                profileId: profileId,
                content: msg.content!,
                role: 'agent',
              ));
            }
          } else {
            // No server ID — just add as new
            conv.add(ChatMessage(
              id: _generateId(),
              profileId: profileId,
              content: msg.content!,
              role: 'agent',
            ));
          }
          // Increment unread if not the currently viewed profile
          if (profileId != _currentProfileId) {
            _unreadCounts[profileId] = (_unreadCounts[profileId] ?? 0) + 1;
          }
          _thinkingStates[profileId] = false;
          _reasoningTexts[profileId] = '';
          _activeMessageIds[profileId] = null;
          _saveHistory();
          notifyListeners();
        }
        break;

      case 'cancelled':
        if (profileId != null) {
          if (_updateSessionId(profileId, msg.sessionId)) {
            unawaited(_saveHistory());
          }
          _thinkingStates[profileId] = false;
          _reasoningTexts[profileId] = '';
          _activeMessageIds[profileId] = null;
          notifyListeners();
        }
        break;

      case 'error':
        _finishHistoryRequest();
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
        break;

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
    _agentResponseIds.clear();
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
    _agentResponseIds.clear();
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

  String? _sessionIdForOutgoingMessage(String profileId) {
    final existing = sessionIdForProfile(profileId);
    return existing.isEmpty ? null : existing;
  }

  bool _updateSessionId(String profileId, String? sessionId) {
    final normalized = sessionId?.trim() ?? '';
    if (normalized.isEmpty) {
      return false;
    }

    if (_sessionIds[profileId] == normalized) {
      return false;
    }

    _sessionIds[profileId] = normalized;
    return true;
  }

  String _mergeReasoningText(String current, String incoming) {
    if (current.isEmpty) {
      return incoming;
    }
    if (incoming.isEmpty || incoming == current) {
      return current;
    }
    if (incoming.startsWith(current)) {
      return incoming;
    }
    if (current.startsWith(incoming)) {
      return current;
    }

    final overlap = _reasoningOverlapLength(current, incoming);
    if (overlap > 1) {
      return current + incoming.substring(overlap);
    }

    final currentLast = current.substring(current.length - 1);
    final incomingFirst = incoming.substring(0, 1);
    final needsSpace =
        _isWordLike(currentLast) && _isWordLike(incomingFirst);
    return needsSpace ? '$current $incoming' : '$current$incoming';
  }

  int _reasoningOverlapLength(String current, String incoming) {
    final maxOverlap = current.length < incoming.length
        ? current.length
        : incoming.length;
    for (var length = maxOverlap; length > 0; length--) {
      if (current.substring(current.length - length) ==
          incoming.substring(0, length)) {
        return length;
      }
    }
    return 0;
  }

  bool _isWordLike(String value) {
    return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(value);
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

  void _finishHistoryRequest() {
    _historyRequestTimeout?.cancel();
    _historyRequestTimeout = null;
    _setRequestingHistory(false);
  }

  void _setRequestingHistory(bool value) {
    if (_isRequestingHistory == value) return;
    _isRequestingHistory = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _historyRequestTimeout?.cancel();
    _wsService.removeMessageListener(_handleMessage);
    super.dispose();
  }
}
