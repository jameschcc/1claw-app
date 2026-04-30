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
  bool get enabled => _enabled;

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
    if (!_enabled) return;

    // Clean up: strip markdown/newlines, truncate to ~120 chars
    final sanitized = content
        .replaceAll(RegExp(r'[*_~`#>\[\]()]'), '')
        .replaceAll(RegExp(r'[\n\r]+'), ' ')
        .trim();
    final preview = sanitized.length > 120
        ? '${sanitized.substring(0, 120)}…'
        : sanitized;

    // Platform-specific notification display
    if (Platform.isLinux) {
      await _linuxNotifySend(profileName, preview);
    } else {
      await _pluginNotify(profileName, preview);
    }

    // Windows taskbar flash (best-effort)
    if (Platform.isWindows) {
      await _flashTaskbar();
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
