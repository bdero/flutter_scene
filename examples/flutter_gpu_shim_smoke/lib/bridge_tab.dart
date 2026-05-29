import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

class BridgeTab extends StatefulWidget {
  const BridgeTab({super.key});

  @override
  State<BridgeTab> createState() => _BridgeTabState();
}

class _BridgeTabState extends State<BridgeTab>
    with SingleTickerProviderStateMixin {
  gpu.Surface? _surface;
  ui.Image? _image;
  int _surfaceW = 0;
  int _surfaceH = 0;
  double _dpr = 1.0;

  bool _animate = true;
  bool _transferOwnership = false;
  bool _renderInProgress = false;
  bool _contextLost = false;
  String? _error;

  late final Ticker _ticker;
  late final TimingsCallback _timingsCallback;

  final _SampleRing _snapshotSamples = _SampleRing(120);
  final _SampleRing _renderSamples = _SampleRing(120);
  final _SampleRing _frameSamples = _SampleRing(120);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _timingsCallback = (List<FrameTiming> timings) {
      for (final t in timings) {
        _frameSamples.add(t.totalSpan.inMicroseconds);
      }
    };
    WidgetsBinding.instance.addTimingsCallback(_timingsCallback);
  }

  @override
  void dispose() {
    _ticker.dispose();
    WidgetsBinding.instance.removeTimingsCallback(_timingsCallback);
    _surface?.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _ensureSurface(int pxW, int pxH) {
    if (_surface != null && _surfaceW == pxW && _surfaceH == pxH) return;
    final old = _surface;
    if (old != null) {
      // Detach callbacks before letting go of the outgoing surface. CanvasKit
      // pins the source OffscreenCanvas behind a lazy SkImage when
      // `transferOwnership: true` is used, so the GL context can outlive our
      // reference; if the browser then evicts it (per-page context limit) the
      // old `webglcontextlost` fires and would mark the new live surface as
      // dead.
      old.onContextLost = null;
      old.onContextRestored = null;
      old.dispose();
    }
    try {
      final s = gpu.Surface(width: pxW, height: pxH);
      s.onContextLost = () {
        if (!mounted) return;
        setState(() => _contextLost = true);
      };
      s.onContextRestored = () {
        if (!mounted) return;
        setState(() => _contextLost = false);
      };
      _surface = s;
      _surfaceW = pxW;
      _surfaceH = pxH;
      _contextLost = false;
      _error = null;
    } catch (e, st) {
      _surface = null;
      _error = '$e\n$st';
    }
  }

  void _recreateSurface() {
    final w = _surfaceW;
    final h = _surfaceH;
    if (w == 0 || h == 0) return;
    // Reset the size so the size-equality early-return in _ensureSurface
    // doesn't no-op us.
    _surfaceW = 0;
    _surfaceH = 0;
    _ensureSurface(w, h);
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (!_animate || _renderInProgress) return;
    _render(elapsed);
  }

  Future<void> _render(Duration elapsed) async {
    final surface = _surface;
    if (surface == null || _contextLost) return;
    _renderInProgress = true;
    final renderSw = Stopwatch()..start();
    try {
      final t = elapsed.inMicroseconds / 1e6;
      final hue = (t * 60.0) % 360.0;
      final c = HSVColor.fromAHSV(1.0, hue, 0.85, 0.95).toColor();
      surface.clearToColor(c.r, c.g, c.b, 1.0);

      final snapSw = Stopwatch()..start();
      final image = await surface.snapshot(
        transferOwnership: _transferOwnership,
      );
      snapSw.stop();
      _snapshotSamples.add(snapSw.elapsedMicroseconds);

      if (!mounted) {
        image.dispose();
        return;
      }
      _image?.dispose();
      _image = image;

      if (_transferOwnership) {
        // The engine took ownership of the canvas; the surface is dead. Recreate.
        _surface = null;
        _ensureSurface(_surfaceW, _surfaceH);
      }

      renderSw.stop();
      _renderSamples.add(renderSw.elapsedMicroseconds);
      setState(() {});
    } catch (e, st) {
      if (mounted) setState(() => _error = '$e\n$st');
    } finally {
      _renderInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.devicePixelRatioOf(context);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (ctx, c) {
                final side = c.biggest.shortestSide;
                final pxSide = (side * _dpr).round().clamp(1, 4096);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _ensureSurface(pxSide, pxSide);
                });
                return Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child:
                        _image != null
                            ? RawImage(image: _image, fit: BoxFit.fill)
                            : _error != null
                            ? _ErrorView(message: _error!)
                            : const Center(child: CircularProgressIndicator()),
                  ),
                );
              },
            ),
          ),
        ),
        _ControlsPanel(
          animate: _animate,
          onAnimateChanged: (v) {
            setState(() {
              _animate = v;
              if (v) {
                if (!_ticker.isActive) _ticker.start();
              } else {
                _ticker.stop();
              }
            });
          },
          transferOwnership: _transferOwnership,
          onTransferOwnershipChanged: (v) {
            setState(() => _transferOwnership = v);
          },
          contextLost: _contextLost,
          onForceLoss: () => _surface?.forceContextLoss(),
          onForceRestore: () => _surface?.forceContextRestore(),
          onRecreate: _recreateSurface,
          surfaceSize: '$_surfaceW x $_surfaceH @ ${_dpr.toStringAsFixed(2)}x',
          snapshotSamples: _snapshotSamples,
          renderSamples: _renderSamples,
          frameSamples: _frameSamples,
        ),
      ],
    );
  }
}

