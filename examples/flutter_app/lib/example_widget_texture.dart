import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';
import 'example_settings.dart';
import 'quake_camera.dart';

/// A live widget subtree on a bulbous CRT screen, run through a custom
/// `.fmat` effect.
///
/// The screen geometry is a dome-curved grid, so the raycast input
/// forwarding works through real interpolated UVs (not a quad shortcut).
/// The widget capture is bound to `assets/crt_effect.fmat`, an old-TV filter
/// (scanlines, chroma fringing, tracking wobble, static, vignette), and the
/// sliders rendered INSIDE the screen drive the effect's parameters, so the
/// panel adjusts its own distortion. The panel is scrollable: drag it or use
/// the scroll wheel. A drag starting off the screen looks around (WASD/QE
/// to fly, shift to boost).
class ExampleWidgetTexture extends StatefulWidget {
  const ExampleWidgetTexture({super.key});

  @override
  State<ExampleWidgetTexture> createState() => _ExampleWidgetTextureState();
}

class _ExampleWidgetTextureState extends State<ExampleWidgetTexture> {
  final Scene scene = Scene();
  final QuakeCamera _quakeCamera = QuakeCamera(
    position: vm.Vector3(0, 1.2, 4.5),
    pitch: -0.15,
  )..speed = 6.0;
  PerspectiveCamera? _camera;
  bool _looking = false;
  bool _recursive = false;

  PreprocessedMaterial? _material;
  WidgetComponent? _component;
  double _elapsedSeconds = 0.0;
  final EnvironmentSelector _environmentSelector = EnvironmentSelector();

