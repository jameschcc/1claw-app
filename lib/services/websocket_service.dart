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
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  String _serverUrl = 'ws://localhost:8080/ws';
  bool _connected = false;
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

  /// Connect to the WebSocket server.
  Future<void> connect() async {
    if (_disposed) return;
    await disconnect();

    try {
      final uri = Uri.parse(_serverUrl);
      _channel = WebSocketChannel.connect(uri);
      _connected = true;
      _reconnectAttempt = 0;
      debugPrint('[ws] Connected to $_serverUrl');
      onConnectionChange?.call(true);

      // Listen for messages
      _channel!.stream.listen(
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
        cancelOnError: false,
      );

      // Start heartbeat
      _startHeartbeat();
    } catch (e) {
      debugPrint('[ws] Connect error: $e');
      _handleDisconnect();
    }
  }

  /// Disconnect from the server.
  Future<void> disconnect() async {
    _stopHeartbeat();
    _connected = false;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    onConnectionChange?.call(false);
  }

  /// Send a chat message to a specific agent profile.
  void sendChat(String profileId, String content, {String? messageId}) {
    if (!_connected) {
      debugPrint('[ws] Cannot send: not connected');
      return;
    }
    final msg = WsMessage(
      type: 'chat',
      profileId: profileId,
      content: content,
      id: messageId ?? _generateId(),
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
    _connected = false;
    _stopHeartbeat();
    onConnectionChange?.call(false);

    if (!_disposed) {
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
    _reconnectTimer?.cancel();
    final delay = min(
      pow(2, _reconnectAttempt).toInt(),
      _maxReconnectDelay,
    );
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
    _stopHeartbeat();
    disconnect();
  }
}
