import 'dart:io';

/// Simple connectivity check using a DNS lookup.
class ConnectivityService {
  ConnectivityService._();

  /// Returns `true` when the device can reach the internet.
  static Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