  @override
  void initState() {
    super.initState();
    scene.add(
      Node(
        name: 'floor',
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.2, 0)),
        mesh: Mesh(
          PlaneGeometry(width: 8, depth: 8),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.25, 0.3, 0.4, 1.0)
            ..roughnessFactor = 0.7,
        ),
      ),
    );
    _load();
  }

  Future<void> _load() async {
    final material = await loadFmatMaterial('assets/crt_effect.fmat');
    if (!mounted) return;
    _material = material;

    final component = WidgetComponent(
      child: _CrtPanel(onChanged: _applyEffectSettings),
      size: const Size(480, 360), // 4:3, like the tube it lives on
      pixelRatio: 2.0,
      geometry: _buildCrtScreen(width: 3.0, height: 2.25, bulge: 0.3),
      material: material,
      bind: (texture) =>
          material.parameters.setTexture('screen_texture', texture),
    );
    _component = component;
    _applyEffectSettings(const CrtEffectSettings());

    final panel = Node(name: 'crt')..addComponent(component);
    // The tube housing: a deep casing behind the curved screen.
    panel.add(
      Node(
        name: 'crtHousing',
        localTransform: vm.Matrix4.translation(vm.Vector3(0, 0, -0.31)),
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(3.25, 2.5, 0.6)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.16, 0.15, 0.14, 1.0)
            ..roughnessFactor = 0.55,
        ),
      ),
    );
    scene.add(panel);
    setState(() {});
  }

  void _applyEffectSettings(CrtEffectSettings settings) {
    final material = _material;
    if (material == null) return;
    material.parameters
      ..setFloat('brightness', settings.brightness)
      ..setFloat('roughness', settings.roughness)
      ..setFloat('tape_wave', settings.wave)
      ..setFloat('tape_crease', settings.crease)
      ..setFloat('switching', settings.switching)
      ..setFloat('bloom_spread', settings.bloom)
      ..setFloat('ac_beat', settings.beat);
  }

  Future<void> _selectEnvironment(ExampleEnvironment environment) async {
    try {
      await _environmentSelector.select(environment, scene);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to load ${environment.title}: $e')),
      );
    }
  }

  /// Whether [position] is over a widget surface (nearest raycast hit
  /// carries a WidgetComponent).
  bool _overWidget(Offset position, Size viewSize) {
    final camera = _camera;
    if (camera == null || viewSize.isEmpty) return false;
    final hit = scene.raycast(camera.screenPointToRay(position, viewSize));
    return hit?.node.getComponent<WidgetComponent>() != null;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _quakeCamera.onKeyEvent,
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                // Camera look only when the drag starts off the screen; on
                // the screen, SceneView's automatic input drives the
                // widgets (including drag-scrolling the panel).
                _looking = !_overWidget(
                  details.localPosition,
                  constraints.biggest,
                );
              },
              onPanUpdate: (details) {
                if (_looking) _quakeCamera.look(details.delta);
              },
              onPanEnd: (details) => _looking = false,
              onPanCancel: () => _looking = false,
              child: SceneView(
                scene,
                debugWidgetInput: true,
                cameraBuilder: (elapsed) {
                  _quakeCamera.move(elapsed.inMicroseconds / 1e6);
                  return _camera = _quakeCamera.camera;
                },
                onTick: (elapsed, deltaSeconds) {
                  exampleSettings.applyTo(scene);
                  _elapsedSeconds = elapsed.inMicroseconds / 1e6;
                  _material?.parameters.setFloat('time', _elapsedSeconds);
                  // Recursive mode samples the scene's own previous frame,
                  // a one-frame feedback loop through the CRT filter.
                  final material = _material;
                  final component = _component;
                  if (material != null && component != null) {
                    final feedback = _recursive
                        ? scene.surface.lastSwapchainColorTexture()
                        : null;
                    final texture = feedback ?? component.controller.texture;
                    if (texture != null) {
                      material.parameters.setTexture('screen_texture', texture);
                    }
                  }
                },
              ),
            ),
          ),
          Positioned(
            top: 48,
            right: 8,
            child: EnvironmentMenu(
              active: _environmentSelector.active,
              loading: _environmentSelector.loading,
              onSelected: _selectEnvironment,
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'recursive',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Switch(
                  value: _recursive,
                  onChanged: (value) => setState(() => _recursive = value),
                ),
              ],
            ),
          ),
          // Capture diagnostics.
          Positioned(
            left: 8,
            bottom: 8,
            child: _component == null
                ? const SizedBox.shrink()
                : ListenableBuilder(
                    listenable: _component!.controller,
                    builder: (context, _) => Text(
                      'captures: ${_component!.controller.captureCount}  '
                      'last: ${_component!.controller.lastCaptureDuration.inMilliseconds}ms',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Builds the bulbous CRT screen: a grid in XY domed toward +Z, so hits on
/// any part of the curve interpolate the right UVs. [width] x [height] world
/// units with [bulge] units of forward curvature at the center.
Geometry _buildCrtScreen({
  required double width,
  required double height,
  required double bulge,
  int segments = 32,
}) {
  final columns = segments + 1;
  final rows = (segments * 3) ~/ 4 + 1;
  final positions = Float32List(columns * rows * 3);
  final texCoords = Float32List(columns * rows * 2);
  for (var r = 0; r < rows; r++) {
    final ny = r / (rows - 1) * 2 - 1; // -1 (bottom) .. 1 (top)
    for (var c = 0; c < columns; c++) {
      final nx = c / (columns - 1) * 2 - 1;
      final v = r * columns + c;
      // A smooth dome: full bulge at the center, flat at the rim.
      final dome = (1 - nx * nx) * (1 - ny * ny);
      positions[v * 3] = nx * width / 2;
      positions[v * 3 + 1] = ny * height / 2;
      positions[v * 3 + 2] = bulge * dome;
      // u = 0 at +x, matching the engine's hand-built front-face
      // convention (see the component quad).
      texCoords[v * 2] = (1 - nx) / 2;
      texCoords[v * 2 + 1] = (1 - ny) / 2; // v = 0 at the top
    }
  }
  // Two triangles per cell, wound to match the engine front-face convention
  // (the same order as the cuboid's +Z face: br, bl, tl, tr).
  final indices = <int>[];
  for (var r = 0; r < rows - 1; r++) {
    for (var c = 0; c < columns - 1; c++) {
      final bl = r * columns + c;
      final br = bl + 1;
      final tl = bl + columns;
      final tr = tl + 1;
      indices.addAll([br, bl, tr, tr, bl, tl]);
    }
  }
  return MeshGeometry.fromArrays(
    positions: positions,
    texCoords: texCoords,
    indices: indices,
  );
}

/// The effect parameters the in-screen sliders drive.
class CrtEffectSettings {
  const CrtEffectSettings({
    this.brightness = 1.5,
    this.roughness = 0.08,
    this.wave = 1.0,
    this.crease = 1.0,
    this.switching = 1.0,
    this.bloom = 1.0,
    this.beat = 1.0,
  });

  final double brightness;
  final double roughness;
  final double wave;
  final double crease;
  final double switching;
  final double bloom;
  final double beat;

  CrtEffectSettings copyWith({
    double? brightness,
    double? roughness,
    double? wave,
    double? crease,
    double? switching,
    double? bloom,
    double? beat,
  }) => CrtEffectSettings(
    brightness: brightness ?? this.brightness,
    roughness: roughness ?? this.roughness,
    wave: wave ?? this.wave,
    crease: crease ?? this.crease,
    switching: switching ?? this.switching,
    bloom: bloom ?? this.bloom,
    beat: beat ?? this.beat,
  );
}

/// The widget tree living on the CRT: a scrollable control panel whose
/// sliders adjust the very effect distorting it.
class _CrtPanel extends StatefulWidget {
  const _CrtPanel({required this.onChanged});

  final ValueChanged<CrtEffectSettings> onChanged;

  @override
  State<_CrtPanel> createState() => _CrtPanelState();
}

class _CrtPanelState extends State<_CrtPanel> {
  CrtEffectSettings _settings = const CrtEffectSettings();
  int _presses = 0;

  void _update(CrtEffectSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  Widget _slider(
    String label,
    double value,
    CrtEffectSettings Function(double) apply, {
    double max = 2.0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF9FE8A8), fontSize: 14),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, max),
              max: max,
              activeColor: const Color(0xFF9FE8A8),
              onChanged: (v) => _update(apply(v)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101A12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFF1D3322),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Text(
              '*** CHANNEL 3 . TRACKING ***',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9FE8A8),
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _slider(
                  'brightness',
                  _settings.brightness,
                  (v) => _settings.copyWith(brightness: v),
                  max: 4.0,
                ),
                _slider(
                  'gloss',
                  _settings.roughness,
                  (v) => _settings.copyWith(roughness: v),
                  max: 1.0,
                ),
                _slider(
                  'tape wave',
                  _settings.wave,
                  (v) => _settings.copyWith(wave: v),
                ),
                _slider(
                  'crease',
                  _settings.crease,
                  (v) => _settings.copyWith(crease: v),
                ),
                _slider(
                  'switching',
                  _settings.switching,
                  (v) => _settings.copyWith(switching: v),
                ),
                _slider(
                  'bloom',
                  _settings.bloom,
                  (v) => _settings.copyWith(bloom: v),
                ),
                _slider(
                  'ac beat',
                  _settings.beat,
                  (v) => _settings.copyWith(beat: v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => setState(() => _presses++),
                          child: Text('Pressed $_presses times'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          color: Color(0xFF9FE8A8),
                          backgroundColor: Color(0xFF1D3322),
                        ),
                      ),
                    ],
                  ),
                ),
                // Filler "channels" so the panel scrolls meaningfully.
                for (var channel = 4; channel <= 12; channel++)
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.tv,
                      color: Color(0xFF9FE8A8),
                      size: 18,
                    ),
                    title: Text(
                      'CHANNEL $channel  .  NO SIGNAL',
                      style: const TextStyle(
                        color: Color(0xFF5F9868),
                        fontSize: 13,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
