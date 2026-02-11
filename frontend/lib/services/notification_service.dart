import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';

/// Handles all local push-notification logic (download progress & completion).
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Call once at app startup.
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          OpenFile.open(details.payload);
        }
      },
    );

    // Request notification permission on Android 13+.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Show / update a progress notification.
  static Future<void> showProgress(int id, int progress) async {
    final android = AndroidNotificationDetails(
      'video_downloads_v3', // Changed ID to force update
      'Downloads',
      channelDescription: 'Download progress',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true, // Prevent dismissal while downloading
    );
    await _plugin.show(
      id,
      'Downloading…',
      '$progress%',
      NotificationDetails(android: android),
    );
  }

  /// Show a completion notification.
  static Future<void> showCompletion(int id, String title, String filePath) async {
    // Explicitly cancel the progress notification first to prevent "stuck" bars
    await _plugin.cancel(id);

    const android = AndroidNotificationDetails(
      'video_downloads_v3',
      'Downloads',
      channelDescription: 'Download progress',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false, // Allow dismissal
      autoCancel: true, // Dismiss on tap
      showProgress: false,
    );
    await _plugin.show(
      id,
      'Download Complete',
      'Tap to open: $title',
      const NotificationDetails(android: android),
      payload: filePath,
    );
  }
}
