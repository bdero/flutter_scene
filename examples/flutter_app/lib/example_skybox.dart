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
// spheres. It also declares `requires: [environment]` and reflects a
// downloaded environment map (Helipad by default, selectable from the
// lighting panel) through `sampledEnvironment`, while its own bake keeps
// driving the scene lighting.

import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';
import 'example_settings.dart';
import 'lighting_panel.dart';

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
  _SkyType _skyType = _SkyType.fmatMenger;
  SkyEnvironment? _skyEnvironment;

  // The lighting panel's environment selection feeds the Menger sky's
  // reflections through sampledEnvironment (the scene's own environment is
  // owned by the sky bake).
  final EnvironmentSelector _environmentSelector = EnvironmentSelector();
  EnvironmentMap? _studioEnvironment;

  // Sun controls, surfaced as sliders.
  double _sunElevation = 0.5; // radians above the horizon
  double _sunAzimuth = 0.6; // radians around +Y
  double _sunSharpness = 400.0; // higher = tighter sun disk

  // Menger sky controls. Hues are in degrees; colors are derived per emitter
  // with a saturation that suits it. Travel and spin advance continuously at
  // the slider speeds, wrapping at the sponge's repeat period.
  double _mengerTravel = 1.0;
  double _mengerTravelSpeed = 1.0; // units per second
  double _mengerSpin = 0.0;
  double _mengerSpinSpeed = 0.25; // radians per second
  double _mengerHoleSize = -0.01;
  double _mengerLightHue = 82.22;
  double _mengerLightIntensity = 1.6;
  double _mengerLightHeight = 0.51;
  double _mengerGlowHue = 200.0;
  double _mengerGlowIntensity = 8.59;
  double _mengerFogHue = 220.0;
  double _mengerFogBrightness = 6.82;
  double _mengerGrade = 0.48;
  double _mengerReflection = 0.7;

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
    _mengerSky = menger..sampledEnvironment = _sampledEnvironment;
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
      refresh: _skyEnvironment?.refresh ?? SkyEnvironmentRefresh.everyFrame,
    );
    scene.skyEnvironment = _skyEnvironment;
  }

  // The Menger sky reflects the map picked in the lighting panel. The scene's
  // environment can't carry it (each sky bake overwrites it), so the resolved
  // map goes to the sky source directly; null falls back to the same studio
  // environment the renderer defaults to. Kept in a field because the panel's
  // initial download can finish before the sky loads (or after).
  EnvironmentMap? _sampledEnvironment;

  void _onEnvironmentResolved(EnvironmentMap? map) {
    _sampledEnvironment =
        map ?? (_studioEnvironment ??= EnvironmentMap.studio());
    _mengerSky?.sampledEnvironment = _sampledEnvironment;
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
          ..setFloat('grade', _mengerGrade)
          ..setFloat('reflection', _mengerReflection);
    }
  }

  // Advances the Menger sky's travel and spin at the slider speeds. Both
  // wrap at the field's period (the sponge repeats every 3 units, rotation
  // every full turn) so the march never runs into float precision.
  void _tickMengerSky(double deltaSeconds) {
    if (_skyType != _SkyType.fmatMenger) return;
    final sky = _mengerSky;
    if (sky == null) return;
    _mengerTravel = (_mengerTravel + _mengerTravelSpeed * deltaSeconds) % 3.0;
    _mengerSpin = (_mengerSpin + _mengerSpinSpeed * deltaSeconds) % (2 * pi);
    sky.parameters
      ..setFloat('travel', _mengerTravel)
      ..setFloat('spin', _mengerSpin);
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
      slider('Travel speed', _mengerTravelSpeed, 0, 6, (v) {
        _mengerTravelSpeed = v;
      }),
      slider('Spin speed', _mengerSpinSpeed, -2, 2, (v) {
        _mengerSpinSpeed = v;
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
      slider('Reflection', _mengerReflection, 0, 2, (v) {
        _mengerReflection = v;
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
            onTick: (elapsed, deltaSeconds) {
              exampleSettings.applyTo(scene);
              _tickMengerSky(deltaSeconds);
            },
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: LightingPanel(
            scene: scene,
            selector: _environmentSelector,
            manageSkybox: false,
            initialEnvironmentId: 'helipad',
            onEnvironmentResolved: _onEnvironmentResolved,
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
