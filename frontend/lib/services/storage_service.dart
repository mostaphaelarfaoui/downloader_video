import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// Handles all local-storage operations (app folder, video counter).
class StorageService {
  StorageService._();

  static Directory? _cachedDir;

  /// Returns the app's dedicated storage directory, creating it if needed.
  ///
  /// On Android the folder is placed inside the system Downloads dir;
  /// on other platforms it falls back to the application documents directory.
  static Future<Directory> getAppStorageDir() async {
    if (_cachedDir != null && await _cachedDir!.exists()) return _cachedDir!;

    final fallback = await getApplicationDocumentsDirectory();
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

    final dir = Directory('${root.path}/${AppConfig.appFolderName}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// Atomically reserves and returns the next sequential video number.
  static Future<int> getAndReserveNextVideoNumber() async {
    final dir = await getAppStorageDir();
    final counterFile =
        File('${dir.path}/${AppConfig.videoCounterFileName}');

    int current = 1;
    try {
      if (await counterFile.exists()) {
        final content = await counterFile.readAsString();
        final parsed = int.tryParse(content.trim());
        if (parsed != null && parsed > 0) current = parsed;
      }
    } catch (_) {}

    try {
      await counterFile.writeAsString('${current + 1}');
    } catch (_) {}

    return current;
  }

  /// Lists media files (videos + images) in the app storage directory.
  static Future<List<FileSystemEntity>> listMediaFiles() async {
    final dir = await getAppStorageDir();
    final all = await dir.list().toList();

    return all.where((f) {
      final path = f.path.toLowerCase();
      return AppConfig.videoExtensions.any((e) => path.endsWith(e)) ||
          AppConfig.imageExtensions.any((e) => path.endsWith(e));
    }).toList()
      ..sort((a, b) {
        // Newest first
        try {
          return b.statSync().modified.compareTo(a.statSync().modified);
        } catch (_) {
          return 0;
        }
      });
  }
}
