// Gaussian splat rendering demo.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_settings.dart';
import 'quake_camera.dart';

/// Gaussian splat rendering with two real captures, an isolated-object macro
/// capture (Strawberry by danylyon, CC BY 4.0) and a room-scale one (a
/// Chinese classroom by hite404, CC BY 4.0), both fetched by
/// `tool/fetch_splat_asset.sh`. A PBR sphere sits inside each scene proving
/// splats and forward-rendered geometry occlude each other, an animated
/// crop box demonstrates GPU-side cropping, and a Quake-style free camera
/// (bottom center) explores the room from inside.
class ExampleSplats extends StatefulWidget {
  const ExampleSplats({super.key});

  @override
  ExampleSplatsState createState() => ExampleSplatsState();
}

/// One selectable capture, where to load it from and how to frame it.
class _SourceConfig {
  const _SourceConfig({
    required this.label,
    required this.asset,
    required this.scale,
    required this.lift,
    required this.orbitRadius,
    required this.orbitHeight,
    required this.targetHeight,
  });

  final String label;
  final String asset;

  /// Uniform scale applied to the capture (captures come at their trained
  /// size; the strawberry is a few centimeters across).
  final double scale;

  /// World-space height the capture's center is lifted to.
  final double lift;

  final double orbitRadius;
  final double orbitHeight;
  final double targetHeight;
}

const List<_SourceConfig> _sourceConfigs = [
  _SourceConfig(
    label: 'Strawberry',
    asset: 'assets_src/strawberry.splat',
    scale: 4.0,
    lift: 1.0,
    orbitRadius: 18.0,
    orbitHeight: 4.0,
    targetHeight: 0.5,
  ),
  _SourceConfig(
    label: 'Classroom',
    asset: 'assets_src/classroom.splat',
    scale: 1.0,
    lift: 1.4,
    orbitRadius: 4.5,
    orbitHeight: 1.9,
    targetHeight: 1.2,
  ),
];

/// Boolean splat controls arranged to fit the standard side-panel width.
class GaussianSplatToggleControls extends StatelessWidget {
  const GaussianSplatToggleControls({
    super.key,
    required this.antialiased,
    required this.cropSweep,
    required this.orbit,
    required this.onAntialiasedChanged,
    required this.onCropSweepChanged,
    required this.onOrbitChanged,
  });

  final bool antialiased;
  final bool cropSweep;
  final bool orbit;
  final ValueChanged<bool> onAntialiasedChanged;
  final ValueChanged<bool> onCropSweepChanged;
  final ValueChanged<bool> onOrbitChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _toggle('Antialiased', antialiased, onAntialiasedChanged),
      _toggle('Crop sweep', cropSweep, onCropSweepChanged),
      _toggle('Orbit', orbit, onOrbitChanged),
    ],
  );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
      Switch(value: value, onChanged: onChanged),
    ],
  );
}

/// Keeps system icons readable over this example's consistently dark skybox.
class GaussianSplatSystemChrome extends StatelessWidget {
  const GaussianSplatSystemChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: child,
  );
}

/// A compact side-panel surface with a fixed source header and scrollable
/// settings, so short landscape viewports keep every control reachable.
class GaussianSplatSettingsPanel extends StatelessWidget {
  const GaussianSplatSettingsPanel({
    super.key,
    required this.header,
    required this.controls,
    this.open = true,
    this.onToggle,
  });

