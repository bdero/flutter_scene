// Custom skybox example: draws a procedural sky authored as a `.fmat` sky.
//
// Demonstrates the recommended custom-sky workflow:
//   1. Author assets/gradient_sky.fmat with a `sky { vec3 Sky(vec3 direction) }`
//      block and typed parameters.
//   2. The build hook (buildMaterials) compiles it into the materials bundle.
//   3. loadFmatSky returns a PreprocessedSky (a SkySource) with typed,
//      hot-reloadable parameters; assign it to scene.skybox.
// The engine owns the full-screen draw, depth, and draw order; no geometry is
// placed for the sky. (For a raw fragment shader instead, see ShaderSkySource.)

import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_settings.dart';

class ExampleSkybox extends StatefulWidget {
  const ExampleSkybox({super.key});

  @override
  State<ExampleSkybox> createState() => _ExampleSkyboxState();
}

enum _SkyType {
  fmatGradient('Gradient (.fmat)'),
  gradient('Gradient (built-in)'),
  physical('Physical atmosphere');

  const _SkyType(this.label);
  final String label;
}

class _ExampleSkyboxState extends State<ExampleSkybox> {
  final Scene scene = Scene();
  bool loaded = false;
  bool _panelOpen = true;
  Object? _loadError;

  PreprocessedSky? _fmatSky;
  GradientSkySource? _gradientSky;
  PhysicalSkySource? _physicalSky;
  _SkyType _skyType = _SkyType.fmatGradient;
  SkyEnvironment? _skyEnvironment;

  // Sun controls, surfaced as sliders.
  double _sunElevation = 0.5; // radians above the horizon
  double _sunAzimuth = 0.6; // radians around +Y
  double _sunSharpness = 400.0; // higher = tighter sun disk

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sky = await loadFmatSky('assets/gradient_sky.fmat');
      if (!mounted) return;
      _fmatSky = sky;
      _applySkyType(_skyType);

