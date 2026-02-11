import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'screens/downloader_tab.dart';
import 'screens/gallery_tab.dart';

import 'screens/social_browser_tab.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  await StorageService.getAppStorageDir();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

/// Root screen with bottom navigation.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  /// GlobalKey so we can call loadFiles() on the GalleryTab from outside.
  final GlobalKey<GalleryTabState> _galleryKey = GlobalKey<GalleryTabState>();

  /// Called after any successful download (from any tab) to auto-refresh gallery.
  void _onDownloadComplete() {
    _galleryKey.currentState?.loadFiles();
  }

  @override
  void initState() {
    super.initState();
    // Request storage permissions at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionService.requestStoragePermission(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DownloaderTab(onDownloadComplete: _onDownloadComplete),
      SocialBrowserTab(onDownloadComplete: _onDownloadComplete),
      GalleryTab(key: _galleryKey),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.download), label: "Downloader"),
          BottomNavigationBarItem(
              icon: Icon(Icons.public), label: "Browser"),
          BottomNavigationBarItem(
              icon: Icon(Icons.video_library), label: "Gallery"),
        ],
      ),


    );
  }
}