  final Widget header;
  final Widget controls;
  final bool open;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Card(
      color: Colors.black.withValues(alpha: 0.55),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: constraints.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.blur_on, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Gaussian splat controls',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            if (open) ...[
              const Divider(height: 1, color: Colors.white24),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, const SizedBox(height: 4), controls],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class ExampleSplatsState extends State<ExampleSplats> {
  Scene scene = Scene();
  bool _ready = false;

  final Map<_SourceConfig, Node> _sourceNodes = {};
  final Map<_SourceConfig, SplatComponent> _sources = {};
  final Map<_SourceConfig, double> _cropExtents = {};
  _SourceConfig? _active;

  double _opacity = 1.0;
  double _splatScale = 1.0;
  bool _antialiased = true;
  bool _cropSweep = false;
  bool _orbit = true;
  bool _controlsOpen = true;

  // The free "inspection" camera. While inactive it is kept synced to the
  // orbit camera so toggling it on does not jump the view.
  bool _freeCamera = false;
  final QuakeCamera _freeCam = QuakeCamera(position: vm.Vector3(0, 4, 14))
    ..speed = 4.0
    ..enabled = false;
  double _elapsedSeconds = 0;

  // Smoothed frames-per-second readout, updated a few times a second so
  // the panel text does not rebuild every frame.
  final ValueNotifier<double> _fps = ValueNotifier<double>(0);
  double _fpsAccum = 0;
  int _fpsFrames = 0;

  @override
  void initState() {
    super.initState();
    // Splat footprints are soft, so MSAA buys nothing here while
    // multiplying blend cost across millions of tiny triangles; prefer the
    // post-process path for this example (still adjustable in the shared
    // settings sidebar).
    exampleSettings.antiAliasingMode = AntiAliasingMode.fxaa;
    _load();
  }

  @override
  void dispose() {
    _fps.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.008, 0.008, 0.02),
        horizonColor: vm.Vector3(0.02, 0.015, 0.045),
        groundColor: vm.Vector3(0.005, 0.005, 0.012),
        sunColor: vm.Vector3(0.06, 0.06, 0.09),
      ),
    );

    for (final config in _sourceConfigs) {
      try {
        final component = SplatComponent(
          await GaussianSplats.fromAsset(config.asset),
        );
        _sources[config] = component;
        _sourceNodes[config] = _placeCapture(component, config);
        final bounds = component.splats.bounds;
        _cropExtents[config] = bounds == null
            ? 5.0
            : ((bounds.max.x - bounds.min.x) * 0.5 * config.scale).clamp(
                3.0,
                12.0,
              );
      } catch (_) {
        // Asset absent (tool/fetch_splat_asset.sh not run); hide the source.
      }
    }
    _active = _sources.keys.isEmpty ? null : _sources.keys.first;

    for (final entry in _sourceNodes.entries) {
      entry.value.visible = entry.key == _active;
      scene.add(entry.value);
    }

    // A shiny sphere inside each capture. Splats in front of it must cover
    // it, and it must occlude the splats behind it.
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.8),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.9, 0.85, 0.8, 1.0)
            ..metallicFactor = 1.0
            ..roughnessFactor = 0.15,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(2.2, 1.0, 0)),
    );

    if (mounted) setState(() => _ready = true);
  }

  /// Places a capture, recentered on its bounds, flipped upright (training
  /// captures are y-down), scaled, and lifted in front of the camera.
  static Node _placeCapture(SplatComponent component, _SourceConfig config) {
    final bounds = component.splats.bounds;
    final center = bounds == null
        ? vm.Vector3.zero()
        : (bounds.min + bounds.max) * 0.5;
    final transform = vm.Matrix4.compose(
      vm.Vector3(0, config.lift, 0),
      vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi),
      vm.Vector3.all(config.scale),
    )..multiply(vm.Matrix4.translation(-center));
    return Node(localTransform: transform)..addComponent(component);
  }

  SplatComponent? get _activeSplats =>
      _active == null ? null : _sources[_active];

  void _setActive(_SourceConfig config) {
    setState(() {
      _active = config;
      for (final entry in _sourceNodes.entries) {
        entry.value.visible = entry.key == config;
      }
      _applyKnobs();
    });
  }

  void _applyKnobs() {
    final splats = _activeSplats;
    if (splats == null) return;
    splats.opacity = _opacity;
    splats.splatScale = _splatScale;
    splats.antialiased = _antialiased;
    if (!_cropSweep) splats.setCropBox(null);
  }

  void _tickCrop(Duration elapsed) {
    if (!_cropSweep) return;
    final splats = _activeSplats;
    final active = _active;
    if (splats == null || active == null) return;
    final extent = _cropExtents[active]!;
    final t = elapsed.inMicroseconds / 1e6;
    // A wipe. A big exclude box slides through the set, eating and then
    // restoring it, evaluated per splat on the GPU so it is free to animate.
    // The box lives in the capture's local (pre-flip) space, so the sweep
    // axis is x either way.
    final sweep = math.sin(t * 0.5) * extent / active.scale;
    final half = extent / active.scale;
    splats.setCropBox(
      vm.Matrix4.compose(
        vm.Vector3(sweep - half, 0, 0),
        vm.Quaternion.identity(),
        vm.Vector3(half, half * 3, half * 3),
      ),
      mode: SplatCropMode.exclude,
    );
  }

  void _toggleFreeCamera() {
    setState(() {
      _freeCamera = !_freeCamera;
      _freeCam
        ..enabled = _freeCamera
        ..releaseKeys()
        ..move(_elapsedSeconds); // Reset the frame clock without moving.
    });
  }

  void _tickFps(double deltaSeconds) {
    _fpsAccum += deltaSeconds;
    _fpsFrames++;
    if (_fpsAccum >= 0.25) {
      _fps.value = _fpsFrames / _fpsAccum;
      _fpsAccum = 0;
      _fpsFrames = 0;
    }
  }

  vm.Vector3 _cameraPosition = vm.Vector3(0, 4, 14);

  @override
  Widget build(BuildContext context) =>
      GaussianSplatSystemChrome(child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF040408),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_active == null) {
      return const ColoredBox(
        color: Color(0xFF040408),
        child: Center(
          child: Text(
            'No splat captures found.\n'
            'Run examples/flutter_app/tool/fetch_splat_asset.sh, then '
            'restart this example.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _freeCam.onKeyEvent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: _freeCamera
                  ? (details) => setState(() => _freeCam.look(details.delta))
                  : null,
              child: SceneView(
                scene,
                cameraBuilder: (elapsed) {
                  _elapsedSeconds = elapsed.inMicroseconds / 1e6;
                  if (_freeCamera) {
                    _freeCam.move(_elapsedSeconds);
                    return _freeCam.camera;
                  }
                  final config = _active!;
                  if (_orbit) {
                    final t = _elapsedSeconds;
                    _cameraPosition = vm.Vector3(
                      math.sin(t * 0.12) * config.orbitRadius,
                      config.orbitHeight +
                          math.sin(t * 0.05) * config.orbitHeight * 0.4,
                      math.cos(t * 0.12) * config.orbitRadius,
                    );
                  }
                  final camera = PerspectiveCamera(
                    position: _cameraPosition,
                    target: vm.Vector3(0, config.targetHeight, 0),
                  );
                  // Keep the free camera parked on the live view so
                  // enabling it starts from what is on screen.
                  _freeCam.syncTo(camera);
                  return camera;
                },
                onTick: (elapsed, deltaSeconds) {
                  _tickCrop(elapsed);
                  _tickFps(deltaSeconds);
                  exampleSettings.applyTo(scene);
                },
              ),
            ),
          ),
          ExampleOverlay.bottomLeftPanel(child: _panel()),
          ExampleOverlay.bottomCenter(
            child: ExampleCameraToggle(
              active: _freeCamera,
              inactiveLabel: 'Orbit camera',
              activeLabel: 'Free camera',
              inactiveIcon: Icons.threesixty,
              activeIcon: Icons.videogame_asset,
              onToggle: _toggleFreeCamera,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel() {
    final splats = _activeSplats;
    if (splats == null) return const SizedBox.shrink();
    return GaussianSplatSettingsPanel(
      open: _controlsOpen,
      onToggle: () => setState(() => _controlsOpen = !_controlsOpen),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_sources.length > 1)
            SegmentedButton<_SourceConfig>(
              expandedInsets: EdgeInsets.zero,
              style: SegmentedButton.styleFrom(
                foregroundColor: Colors.white70,
                backgroundColor: Colors.black26,
                selectedForegroundColor: Colors.white,
                selectedBackgroundColor: Colors.white24,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              segments: [
                for (final config in _sources.keys)
                  ButtonSegment(value: config, label: Text(config.label)),
              ],
              selected: {_active!},
              onSelectionChanged: (s) => _setActive(s.first),
            ),
          const SizedBox(height: 4),
          ValueListenableBuilder<double>(
            valueListenable: _fps,
            builder: (context, fps, _) => Text(
              '${splats.splats.count} splats · ${fps.toStringAsFixed(0)} fps',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slider(
            'Opacity',
            _opacity,
            0.0,
            1.0,
            (v) => setState(() {
              _opacity = v;
              _applyKnobs();
            }),
          ),
          _slider(
            'Splat scale',
            _splatScale,
            0.2,
            2.5,
            (v) => setState(() {
              _splatScale = v;
              _applyKnobs();
            }),
          ),
          GaussianSplatToggleControls(
            antialiased: _antialiased,
            cropSweep: _cropSweep,
            orbit: _orbit,
            onAntialiasedChanged: (v) => setState(() {
              _antialiased = v;
              _applyKnobs();
            }),
            onCropSweepChanged: (v) => setState(() {
              _cropSweep = v;
              _applyKnobs();
            }),
            onOrbitChanged: (v) => setState(() => _orbit = v),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        SizedBox(
          width: 160,
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
