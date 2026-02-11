/// App-wide configuration.
///
/// Change [backendBaseUrl] to switch between local development and production.
class AppConfig {
  AppConfig._();

  // ──────────────────────────────────────────────
  //  🔧  CHANGE THIS WHEN DEPLOYING TO RENDER
  // ──────────────────────────────────────────────
  // Local dev:   "http://10.0.2.2:8000"   (Android emulator)
  //              "http://localhost:8000"    (iOS simulator / desktop)
  // Production:  "https://your-app.onrender.com"
  static const String backendBaseUrl =
      "http://192.168.11.126:8000";
 
  /// Full extract endpoint.
  static String get extractUrl => "$backendBaseUrl/extract";

  /// App display name.
  static const String appName = "Smart Downloader";

  /// Folder created on the device for saved media.
  static const String appFolderName = "My Downloader";

  /// Hidden counter file inside the app folder.
  static const String videoCounterFileName = ".video_counter";

  /// Supported video extensions for gallery listing.
  static const List<String> videoExtensions = ['.mp4', '.mkv', '.mov', '.webm'];

  /// Supported image extensions for gallery listing.
  static const List<String> imageExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
}