class _SampleRing {
  _SampleRing(this.capacity);
  final int capacity;
  final List<int> _samples = [];

  void add(int us) {
    _samples.add(us);
    if (_samples.length > capacity) {
      _samples.removeRange(0, _samples.length - capacity);
    }
  }

  int get count => _samples.length;

  double get avgUs =>
      _samples.isEmpty ? 0 : _samples.reduce((a, b) => a + b) / _samples.length;

  int get p95Us {
    if (_samples.isEmpty) return 0;
    final sorted = [..._samples]..sort();
    final i = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
    return sorted[i];
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Text(message, style: const TextStyle(color: Colors.red)),
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.animate,
    required this.onAnimateChanged,
    required this.transferOwnership,
    required this.onTransferOwnershipChanged,
    required this.contextLost,
    required this.onForceLoss,
    required this.onForceRestore,
    required this.onRecreate,
    required this.surfaceSize,
    required this.snapshotSamples,
    required this.renderSamples,
    required this.frameSamples,
  });

  final bool animate;
  final ValueChanged<bool> onAnimateChanged;
  final bool transferOwnership;
  final ValueChanged<bool> onTransferOwnershipChanged;
  final bool contextLost;
  final VoidCallback onForceLoss;
  final VoidCallback onForceRestore;
  final VoidCallback onRecreate;
  final String surfaceSize;
  final _SampleRing snapshotSamples;
  final _SampleRing renderSamples;
  final _SampleRing frameSamples;

  @override
  Widget build(BuildContext context) {
    final snapAvg = snapshotSamples.avgUs / 1000.0;
    final snapP95 = snapshotSamples.p95Us / 1000.0;
    final renderAvg = renderSamples.avgUs / 1000.0;
    final renderP95 = renderSamples.p95Us / 1000.0;
    final frameAvg = frameSamples.avgUs / 1000.0;
    final frameP95 = frameSamples.p95Us / 1000.0;
    final fps = frameSamples.avgUs > 0 ? 1e6 / frameSamples.avgUs : 0.0;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _Stat('snapshot avg', '${snapAvg.toStringAsFixed(2)} ms'),
                _Stat('snapshot p95', '${snapP95.toStringAsFixed(2)} ms'),
                _Stat('render avg', '${renderAvg.toStringAsFixed(2)} ms'),
                _Stat('render p95', '${renderP95.toStringAsFixed(2)} ms'),
                _Stat('frame avg', '${frameAvg.toStringAsFixed(2)} ms'),
                _Stat('frame p95', '${frameP95.toStringAsFixed(2)} ms'),
                _Stat('fps', fps.toStringAsFixed(1)),
                _Stat('surface', surfaceSize),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Animate'),
                    subtitle: const Text('re-render every frame'),
                    value: animate,
                    onChanged: onAnimateChanged,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    title: const Text('transferOwnership'),
                    subtitle: const Text('engine consumes canvas (recreate)'),
                    value: transferOwnership,
                    onChanged: onTransferOwnershipChanged,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Icon(
                  contextLost ? Icons.error : Icons.check_circle,
                  color: contextLost ? Colors.red : Colors.green,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text('context: ${contextLost ? "LOST" : "alive"}'),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: contextLost ? null : onForceLoss,
                  child: const Text('Force loss'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: contextLost ? onForceRestore : null,
                  child: const Text('Try restore'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onRecreate,
                  child: const Text('Recreate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
