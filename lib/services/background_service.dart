import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// Android foreground service to keep the Dart isolate alive in background.
/// Without this, Android kills the process → WebSocket dies → Dart VM stops.
///
/// The service shows a minimal notification so the OS treats it as a foreground
/// process with higher priority and lower kill probability.
class BackgroundService {
  BackgroundService._();

  static final BackgroundService _instance = BackgroundService._();
  factory BackgroundService() => _instance;

  bool _initialized = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _isSupportedPlatform => _isAndroid || _isIOS;

  /// Whether the foreground service is currently active.
  Future<bool> isRunning() {
    if (!_isSupportedPlatform) return Future.value(false);
    return FlutterBackgroundService().isRunning();
  }

  /// Initialize the background service.
  /// Call once at app startup (in main.dart).
  Future<void> initialize() async {
    if (_initialized) return;

    if (!_isSupportedPlatform) {
      debugPrint('[bg] Background service not supported on this platform');
      _initialized = true;
      return;
    }

    // Android 14+ requires the notification channel to exist BEFORE any
    // foreground service starts. The flutter_background_service library has
    // a bug: when a custom notificationChannelId is provided, it skips
    // createNotificationChannel(). We pre-create it ourselves here.
    if (_isAndroid) {
      try {
        const channel = MethodChannel('com.claw.claw_app/background_service');
        await channel.invokeMethod('createNotificationChannel');
        debugPrint('[bg] Notification channel pre-created');
      } catch (e) {
        debugPrint('[bg] Failed to pre-create channel: $e');
      }
    }

    final service = FlutterBackgroundService();

    // NOTE: onStart must be a top-level or static function (runs in a
    // separate isolate). We use _onStartCallback defined at top level.
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStartCallback,
        autoStart: false,
        isForegroundMode: true,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
        notificationChannelId: '1claw_background',
        initialNotificationTitle: '1Claw',
        initialNotificationContent: '正在保持连接…',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
      ),
    );

    _initialized = true;
    debugPrint('[bg] Background service initialized');
  }

  /// Start the foreground service — keeps app process alive.
  Future<void> start() async {
    if (!_initialized) {
      debugPrint('[bg] Not initialized yet');
      return;
    }
    if (!_isSupportedPlatform) {
      debugPrint('[bg] Background service not supported on this platform');
      return;
    }
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      debugPrint('[bg] Already running');
      return;
    }
    await service.startService();
    debugPrint('[bg] Service started');
  }

  /// Stop the foreground service.
  Future<void> stop() async {
    if (!_isSupportedPlatform) {
      debugPrint('[bg] Background service not supported on this platform');
      return;
    }
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) return;
    // Send stop signal to the background isolate
    service.invoke('stopService');
    debugPrint('[bg] Service stop requested');
  }
}

/// Top-level callback — required because it runs in a separate Dart isolate.
/// This is the entry point for the background service after the system starts it.
@pragma('vm:entry-point')
void _onStartCallback(ServiceInstance service) {
  debugPrint('[bg] Background service started in isolate');

  // Listen for stop signal from the main isolate
  service.on('stopService').listen((_) {
    service.stopSelf();
    debugPrint('[bg] Service stopped via signal');
  });

  // Keep the service alive indefinitely — the isolate stays running
  // as long as this callback doesn't return.
  Timer.periodic(const Duration(seconds: 30), (_) {
    if (!service.on('stopService').isBroadcast) {
      // Periodic keepalive — do nothing, just keep the isolate alive
    }
  });

  debugPrint('[bg] Background service callback ready');
}
