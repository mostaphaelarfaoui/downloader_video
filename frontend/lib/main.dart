import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import 'package:chewie/chewie.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:webview_flutter/webview_flutter.dart';

// --- CONFIGURATION ---
// CHECK YOUR IP
final String backendUrl = "https://naval-holly-sosta04-e7fdb863.koyeb.app/extract";

// --- STORAGE CONFIG ---
// Folder name that will be created on the phone for this app
const String appFolderName = "My Downloader";
const String _videoCounterFileName = ".video_counter";

Future<Directory> _getAppStorageDir() async {
  final fallback = await getApplicationDocumentsDirectory();

  // User requirement: store inside the phone's main Downloads folder.
  // On Android, the common path is /storage/emulated/0/Download
  // (Some devices use /storage/emulated/0/Downloads)
  Directory root;
  if (Platform.isAndroid) {
    final download1 = Directory('/storage/emulated/0/Download');
    final download2 = Directory('/storage/emulated/0/Downloads');
    if (await download1.exists()) {
      root = download1;
    } else if (await download2.exists()) {
      root = download2;
    } else {
      final external = await getExternalStorageDirectory();
      root = external ?? fallback;
    }
  } else {
    root = fallback;
  }

  final dir = Directory('${root.path}/$appFolderName');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<int> _getAndReserveNextVideoNumber() async {
  final dir = await _getAppStorageDir();
  final counterFile = File('${dir.path}/$_videoCounterFileName');

  int current = 1;
  try {
    if (await counterFile.exists()) {
      final content = await counterFile.readAsString();
      final parsed = int.tryParse(content.trim());
      if (parsed != null && parsed > 0) {
        current = parsed;
      }
    }
  } catch (_) {
    // Ignore read errors
  }

  // Reserve current number by incrementing immediately and persisting.
  try {
    await counterFile.writeAsString('${current + 1}');
  } catch (_) {
    // Ignore write errors (fallback: could repeat next run)
  }

  return current;
}

// --- NOTIFICATIONS SETUP ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  
  await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
}

Future<void> _showProgressNotification(int id, int progress, String title) async {
  final AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'download_channel', 'Downloads',
    channelDescription: 'Show download progress',
    importance: Importance.low,
    priority: Priority.low,
    onlyAlertOnce: true,
    showProgress: true,
    maxProgress: 100,
    progress: progress,
  );
  await flutterLocalNotificationsPlugin.show(
      id, 'Downloading: $title', '$progress%', NotificationDetails(android: androidPlatformChannelSpecifics));
}

Future<void> _showCompletionNotification(int id, String title) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'download_channel', 'Downloads',
    importance: Importance.high,
    priority: Priority.high,
  );
  await flutterLocalNotificationsPlugin.show(
      id, 'Download Complete', 'Saved: $title', const NotificationDetails(android: androidPlatformChannelSpecifics));
}

// --- PERMISSION HANDLING ---
Future<bool> _requestStoragePermission() async {
  if (Platform.isAndroid) {
    // For Android 13+ (API 33+), we don't need WRITE_EXTERNAL_STORAGE
    // but we may need MANAGE_EXTERNAL_STORAGE for Downloads folder access
    final sdkInt = await _getAndroidSdkVersion();
    
    if (sdkInt >= 33) {
      // Android 13+: Check for media permissions
      final photos = await Permission.photos.status;
      final videos = await Permission.videos.status;
      
      if (!photos.isGranted || !videos.isGranted) {
        final results = await [
          Permission.photos,
          Permission.videos,
        ].request();
        
        return results[Permission.photos]?.isGranted == true ||
               results[Permission.videos]?.isGranted == true;
      }
      return true;
    } else if (sdkInt >= 30) {
      // Android 11-12: Need manage external storage or scoped access
      final storage = await Permission.storage.status;
      if (!storage.isGranted) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      return true;
    } else {
      // Android 10 and below
      final storage = await Permission.storage.status;
      if (!storage.isGranted) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      return true;
    }
  }
  // iOS doesn't need explicit storage permission for app documents
  return true;
}

