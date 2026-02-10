import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/storage_service.dart';
import '../widgets/top_message_bar.dart';
import 'video_player_screen.dart';

/// Displays all downloaded media files with delete support.
class GalleryTab extends StatefulWidget {
  const GalleryTab({super.key});

  @override
  State<GalleryTab> createState() => GalleryTabState();
}

class GalleryTabState extends State<GalleryTab> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  /// Public so it can be called from outside (e.g. after a download completes).
  Future<void> loadFiles() async {
    final files = await StorageService.listMediaFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
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
    final name = entity.path.split(Platform.pathSeparator).last;
    final ok = await _confirmAction(
      title: "Delete file?",
      message: "Are you sure you want to delete:\n$name",
    );
    if (!ok) return;

    try {
      await File(entity.path).delete();
      if (!mounted) return;
      await loadFiles();
      if (!mounted) return;
      TopMessageBar.show(context, "Deleted", backgroundColor: Colors.green);
    } catch (e) {
      if (!mounted) return;
      TopMessageBar.show(context, "Delete failed: $e",
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 3));
    }
  }

  Future<void> _deleteAllVideos() async {
    final videos = _files
        .where((f) =>
            AppConfig.videoExtensions.any((e) => f.path.toLowerCase().endsWith(e)))
        .toList();

    if (videos.isEmpty) {
      TopMessageBar.show(context, "No videos to delete");
      return;
    }

    final ok = await _confirmAction(
      title: "Delete all videos?",
      message:
          "This will permanently delete ${videos.length} video(s) from the app storage.",
      confirmText: "Delete all",
    );
    if (!ok) return;

    int deleted = 0;
    for (final v in videos) {
      try {
        await File(v.path).delete();
        deleted++;
      } catch (_) {}
    }

    if (!mounted) return;
    await loadFiles();
    if (!mounted) return;
    TopMessageBar.show(context, "Deleted $deleted video(s)",
        backgroundColor: Colors.green);
  }

  bool _isVideo(String path) =>
      AppConfig.videoExtensions.any((e) => path.toLowerCase().endsWith(e));

  void _openMedia(String path) {
    if (_isVideo(path)) {
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadFiles,
          ),
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
                    final isVideo = _isVideo(file.path);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: Container(
                          width: 80,
                          height: 50,
                          color: Colors.black12,
                          child: isVideo
                              ? const Icon(Icons.movie)
                              : Image.file(File(file.path),
                                  fit: BoxFit.cover),
                        ),
                        title: Text(
                          file.path.split(Platform.pathSeparator).last,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
