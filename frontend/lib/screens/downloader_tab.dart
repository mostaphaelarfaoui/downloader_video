import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/connectivity_service.dart';
import '../services/download_service.dart';
import '../widgets/top_message_bar.dart';

/// Manual download tab — user pastes a URL and taps Download.
class DownloaderTab extends StatefulWidget {
  /// Called after a successful download to let the parent refresh, e.g. gallery.
  final VoidCallback? onDownloadComplete;

  const DownloaderTab({super.key, this.onDownloadComplete});

  @override
  State<DownloaderTab> createState() => _DownloaderTabState();
}

class _DownloaderTabState extends State<DownloaderTab> {
  final TextEditingController _urlController = TextEditingController();
  double _downloadProgress = 0.0;
  String _downloadStatus = "";
  bool _isDownloading = false;
  CancelToken? _cancelToken;

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _urlController.text = data!.text!);
    }
  }

  Future<void> _startDownload() async {
    FocusScope.of(context).unfocus();

    // Connectivity check
    final connected = await ConnectivityService.hasInternet();
    if (!connected && mounted) {
      TopMessageBar.show(
        context,
        "⚠️ No internet connection!",
        backgroundColor: Colors.orange,
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = "Preparing…";
      _cancelToken = CancelToken();
    });

    await DownloadService.startDownload(
      context,
      _urlController.text,
      onStatusChange: (status) {
        if (!mounted) return;
        setState(() => _downloadStatus = status);
      },
      onProgress: (percent) {
        if (!mounted) return;
        setState(() => _downloadProgress = percent / 100.0);
      },
      onComplete: widget.onDownloadComplete,
      cancelToken: _cancelToken,
    );

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _cancelToken = null;
    });
  }

  void _cancelDownload() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel("Cancelled by user");
    }
    setState(() {
      _isDownloading = false;
      _downloadStatus = "Cancelled";
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manual Download")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: "Paste Video Link",
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _urlController.clear,
                    ),
                    IconButton(
                      icon: const Icon(Icons.paste),
                      onPressed: _pasteLink,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? null : _startDownload,
                    icon: const Icon(Icons.download),
                    label: const Text("Start Download"),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isDownloading ? _cancelDownload : null,
                    icon: const Icon(Icons.cancel),
                    label: const Text("Cancel"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
              ],
            ),

            // ── Progress indicator ──
            if (_isDownloading || _downloadProgress > 0) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _downloadProgress == 0.0 ? null : _downloadProgress,
              ),
              const SizedBox(height: 8),
              Text(
                _downloadStatus,
                textAlign: TextAlign.center,
              ),
              if (_downloadProgress > 0 && _downloadProgress < 1.0)
                Text(
                  "${(_downloadProgress * 100).toInt()}%",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