Future<int> _getAndroidSdkVersion() async {
  try {
    if (Platform.isAndroid) {
      // Use ProcessResult to get SDK version
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      final sdk = int.tryParse(result.stdout.toString().trim());
      return sdk ?? 30;
    }
  } catch (_) {}
  return 30; // Default fallback
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  // Create the storage folder on first run (after install)
  await _getAppStorageDir();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

// --- UI HELPER: TOP MESSAGE BAR ---
class TopMessageBar {
  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = const Color(0xFF323232),
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final overlayEntry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final paddingTop = MediaQuery.of(ctx).padding.top;
        return Positioned(
          top: paddingTop + 16,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: size.width * 0.8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);
    Future.delayed(duration, () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}

// --- VIDEO INFO MODEL ---
class VideoInfo {
  final String directUrl;
  final String title;
  final String? thumbnail;
  final String source;
  final String ext;
  final String mediaType;
  final int? duration;
  final int? filesize;

  VideoInfo({
    required this.directUrl,
    required this.title,
    this.thumbnail,
    required this.source,
    required this.ext,
    required this.mediaType,
    this.duration,
    this.filesize,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      directUrl: json['direct_url'] ?? '',
      title: json['title'] ?? 'Untitled',
      thumbnail: json['thumbnail'],
      source: json['source'] ?? 'unknown',
      ext: json['ext'] ?? 'mp4',
      mediaType: json['media_type'] ?? 'video',
      duration: json['duration'],
      filesize: json['filesize'],
    );
  }
}

// --- DOWNLOAD SERVICE ---
class DownloadService {
  final Dio _dio;
  
  DownloadService() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
    sendTimeout: const Duration(seconds: 60),
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  ));

  /// Extract video info from the backend (no download on server)
  Future<VideoInfo> extractVideoInfo(String url) async {
    final response = await _dio.post(
      backendUrl,
      data: {"url": url},
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Unexpected server response');
    }

    if (data['status'] != 'success') {
      final serverMessage = data['detail']?.toString() ?? data['message']?.toString();
      throw Exception(serverMessage ?? 'Server could not extract this media.');
    }

    return VideoInfo.fromJson(data);
  }

  /// Download video directly from the direct URL to local storage
  Future<String> downloadVideo({
    required String directUrl,
    required String fileName,
    required String savePath,
    CancelToken? cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    // Configure Dio for large file downloads with custom headers
    final downloadDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
      },
    ));

    await downloadDio.download(
      directUrl,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        maxRedirects: 5,
      ),
    );

    return savePath;
  }
}

// --- SHARED DOWNLOAD MANAGER ---
class DownloadManager {
  static final DownloadService _downloadService = DownloadService();

  static Future<void> startDownload(
    BuildContext context,
    String url, {
    void Function(String status)? onStatusChange,
    void Function(int progress)? onProgress,
    void Function(VideoInfo? info)? onVideoInfoReceived,
    CancelToken? cancelToken,
  }) async {
    if (url.isEmpty) return;
    
    // Show immediate feedback
    TopMessageBar.show(
      context,
      "\u23f3 Analyzing...",
      duration: const Duration(seconds: 2),
    );

    onStatusChange?.call("Preparing...");

    // Generate a unique ID for notifications
    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      // Step 1: Request storage permission
      onStatusChange?.call("Checking permissions...");
      final hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        throw Exception('Storage permission denied. Please grant permission in settings.');
      }

      // Step 2: Extract video info from backend (NO download on server)
      onStatusChange?.call("Extracting video info...");
      final videoInfo = await _downloadService.extractVideoInfo(url);
      
      onVideoInfoReceived?.call(videoInfo);

      if (videoInfo.directUrl.isEmpty) {
        throw Exception('Could not get direct download URL');
      }

      // Step 3: Prepare save path
      final appDir = await _getAppStorageDir();
      String fileName;
      if (videoInfo.mediaType == "video") {
        final n = await _getAndReserveNextVideoNumber();
        fileName = "Video $n.${videoInfo.ext}";
      } else {
        fileName = "Image_${DateTime.now().millisecondsSinceEpoch}.${videoInfo.ext}";
      }

      final savePath = "${appDir.path}/$fileName";

      // Notify start
      TopMessageBar.show(
        context,
        "\u2b07\ufe0f Downloading ${videoInfo.mediaType}...\n${videoInfo.title}",
        duration: const Duration(seconds: 2),
      );

      onStatusChange?.call("Downloading ${videoInfo.mediaType}...");

      // Step 4: Download file directly from direct URL (CLIENT-SIDE DOWNLOAD)
      int lastNotifiedPercent = 0;
      