      // Left: a smooth metallic sphere mirrors the baked environment (specular).
      scene.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 1.0),
            PhysicallyBasedMaterial()
              ..metallicFactor = 1.0
              ..roughnessFactor = 0.08,
          ),
        )..localTransform = vm.Matrix4.translationValues(-1.5, 0, 0),
      );
      // Right: a matte sphere lit by the sky's diffuse irradiance (the SH term).
      scene.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 1.0),
            PhysicallyBasedMaterial()
              ..metallicFactor = 0.0
              ..roughnessFactor = 1.0
              ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.85, 1.0),
          ),
        )..localTransform = vm.Matrix4.translationValues(1.5, 0, 0),
      );

      setState(() => loaded = true);
    } catch (error, stackTrace) {
      debugPrint('Custom Skybox could not load: $error\n$stackTrace');
      if (mounted) setState(() => _loadError = error);
    }
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  // The source for [type], created on first use. The built-in sources are
  // plain ShaderSkySource subclasses, so all three drive the skybox and the
  // lighting identically.
  ShaderSkySource _sourceFor(_SkyType type) {
    return switch (type) {
      _SkyType.fmatGradient => _fmatSky!,
      _SkyType.gradient => _gradientSky ??= GradientSkySource(),
      _SkyType.physical => _physicalSky ??= PhysicalSkySource(),
    };
  }

  // Shows [type] as the background and rebinds the lighting to it. A fresh
  // binding bakes synchronously, so switching skies relights immediately; the
  // refresh mode carries over.
  void _applySkyType(_SkyType type) {
    _skyType = type;
    final source = _sourceFor(type);
    _refreshSky();
    scene.skybox = Skybox(source);
    _skyEnvironment = SkyEnvironment(
      source,
      refresh: _skyEnvironment?.refresh ?? SkyEnvironmentRefresh.manual,
    );
    scene.skyEnvironment = _skyEnvironment;
  }

  void _refreshSky() {
    final dir = vm.Vector3(
      cos(_sunElevation) * sin(_sunAzimuth),
      sin(_sunElevation),
      cos(_sunElevation) * cos(_sunAzimuth),
    );
    switch (_skyType) {
      case _SkyType.fmatGradient:
        // Typed, name-addressed parameters from the .fmat sidecar; the colors
        // keep their .fmat defaults.
        final sky = _fmatSky;
        if (sky == null) return;
        sky.parameters.setVec3('sun_direction', dir);
        sky.parameters.setFloat('sun_sharpness', _sunSharpness);
      case _SkyType.gradient:
        _gradientSky!
          ..sunDirection = dir
          ..sunSharpness = _sunSharpness;
      case _SkyType.physical:
        // The physical sun is a disk with a fixed angular size; the sharpness
        // slider does not apply.
        _physicalSky!.sunDirection = dir;
    }
  }

  Widget _dropdownTrigger<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => ExampleDropdown<T>(
    value: value,
    triggerColor: Colors.white12,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    items: items,
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final loadError = _loadError;
    if (loadError != null) {
      return _SkyboxLoadFailure(detail: '$loadError');
    }
    if (!loaded) {
      return const _SkyboxLoading();
    }
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) {
              final t = elapsed.inMicroseconds / 1e6 * 0.25;
              return PerspectiveCamera(
                position: vm.Vector3(sin(t) * 6, 2, cos(t) * 6),
                target: vm.Vector3(0, 0, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableBodyHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight - 57
                  : 340.0;
              final bodyMaxHeight = availableBodyHeight
                  .clamp(0.0, 340.0)
                  .toDouble();

              return Card(
                color: Colors.black54,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _panelOpen = !_panelOpen),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wb_sunny_outlined,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Sky controls',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              _panelOpen
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_panelOpen) ...[
                      const Divider(height: 1, color: Colors.white24),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: bodyMaxHeight),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Sky:',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _dropdownTrigger<_SkyType>(
                                      value: _skyType,
                                      items: [
                                        for (final type in _SkyType.values)
                                          DropdownMenuItem(
                                            value: type,
                                            child: Text(type.label),
                                          ),
                                      ],
                                      onChanged: (type) => setState(() {
                                        if (type != null) _applySkyType(type);
                                      }),
                                    ),
                                  ),
                                ],
                              ),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Lighting refresh',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(height: 4),
                              _dropdownTrigger<SkyEnvironmentRefresh>(
                                value:
                                    _skyEnvironment?.refresh ??
                                    SkyEnvironmentRefresh.manual,
                                items: const [
                                  DropdownMenuItem(
                                    value: SkyEnvironmentRefresh.manual,
                                    child: Text('Manual'),
                                  ),
                                  DropdownMenuItem(
                                    value: SkyEnvironmentRefresh.interval,
                                    child: Text('Interval (1s)'),
                                  ),
                                  DropdownMenuItem(
                                    value: SkyEnvironmentRefresh.everyFrame,
                                    child: Text('Every frame'),
                                  ),
                                ],
                                onChanged: (mode) => setState(() {
                                  if (mode != null) {
                                    _skyEnvironment?.refresh = mode;
                                  }
                                }),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.white12,
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () =>
                                      _skyEnvironment?.invalidate(),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Re-bake lighting'),
                                ),
                              ),
                              _SliderRow(
                                label: 'Sun elevation',
                                value: _sunElevation,
                                min: -0.3,
                                max: 1.4,
                                onChanged: (v) => setState(() {
                                  _sunElevation = v;
                                  _refreshSky();
                                }),
                              ),
                              _SliderRow(
                                label: 'Sun azimuth',
                                value: _sunAzimuth,
                                min: -pi,
                                max: pi,
                                onChanged: (v) => setState(() {
                                  _sunAzimuth = v;
                                  _refreshSky();
                                }),
                              ),
                              _SliderRow(
                                label: 'Sun sharpness',
                                value: _sunSharpness,
                                min: 16,
                                max: 2000,
                                onChanged: (v) => setState(() {
                                  _sunSharpness = v;
                                  _refreshSky();
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkyboxLoading extends StatelessWidget {
  const _SkyboxLoading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Card(
      color: Colors.black87,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Loading custom skybox...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _SkyboxLoadFailure extends StatelessWidget {
  const _SkyboxLoadFailure({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      color: Colors.black87,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Custom Skybox could not load',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(detail, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    ),
  );
}
