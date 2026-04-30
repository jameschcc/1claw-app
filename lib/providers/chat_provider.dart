import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/ws_message.dart';
import '../services/notification_service.dart';
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

  /// Per-profile draft input text — preserved across layout switches.
  final Map<String, String> _draftTexts = {};

  /// Maps server-provided msg IDs → local agent response IDs.
  /// Server reuses the user's message ID for agent responses (chat_chunk/chat),
  /// so we need our own IDs to avoid overwriting user messages with agent content.
  final Map<String, String> _agentResponseIds = {};

  /// IDs of user messages that failed to send (not connected).
  final Set<String> _failedMessageIds = {};

  /// Tracks the session id that was attached to the original outbound request.
  final Map<String, String?> _requestSessionIds = {};

  /// Pending messages queued by "稍后发送" — auto-sent when agent finishes.
  final List<String> _pendingQueue = [];

  /// Whether there are pending messages waiting to be sent.
  bool get hasPendingMessages => _pendingQueue.isNotEmpty;

  /// Number of pending messages.
  int get pendingCount => _pendingQueue.length;

  /// The pending queue items — for UI display.
  List<String> get pendingQueue => List.unmodifiable(_pendingQueue);

  /// Remove an item from pending queue by index. Returns the removed content.
  String removeFromPendingQueue(int index) {
    if (index < 0 || index >= _pendingQueue.length) return '';
    final removed = _pendingQueue.removeAt(index);
    notifyListeners();
    return removed;
  }

  /// Per-profile input history for up/down navigation (max 10 per profile).
  final Map<String, List<String>> _inputHistories = {};

  /// Get input history for a profile.
  List<String> inputHistoryForProfile(String profileId) =>
      _inputHistories[profileId] ?? [];

  /// Push content to input history (max 10). The last entry = most recent.
  void pushToInputHistory(String profileId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _inputHistories.putIfAbsent(profileId, () => []);
    final hist = _inputHistories[profileId]!;
    hist.add(trimmed);
    if (hist.length > 10) {
      hist.removeAt(0);
    }
    // Don't notify — input history is for keyboard nav, not UI display
  }

  /// Clear input history for a profile.
  void clearInputHistory(String profileId) {
    _inputHistories.remove(profileId);
  }

  /// Get chat messages for a specific profile (public access).
  List<ChatMessage> getMessagesForProfile(String profileId) =>
      _getConversationFor(profileId);

  /// Queue a message to be auto-sent when the current agent response finishes.
  void enqueueMessage(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    _pendingQueue.add(trimmed);
    notifyListeners();
  }

  /// Flush all pending messages — send them one by one.
  void _flushPendingQueue() {
    while (_pendingQueue.isNotEmpty) {
      final content = _pendingQueue.removeAt(0);
      // This triggers isThinking=true → each sendMessage will create its
      // own agent response cycle, which will flush the next queued message.
      sendMessage(content);
    }
    notifyListeners();
  }

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
  bool isMessageFailed(String msgId) => _failedMessageIds.contains(msgId);
  String? get activeMessageId => _activeMessageIds[_currentProfileId];

  int unreadCount(String profileId) => _unreadCounts[profileId] ?? 0;
  String sessionIdForProfile(String profileId) => _sessionIds[profileId] ?? '';

  /// Save draft input text for a profile — survives widget rebuilds.
  void saveDraft(String profileId, String text) {
    if (text.trim().isEmpty) {
      _draftTexts.remove(profileId);
    } else {
      _draftTexts[profileId] = text;
    }
  }

  /// Get saved draft input text for a profile.
  String getDraft(String profileId) => _draftTexts[profileId] ?? '';

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
    _wsService.requestProfileHistory(_currentProfileId);
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty || _currentProfileId.isEmpty) return;

    final profileId = _currentProfileId;
    final conversation = _getConversation();
    final sessionId = _sessionIdForOutgoingMessage(profileId);

    // If replying to a message, prepend the original content as blockquote
    if (_replyTarget != null) {
      final quoted = _replyTarget!.content;
      // Use markdown blockquote format, keeping it under reasonable length
      final quoteLines = quoted.split('\n');
      final quoteBlock = quoteLines.length > 5
          ? '> ${quoteLines.take(5).join('\n> ')}\n> ...'
          : quoteLines.map((l) => '> $l').join('\n');
      content = '$quoteBlock\n\n$content';
    }

    final bootstrapHistory = _buildBootstrapHistory(conversation);

    _replyTarget = null;
    _reasoningTexts[profileId] = '';
    final msgId = _generateId();
    final userMsg = ChatMessage(
      id: msgId,
      profileId: profileId,
      content: content.trim(),
      role: 'user',
      sessionId: sessionId,
      requestSessionId: sessionId,
    );

    conversation.add(userMsg);
    _requestSessionIds[msgId] = sessionId;
    _thinkingStates[profileId] = true;
    _reasoningTexts[profileId] = '';
    _activeMessageIds[profileId] = msgId;
    _saveHistory();
    notifyListeners();

    final sent = _wsService.sendChat(
      profileId,
      content.trim(),
      messageId: msgId,
      sessionId: sessionId,
      history: bootstrapHistory,
    );
    if (!sent) {
      _thinkingStates[profileId] = false;
      _reasoningTexts[profileId] = '';
      _activeMessageIds[profileId] = null;
      _failedMessageIds.add(msgId);
      notifyListeners();
    }
  }

  /// Re-send a previously failed message — removes the failed entry,
  /// generates a fresh message with the same content.
  void retryMessage(String msgId) {
    final conversation = _getConversation();
    final idx = conversation.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    final msg = conversation[idx];
    if (!msg.isUser) return;
    conversation.removeAt(idx);
    _failedMessageIds.remove(msgId);
    sendMessage(msg.content);
  }

  void cancelActiveResponse() {

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

      case 'profile_history':
        _finishHistoryRequest();
        // Cross-device profile history — merge into the correct profile's conversation
        if (msg.messages != null && msg.messages!.isNotEmpty) {
          debugPrint('[chat] profile_history: ${msg.messages!.length} msgs for ${msg.profileId}');
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
          _attachResolvedSessionToUserMessage(profileId, msg.id, msg.sessionId);
          final conv = _getConversationFor(profileId);
          final serverId = msg.id ?? '';
          final requestSessionId = _requestSessionIds[serverId];

          if (serverId.isNotEmpty) {
            // Look up our local agent response ID for this server-provided ID
            final localId = _agentResponseIds[serverId];
            if (localId != null) {
              // Update existing streaming agent response
              final idx = conv.indexWhere((m) => m.id == localId);
              if (idx >= 0) {
                final current = conv[idx];
                conv[idx] = ChatMessage(
                  id: localId,
                  profileId: profileId,
                  content: msg.content!,
                  role: 'agent',
                  timestamp: current.timestamp,
                  sessionId: msg.sessionId,
                  requestSessionId:
                      current.requestSessionId ?? requestSessionId,
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
                sessionId: msg.sessionId,
                requestSessionId: requestSessionId,
              ));
            }
          } else {
            // No server ID — treat as one-shot non-streaming update
            conv.add(ChatMessage(
              id: _generateId(),
              profileId: profileId,
              content: msg.content!,
              role: 'agent',
              sessionId: msg.sessionId,
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
          _attachResolvedSessionToUserMessage(profileId, msg.id, msg.sessionId);
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
          _attachResolvedSessionToUserMessage(profileId, msg.id, msg.sessionId);
          final conv = _getConversationFor(profileId);
          final serverId = msg.id ?? '';
          final requestSessionId = _requestSessionIds[serverId];

          if (serverId.isNotEmpty) {
            final localId = _agentResponseIds.remove(serverId);
            if (localId != null) {
              // Update streaming agent response with final content
              final idx = conv.indexWhere((m) => m.id == localId);
              if (idx >= 0) {
                final current = conv[idx];
                conv[idx] = ChatMessage(
                  id: localId,
                  profileId: profileId,
                  content: msg.content!,
                  role: 'agent',
                  timestamp: current.timestamp,
                  sessionId: msg.sessionId,
                  requestSessionId:
                      current.requestSessionId ?? requestSessionId,
                );
              }
            } else {
              // Batch response (no prior streaming) — add with new ID
              conv.add(ChatMessage(
                id: _generateId(),
                profileId: profileId,
                content: msg.content!,
                role: 'agent',
                sessionId: msg.sessionId,
                requestSessionId: requestSessionId,
              ));
            }
          } else {
            // No server ID — just add as new
            conv.add(ChatMessage(
              id: _generateId(),
              profileId: profileId,
              content: msg.content!,
              role: 'agent',
              sessionId: msg.sessionId,
            ));
          }
          // Increment unread if not the currently viewed profile
          if (profileId != _currentProfileId) {
            _unreadCounts[profileId] = (_unreadCounts[profileId] ?? 0) + 1;
            // Fire system notification for new agent message
            NotificationService().showMessageNotification(
              profileName: profileId,
              content: msg.content!,
            );
          }
          _thinkingStates[profileId] = false;
          _reasoningTexts[profileId] = '';
          _activeMessageIds[profileId] = null;
          _saveHistory();
          notifyListeners();

          // Auto-flush: send any queued messages now that agent is done
          if (_pendingQueue.isNotEmpty && _thinkingStates[_currentProfileId] != true) {
            _flushPendingQueue();
          }
        }
        break;

      case 'cancelled':
        if (profileId != null) {
          if (_updateSessionId(profileId, msg.sessionId)) {
            unawaited(_saveHistory());
          }
          _attachResolvedSessionToUserMessage(profileId, msg.id, msg.sessionId);
          _thinkingStates[profileId] = false;
          _reasoningTexts[profileId] = '';
          _activeMessageIds[profileId] = null;
          notifyListeners();
        }
        break;

      case 'user_message':
        // Broadcast user message from another device — insert into conversation
        if (msg.content != null && profileId != null) {
          final conv = _getConversationFor(profileId);
          // Dedup by message ID — skip if we already have this message
          if (msg.id != null && conv.any((m) => m.id == msg.id)) break;
          conv.add(ChatMessage(
            id: msg.id ?? _generateId(),
            profileId: profileId,
            content: msg.content!,
            role: 'user',
            sessionId: msg.sessionId,
          ));
          _saveHistory();
          notifyListeners();

          // Notify for messages from other devices on non-visible profiles
          if (profileId != _currentProfileId) {
            NotificationService().showMessageNotification(
              profileName: profileId,
              content: msg.content!,
            );
          }
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
            sessionId: msg.sessionId,
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
    _pendingQueue.clear();
    _conversations[_currentProfileId] = [];
    _sessionIds.remove(_currentProfileId);
    _thinkingStates[_currentProfileId] = false;
    _reasoningTexts[_currentProfileId] = '';
    _activeMessageIds[_currentProfileId] = null;
    _agentResponseIds.clear();
    _requestSessionIds.clear();
    _replyTarget = null;
    _saveHistory();
    notifyListeners();
  }

  void clearAll() {
    _pendingQueue.clear();
    _conversations.clear();
    _sessionIds.clear();
    _thinkingStates.clear();
    _reasoningTexts.clear();
    _activeMessageIds.clear();
    _agentResponseIds.clear();
    _requestSessionIds.clear();
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

  void _attachResolvedSessionToUserMessage(
    String profileId,
    String? messageId,
    String? sessionId,
  ) {
    final normalizedId = messageId?.trim() ?? '';
    final normalizedSession = sessionId?.trim() ?? '';
    if (normalizedId.isEmpty || normalizedSession.isEmpty) {
      return;
    }

    final conversation = _getConversationFor(profileId);
    final idx = conversation.indexWhere(
      (message) => message.id == normalizedId && message.isUser,
    );
    if (idx < 0) {
      return;
    }

    final current = conversation[idx];
    if (current.sessionId == normalizedSession) {
      return;
    }

    conversation[idx] = ChatMessage(
      id: current.id,
      profileId: current.profileId,
      content: current.content,
      role: current.role,
      timestamp: current.timestamp,
      sessionId: normalizedSession,
      requestSessionId: current.requestSessionId,
    );
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
