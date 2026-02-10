import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles Android storage permission request flow.
class PermissionService {
  PermissionService._();

  /// Request storage / media permissions.
  ///
  /// On Android 13+ (API 33) uses granular media permissions.
  /// On older Android uses WRITE_EXTERNAL_STORAGE.
  /// Returns `true` when permission is granted.
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) return true; // other platforms don't need it

    PermissionStatus status;

    // Android 13+ (SDK 33): use granular media permissions
    // Android <13: use legacy storage permission
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // Try videos + photos first (Android 13+)
    final results = await [
      Permission.videos,
      Permission.photos,
      Permission.storage,
    ].request();

    final anyGranted = results.values.any(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );

    if (anyGranted) return true;

    // If all denied, try manage external storage as fallback
    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // Show explanation if permanently denied
    if (status.isPermanentlyDenied && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Storage permission is required. Please enable it in Settings.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      openAppSettings();
    }

    return false;
  }
}
