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
    const double btnSize = 60;
    final double maxX = size.width - btnSize;
    final double maxY = size.height - btnSize;

    return Positioned(
      left: position.dx.clamp(0.0, maxX),
      top: position.dy.clamp(0.0, maxY),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position += details.delta;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              )
            ],
          ),
          child: FloatingActionButton(
            heroTag: "draggable_download_fab",
            backgroundColor: Colors.redAccent,
            elevation: 0, 
            shape: const CircleBorder(
              side: BorderSide(color: Colors.white, width: 2),
            ),
            onPressed: widget.onPressed,
            child: const Icon(Icons.download, size: 30, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
