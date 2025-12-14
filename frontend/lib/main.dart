import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:webview_flutter/webview_flutter.dart';

// --- CONFIGURATION ---
// CHECK YOUR IP
final String backendUrl = "http://192.168.11.130:8000/extract";

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
  static Future<void> startDownload(BuildContext context, String url) async {
    if (url.isEmpty) return;
    
    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Analyzing link... Please wait.")),
    );

    // Generate a unique ID for notifications
    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      BaseOptions options = BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 60),
      );

      // 1. Backend Request
      final response = await Dio(options).post(
        backendUrl, 
        data: {"url": url},
      );
      
      final data = response.data;
      if (data['status'] == 'success') {
        String downloadUrl = data['download_url'];
        String ext = data['ext'];
        String mediaType = data['media_type'] ?? "video"; 
        
        String fileName = "revert_${DateTime.now().millisecondsSinceEpoch}.$ext";
        final appDir = await getApplicationDocumentsDirectory(); 
        final savePath = "${appDir.path}/$fileName";

        // Notify start
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⬇️ Downloading $mediaType in background...")),
        );

        // 2. Download File
        await Dio(options).download(downloadUrl, savePath, 
          onReceiveProgress: (received, total) {
            if (total != -1) {
              int percent = ((received / total) * 100).toInt();
              if (percent % 10 == 0) _showProgressNotification(notificationId, percent);
            }
          }
        );

        // 3. Save to Gallery
        if (mediaType == "image") {
          await Gal.putImage(savePath);
        } else {
          await Gal.putVideo(savePath);
        }

        _showCompletionNotification(notificationId, fileName);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Download Complete! Saved to Gallery.")),
        );
      }
    } catch (e) {
      String errorMessage = "Download Failed";
      
      if (e is DioException) {
        if (e.response?.statusCode == 400) {
          // This usually means the backend failed (e.g. Login required)
          errorMessage = "Server Error: Video locked or Login required.";
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = "Connection Timeout. Check Server.";
        } else {
          errorMessage = "${e.message}";
        }
      } else {
        errorMessage = e.toString();
      }

      // Show a shorter, cleaner error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, maxLines: 2, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _urlController.text = data!.text!;
      });
    }
  }

  void _startDownload() {
    FocusScope.of(context).unfocus();
    DownloadManager.startDownload(context, _urlController.text);
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
                suffixIcon:
                    IconButton(icon: const Icon(Icons.paste), onPressed: _pasteLink),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.download),
              label: const Text("Start Download"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
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
          _buildCard(context, "Instagram", "https://instagram.com", Colors.purple),
          _buildCard(context, "TikTok", "https://tiktok.com", Colors.black),
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

// --- SMART WEBVIEW SCREEN (Draggable & Story Support) ---
class WebViewScreen extends StatefulWidget {
  final String initialUrl;
  final String title;
  const WebViewScreen({super.key, required this.initialUrl, required this.title});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  String _currentUrl = "";

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) => setState(() => _currentUrl = url),
          onUrlChange: (change) {
            setState(() => _currentUrl = change.url ?? _currentUrl);
            debugPrint("🔗 URL Changed: $_currentUrl");
          },
        ),
      );

    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<String?> _detectVideoLink() async {
    // 1. If it's a Story, return immediately
    if (_currentUrl.contains('/stories/')) {
      return _currentUrl;
    }

    // 2. Try Smart Detection (JS)
    const String script = """
      (function() {
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) {
          var rect = videos[i].getBoundingClientRect();
          var screenCenter = window.innerHeight / 2;
          var elementCenter = rect.top + rect.height / 2;
          
          // Check if video is roughly in center
          if (Math.abs(elementCenter - screenCenter) < 300) {
            // Try to find parent link
            var parent = videos[i].closest('a');
            if (parent && parent.href) return parent.href;
          }
        }
        return null;
      })();
    """;

    try {
      final result = await _controller.runJavaScriptReturningResult(script);
      if (result != null && result.toString() != 'null' && result.toString() != '""') {
        String jsLink = result.toString().replaceAll('"', '');
        debugPrint("✅ JS Detected: $jsLink");
        return jsLink;
      }
    } catch (e) {
      debugPrint("JS Error: $e");
    }
    
    // 3. FALLBACK (الحل الاحتياطي): 
    // If JS fails, just return the current page URL.
    // Let the Backend handle the filtering.
    debugPrint("⚠️ JS failed, using current URL: $_currentUrl");
    return _currentUrl;
  }

  void _handleDownload() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("🔍 Detecting media..."),
        duration: Duration(milliseconds: 500),
      ),
    );

    String? targetUrl = await _detectVideoLink();

    if (targetUrl != null) {
      debugPrint("✅ Target Found: $targetUrl");
      if (mounted) {
        DownloadManager.startDownload(context, targetUrl);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Couldn't find a video/story. Try opening the post directly."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), elevation: 0),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),

          // DRAGGABLE DOWNLOAD BUTTON
          DraggableFloatingButton(
            onPressed: _handleDownload,
          ),
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
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            // Update position with drag
            position += details.delta;
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
    final appDir = await getApplicationDocumentsDirectory();
    final allFiles = appDir.listSync();
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
                        title: Text(file.path.split('/').last),
                        trailing: const Icon(Icons.play_circle_outline),
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