import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/ws_message.dart';

/// WebSocket service that maintains a persistent connection to the 1Claw server.
/// Handles auto-reconnect with exponential backoff and heartbeat ping/pong.
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

  /// Update the server URL (takes effect on next connect).
  void setServerUrl(String url) {
    _serverUrl = url;
  }

  Future<void> reconnect() async {
    if (_disposed) return;
    await disconnect();
    await connect();
  }

  /// Connect to the WebSocket server.
  Future<void> connect() async {
    if (_disposed || _connected || _isConnecting) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = true;
    await _closeChannel();

    final uri = Uri.parse(_serverUrl);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    try {
      await channel.ready;
      if (_disposed || !identical(_channel, channel)) {
        await _closeChannel(channel: channel);
        return;
      }

      _setConnected(true);
      _isConnecting = false;
      _reconnectAttempt = 0;
      debugPrint('[ws] Connected to $_serverUrl');

      // Listen for messages
      _channelSubscription = channel.stream.listen(
        (data) {
          if (_disposed) return;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            final msg = WsMessage.fromJson(json);
            _handleMessage(msg);
          } catch (e) {
            debugPrint('[ws] Parse error: $e');
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
    } catch (e) {
      debugPrint('[ws] Connect error: $e');
      _isConnecting = false;
      await _closeChannel(channel: channel);
      _handleDisconnect();
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

      case 'status':
        // The "status" message should include full profile data
        // For now, we handle it as profile update
        if (msg.profiles != null) {
          // This won't be called directly since profiles is in a nested structure
          // We handle it via onMessage
        }
        break;

      case 'chat':
        // Forward chat response to the callbacks
        break;

      case 'error':
        debugPrint('[ws] Server error: ${msg.code}: ${msg.message}');
        break;
    }

    // Forward to all listeners
    for (final listener in _messageListeners) {
      listener(msg);
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
