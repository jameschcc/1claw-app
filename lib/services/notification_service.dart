import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _key = 'notifications_enabled';

/// Cross-platform notification service.
///
/// - **Android**: `flutter_local_notifications` → heads-up banner + bubble support
/// - **Linux**: `notify-send` via `Process.run` (libnotify must be installed)
/// - **Windows**: `flutter_local_notifications` toast + taskbar flash via MethodChannel
/// - **macOS/iOS**: `flutter_local_notifications` → Notification Center
///
/// Singleton — accessible from anywhere via `NotificationService()`.
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// MethodChannel for Windows taskbar flash (no-op on other platforms).
  static const MethodChannel _windowFlashChannel =
      MethodChannel('com.claw.claw_app/window_flash');

  bool _enabled = true;
  bool _initialized = false;
  bool get enabled => _enabled;

  bool get _isWeb => kIsWeb;

  bool get _isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Load the persisted enabled/disabled state.
  Future<void> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_key) ?? true;
  }

  /// Persist the enabled/disabled state.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  /// Initialize notification plugins for all platforms.
  /// Call once in `main()` before `runApp()`.
  Future<void> initialize() async {
    await loadEnabled();

    if (_isWeb) {
      debugPrint('[notif] Notifications are not configured for web');
      return;
    }

    // --- flutter_local_notifications setup ---
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create high-importance channel for heads-up display (Android 8+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          '1claw_messages',
          '1Claw Messages',
          description: 'New messages from your AI agents',
          importance: Importance.high,
        ));

    _initialized = true;

    debugPrint('[notif] Notification service initialized');
  }

  /// Show a notification for a new message.
  ///
  /// [profileName] — agent profile display name
  /// [content] — message preview text
  Future<void> showMessageNotification({
    required String profileName,
    required String content,
  }) async {
    if (!_enabled || _isWeb) return;

    final title = _sanitizeNotificationText(
      profileName,
      maxLength: 80,
      fallback: '1Claw',
    );
    final preview = _sanitizeNotificationText(
      content,
      maxLength: 120,
      fallback: 'New message',
    );

    try {
      // Platform-specific notification display
      if (_isLinux) {
        await _linuxNotifySend(title, preview);
      } else {
        await _pluginNotify(title, preview);
      }

      // Windows taskbar flash (best-effort)
      if (_isWindows) {
        await _flashTaskbar();
      }
    } catch (e) {
      debugPrint('[notif] Failed to show notification: $e');
    }
  }

  /// Linux: use `notify-send` (part of libnotify).
  Future<void> _linuxNotifySend(String title, String body) async {
    try {
      await Process.run('notify-send', [
        '--app-name=1Claw',
        '--category=im.received',
        '--urgency=normal',
        title,
        body,
      ]);
    } catch (_) {
      // notify-send not available — silently ignore
    }
  }

  /// Android / Windows / macOS / iOS: use flutter_local_notifications.
  Future<void> _pluginNotify(String title, String body) async {
    if (!_initialized) {
      debugPrint('[notif] Skipped plugin notification before initialization');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      '1claw_messages',
      '1Claw Messages',
      channelDescription: 'New messages from your AI agents',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: false,
      category: AndroidNotificationCategory.message,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // Unique ID per message (positive, non-repeating)
    final notificationId =
        (DateTime.now().millisecondsSinceEpoch % 100000).abs();
    await _plugin.show(notificationId, title, body, details);
  }

  String _sanitizeNotificationText(
    String input, {
    required int maxLength,
    required String fallback,
  }) {
    final sanitized = input
        // Remove common markdown punctuation to keep toast text compact.
        .replaceAll(RegExp(r'[*_~`#>\[\]()]'), '')
        // Drop ASCII control chars that can break some platform transports.
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .replaceAll(RegExp(r'[\n\r]+'), ' ')
        .trim();

    if (sanitized.isEmpty) {
      return fallback;
    }

    return sanitized.length > maxLength
        ? '${sanitized.substring(0, maxLength)}…'
        : sanitized;
  }

  /// Flash Windows taskbar button via MethodChannel.
  /// No-op on non-Windows (channel not registered → throws, we catch).
  Future<void> _flashTaskbar() async {
    try {
      await _windowFlashChannel.invokeMethod('flashWindow');
    } catch (_) {
      // Windows runner not set up yet — that's fine
    }
  }

  void _onNotificationTap(NotificationResponse? response) {
    debugPrint('[notif] Tapped: ${response?.payload}');
    // Future: navigate to the profile's conversation
  }
}
