import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'package:chewie/chewie.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:webview_flutter/webview_flutter.dart';

// --- CONFIGURATION ---
// CHECK YOUR IP
final String backendUrl = "https://naval-holly-sosta04-e7fdb863.koyeb.app/";

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

Future<void> _showProgressNotification(int id, int progress) async {
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
      id, 'Downloading...', '$progress%', NotificationDetails(android: androidPlatformChannelSpecifics));
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

// --- SHARED DOWNLOAD MANAGER ---
class DownloadManager {
  static Future<void> startDownload(
    BuildContext context,
    String url, {
    void Function(String status)? onStatusChange,
    void Function(int progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (url.isEmpty) return;
    
    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("\u23f3 Analyzing link... Please wait.")),
    );

    onStatusChange?.call("Preparing...");

    // Generate a unique ID for notifications
    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      BaseOptions options = BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 60),
      );

      // 1. Backend Request
      onStatusChange?.call("Contacting server...");
      final response = await Dio(options).post(
        backendUrl, 
        data: {"url": url},
      );
      
      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected server response');
      }

      if (data['status'] != 'success') {
        final serverMessage = data['message']?.toString();
        throw Exception(serverMessage == null || serverMessage.isEmpty
            ? 'Server could not extract this media.'
            : serverMessage);
      }

      final downloadUrl = data['download_url']?.toString();
      final ext = data['ext']?.toString();
      final mediaType = data['media_type']?.toString() ?? "video";

      if (downloadUrl == null || ext == null || downloadUrl.isEmpty || ext.isEmpty) {
        throw Exception('Server returned invalid download information.');
      }

      final appDir = await _getAppStorageDir();
      String fileName;
      if (mediaType == "video") {
        final n = await _getAndReserveNextVideoNumber();
        fileName = "Video $n.$ext";
      } else {
        fileName = "Image_${DateTime.now().millisecondsSinceEpoch}.$ext";
      }

      final savePath = "${appDir.path}/$fileName";

      // Notify start
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("\u2b07\ufe0f Downloading $mediaType in background...")),
      );

      onStatusChange?.call("Downloading $mediaType...");

      // 2. Download File
      await Dio(options).download(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            int percent = ((received / total) * 100).toInt();
            if (percent % 10 == 0) _showProgressNotification(notificationId, percent);
            onProgress?.call(percent);
          }
        },
      );

      _showCompletionNotification(notificationId, fileName);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("\u2705 Download Complete! Saved in My Downloader folder.")),
      );

      onProgress?.call(100);
      onStatusChange?.call("Completed");
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
            // Fallback generic message
            errorMessage = "Server Error: Video locked or Login required.";
          }
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = "Connection Timeout. Check Server.";
        } else {
          errorMessage = "${e.message}";
        }
      } else {
        errorMessage = e.toString();
      }

      // Special case: Instagram image posts not supported by backend/yt-dlp
      if (errorMessage.contains('No media file found (Video or Image)')) {
        errorMessage =
            'Instagram: هذا المنشور غير مدعوم حالياً (خصوصاً بعض الصور). جرّب Reel أو فيديو آخر.';
      }

      // Show a shorter, cleaner error message (different color if cancelled)
      final isCancelled = errorMessage == "Download cancelled";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, maxLines: 2, overflow: TextOverflow.ellipsis),
          backgroundColor: isCancelled ? Colors.orange : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manual Download")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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

            if (_isDownloading || _downloadProgress > 0) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _downloadProgress == 0.0 ? null : _downloadProgress,
              ),
              const SizedBox(height: 8),
              Text(
                _downloadStatus,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🔍 Detecting video..."), duration: Duration(milliseconds: 500)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Open the video fully or wait a moment!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    debugPrint("🎯 Sending to Backend: $targetUrl");
    if (mounted) {
      DownloadManager.startDownload(context, targetUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), elevation: 0),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          DraggableFloatingButton(onPressed: _handleDownload),
        ],
      ),
    );
  }
}

// --- NEW WIDGET: DRAGGABLE BUTTON ---
class DraggableFloatingButton extends StatefulWidget {
  final VoidCallback onPressed;
  const DraggableFloatingButton({super.key, required this.onPressed});

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
          backgroundColor: Colors.redAccent.withOpacity(0.9),
          onPressed: widget.onPressed,
          child: const Icon(Icons.download, size: 20, color: Colors.white),
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
            path.endsWith(".png");
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Deleted")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete failed: $e")),
      );
    }
  }

  Future<void> _deleteAllVideos() async {
    final videos = _files.where((f) => f.path.toLowerCase().endsWith('.mp4')).toList();
    if (videos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No videos to delete")),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Deleted $deleted video(s)")),
    );
  }

  void _openMedia(String path) {
    if (path.endsWith(".mp4")) {
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
                    final isVideo = file.path.endsWith(".mp4");
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