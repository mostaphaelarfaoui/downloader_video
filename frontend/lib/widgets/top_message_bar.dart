import 'package:flutter/material.dart';

/// Displays a brief overlay message near the top of the screen.
class TopMessageBar {
  TopMessageBar._();

  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = const Color(0xFF323232),
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final paddingTop = MediaQuery.of(ctx).padding.top;
        return Positioned(
          top: paddingTop + 16,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size.width * 0.8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future.delayed(duration, () {
      if (entry.mounted) entry.remove();
    });
  }
}
