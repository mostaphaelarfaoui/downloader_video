import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Communicates with the backend `/extract` endpoint.
///
/// Returns a map with `direct_url`, `title`, `ext`, `media_type` on success.
class ApiService {
  ApiService._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  /// Calls the backend to extract the direct media URL and metadata.
  ///
  /// [cookies] is an optional base64-encoded Netscape cookie string
  /// used for authenticated content (e.g. Instagram Stories).
  ///
  /// Throws [DioException] on network/server errors.
  static Future<Map<String, dynamic>> extractMedia(
    String url, {
    String? cookies,
  }) async {
    final body = <String, dynamic>{"url": url};
    if (cookies != null) body["cookies"] = cookies;

    final response = await _dio.post(
      AppConfig.extractUrl,
      data: body,
    );

    final data = response.data;
    if (data is! Map) {
      throw Exception('Unexpected server response.');
    }

    if (data['status'] != 'success') {
      final msg = data['message']?.toString();
      throw Exception(
        msg == null || msg.isEmpty
            ? 'Server could not extract this media.'
            : msg,
      );
    }

    final directUrl = data['direct_url']?.toString();
    final ext = data['ext']?.toString();
    final mediaType = data['media_type']?.toString() ?? 'video';
    final title = data['title']?.toString() ?? 'Media';

    if (directUrl == null ||
        ext == null ||
        directUrl.isEmpty ||
        ext.isEmpty) {
      throw Exception('Server returned invalid extraction data.');
    }

    return {
      'direct_url': directUrl,
      'ext': ext,
      'media_type': mediaType,
      'title': title,
    };
  }
}