      await _downloadService.downloadVideo(
        directUrl: videoInfo.directUrl,
        fileName: fileName,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: (received, total) {
          if (total != -1 && total > 0) {
            int percent = ((received / total) * 100).toInt();
            
            // Update UI progress
            onProgress?.call(percent);
            
            // Update notification (throttle to every 5%)
            if (percent >= lastNotifiedPercent + 5 || percent == 100) {
              lastNotifiedPercent = percent;
              _showProgressNotification(notificationId, percent, videoInfo.title);
            }
          }
        },
      );

      // Step 5: Show completion
      _showCompletionNotification(notificationId, fileName);
      
      TopMessageBar.show(
        context,
        "\u2705 Download Complete!\nSaved: $fileName",
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      );

      onProgress?.call(100);
      onStatusChange?.call("Completed: $fileName");

    } catch (e) {
      String errorMessage = "Download Failed";
      
      if (e is DioException) {
        if (e.type == DioExceptionType.cancel) {
          errorMessage = "Download cancelled";
        } else if (e.response?.statusCode == 400) {
          // Prefer the backend's detailed message if available
          final data = e.response?.data;
          if (data is Map && data['detail'] != null) {
            errorMessage = data['detail'].toString();
          } else {
            errorMessage = "Server Error: Video locked or Login required.";
          }
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = "Connection Timeout. Check your internet.";
        } else if (e.type == DioExceptionType.receiveTimeout) {
          errorMessage = "Download timed out. Try again.";
        } else if (e.response?.statusCode == 403) {
          errorMessage = "Access denied. The direct URL may have expired.";
        } else if (e.response?.statusCode == 404) {
          errorMessage = "File not found on server.";
        } else {
          errorMessage = e.message ?? "Network error occurred";
        }
      } else {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }

      // Show a shorter, cleaner error message (different color if cancelled)
      final isCancelled = errorMessage == "Download cancelled";
      TopMessageBar.show(
        context,
        errorMessage,
        backgroundColor: isCancelled ? Colors.orange : Colors.redAccent,
        duration: const Duration(seconds: 4),
      );

      onStatusChange?.call(errorMessage);
    }
  }
}

// --- MAIN SCREEN ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const DownloaderTab(),
    const SocialBrowserTab(),
    const GalleryTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.download), label: "Downloader"),
          BottomNavigationBarItem(icon: Icon(Icons.public), label: "Browser"),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: "Gallery"),
        ],
      ),
    );
  }
}

// --- TAB 1: DOWNLOADER (Manual) ---
class DownloaderTab extends StatefulWidget {
  const DownloaderTab({super.key});
  @override
  State<DownloaderTab> createState() => _DownloaderTabState();
}

