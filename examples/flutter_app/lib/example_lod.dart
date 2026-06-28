import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';
import 'quake_camera.dart';

/// A field of identical icospheres receding into the distance, each an
/// [LodComponent] that swaps its geometry by projected screen size. Each
/// level is tinted a different color (green is highest detail, red is
/// lowest) so the switches and the cull floor are visible at a glance. Fly
/// with WASD/QE and drag to look; the colored bands move with the camera.
class ExampleLod extends StatefulWidget {
  const ExampleLod({super.key});

  @override
  State<ExampleLod> createState() => _ExampleLodState();
}

class _ExampleLodState extends State<ExampleLod> {
  final Scene scene = Scene();
  final QuakeCamera _quakeCamera = QuakeCamera(
    position: vm.Vector3(0, 5, 7),
    pitch: -0.3,
  )..speed = 12.0;
  final FocusNode _sceneFocus = FocusNode(debugLabel: 'lod-scene');

  // The spawned LOD components, so the controls can update them all.
  final List<LodComponent> _lods = [];
  bool _crossFade = true;
  double _blendRange = 0.12;
  double _lodBias = 1.0;

  // Color per level: green (highest detail) down to red (lowest).
  static final List<vm.Vector4> _levelColors = [
    vm.Vector4(0.36, 0.80, 0.42, 1),
    vm.Vector4(0.96, 0.82, 0.25, 1),
    vm.Vector4(0.95, 0.55, 0.22, 1),
    vm.Vector4(0.88, 0.30, 0.32, 1),
  ];

  // Icosphere subdivisions and the screen-size threshold (fraction of the
  // viewport height) at which each level takes over. Descending thresholds,
  // highest detail first; below the last one the sphere is culled.
  static const List<({int subdivisions, double screenSize})> _levels = [
    (subdivisions: 4, screenSize: 0.35),
    (subdivisions: 2, screenSize: 0.18),
    (subdivisions: 1, screenSize: 0.09),
    (subdivisions: 0, screenSize: 0.05),
  ];

  @override
  void initState() {
    super.initState();
    // Shared geometry and material per level, reused by every sphere.
    final levels = [
      for (var i = 0; i < _levels.length; i++)
        LodLevel(
          geometry: IcosphereGeometry(
            radius: 1.0,
            subdivisions: _levels[i].subdivisions,
          ),
          material: PhysicallyBasedMaterial()
            ..baseColorFactor = _levelColors[i]
            ..roughnessFactor = 0.5,
          screenSize: _levels[i].screenSize,
        ),
    ];

    const columns = 7;
    const rows = 12;
    const spacing = 3.2;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final x = (c - (columns - 1) / 2) * spacing;
        final z = -r * spacing;
        // blendRange cross-fades adjacent levels with a screen-space dither,
        // so the color bands dissolve into each other instead of popping; 0
        // hard-switches. Toggled live by the checkbox.
        final lod = LodComponent(
          levels,
          blendRange: _crossFade ? _blendRange : 0.0,
        );
        _lods.add(lod);
        scene.add(
          Node(localTransform: vm.Matrix4.translation(vm.Vector3(x, 1, z)))
            ..addComponent(lod),
        );
      }
    }
  }

  @override
  void dispose() {
    _sceneFocus.dispose();
    super.dispose();
  }

  void _setCrossFade(bool on) {
    setState(() {
      _crossFade = on;
      for (final lod in _lods) {
        lod.blendRange = on ? _blendRange : 0.0;
      }
    });
  }

  void _setBlendRange(double value) {
    setState(() {
      _blendRange = value;
      if (_crossFade) {
        for (final lod in _lods) {
          lod.blendRange = value;
        }
      }
    });
  }

  void _setLodBias(double value) {
    setState(() {
      _lodBias = value;
      for (final lod in _lods) {
        lod.lodBias = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Focus(
            focusNode: _sceneFocus,
            autofocus: true,
            onKeyEvent: _quakeCamera.onKeyEvent,
            child: Listener(
              onPointerDown: (_) => _sceneFocus.requestFocus(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => _quakeCamera.look(details.delta),
                child: SceneView(
                  scene,
                  cameraBuilder: (elapsed) {
                    _quakeCamera.move(elapsed.inMicroseconds / 1e6);
                    return _quakeCamera.camera;
                  },
                  onTick: (elapsed, deltaSeconds) =>
                      exampleSettings.applyTo(scene),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Card(
                color: Colors.black54,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Each sphere swaps detail by on-screen size  •  fly '
                        'with WASD/QE, drag to look',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _crossFade,
                            onChanged: (v) => _setCrossFade(v ?? false),
                            side: const BorderSide(color: Colors.white70),
                            checkColor: Colors.black,
                            activeColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          const Text(
                            'Cross-fade (dither)',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      _slider('LOD bias', _lodBias, 0.3, 3.0, _setLodBias),
                      _slider(
                        'Blend range',
                        _blendRange,
                        0.02,
                        0.3,
                        _setBlendRange,
                        enabled: _crossFade,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(left: 16, bottom: 16, child: _legend()),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    bool enabled = true,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: enabled ? 1.0 : 0.4),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _legend() {
    Color toColor(vm.Vector4 c) => Color.fromARGB(
      255,
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
    );
    Widget row(String label, Color? swatch) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: swatch ?? Colors.transparent,
              border: swatch == null ? Border.all(color: Colors.white38) : null,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
    return Card(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detail level',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _levels.length; i++)
              row(
                'L$i  (${_levels[i].subdivisions} subdiv)',
                toColor(_levelColors[i]),
              ),
            row('culled', null),
          ],
        ),
      ),
    );
  }
}
