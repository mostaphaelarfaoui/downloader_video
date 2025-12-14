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

// --- CONFIGURATION ---
// CHECK YOUR IP HERE
final String backendUrl = "http://192.168.11.130:8000/extract";

// --- NOTIFICATIONS ---
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

Future<void> _showProgressNotification(int progress) async {
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
      0, 'Downloading...', '$progress%', NotificationDetails(android: androidPlatformChannelSpecifics));
}

Future<void> _showCompletionNotification(String title) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'download_channel', 'Downloads',
    importance: Importance.high,
    priority: Priority.high,
  );
  await flutterLocalNotificationsPlugin.show(
      0, 'Download Complete', 'Saved: $title', const NotificationDetails(android: androidPlatformChannelSpecifics));
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
      title: 'Revert Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const DownloaderTab(),
    const GalleryTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.download), label: "Downloader"),
          BottomNavigationBarItem(icon: Icon(Icons.video_library), label: "My Gallery"),
        ],
      ),
    );
  }
}

// --- TAB 1: DOWNLOADER ---
class DownloaderTab extends StatefulWidget {
  const DownloaderTab({super.key});
  @override
  State<DownloaderTab> createState() => _DownloaderTabState();
}

class _DownloaderTabState extends State<DownloaderTab> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  double? _progress;
  String _status = "Ready to download";

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() { _urlController.text = data!.text!; });
    }
  }

  void _clearLink() {
    _urlController.clear();
    setState(() => _status = "Ready");
  }

  Future<void> _processLink() async {
    if (_urlController.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _isLoading = true; _status = "Connecting..."; _progress = null; });

    try {
      // FIX: Set timeouts using BaseOptions for Dio v5+
      BaseOptions options = BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 60),
      );
      
      // 1. Backend Request using the configured Dio instance
      final dio = Dio(options);
      final response = await dio.post(
        backendUrl, 
        data: {"url": _urlController.text},
      );
      
      final data = response.data;
      if (data['status'] == 'success') {
        String downloadUrl = data['download_url'];
        String ext = data['ext'];
        String mediaType = data['media_type'] ?? "video"; 
        
        String fileName = "revert_${DateTime.now().millisecondsSinceEpoch}.$ext";
        final appDir = await getApplicationDocumentsDirectory(); 
        final savePath = "${appDir.path}/$fileName";

        setState(() { _status = "Downloading $mediaType..."; });

        // Use the same Dio instance for download
        await dio.download(downloadUrl, savePath, 
          onReceiveProgress: (received, total) {
            if (total != -1) {
              int percent = ((received / total) * 100).toInt();
              if (percent % 10 == 0) _showProgressNotification(percent);
              setState(() { _progress = received / total; });
            }
          }
        );

        if (mediaType == "image") {
          await Gal.putImage(savePath);
        } else {
          await Gal.putVideo(savePath);
        }

        _showCompletionNotification(fileName);

        setState(() { 
          _isLoading = false; 
          _status = "Done! Check Gallery Tab"; 
          _progress = 0.0;
          _urlController.clear(); 
        });
        
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download Complete!")));
      }
    } catch (e) {
      setState(() { _isLoading = false; _status = "Error: $e"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Revert Downloader")),
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
                    if (_urlController.text.isNotEmpty)
                      IconButton(icon: const Icon(Icons.clear), onPressed: _clearLink),
                    IconButton(icon: const Icon(Icons.paste), onPressed: _pasteLink),
                  ],
                ),
              ),
              onChanged: (val) => setState(() {}),
            ),
            const SizedBox(height: 20),
            if (_isLoading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 10),
              Text(_status),
            ] else 
              ElevatedButton.icon(
                onPressed: _processLink,
                icon: const Icon(Icons.download),
                label: const Text("Start Download"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              ),
          ],
        ),
      ),
    );
  }
}

// --- TAB 2: GALLERY ---
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
        return path.endsWith(".mp4") || path.endsWith(".jpg") || path.endsWith(".png") || path.endsWith(".webp");
      }).toList().reversed.toList();
      _loading = false;
    });
  }

  void _openMedia(String path) {
    if (path.endsWith(".mp4")) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(path: path)));
    } else {
      showDialog(context: context, builder: (_) => Dialog(child: Image.file(File(path))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Downloads"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFiles)],
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
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: Container(
                          width: 80, height: 50, color: Colors.black12,
                          child: isVideo 
                            ? FutureBuilder<Uint8List?>(
                                future: VideoThumbnail.thumbnailData(video: file.path, imageFormat: ImageFormat.JPEG, quality: 50),
                                builder: (context, snapshot) {
                                  if (snapshot.data != null) return Image.memory(snapshot.data!, fit: BoxFit.cover);
                                  return const Icon(Icons.movie);
                                },
                              )
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
          autoPlay: true, looping: true,
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