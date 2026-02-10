import 'package:flutter/material.dart';

/// A floating action button that the user can drag anywhere on the screen.
class DraggableFab extends StatefulWidget {
  final VoidCallback onPressed;
  const DraggableFab({super.key, required this.onPressed});

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  Offset position = const Offset(20, 100);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double btnSize = 56;
    final double maxX = size.width - btnSize;
    final double maxY = size.height - btnSize - 80;

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
          mini: true,
          backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
          onPressed: widget.onPressed,
          child: const Icon(Icons.download, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