class _DownloaderTabState extends State<DownloaderTab> {
  final TextEditingController _urlController = TextEditingController();
  double _downloadProgress = 0.0;
  String _downloadStatus = "";
  bool _isDownloading = false;
  CancelToken? _cancelToken;
  VideoInfo? _currentVideoInfo;

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _urlController.text = data!.text!;
      });
    }
  }

  void _startDownload() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = "Preparing...";
      _cancelToken = CancelToken();
      _currentVideoInfo = null;
    });

    await DownloadManager.startDownload(
      context,
      _urlController.text,
      onStatusChange: (status) {
        if (!mounted) return;
        setState(() {
          _downloadStatus = status;
        });
      },
      onProgress: (percent) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = percent / 100.0;
        });
      },
      onVideoInfoReceived: (info) {
        if (!mounted) return;
        setState(() {
          _currentVideoInfo = info;
        });
      },
      cancelToken: _cancelToken,
    );

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _cancelToken = null;
    });
  }

  void _cancelDownload() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel("Cancelled by user");
    }
    setState(() {
      _isDownloading = false;
      _downloadStatus = "Cancelled";
    });
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manual Download")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: "Paste Video Link",
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _urlController.clear();
                          setState(() {
                            _currentVideoInfo = null;
                            _downloadProgress = 0.0;
                            _downloadStatus = "";
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.paste),
                        onPressed: _pasteLink,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isDownloading ? null : _startDownload,
                      icon: const Icon(Icons.download),
                      label: const Text("Start Download"),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isDownloading ? _cancelDownload : null,
                      icon: const Icon(Icons.cancel),
                      label: const Text("Cancel"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ),
                ],
              ),

              // Video Info Card
              if (_currentVideoInfo != null) ...[
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail
                        if (_currentVideoInfo!.thumbnail != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _currentVideoInfo!.thumbnail!,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    height: 150,
                                    color: Colors.grey[800],
                                    child: const Center(
                                      child: Icon(Icons.image_not_supported, size: 50),
                                    ),
                                  ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Title
                        Text(
                          _currentVideoInfo!.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Metadata row
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text(_currentVideoInfo!.source.toUpperCase()),
                              backgroundColor: _getSourceColor(_currentVideoInfo!.source),
                            ),
                            Chip(
                              label: Text(_currentVideoInfo!.mediaType.toUpperCase()),
                              avatar: Icon(
                                _currentVideoInfo!.mediaType == 'video'
                                    ? Icons.videocam
                                    : Icons.image,
                                size: 18,
                              ),
                            ),
                            if (_currentVideoInfo!.duration != null)
                              Chip(
                                label: Text(_formatDuration(_currentVideoInfo!.duration)),
                                avatar: const Icon(Icons.timer, size: 18),
                              ),
                            if (_currentVideoInfo!.filesize != null)
                              Chip(
                                label: Text(_formatFileSize(_currentVideoInfo!.filesize)),
                                avatar: const Icon(Icons.storage, size: 18),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Progress Section
              if (_isDownloading || _downloadProgress > 0) ...[
                const SizedBox(height: 20),
                Column(
                  children: [
                    // Progress bar with percentage
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: _downloadProgress == 0.0 ? null : _downloadProgress,
                              minHeight: 12,
                              backgroundColor: Colors.grey[800],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _downloadProgress >= 1.0 ? Colors.green : Colors.blue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(_downloadProgress * 100).toInt()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Status text
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isDownloading && _downloadProgress < 1.0)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (_isDownloading && _downloadProgress < 1.0)
                            const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _downloadStatus,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _downloadStatus.contains("Completed")
                                    ? Colors.green
                                    : _downloadStatus.contains("Failed") ||
                                            _downloadStatus.contains("Error")
                                        ? Colors.red
                                        : Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'instagram':
        return Colors.purple.withOpacity(0.3);
      case 'tiktok':
        return Colors.cyan.withOpacity(0.3);
      case 'facebook':
        return Colors.blue.withOpacity(0.3);
      case 'youtube':
        return Colors.red.withOpacity(0.3);
      case 'twitter':
        return Colors.lightBlue.withOpacity(0.3);
      default:
        return Colors.grey.withOpacity(0.3);
    }
  }
}

// --- TAB 2: SOCIAL BROWSER (Smart) ---
class SocialBrowserTab extends StatelessWidget {
  const SocialBrowserTab({super.key});

  void _openBrowser(BuildContext context, String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(initialUrl: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose Platform")),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(20),
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        children: [
          _buildCard(context, "Instagram", "https://www.instagram.com/", Colors.purple),
          _buildCard(context, "TikTok", "https://www.tiktok.com/", Colors.black),
          _buildCard(context, "Facebook", "https://facebook.com", Colors.blue),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, String title, String url, Color color) {
    return InkWell(
      onTap: () => _openBrowser(context, url, title),
      child: Card(
        color: color.withOpacity(0.2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public, size: 50, color: color),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  final String initialUrl;
  final String title;
  const WebViewScreen({super.key, required this.initialUrl, required this.title});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = "";

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) => debugPrint("Page Load: $url"),
          // 🛑 STOP PLAY STORE REDIRECTS 🛑
          onNavigationRequest: (NavigationRequest request) {
            String url = request.url.toLowerCase();

            // Block TikTok deep-links/OneLink pages that try to force-open the app
            if (url.contains('onelink.me') || url.contains('snssdk')) {
              debugPrint("🚫 Blocked TikTok deep-link landing: $url");
              return NavigationDecision.prevent;
            }

            // Block Play Store, Intents, and Market links
            if (url.startsWith('intent://') ||
                url.startsWith('market://') ||
                url.contains('play.google.com') ||
                url.contains('itunes.apple.com')) {
              debugPrint("🚫 Blocked Redirect to: $url");
              return NavigationDecision.prevent; // Prevent leaving the app
            }

            // Block any other non-http(s) deep-links (e.g. snssdk1233://)
            if (!url.startsWith('http')) {
              debugPrint("🚫 Blocked non-http(s) navigation: $url");
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate; // Allow normal browsing
          },
        ),
      );
    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<String?> _getRealLink() async {
    const String script = """
      (function() {
        var currentUrl = window.location.href;
        
        // 1. If URL already looks like a specific video/post/story -> Return it
        if (currentUrl.includes('/video/') || currentUrl.includes('/p/') || currentUrl.includes('/reel/') || currentUrl.includes('/stories/')) {
          return currentUrl;
        }

        // 2. TIKTOK SPECIFIC FIX
        if (currentUrl.includes('tiktok.com')) {
          // Try to grab the actual playing video URL first
          var video = document.querySelector('video');
          if (video) {
            if (video.currentSrc) return video.currentSrc;
            if (video.src) return video.src;

            var source = video.querySelector('source');
            if (source && source.src) return source.src;
          }

          // Prefer a canonical video page link if available
          var canonical = document.querySelector('link[rel="canonical"]');
          if (canonical && canonical.href && canonical.href.includes('/video/')) {
            return canonical.href;
          }

          // Fallback: closest /video/ anchor in the DOM
          var aTag = document.querySelector('a[href*="/video/"]');
          if (aTag && aTag.href) return aTag.href;
        }

        // 3. GENERIC FEED SEARCH (Instagram/Facebook)
        var screenCenter = window.innerHeight / 2;
        var bestLink = null;
        var minDistance = 10000;

        var links = document.querySelectorAll('a[href*="/p/"], a[href*="/reel/"], a[href*="/video/"]');

        for (var i = 0; i < links.length; i++) {
          var rect = links[i].getBoundingClientRect();
          if (rect.top > 0 && rect.bottom < window.innerHeight) {
            var center = rect.top + rect.height / 2;
            var dist = Math.abs(center - screenCenter);
            if (dist < minDistance) {
              minDistance = dist;
              bestLink = links[i].href;
            }
          }
        }

        if (bestLink) return bestLink;

        // Fallback: Return current URL (Let Backend handle it)
        return currentUrl;
      })();
    """;

    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      if (result != null && result.toString() != 'null' && result.toString() != '""') {
        return result.toString().replaceAll('"', '');
      }
    } catch (e) {
      debugPrint("JS Error: $e");
    }
    return null;
  }

  void _handleDownload() async {
    if (_isDownloading) return;

    TopMessageBar.show(
      context,
      "🔍 Detecting media... ",
      duration: const Duration(milliseconds: 500),
    );

    String? targetUrl = await _getRealLink();

    // Normalize and discard non-http URLs (e.g. blob: from TikTok video element)
    if (targetUrl != null) {
      final normalized = targetUrl.trim();
      if (!normalized.toLowerCase().startsWith('http')) {
        targetUrl = null;
      } else {
        targetUrl = normalized;
      }
    }

    // Fallback: if JS couldn't detect a proper media URL, use current WebView URL
    if (targetUrl == null || targetUrl.isEmpty) {
      try {
        final current = await _controller.currentUrl();
        if (current != null && current.toLowerCase().startsWith('http')) {
          targetUrl = current.trim();
        }
      } catch (_) {
        // ignore and let the generic warning handle it
      }
    }

    // Block Generic Home URLs
    if (targetUrl == null ||
        targetUrl.trim() == "https://www.tiktok.com/" ||
        targetUrl.trim() == "https://www.instagram.com/") {
      TopMessageBar.show(
        context,
        "⚠️ Open the video fully or wait a moment!",
        backgroundColor: Colors.orange,
      );
      return;
    }

    debugPrint("🎯 Sending to Backend: $targetUrl");
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = "Preparing...";
    });

    if (mounted) {
      await DownloadManager.startDownload(
        context,
        targetUrl,
        onStatusChange: (status) {
          if (!mounted) return;
          setState(() => _downloadStatus = status);
        },
        onProgress: (percent) {
          if (!mounted) return;
          setState(() => _downloadProgress = percent / 100.0);
        },
      );
    }

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), elevation: 0),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          
          // Download progress overlay
          if (_isDownloading)
            Positioned(
              bottom: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _downloadProgress == 0.0 ? null : _downloadProgress,
                              minHeight: 8,
                              backgroundColor: Colors.grey[700],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(_downloadProgress * 100).toInt()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _downloadStatus,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          
          DraggableFloatingButton(
            onPressed: _handleDownload,
            isLoading: _isDownloading,
          ),
        ],
      ),
    );
  }
}

