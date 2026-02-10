import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Settings screen — currently shows backend URL config and app info.
/// Easily extendable for future settings.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Server Info ──
          const Text(
            "Server Configuration",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns),
              title: const Text("Backend URL"),
              subtitle: const Text(
                AppConfig.backendBaseUrl,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              trailing: const Icon(Icons.info_outline),
              onTap: () => _showInfoDialog(context),
            ),
          ),
          const SizedBox(height: 24),

          // ── About ──
          const Text(
            "About",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info),
              title: Text(AppConfig.appName),
              subtitle: Text("Version 2.0.0"),
            ),
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.folder),
              title: Text("Storage Folder"),
              subtitle: Text(AppConfig.appFolderName),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              tileColor: Colors.redAccent.withValues(alpha: 0.9),
              leading: const Icon(Icons.architecture),
              title: const Text("Architecture"),
              subtitle: const Text(
                "Client-side downloading\n"
                "Backend: Link extraction only",
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Backend URL"),
        content: const Text(
          "To change the backend URL, update the value in:\n\n"
          "lib/config/app_config.dart\n\n"
          "Set backendBaseUrl to your Render or local server address.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}
