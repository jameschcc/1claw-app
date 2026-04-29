import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/ws_message.dart';

/// WebSocket service that maintains a persistent connection to the 1Claw server.
/// Handles auto-reconnect with exponential backoff and heartbeat ping/pong.
/// Supports cross-device conversations via a persistent client_id.
class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  String _serverUrl = 'ws://localhost:8080/ws';
  bool _connected = false;
  bool _isConnecting = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  static const int _maxReconnectDelay = 30; // seconds

  /// Persistent client ID for cross-device conversation identification.
  String? _clientId;

  /// Conversation ID assigned by the server.
  String? conversationId;

  /// Callback when connection state changes.
  void Function(bool connected)? onConnectionChange;

  /// Message listeners (multiple, not overwritten).
  final List<void Function(WsMessage)> _messageListeners = [];

  /// Register a listener for incoming messages.
  void addMessageListener(void Function(WsMessage) listener) {
    _messageListeners.add(listener);
  }

  /// Remove a previously registered listener.
  void removeMessageListener(void Function(WsMessage) listener) {
    _messageListeners.remove(listener);
  }

  WebSocketService();

  String get serverUrl => _serverUrl;
  bool get isConnected => _connected;
  String? get clientId => _clientId;

  /// Update the server URL (takes effect on next connect).
  void setServerUrl(String url) {
    _serverUrl = url;
  }

  /// Get or generate a persistent client ID from SharedPreferences.
  Future<String> _ensureClientId() async {
    if (_clientId != null) return _clientId!;
    final prefs = await SharedPreferences.getInstance();
    const key = '1claw_client_id';
    var id = prefs.getString(key);
    if (id == null || id.isEmpty) {
      id = 'client_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      await prefs.setString(key, id);
    }
    _clientId = id;
    return id;
  }

  /// Force a reconnect using the current server URL and client id.
  /// Returns true if connection was established, false if failed or disposed.
  Future<bool> reconnect() async {
    if (_disposed) return false;
    await disconnect();
    return await connect();
  }

  /// Connect to the WebSocket server.
  /// Returns true if connected successfully, false otherwise.
  Future<bool> connect() async {
    if (_disposed || _connected || _isConnecting) return false;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = true;
    await _closeChannel();

    final clientId = await _ensureClientId();
    final baseUri = Uri.parse(_serverUrl);
    final uri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'client_id': clientId,
      },
    );
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    try {
      await channel.ready.timeout(const Duration(seconds: 5));
      if (_disposed || !identical(_channel, channel)) {
        await _closeChannel(channel: channel);
        return false;
      }

      _setConnected(true);
      _isConnecting = false;
      _reconnectAttempt = 0;
      debugPrint('[ws] Connected as $clientId to $_serverUrl');

      // Listen for messages
      _channelSubscription = channel.stream.listen(
        (data) {
          if (_disposed) return;
          WsMessage msg;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            msg = WsMessage.fromJson(json);
          } catch (e) {
            debugPrint('[ws] Parse error: $e');
            return;
          }

          try {
            _handleMessage(msg);
          } catch (e) {
            debugPrint('[ws] Message handling error: $e');
          }
        },
        onError: (error) {
          debugPrint('[ws] Error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[ws] Connection closed');
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      // Start heartbeat
      _startHeartbeat();
      return true;
    } on TimeoutException {
      debugPrint('[ws] Connect timeout');
      _isConnecting = false;
      await _closeChannel(channel: channel);
      _handleDisconnect();
      return false;
    } catch (e) {
      debugPrint('[ws] Connect error: $e');
      _isConnecting = false;
      await _closeChannel(channel: channel);
      _handleDisconnect();
      return false;
    }
  }

  /// Disconnect from the server.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = false;
    _setConnected(false);
    await _closeChannel();
  }

  Future<void> _closeChannel({WebSocketChannel? channel}) async {
    _stopHeartbeat();

    final targetChannel = channel ?? _channel;
    if (channel == null) {
      final subscription = _channelSubscription;
      _channelSubscription = null;
      await subscription?.cancel();
      _channel = null;
    }

    try {
      await targetChannel?.sink.close();
    } catch (_) {}
  }

  /// Send a chat message to a specific agent profile.
  void sendChat(
    String profileId,
    String content, {
    String? messageId,
    String? sessionId,
    List<Map<String, String>>? history,
  }) {
    if (!_connected) {
      debugPrint('[ws] Cannot send: not connected');
      return;
    }
    final msg = WsMessage(
      type: 'chat',
      profileId: profileId,
      content: content,
      id: messageId ?? _generateId(),
      sessionId: sessionId,
      history: history,
    );
    _send(msg);
  }

  /// Request cancellation of the in-flight response for a session.
  void cancelChat(String profileId, {String? messageId, String? sessionId}) {
    if (!_connected) {
      debugPrint('[ws] Cannot cancel: not connected');
      return;
    }

    final msg = WsMessage(
      type: 'cancel_chat',
      profileId: profileId,
      id: messageId,
      sessionId: sessionId,
    );
    _send(msg);
  }

  /// Switch the active profile.
  void switchProfile(String profileId) {
    if (!_connected) return;
    final msg = WsMessage(type: 'switch_profile', profileId: profileId);
    _send(msg);
  }

  /// Request current status from the server.
  void requestStatus() {
    if (!_connected) return;
    _send(WsMessage(type: 'get_status'));
  }

  /// Request recent conversation history from the server.
  void requestHistory() {
    if (!_connected) return;
    _send(WsMessage(type: 'get_history'));
  }

  /// Send a raw JSON-serializable object.
  void _send(WsMessage msg) {
    try {
      _channel?.sink.add(jsonEncode(msg.toJson()));
    } catch (e) {
      debugPrint('[ws] Send error: $e');
    }
  }

  void _handleMessage(WsMessage msg) {
    switch (msg.type) {
      case 'pong':
        // Heartbeat response — no action needed
        break;

      case 'conversation':
        // Server assigned a conversation ID
        if (msg.conversationId != null) {
          conversationId = msg.conversationId;
          debugPrint('[ws] Conversation: $conversationId');
        }
        break;

      case 'chat':
        // Forward chat response to the callbacks
        break;

      case 'history':
        // Server sent conversation history — will be handled by listeners
        break;

      case 'error':
        debugPrint('[ws] Server error: ${msg.code}: ${msg.message}');
        break;
    }

    // Forward to all listeners
    for (final listener in List<void Function(WsMessage)>.from(_messageListeners)) {
      try {
        listener(msg);
      } catch (e) {
        debugPrint('[ws] Listener error: $e');
      }
    }
  }

  void _handleDisconnect() {
    _isConnecting = false;
    _setConnected(false);
    unawaited(_closeChannel());

    if (!_disposed && _reconnectTimer?.isActive != true) {
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_connected) {
        _send(WsMessage(type: 'ping'));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (_disposed || _connected || _isConnecting || _reconnectTimer?.isActive == true) {
      return;
    }

    _reconnectTimer?.cancel();
    final delay = min(pow(2, _reconnectAttempt).toInt(), _maxReconnectDelay);
    _reconnectAttempt++;
    debugPrint('[ws] Reconnecting in ${delay}s (attempt $_reconnectAttempt)');
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_disposed && !_connected) {
        connect();
      }
    });
  }

  String _generateId() {
    final r = Random();
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${r.nextInt(9999)}';
  }

  /// Dispose the service — call when app is shutting down.
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(disconnect());
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnectionChange?.call(value);
  }
}
