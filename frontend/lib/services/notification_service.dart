import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles all local push-notification logic (download progress & completion).
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Call once at app startup.
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    // Request notification permission on Android 13+.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Show / update a progress notification.
  static Future<void> showProgress(int id, int progress) async {
    final android = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Download progress',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
    );
    await _plugin.show(
      id,
      'Downloading…',
      '$progress%',
      NotificationDetails(android: android),
    );
  }

  /// Show a completion notification.
  static Future<void> showCompletion(int id, String title) async {
    const android = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id,
      'Download Complete',
      'Saved: $title',
      const NotificationDetails(android: android),
    );
  }
}
