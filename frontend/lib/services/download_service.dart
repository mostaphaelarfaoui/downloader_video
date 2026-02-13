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
    String? cookies,
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
      final data = await ApiService.extractMedia(url, cookies: cookies);

      final directUrl = data['direct_url'] as String;
      final mediaUrls = (data['media_urls'] as List?)?.map((e) => e.toString()).toList() ?? [directUrl];
      
      final ext = data['ext'] as String;
      final mediaType = data['media_type'] as String;
      String title = data['title'] as String? ?? "Video";

      // Get headers if available (User-Agent, Cookies, etc.)
      Map<String, dynamic>? headers;
      if (data['headers'] != null) {
        headers = Map<String, dynamic>.from(data['headers']);
      }
      
      final appDir = await StorageService.getAppStorageDir();
      int totalItems = mediaUrls.length;
      
      for (int i = 0; i < totalItems; i++) {
        final currentUrl = mediaUrls[i];
        final isMultiple = totalItems > 1;
        
        // ── Step 2: Resolve local save path ───────────────────────
        String fileName;

        if (mediaType == "video") {
          String prefix = "Video";
          if (url.contains("facebook.com") || url.contains("fb.watch")) {
            prefix = "FB";
          } else if (url.contains("instagram.com")) {
            prefix = "iN";
          } else if (url.contains("tiktok.com")) {
            prefix = "TK";
          } else if (url.contains("youtube.com") || url.contains("youtu.be")) {
            prefix = "YT";
          }
          
          // Use robust directory scanning to get the next number
          final n = await StorageService.getNextVideoNumber();
          fileName = "${prefix}_Video_$n.$ext";
        } else {
          // For images, append index if multiple
          String suffix = isMultiple ? "_${i + 1}" : "";
          fileName = "Image_${DateTime.now().millisecondsSinceEpoch}$suffix.$ext";
        }
        
        final savePath = "${appDir.path}/$fileName";

        // ── Step 3: Download directly from source (client-side) ──
        if (context.mounted) {
           String msg = isMultiple 
              ? "⬇️ Downloading ${i + 1}/$totalItems…" 
              : "⬇️ Downloading $mediaType…";
           
           TopMessageBar.show(
              context,
              msg,
              duration: const Duration(seconds: 2),
           );
        }
        onStatusChange?.call(isMultiple ? "Downloading ${i + 1}/$totalItems…" : "Downloading $mediaType…");

        await _dio.download(
          currentUrl,
          savePath,
          cancelToken: cancelToken,
          options: Options(
            headers: headers,
            validateStatus: (status) => status != null && status >= 200 && status < 300,
          ),
          onReceiveProgress: (received, total) {
            if (total != -1) {
              final percent = ((received / total) * 100).toInt();
              // Only report progress for single items or overall? 
              // Simple progress for current item
              if (percent % 5 == 0) {
                 NotificationService.showProgress(notificationId + i, percent); // Distinct IDs for multiple?
              }
              onProgress?.call(percent);
            }
          },
        );

        // ── Step 4: Success per item ──────────────────────────────
        // Use unique ID for each notification if multiple
        NotificationService.showCompletion(notificationId + i, fileName, savePath);
      }

      if (context.mounted) {
        TopMessageBar.show(
          context,
          totalItems > 1 ? "✅ All $totalItems items downloaded!" : "✅ Download Complete!",
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
