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
//
// assets/menger_sky.fmat is a second, much heavier sky (a raymarched Menger
// sponge interior) driven the same way; its light, glow, and fog parameters
// change the emitted light dramatically, so re-baking visibly relights the
// spheres.

import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

class ExampleSkybox extends StatefulWidget {
  const ExampleSkybox({super.key});

  @override
  State<ExampleSkybox> createState() => _ExampleSkyboxState();
}

enum _SkyType {
  fmatGradient('Gradient (.fmat)'),
  gradient('Gradient (built-in)'),
  physical('Physical atmosphere'),
  fmatMenger('Menger sponge (.fmat)');

  const _SkyType(this.label);
  final String label;
}

class _ExampleSkyboxState extends State<ExampleSkybox> {
  final Scene scene = Scene();
  bool loaded = false;

  PreprocessedSky? _fmatSky;
  PreprocessedSky? _mengerSky;
  GradientSkySource? _gradientSky;
  PhysicalSkySource? _physicalSky;
  _SkyType _skyType = _SkyType.fmatGradient;
  SkyEnvironment? _skyEnvironment;

  // Sun controls, surfaced as sliders.
  double _sunElevation = 0.5; // radians above the horizon
  double _sunAzimuth = 0.6; // radians around +Y
  double _sunSharpness = 400.0; // higher = tighter sun disk

  // Menger sky controls. Hues are in degrees; colors are derived per emitter
  // with a saturation that suits it.
  double _mengerTravel = 1.0;
  double _mengerSpin = 0.5;
  double _mengerHoleSize = 0.03;
  double _mengerLightHue = 37.0;
  double _mengerLightIntensity = 1.6;
  double _mengerLightHeight = 1.0;
  double _mengerGlowHue = 200.0;
  double _mengerGlowIntensity = 2.0;
  double _mengerFogHue = 220.0;
  double _mengerFogBrightness = 2.5;
  double _mengerGrade = 0.5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sky = await loadFmatSky('assets/gradient_sky.fmat');
    final menger = await loadFmatSky('assets/menger_sky.fmat');
    if (!mounted) return;
    _fmatSky = sky;
    _mengerSky = menger;
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
      _SkyType.fmatMenger => _mengerSky!,
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

  // A slider hue as a light color, with a per-emitter saturation.
  vm.Vector3 _hueColor(double hueDegrees, double saturation) {
    final c = HSVColor.fromAHSV(
      1.0,
      hueDegrees % 360.0,
      saturation,
      1.0,
    ).toColor();
    return vm.Vector3(c.r, c.g, c.b);
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
      case _SkyType.fmatMenger:
        final sky = _mengerSky;
        if (sky == null) return;
        sky.parameters
          ..setFloat('travel', _mengerTravel)
          ..setFloat('spin', _mengerSpin)
          ..setFloat('hole_size', _mengerHoleSize)
          ..setVec3('light_color', _hueColor(_mengerLightHue, 0.45))
          ..setFloat('light_intensity', _mengerLightIntensity)
          ..setFloat('light_height', _mengerLightHeight)
          ..setVec3('glow_color', _hueColor(_mengerGlowHue, 0.9))
          ..setFloat('glow_intensity', _mengerGlowIntensity)
          ..setVec3('fog_color', _hueColor(_mengerFogHue, 0.3))
          ..setFloat('fog_brightness', _mengerFogBrightness)
          ..setFloat('grade', _mengerGrade);
    }
  }

  // One slider per parameter of the active sky. Each one pushes the new
  // value into the sky source; with the lighting refresh on manual, the
  // skybox updates immediately while the scene lighting holds until re-bake,
  // making the environment recompute visible.
  List<Widget> _parameterRows() {
    _SliderRow slider(
      String label,
      double value,
      double min,
      double max,
      void Function(double) assign,
    ) {
      return _SliderRow(
        label: label,
        value: value,
        min: min,
        max: max,
        onChanged: (v) => setState(() {
          assign(v);
          _refreshSky();
        }),
      );
    }

    if (_skyType != _SkyType.fmatMenger) {
      return [
        slider('Sun elevation', _sunElevation, -0.3, 1.4, (v) {
          _sunElevation = v;
        }),
        slider('Sun azimuth', _sunAzimuth, -pi, pi, (v) {
          _sunAzimuth = v;
        }),
        slider('Sun sharpness', _sunSharpness, 16, 2000, (v) {
          _sunSharpness = v;
        }),
      ];
    }
    return [
      slider('Travel', _mengerTravel, 0, 60, (v) {
        _mengerTravel = v;
      }),
      slider('Spin', _mengerSpin, -pi, pi, (v) {
        _mengerSpin = v;
      }),
      slider('Hole size', _mengerHoleSize, -0.02, 0.1, (v) {
        _mengerHoleSize = v;
      }),
      slider('Light hue', _mengerLightHue, 0, 360, (v) {
        _mengerLightHue = v;
      }),
      slider('Light intensity', _mengerLightIntensity, 0, 8, (v) {
        _mengerLightIntensity = v;
      }),
      slider('Light height', _mengerLightHeight, -1.4, 1.4, (v) {
        _mengerLightHeight = v;
      }),
      slider('Glow hue', _mengerGlowHue, 0, 360, (v) {
        _mengerGlowHue = v;
      }),
      slider('Glow intensity', _mengerGlowIntensity, 0, 12, (v) {
        _mengerGlowIntensity = v;
      }),
      slider('Fog hue', _mengerFogHue, 0, 360, (v) {
        _mengerFogHue = v;
      }),
      slider('Fog brightness', _mengerFogBrightness, 0, 8, (v) {
        _mengerFogBrightness = v;
      }),
      slider('Grade', _mengerGrade, 0, 1, (v) {
        _mengerGrade = v;
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
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
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Card(
            color: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('Sky:', style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 8),
                      DropdownButton<_SkyType>(
                        value: _skyType,
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
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
                    ],
                  ),
                  Row(
                    children: [
                      const Text(
                        'Lighting refresh:',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<SkyEnvironmentRefresh>(
                        value:
                            _skyEnvironment?.refresh ??
                            SkyEnvironmentRefresh.manual,
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
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
                          if (mode != null) _skyEnvironment?.refresh = mode;
                        }),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () => _skyEnvironment?.invalidate(),
                        child: const Text('Re-bake lighting'),
                      ),
                    ],
                  ),
                  Wrap(
                    children: [
                      for (final row in _parameterRows())
                        SizedBox(width: 380, child: row),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
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
