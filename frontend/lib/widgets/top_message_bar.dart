import 'package:flutter/material.dart';

/// Controller for a persistent top message that can be updated and dismissed.
class PersistentMessageController {
  OverlayEntry? _entry;
  final _notifier = ValueNotifier<_PersistentState>(
    const _PersistentState('', Color(0xFF323232), false, 0),
  );

  bool get isShowing => _entry?.mounted ?? false;

  void update(
    String message, {
    Color? backgroundColor,
    bool showProgress = false,
    int progress = 0,
  }) {
    _notifier.value = _PersistentState(
      message,
      backgroundColor ?? _notifier.value.color,
      showProgress,
      progress,
    );
  }

  void dismiss({String? finalMessage, Color? backgroundColor}) {
    if (finalMessage != null) {
      update(finalMessage, backgroundColor: backgroundColor ?? Colors.green);
      Future.delayed(const Duration(seconds: 2), _remove);
    } else {
      _remove();
    }
  }

  void _remove() {
    if (_entry?.mounted ?? false) _entry!.remove();
    _entry = null;
    _notifier.dispose();
  }
}

class _PersistentState {
  final String message;
  final Color color;
  final bool showProgress;
  final int progress;

  const _PersistentState(this.message, this.color, this.showProgress, this.progress);
}

/// Displays overlay messages near the top of the screen.
class TopMessageBar {
  TopMessageBar._();

  /// Shows a brief auto-dismissing message.
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

  /// Shows a persistent message that stays until [PersistentMessageController.dismiss] is called.
  /// The returned controller can update the text, color, and progress in real time.
  static PersistentMessageController showPersistent(
    BuildContext context,
    String initialMessage, {
    Color backgroundColor = const Color(0xFF323232),
  }) {
    final overlay = Overlay.of(context);
    final controller = PersistentMessageController();
    controller._notifier.value = _PersistentState(
      initialMessage,
      backgroundColor,
      false,
      0,
    );

    final entry = OverlayEntry(
      builder: (ctx) {
        final paddingTop = MediaQuery.of(ctx).padding.top;
        return Positioned(
          top: paddingTop + 16,
          left: 16,
          right: 16,
          child: ValueListenableBuilder<_PersistentState>(
            valueListenable: controller._notifier,
            builder: (_, state, __) {
              return Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: state.color.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (!state.showProgress)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          if (state.showProgress)
                            Text(
                              '${state.progress}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              state.message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (state.showProgress) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: state.progress / 100,
                            minHeight: 4,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    controller._entry = entry;
    overlay.insert(entry);
    return controller;
  }
}
