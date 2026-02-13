import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/download_service.dart';
import '../widgets/draggable_fab.dart';
import '../widgets/top_message_bar.dart';

/// Platform picker grid + in-app browser with download FAB.
class SocialBrowserTab extends StatelessWidget {
  final VoidCallback? onDownloadComplete;

  const SocialBrowserTab({super.key, this.onDownloadComplete});

  void _openBrowser(BuildContext context, String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(
          initialUrl: url,
          title: title,
          onDownloadComplete: onDownloadComplete,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose Platform")),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(20),
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        children: [
          _buildCard(context, "Instagram", "https://www.instagram.com/",
              Colors.purple),
          _buildCard(
              context, "TikTok", "https://www.tiktok.com/", Colors.black),
          _buildCard(
              context, "Facebook", "https://facebook.com", Colors.blue),
        ],
      ),
    );
  }

  Widget _buildCard(
      BuildContext context, String title, String url, Color color) {
    return InkWell(
      onTap: () => _openBrowser(context, url, title),
      child: Card(
        color: color.withValues(alpha: 0.2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public, size: 50, color: color),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────
// In-app WebView with smart link detection
// ─────────────────────────────────────────────────

class WebViewScreen extends StatefulWidget {
  final String initialUrl;
  final String title;
  final VoidCallback? onDownloadComplete;

  const WebViewScreen({
    super.key,
    required this.initialUrl,
    required this.title,
    this.onDownloadComplete,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;
  String _currentUrl = "";

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
  }

  /// Runs JS to detect the most relevant media link on the current page.
  Future<String?> _getRealLink() async {
    if (_controller == null) return null;

    const script = """
      (function() {
        var currentUrl = window.location.href;

        if (currentUrl.includes('/video/') || currentUrl.includes('/p/') ||
            currentUrl.includes('/reel/') || currentUrl.includes('/stories/')) {
          return currentUrl;
        }

        if (currentUrl.includes('tiktok.com')) {
          var video = document.querySelector('video');
          if (video) {
            if (video.currentSrc) return video.currentSrc;
            if (video.src) return video.src;
            var source = video.querySelector('source');
            if (source && source.src) return source.src;
          }
          var canonical = document.querySelector('link[rel="canonical"]');
          if (canonical && canonical.href && canonical.href.includes('/video/')) {
            return canonical.href;
          }
          var aTag = document.querySelector('a[href*="/video/"]');
          if (aTag && aTag.href) return aTag.href;
        }

        var screenCenter = window.innerHeight / 2;
        var bestLink = null;
        var minDistance = 10000;
        var links = document.querySelectorAll(
          'a[href*="/p/"], a[href*="/reel/"], a[href*="/video/"]');

        for (var i = 0; i < links.length; i++) {
          var rect = links[i].getBoundingClientRect();
          if (rect.top > 0 && rect.bottom < window.innerHeight) {
            var center = rect.top + rect.height / 2;
            var dist = Math.abs(center - screenCenter);
            if (dist < minDistance) {
              minDistance = dist;
              bestLink = links[i].href;
            }
          }
        }

        if (bestLink) return bestLink;
        return currentUrl;
      })();
    """;

    try {
      final result = await _controller!.evaluateJavascript(source: script);
      if (result.toString() != 'null' && result.toString() != '""') {
        return result.toString().replaceAll('"', '');
      }
    } catch (e) {
      debugPrint("JS Error: $e");
    }
    return null;
  }

  void _handleDownload() async {
    TopMessageBar.show(context, "🔍 Detecting media…",
        duration: const Duration(milliseconds: 500));

    String? target = await _getRealLink();

    // Normalize
    if (target != null) {
      final t = target.trim();
      if (!t.toLowerCase().startsWith('http')) {
        target = null;
      } else {
        target = t;
      }
    }

    // Fallback to current URL
    if (target == null || target.isEmpty) {
      if (_currentUrl.toLowerCase().startsWith('http')) {
        target = _currentUrl.trim();
      }
    }

    // Block generic home URLs
    if (target == null ||
        target.trim() == "https://www.tiktok.com/" ||
        target.trim() == "https://www.instagram.com/") {
      if (mounted) {
        TopMessageBar.show(
          context,
          "⚠️ Open the video fully or wait a moment!",
          backgroundColor: Colors.orange,
        );
      }
      return;
    }

    debugPrint("🎯 Sending to backend: $target");

    // Extract cookies using our existing CookieService logic
    // Since we are now using InAppWebView, we can also use CookieManager directly here
    // But for consistency let's use the CookieService which is already set up to use InAppWebView's CookieManager
    // However, CookieService expects a WebViewController (webview_flutter).
    // Let's UPDATE CookieService to accept InAppWebViewController or just use the static CookieManager logic directly here
    // to avoid circular dependency or type mismatches.
    
    // We already updated CookieService to use `inapp.CookieManager.instance()`.
    // It doesn't actually Use `WebViewController` argument for anything other than getting current URL.
    // So we can just use the static logic here.

    String? cookies;
    try {
      // Direct cookie extraction using InAppWebView's CookieManager
      final cookieManager = CookieManager.instance();
      final cookiesList = await cookieManager.getCookies(url: WebUri(target));
      
      if (cookiesList.isNotEmpty) {
         // Convert to Netscape format (duplicate logic from CookieService, but cleaner to inline for now)
         // Actually, let's just reuse the logic from CookieService but we need to pass the controller?
         // No, let's copy the logic here to keep it self-contained and avoid refactoring CookieService again right now.
         
         final buffer = StringBuffer();
         buffer.writeln('# Netscape HTTP Cookie File');
         final uri = Uri.parse(target);
         final domain = uri.host;
         
         for (final cookie in cookiesList) {
            final name = cookie.name;
            final value = cookie.value;
            final rootDomain = domain.startsWith('www.') ? domain.substring(3) : '.$domain';
            final isSecure = cookie.isSecure ?? true;
            buffer.writeln('$rootDomain\tTRUE\t/\t${isSecure ? "TRUE" : "FALSE"}\t0\t$name\t$value');
         }
         
         final netscapeCookies = buffer.toString();
         if (netscapeCookies.trim() != '# Netscape HTTP Cookie File') {
            cookies = base64Encode(utf8.encode(netscapeCookies));
            debugPrint("🍪 Cookies extracted successfully via InAppWebView");
         }
      }
    } catch (e) {
      debugPrint("🍪 Cookie extraction error: $e");
    }

    if (mounted) {
      DownloadService.startDownload(
        context,
        target,
        cookies: cookies,
        onComplete: widget.onDownloadComplete,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), elevation: 0),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useHybridComposition: true, // Forces correct Z-ordering on Android
              allowsInlineMediaPlayback: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            onLoadStop: (controller, url) {
              if (url != null) {
                setState(() {
                  _currentUrl = url.toString();
                });
              }
            },
            onUpdateVisitedHistory: (controller, url, androidIsReload) {
              if (url != null) {
                _currentUrl = url.toString();
              }
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri == null) return NavigationActionPolicy.CANCEL;

              final url = uri.toString().toLowerCase();

              // Block deep-links
              if (url.startsWith('intent://') ||
                  url.startsWith('market://') ||
                  url.contains('play.google.com') ||
                  url.contains('itunes.apple.com')) {
                return NavigationActionPolicy.CANCEL;
              }
              
              if (!url.startsWith('http')) {
                 return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },
          ),
          SafeArea(
            child: DraggableFab(onPressed: _handleDownload),
          ),
        ],
      ),
    );
  }
}

