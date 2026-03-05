import 'package:flutter/material.dart';

/// A small floating download button that the user can drag anywhere on screen.
class DraggableFab extends StatefulWidget {
  final VoidCallback onPressed;
  const DraggableFab({super.key, required this.onPressed});

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab>
    with SingleTickerProviderStateMixin {
  static const double _btnSize = 42;

  late Offset _position;
  bool _isInit = false;
  bool _isDragging = false;

  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final size = MediaQuery.of(context).size;
      _position = Offset(size.width - _btnSize - 16, size.height - 160);
      _isInit = true;
    }
  }

  void _snapToEdge(Size screenSize) {
    final double centerX = _position.dx + _btnSize / 2;
    final double targetX = centerX < screenSize.width / 2
        ? 8.0
        : screenSize.width - _btnSize - 8;
    setState(() {
      _position = Offset(
        targetX,
        _position.dy.clamp(8.0, screenSize.height - _btnSize - 8),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double maxX = size.width - _btnSize;
    final double maxY = size.height - _btnSize;

    return Positioned(
      left: _position.dx.clamp(0.0, maxX),
      top: _position.dy.clamp(0.0, maxY),
      child: GestureDetector(
        onPanStart: (_) {
          setState(() => _isDragging = true);
          _scaleCtrl.forward();
        },
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onPanEnd: (_) {
          _scaleCtrl.reverse();
          setState(() => _isDragging = false);
          _snapToEdge(size);
        },
        onTap: widget.onPressed,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AnimatedOpacity(
            opacity: _isDragging ? 0.7 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: _btnSize,
              height: _btnSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFD50000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(_isDragging ? 0.15 : 0.25),
                    blurRadius: _isDragging ? 12 : 6,
                    spreadRadius: _isDragging ? 1 : 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.download_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
