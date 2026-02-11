import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../widgets/top_message_bar.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Orchestrates the full download flow:
///   1. Call backend → get direct URL
///   2. Download file from direct URL to local storage (client-side)
///   3. Show progress via notification + callbacks
class DownloadService {
  DownloadService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  /// Starts the full extract → download pipeline.
  ///
  /// [onStatusChange] receives human-readable status strings.
  /// [onProgress] receives 0-100 percentage values.
  /// [onComplete] is called when the download finishes successfully.
  static Future<void> startDownload(
    BuildContext context,
    String url, {
    void Function(String status)? onStatusChange,
    void Function(int progress)? onProgress,
    VoidCallback? onComplete,
    CancelToken? cancelToken,
  }) async {
    if (url.isEmpty) return;

    TopMessageBar.show(context, "⏳ Analyzing…", duration: const Duration(seconds: 2));
    onStatusChange?.call("Preparing…");

    final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      // ── Step 1: Extract direct URL from backend ───────────────
      onStatusChange?.call("Contacting server…");
      final data = await ApiService.extractMedia(url);

      final directUrl = data['direct_url'] as String;
      final ext = data['ext'] as String;
      final mediaType = data['media_type'] as String;
      
      // Get headers if available (User-Agent, Cookies, etc.)
      Map<String, dynamic>? headers;
      if (data['headers'] != null) {
        headers = Map<String, dynamic>.from(data['headers']);
      }

      // ── Step 2: Resolve local save path ───────────────────────
      final appDir = await StorageService.getAppStorageDir();
      String fileName;
      if (mediaType == "video") {
        final n = await StorageService.getAndReserveNextVideoNumber();
        fileName = "Video $n.$ext";
      } else {
        fileName = "Image_${DateTime.now().millisecondsSinceEpoch}.$ext";
      }
      final savePath = "${appDir.path}/$fileName";

      // ── Step 3: Download directly from source (client-side) ──
      if (context.mounted) {
        TopMessageBar.show(
          context,
          "⬇️ Downloading $mediaType…",
          duration: const Duration(seconds: 2),
        );
      }
      onStatusChange?.call("Downloading $mediaType…");

      await _dio.download(
        directUrl,
        savePath,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          validateStatus: (status) => status != null && status >= 200 && status < 300,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final percent = ((received / total) * 100).toInt();
            if (percent % 5 == 0) {
              NotificationService.showProgress(notificationId, percent);
            }
            onProgress?.call(percent);
          }
        },
      );

      // ── Step 4: Success ──────────────────────────────────────
      NotificationService.showCompletion(notificationId, fileName, savePath);
      if (context.mounted) {
        TopMessageBar.show(
          context,
          "✅ Download Complete!",
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        );
      }
      onProgress?.call(100);
      onStatusChange?.call("Completed");
      onComplete?.call();
    } catch (e) {
      String errorMessage = "Download Failed";

      if (e is DioException) {
        if (e.type == DioExceptionType.cancel) {
          errorMessage = "Download cancelled";
        } else if (e.response?.statusCode == 400) {
          final d = e.response?.data;
          if (d is Map && d['detail'] != null) {
            errorMessage = d['detail'].toString();
          } else {
            errorMessage = "Server Error: Video locked or login required.";
          }
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = "Connection Timeout — check your server.";
        } else {
          errorMessage = e.message ?? "Network error";
        }
      } else {
        errorMessage = e.toString();
      }

      final isCancelled = errorMessage == "Download cancelled";

      if (context.mounted) {
        TopMessageBar.show(
          context,
          errorMessage,
          backgroundColor: isCancelled ? Colors.orange : Colors.redAccent,
          duration: const Duration(seconds: 3),
        );
      }

      onStatusChange?.call(errorMessage);
    }
  }
}