// --- NEW WIDGET: DRAGGABLE BUTTON ---
class DraggableFloatingButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isLoading;
  const DraggableFloatingButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<DraggableFloatingButton> createState() => _DraggableFloatingButtonState();
}

class _DraggableFloatingButtonState extends State<DraggableFloatingButton> {
  Offset position = const Offset(20, 100); // Initial position

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const double buttonSize = 56; // default FAB size (approx)
    final double maxX = screenSize.width - buttonSize;
    final double maxY = screenSize.height - buttonSize - 80; // leave some bottom margin

    // Clamp position in case screen size changed
    position = Offset(
      position.dx.clamp(0.0, maxX) as double,
      position.dy.clamp(0.0, maxY) as double,
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            // Update position with drag and keep inside screen bounds
            final double newX = (position.dx + details.delta.dx).clamp(0.0, maxX) as double;
            final double newY = (position.dy + details.delta.dy).clamp(0.0, maxY) as double;
            position = Offset(newX, newY);
          });
        },
        child: FloatingActionButton(
          mini: true, // Smaller size
          backgroundColor: widget.isLoading 
              ? Colors.orange.withOpacity(0.9) 
              : Colors.redAccent.withOpacity(0.9),
          onPressed: widget.isLoading ? null : widget.onPressed,
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

// --- TAB 3: GALLERY ---
class GalleryTab extends StatefulWidget {
  const GalleryTab({super.key});

  @override
  State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final appDir = await _getAppStorageDir();
    final allFiles = await appDir.list().toList();
    setState(() {
      _files = allFiles.where((file) {
        String path = file.path.toLowerCase();

        return path.endsWith(".mp4") ||
            path.endsWith(".jpg") ||
            path.endsWith(".png") ||
            path.endsWith(".webm") ||
            path.endsWith(".mkv");
      }).toList().reversed.toList();
      _loading = false;
    });
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String confirmText = "Delete",
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteOne(FileSystemEntity entity) async {
    final path = entity.path;
    final name = path.split(Platform.pathSeparator).last;

    final ok = await _confirmAction(
      title: "Delete video?",
      message: "Are you sure you want to delete:\n$name",
    );
    if (!ok) return;

    try {
      await File(path).delete();
      if (!mounted) return;
      await _loadFiles();
      if (!mounted) return;
      TopMessageBar.show(
        context,
        "Deleted",
        backgroundColor: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      TopMessageBar.show(
        context,
        "Delete failed: $e",
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _deleteAllVideos() async {
    final videos = _files.where((f) {
      final path = f.path.toLowerCase();
      return path.endsWith('.mp4') || path.endsWith('.webm') || path.endsWith('.mkv');
    }).toList();
    
    if (videos.isEmpty) {
      TopMessageBar.show(
        context,
        "No videos to delete",
      );
      return;
    }

    final ok = await _confirmAction(
      title: "Delete all videos?",
      message: "This will permanently delete ${videos.length} video(s) from the app storage.",
      confirmText: "Delete all",
    );
    if (!ok) return;

    int deleted = 0;
    for (final v in videos) {
      try {
        await File(v.path).delete();
        deleted++;
      } catch (_) {
        // Ignore single-file failures
      }
    }

    if (!mounted) return;
    await _loadFiles();
    if (!mounted) return;
    TopMessageBar.show(
      context,
      "Deleted $deleted video(s)",
      backgroundColor: Colors.green,
    );
  }

  void _openMedia(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith(".mp4") || lowerPath.endsWith(".webm") || lowerPath.endsWith(".mkv")) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoPlayerScreen(path: path)),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(child: Image.file(File(path))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Gallery"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _deleteAllVideos,
            tooltip: "Delete all videos",
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text("No downloads yet"))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final lowerPath = file.path.toLowerCase();
                    final isVideo = lowerPath.endsWith(".mp4") || 
                                   lowerPath.endsWith(".webm") || 
                                   lowerPath.endsWith(".mkv");
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 80,
                          height: 50,
                          color: Colors.black12,
                          child: isVideo
                              ? const Icon(Icons.movie)
                              : Image.file(File(file.path), fit: BoxFit.cover),
                        ),
                        title: Text(file.path.split(Platform.pathSeparator).last),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isVideo)
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteOne(file),
                                tooltip: "Delete",
                              ),
                            const Icon(Icons.play_circle_outline),
                          ],
                        ),
                        onTap: () => _openMedia(file.path),
                      ),
                    );
                  },
                ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String path;
  const VideoPlayerScreen({super.key, required this.path});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.file(File(widget.path));
    _videoController.initialize().then((_) {
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoController,
          autoPlay: true,
          looping: true,
        );
      });
    });
  }

  @override
  void dispose() {
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _chewieController != null && _videoController.value.isInitialized
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(),
      ),
    );
  }
}