import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lightweight diagnostic performance overlay widget for 3D framerate and render monitoring.
/// {@category Widgets}
class PerformanceOverlay3D extends StatefulWidget {
  /// Whether the overlay is visible.
  final bool visible;

  /// Custom alignment on screen (defaults to top-left).
  final Alignment alignment;

  const PerformanceOverlay3D({
    super.key,
    this.visible = true,
    this.alignment = Alignment.topLeft,
  });

  @override
  State<PerformanceOverlay3D> createState() => _PerformanceOverlay3DState();
}

class _PerformanceOverlay3DState extends State<PerformanceOverlay3D>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTime = Duration.zero;
  double _fps = 60.0;
  double _frameMs = 16.6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (_lastTime != Duration.zero) {
        final dt = (elapsed - _lastTime).inMicroseconds / 1000000.0;
        if (dt > 0.0) {
          final instantFps = 1.0 / dt;
          _fps = _fps * 0.9 + instantFps * 0.1;
          _frameMs = dt * 1000.0;
          if (mounted) setState(() {});
        }
      }
      _lastTime = elapsed;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final fpsColor = _fps >= 55.0
        ? const Color(0xFF00FF66)
        : _fps >= 30.0
        ? const Color(0xFFFFCC00)
        : const Color(0xFFFF3333);

    return Align(
      alignment: widget.alignment,
      child: Container(
        margin: const EdgeInsets.all(12.0),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: const Color(0xCC111118),
          borderRadius: BorderRadius.circular(6.0),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_fps.toStringAsFixed(0)} FPS',
                  style: TextStyle(
                    color: fpsColor,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8.0),
                Text(
                  '(${_frameMs.toStringAsFixed(1)} ms)',
                  style: const TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 12.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
