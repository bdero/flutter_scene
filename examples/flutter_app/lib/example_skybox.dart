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
// scene. It also declares `requires: [environment]` and reflects a
// downloaded environment map (Field by default, selectable from the
// lighting panel) through `sampledEnvironment`, while its own bake keeps
// driving the scene lighting.
//
// The lit content is a 5x5 grid of randomly spinning random shapes, metallic
// ascending along one axis and roughness along the other, so every
// combination of the baked environment's specular and diffuse response is
// visible at once.

import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';
import 'example_settings.dart';
import 'lighting_panel.dart';
import 'quake_camera.dart';

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
  double _mengerTravelSpeed = 1.22; // units per second
  double _mengerSpin = 0.0;
  double _mengerSpinSpeed = 0.30; // radians per second
  double _mengerHoleSize = -0.02;
  double _mengerLightHue = 153.94;
  double _mengerLightIntensity = 0.25;
  double _mengerLightHeight = 0.51;
  double _mengerGlowHue = 134.60;
  double _mengerGlowIntensity = 8.59;
  double _mengerFogHue = 259.43;
  double _mengerFogBrightness = 3.15;
  double _mengerGrade = 0.59;
  double _mengerReflection = 1.44;

  // The 5x5 shape grid: metallic ascends along +X, roughness along +Z. Each
  // shape tumbles around its own random axis at its own rate, scaled by the
  // shared spin slider.
  static const int _gridSize = 5;
  static const double _gridSpacing = 1.5;
  final List<Node> _shapeNodes = [];
  final List<vm.Vector3> _shapePositions = [];
  final List<vm.Vector3> _shapeAxes = [];
  final List<double> _shapeAngles = [];
  final List<double> _shapeRates = [];
  double _shapeSpinSpeed = 1.0; // radians per second, per-shape scaled
  double _cameraDistance = 8.0;

  // Optional detached "quake" fly camera, as in the DICOM example.
  bool _freeCamera = false;
  final QuakeCamera _freeCam = QuakeCamera();
  double _elapsedSeconds = 0.0;

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

    _buildShapeGrid();

    setState(() => loaded = true);
  }

  // A random primitive, roughly matched in visual size.
  MeshGeometry _randomShape(Random rng) => switch (rng.nextInt(6)) {
    0 => SphereGeometry(radius: 0.45),
    1 => CuboidGeometry(vm.Vector3(0.7, 0.7, 0.7)),
    2 => CylinderGeometry(bottomRadius: 0.35, topRadius: 0.35, height: 0.8),
    3 => CapsuleGeometry(radius: 0.28, height: 0.5),
    4 => TorusGeometry(radius: 0.35, tubeRadius: 0.15),
    _ => WedgeGeometry(vm.Vector3(0.7, 0.7, 0.7)),
  };

  void _buildShapeGrid() {
    // Fixed seed so the assortment is stable across runs.
    final rng = Random(1337);
    for (var ix = 0; ix < _gridSize; ix++) {
      for (var iz = 0; iz < _gridSize; iz++) {
        final node = Node(
          mesh: Mesh(
            _randomShape(rng),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.85, 1.0)
              ..metallicFactor = ix / (_gridSize - 1)
              ..roughnessFactor = iz / (_gridSize - 1),
          ),
        );
        _shapePositions.add(
          vm.Vector3(
            (ix - (_gridSize - 1) / 2) * _gridSpacing,
            0,
            (iz - (_gridSize - 1) / 2) * _gridSpacing,
          ),
        );
        var axis = vm.Vector3(
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
        );
        if (axis.length2 < 1e-3) axis = vm.Vector3(0, 1, 0);
        _shapeAxes.add(axis..normalize());
        _shapeAngles.add(rng.nextDouble() * 2 * pi);
        _shapeRates.add(0.5 + rng.nextDouble());
        _shapeNodes.add(node);
        scene.add(node);
      }
    }
    _updateShapeTransforms();
  }

  void _updateShapeTransforms() {
    for (var i = 0; i < _shapeNodes.length; i++) {
      _shapeNodes[i].localTransform = vm.Matrix4.translation(_shapePositions[i])
        ..rotate(_shapeAxes[i], _shapeAngles[i]);
    }
  }

  void _tickShapes(double deltaSeconds) {
    if (_shapeSpinSpeed == 0.0) return;
    for (var i = 0; i < _shapeAngles.length; i++) {
      _shapeAngles[i] =
          (_shapeAngles[i] + _shapeRates[i] * _shapeSpinSpeed * deltaSeconds) %
          (2 * pi);
    }
    _updateShapeTransforms();
  }

  PerspectiveCamera _orbitCamera(double seconds) {
    final t = seconds * 0.25;
    return PerspectiveCamera(
      position: vm.Vector3(
        sin(t) * _cameraDistance,
        _cameraDistance * 0.4,
        cos(t) * _cameraDistance,
      ),
      target: vm.Vector3(0, 0, 0),
    );
  }

  // Toggles the detached fly camera. Turning it on adopts the current orbit
  // pose so the view does not jump; turning it off drops back to the orbit.
  void _toggleFreeCamera() {
    setState(() {
      _freeCamera = !_freeCamera;
      if (_freeCamera) _freeCam.syncTo(_orbitCamera(_elapsedSeconds));
      _freeCam
        ..enabled = _freeCamera
        ..releaseKeys()
        ..move(_elapsedSeconds); // reset the frame clock without moving
    });
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

    // Scene controls shown for every sky.
    final common = [
      slider('Shape spin', _shapeSpinSpeed, 0, 4, (v) {
        _shapeSpinSpeed = v;
      }),
      slider('Camera distance', _cameraDistance, 3, 20, (v) {
        _cameraDistance = v;
      }),
    ];

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
        ...common,
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
      ...common,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _freeCam.onKeyEvent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: (d) {
                if (_freeCamera) _freeCam.look(d.delta);
              },
              child: SceneView(
                scene,
                cameraBuilder: (elapsed) => _freeCamera
                    ? _freeCam.camera
                    : _orbitCamera(elapsed.inMicroseconds / 1e6),
                onTick: (elapsed, deltaSeconds) {
                  exampleSettings.applyTo(scene);
                  _elapsedSeconds = elapsed.inMicroseconds / 1e6;
                  if (_freeCamera) {
                    _freeCam.move(_elapsedSeconds);
                  } else {
                    // Keep the free camera glued to the orbit pose so
                    // toggling it on never jumps.
                    _freeCam.syncTo(_orbitCamera(_elapsedSeconds));
                  }
                  _tickMengerSky(deltaSeconds);
                  _tickShapes(deltaSeconds);
                },
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: LightingPanel(
              scene: scene,
              selector: _environmentSelector,
              manageSkybox: false,
              initialEnvironmentId: 'field',
              initialExposure: 1.63,
              initialIblIntensity: 1.14,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _toggleFreeCamera,
                          icon: Icon(
                            _freeCamera
                                ? Icons.videocam
                                : Icons.videocam_outlined,
                          ),
                          label: Text(
                            _freeCamera ? 'Quake camera' : 'Orbit camera',
                          ),
                        ),
                        if (_freeCamera) ...[
                          const SizedBox(width: 12),
                          const Text(
                            'WASD move · QE up/down · drag to look · '
                            'shift to boost',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
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
      ),
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
