import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:webview_flutter/webview_flutter.dart';

/// Extracts cookies from a WebView and converts them to
/// base64-encoded Netscape cookie format for yt-dlp.
class CookieService {
  CookieService._();

  /// Uses flutter_inappwebview's CookieManager to extract ALL cookies
  /// (including HttpOnly like sessionid) from the shared Android cookie store.
  ///
  /// Returns base64-encoded Netscape cookie file content, or null.
  static Future<String?> extractCookiesBase64(
      WebViewController controller) async {
    try {
      // Get the current URL from WebView
      final currentUrl = await controller.currentUrl();
      debugPrint('🍪 CookieService: currentUrl = $currentUrl');
      if (currentUrl == null) return null;

      final uri = Uri.parse(currentUrl);
      final domain = uri.host;

      // Use flutter_inappwebview's CookieManager to get ALL cookies
      // This wraps Android's native CookieManager and can access HttpOnly cookies
      final cookieManager = inapp.CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: inapp.WebUri(currentUrl));

      debugPrint('🍪 CookieService: Found ${cookies.length} cookies');

      if (cookies.isEmpty) {
        debugPrint('🍪 CookieService: No cookies found!');
        return null;
      }

      // Convert to Netscape cookie format
      // Format: domain\tTRUE\tpath\tTRUE\t0\tname\tvalue
      final buffer = StringBuffer();
      buffer.writeln('# Netscape HTTP Cookie File');

      for (final cookie in cookies) {
        final name = cookie.name;
        final value = cookie.value;
        if (name.isEmpty) continue;

        // Use the root domain (e.g. .instagram.com)
        final rootDomain =
            domain.startsWith('www.') ? domain.substring(3) : '.$domain';

        // Check if cookie is secure
        final isSecure = cookie.isSecure ?? true;

        buffer.writeln(
            '$rootDomain\tTRUE\t/\t${isSecure ? "TRUE" : "FALSE"}\t0\t$name\t$value');

        debugPrint('🍪   Cookie: $name = ${value.substring(0, value.length > 10 ? 10 : value.length)}...');
      }

      final netscapeCookies = buffer.toString();
      if (netscapeCookies.trim() == '# Netscape HTTP Cookie File') {
        debugPrint('🍪 CookieService: Netscape file is empty after conversion');
        return null;
      }

      debugPrint('🍪 CookieService: ✅ Cookie file generated (${cookies.length} cookies)');
      return base64Encode(utf8.encode(netscapeCookies));
    } catch (e) {
      debugPrint('🍪 CookieService ERROR: $e');
      return null;
    }
  }
}
