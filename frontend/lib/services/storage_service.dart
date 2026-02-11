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

  /// Scans existing files to find the next available video number.
  /// Matches pattern: [Prefix]_Video_[Number].[ext]
  static Future<int> getNextVideoNumber() async {
    final dir = await getAppStorageDir();
    int maxId = 0;

    try {
      final List<FileSystemEntity> files = dir.listSync();
      final regExp = RegExp(r'_Video_(\d+)\.');

      for (var file in files) {
        if (file is File) {
          final filename = file.uri.pathSegments.last;
          final match = regExp.firstMatch(filename);
          if (match != null) {
            final id = int.tryParse(match.group(1) ?? '0') ?? 0;
            if (id > maxId) maxId = id;
          }
        }
      }
    } catch (e) {
      // If error occurs (e.g. permission), default to timestamp to avoid overwrite
      return DateTime.now().millisecondsSinceEpoch;
    }

    return maxId + 1;
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
