import 'package:flutter/material.dart';

/// A floating action button that the user can drag anywhere on the screen.
class DraggableFab extends StatefulWidget {
  final VoidCallback onPressed;
  const DraggableFab({super.key, required this.onPressed});

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  late Offset position;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final size = MediaQuery.of(context).size;
      // Initialize bottom-right
      position = Offset(size.width - 80, size.height - 150);
      _isInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double btnSize = 56;
    final double maxX = size.width - btnSize;
    final double maxY = size.height - btnSize; // Removed arbitrary -80 to allow full usage

    // Clamp position to keep on screen
    position = Offset(
      position.dx.clamp(0.0, maxX),
      position.dy.clamp(0.0, maxY),
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position = Offset(
              (position.dx + details.delta.dx).clamp(0.0, maxX),
              (position.dy + details.delta.dy).clamp(0.0, maxY),
            );
          });
        },
        child: FloatingActionButton(
          mini: false, // Make it standard size for better visibility
          backgroundColor: Colors.redAccent,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white, width: 2), // High contrast border
          ),
          onPressed: widget.onPressed,
          child: const Icon(Icons.download, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}
