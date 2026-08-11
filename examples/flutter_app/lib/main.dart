import 'package:example_app/example_car.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart'
    show
        AmbientOcclusionMethod,
        AntiAliasingMode,
        DepthOfFieldQuality,
        Scene,
        PostInsertion,
        ShadowCasterFaces,
        SpecularAmbientOcclusionMode;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart'
    show RapierWorld;
import 'package:flutter_scene_box3d/flutter_scene_box3d.dart'
    show Box3dPhysicsWorld;
import 'package:example_app/example_animation.dart';

import 'example_accessibility.dart';
import 'example_audio.dart';
import 'example_auto_exposure.dart';
import 'example_configurator.dart';
import 'example_dicom.dart';
import 'example_lights.dart';
import 'example_spot_shadow.dart';
import 'example_fscene.dart';
import 'example_fscene_animated.dart';
import 'example_fscene_import.dart';
import 'example_fscene_prefab.dart';
import 'example_fscene_stream.dart';
import 'example_lod.dart';
import 'example_logo.dart';
import 'example_materialize.dart';
import 'example_multiplayer.dart';
import 'example_nav_route.dart';
import 'example_physics.dart';
import 'example_physics_box3d.dart';
import 'example_physics_car.dart';
import 'example_render_target.dart';
import 'example_settings.dart';
import 'example_chrome.dart';
import 'example_shapes.dart';
import 'example_explosion.dart';
import 'example_particles.dart';
import 'example_splats.dart';
import 'example_skybox.dart';
import 'example_ssr.dart';
import 'example_widget_texture.dart';
import 'example_split_screen.dart';
import 'example_stress_tests.dart';
import 'example_raw_shader.dart';
import 'example_toon.dart';
import 'example_toon_fmat.dart';
import 'example_vertex_curve.dart';

void main() {
  runApp(const MyApp());
}

/// Per-example overrides of the stock [ExampleSettings] defaults, keyed by
/// the example's name in the picker. Examples not listed start from the
/// stock defaults. Every example gets its own fresh instance either way
/// (see [resetExampleSettings]), so tuning one scene never leaks into
/// another.
final Map<String, ExampleSettings Function()> settingsDefaults = {
  // The campfire's night look: a soft blue moonlight key from the south,
  // ambient occlusion grounding the logs, rocks, and grass, and a warm
  // saturated grade that leans into the firelight.
  'Particles': () => ExampleSettings()
    ..lightAzimuthDegrees = 190.70
    ..lightElevationDegrees = 16.79
    ..lightIntensity = 0.97
    ..lightColor.setValues(1.0, 0.80, 1.0)
    ..ambientOcclusion.enabled = true
    ..ambientOcclusion.halfResolution = true
    ..ambientOcclusion.radius = 0.66
    ..ambientOcclusion.intensity = 2.02
    ..ambientOcclusion.bias = 0.053
    ..ambientOcclusion.sampleCount = 17
    ..colorGrading.enabled = true
    ..colorGrading.brightness = 1.39
    ..colorGrading.contrast = 0.93
    ..colorGrading.saturation = 1.36
    ..colorGrading.temperature = 0.35
    ..colorGrading.tint = -0.31
    ..bloom.enabled = true
    ..bloom.threshold = 3.63
    ..bloom.intensity = 0.089
    ..bloom.scatter = 1.0
    ..godRays.enabled = true
    ..godRays.intensity = 1.24
    ..godRays.density = 0.63
    ..godRays.anisotropy = 0.40
    ..godRays.stepCount = 5
    ..godRays.maxDistance = 141.70
    ..godRays.jitter = 1.0
    ..godRays.color.setValues(0.77, 0.90, 1.0)
    ..depthOfField.enabled = true
    ..depthOfField.focusDistance = 7.07
    ..depthOfField.fStop = 8.98
    ..depthOfField.focalLength = 0.178
    ..depthOfField.blurScale = 1.0
    ..depthOfField.quality = DepthOfFieldQuality.medium
    ..chromaticAberration.enabled = true
    ..chromaticAberration.intensity = 0.151
    ..vignette.enabled = true
    ..vignette.intensity = 0.71
    ..vignette.radius = 0.71
    ..vignette.smoothness = 0.5,
  // A strong sun for the adaptation walk: the outdoor half of the path
  // should overexpose while the meter is adapted to the room.
  'Auto Exposure': () => ExampleSettings()..lightIntensity = 7.0,
  'Stress Tests': () => ExampleSettings()..directionalLightEnabled = false,
  // A cinematic grade for the dark materialize stage: no key light (the
  // effect's own emissives and the environment carry it), bloom for the hot
  // seam and shard glows, and a subtle lens treatment.
  'Materialize (.fmat)': () => ExampleSettings()
    ..directionalLightEnabled = false
    ..colorGrading.enabled = true
    ..colorGrading.brightness = 1.05
    ..colorGrading.contrast = 1.19
    ..colorGrading.saturation = 1.16
    ..colorGrading.temperature = -0.20
    ..colorGrading.tint = 0.01
    ..bloom.enabled = true
    ..bloom.intensity = 0.06
    ..chromaticAberration.enabled = true
    ..chromaticAberration.intensity = 0.14
    ..vignette.enabled = true,
  // The Menger sky's look: no key light (the sky's emitters and the baked
  // environment carry it), a bright cool saturated grade, bloom for the neon
  // bracing, and a lens treatment.
  'Custom Skybox': () => ExampleSettings()
    ..directionalLightEnabled = false
    ..colorGrading.enabled = true
    ..colorGrading.brightness = 1.15
    ..colorGrading.contrast = 1.07
    ..colorGrading.saturation = 1.19
    ..colorGrading.temperature = -0.37
    ..colorGrading.tint = -0.05
    ..bloom.enabled = true
    ..bloom.threshold = 1.35
    ..chromaticAberration.enabled = true
    ..chromaticAberration.intensity = 0.32
    ..vignette.enabled = true,
};

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String selectedExample = '';
  Map<String, WidgetBuilder> examples = {};
  late final Future<void> _ready;

  // The Rapier wasm module (~1 MB on the web) loads in the background as
  // soon as the app starts, but only the Physics example waits on it, so
  // the other examples are not delayed by it. A no-op on native.
  final Future<void> _physicsReady = RapierWorld.ensureInitialized();
  final Future<void> _box3dReady = Box3dPhysicsWorld.ensureInitialized();

  @override
  void initState() {
    // Each example owns its own per-frame loop through SceneView, so there
    // is no app-level ticker here.
    examples = {
      'Car': (context) => const ExampleCar(),
      'Animation': (context) => const ExampleAnimation(),
      'Flutter Logo': (context) => const ExampleLogo(),
      'Multiplayer': (context) => const ExampleMultiplayer(),
      'Configurator': (context) => const ExampleConfigurator(),
      'Lights': (context) => const ExampleLights(),
      'Spot Shadow': (context) => const ExampleSpotShadow(),
      'Particles': (context) => const ExampleParticles(),
      'Explosions': (context) => const ExampleExplosion(),
      'Gaussian Splats': (context) => const ExampleSplats(),
      'Geometry LOD': (context) => const ExampleLod(),
      'Screen-space Reflections': (context) => const ExampleSsr(),
      'Auto Exposure': (context) => const ExampleAutoExposure(),
      'Navigation Route': (context) => const ExampleNavRoute(),
      'Toon': (context) => const ExampleToon(),
      'Raw shader': (context) => const ExampleRawShader(),
      'Toon (.fmat)': (context) => const ExampleToonFmat(),
      'Custom vertices (.fmat)': (context) => const ExampleVertexCurve(),
      'Materialize (.fmat)': (context) => const ExampleMaterialize(),
      'DICOM Volume': (context) => const ExampleDicom(),
      'Custom Skybox': (context) => const ExampleSkybox(),
      'Audio': (context) => const ExampleAudio(),
      'Widget Texture': (context) => const ExampleWidgetTexture(),
      'Accessibility': (context) => const ExampleAccessibility(),
      'Render Targets': (context) => const ExampleRenderTarget(),
      'Physics': (context) => FutureBuilder<void>(
        // The Rapier backend needs its wasm module loaded before a world
        // can be built on the web; wait on it here so only this example
        // pays the cost.
        future: _physicsReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const ExamplePhysics();
        },
      ),
      'Physics (box3d)': (context) => FutureBuilder<void>(
        // The box3d backend readiness (a no-op on native; the wasm load on
        // the web) before a world can be built.
        future: _box3dReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const ExamplePhysicsBox3d();
        },
      ),
      'Car Physics': (context) => FutureBuilder<void>(
        // Shares the Rapier backend with the Physics example, so it waits on
        // the same wasm load before building its world.
        future: _physicsReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const ExamplePhysicsCar();
        },
      ),
      'Shapes': (context) => FutureBuilder<void>(
        // Shares the Rapier backend with the Physics example, so it waits on
        // the same wasm load before building its world.
        future: _physicsReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return const ExampleShapes();
        },
      ),
      'fscene': (context) => const ExampleFscene(),
      'fscene (import)': (context) => const ExampleFsceneImport(),
      'fscene (animated)': (context) => const ExampleFsceneAnimated(),
      'fscene (prefab)': (context) => const ExampleFscenePrefab(),
      'fscene (stream)': (context) => const ExampleFsceneStream(),
      'Split Screen': (context) => const ExampleSplitScreen(),
      'Stress Tests': (context) => const ExampleStressTests(),
    };
    selectedExample = examples.keys.first;
    resetExampleSettings(settingsDefaults[selectedExample]);

    _ready = Future.wait([
      Scene.initializeStaticResources(),
      loadExampleEffects(),
    ]);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_scene Example App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      home: Scaffold(
        body: FutureBuilder<void>(
          // Gate example construction on static-resource init. Examples build
          // geometry/materials in initState, which touches the shader bundle;
          // on web that bundle must finish loading first (sync asset reads
          // aren't possible there).
          future: _ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return Stack(
              children: [
                SizedBox.expand(child: examples[selectedExample]!(context)),
                // Example picker (top-left, overlaid on the scene).
                ValueListenableBuilder<bool>(
                  valueListenable: exampleChromeVisible,
                  builder: (context, visible, child) =>
                      Offstage(offstage: !visible, child: child),
                  child: SafeArea(
                    minimum: const EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _ExamplePicker(
                        examples: examples.keys.toList(growable: false),
                        selected: selectedExample,
                        onSelected: (next) {
                          setState(() {
                            selectedExample = next;
                            // Every example runs on its own settings instance;
                            // examples listed in settingsDefaults start from
                            // their own defaults instead of the stock ones.
                            resetExampleSettings(settingsDefaults[next]);
                          });
                        },
                      ),
                    ),
                  ),
                ),
                // Settings sidebar (top-right): global post-processing
                // controls applied to whichever example is on screen.
                ValueListenableBuilder<bool>(
                  valueListenable: exampleChromeVisible,
                  builder: (context, visible, child) =>
                      Offstage(offstage: !visible, child: child),
                  child: const SafeArea(
                    minimum: EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _SettingsSidebar(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Top-left example selector. Uses [PopupMenuButton] so the menu opens
/// as an overlay above any of the example screens — a plain
/// [DropdownButton] tries to draw in-line and ended up clipped behind
/// list content on the stress-tests screen.
class _ExamplePicker extends StatelessWidget {
  const _ExamplePicker({
    required this.examples,
    required this.selected,
    required this.onSelected,
  });

  final List<String> examples;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: PopupMenuButton<String>(
        initialValue: selected,
        onSelected: onSelected,
        tooltip: 'Switch example',
        itemBuilder: (context) => [
          for (final name in examples)
            PopupMenuItem<String>(value: name, child: Text(name)),
        ],
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(selected, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsible settings sidebar (top-right). Edits the shared
/// [exampleSettings], which every example applies to its scene before
/// rendering, so one set of controls drives whichever example is shown.
///
/// Effects are grouped under collapsible sections so more can be added as
/// the post-processing suite grows.
class _SettingsSidebar extends StatefulWidget {
  const _SettingsSidebar();

  @override
  State<_SettingsSidebar> createState() => _SettingsSidebarState();
}

class _SettingsSidebarState extends State<_SettingsSidebar> {
  bool _expanded = false;
  double _width = 320;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: 0.95);

    if (!_expanded) {
      return Material(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: IconButton(
          icon: const Icon(Icons.tune),
          tooltip: 'Settings',
          onPressed: () => setState(() => _expanded = true),
        ),
      );
    }

    final maxWidth = MediaQuery.of(context).size.width - 32;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: SizedBox(
        width: _width.clamp(280.0, maxWidth),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height - 16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag the panel's left edge to resize it.
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => setState(() {
                    _width = (_width - details.delta.dx).clamp(280.0, maxWidth);
                  }),
                  child: const SizedBox(
                    width: 8,
                    child: Center(
                      child: SizedBox(
                        width: 2,
                        height: 32,
                        child: ColoredBox(color: Colors.black26),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                      child: Row(
                        children: [
                          Text(
                            'Settings',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.receipt_long),
                            tooltip: 'Print all settings to the log',
                            onPressed: () => debugPrint(
                              'Shared settings dump:\n'
                              '${exampleSettings.describe()}',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Close settings',
                            onPressed: () => setState(() => _expanded = false),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildRendering(),
                            _buildDirectionalLight(),
                            _buildAmbientOcclusion(),
                            _buildPostProcessing(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRendering() {
    final msaaSupported = Scene.isAntiAliasingModeSupported(
      AntiAliasingMode.msaa,
    );
    return ExpansionTile(
      title: const Text('Rendering'),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        Row(
          children: [
            const Text('Anti-aliasing'),
            const Spacer(),
            DropdownButton<AntiAliasingMode>(
              value: exampleSettings.antiAliasingMode,
              onChanged: (value) {
                if (value != null) {
                  setState(() => exampleSettings.antiAliasingMode = value);
                }
              },
              items: [
                for (final mode in AntiAliasingMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.name)),
              ],
            ),
          ],
        ),
        if (!msaaSupported)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'MSAA is unavailable on this backend; msaa and auto render '
              'with FXAA.',
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _slider(
                'Render scale',
                exampleSettings.renderScale,
                0.001,
                2,
                (v) {
                  exampleSettings.renderScale = v;
                },
                decimals: 3,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 18),
              tooltip: 'Reset render scale',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => exampleSettings.renderScale = 1.0),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Filter'),
            const Spacer(),
            DropdownButton<FilterQuality>(
              value: exampleSettings.filterQuality,
              onChanged: (value) {
                if (value != null) {
                  setState(() => exampleSettings.filterQuality = value);
                }
              },
              items: [
                for (final quality in FilterQuality.values)
                  DropdownMenuItem(value: quality, child: Text(quality.name)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPostProcessing() {
    return ExpansionTile(
      title: const Text('Post-processing'),
      initiallyExpanded: true,
      childrenPadding: EdgeInsets.zero,
      children: [
        _buildColorGrading(),
        _buildBloom(),
        _buildGodRays(),
        _buildDepthOfField(),
        _buildChromaticAberration(),
        _buildVignette(),
        _buildFilmGrain(),
        _buildCustomEffect(),
      ],
    );
  }

  Widget _buildDirectionalLight() {
    final settings = exampleSettings;
    return ExpansionTile(
      title: const Text('Directional light'),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.directionalLightEnabled,
          onChanged: (value) =>
              setState(() => settings.directionalLightEnabled = value),
        ),
        _slider('Azimuth', settings.lightAzimuthDegrees, 0, 360, (v) {
          settings.lightAzimuthDegrees = v;
        }),
        _slider('Elevation', settings.lightElevationDegrees, 0, 90, (v) {
          settings.lightElevationDegrees = v;
        }),
        _slider('Intensity', settings.lightIntensity, 0, 10, (v) {
          settings.lightIntensity = v;
        }),
        _slider('Color R', settings.lightColor.r, 0, 1, (v) {
          settings.lightColor.r = v;
        }),
        _slider('Color G', settings.lightColor.g, 0, 1, (v) {
          settings.lightColor.g = v;
        }),
        _slider('Color B', settings.lightColor.b, 0, 1, (v) {
          settings.lightColor.b = v;
        }),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Casts shadow'),
          value: settings.lightCastsShadow,
          onChanged: (value) =>
              setState(() => settings.lightCastsShadow = value),
        ),
        _slider('Softness', settings.shadowSoftness, 0, 0.3, (v) {
          settings.shadowSoftness = v;
        }),
        _slider('Fade range', settings.shadowFadeRange, 0, 20, (v) {
          settings.shadowFadeRange = v;
        }),
        _slider('Cascades', settings.shadowCascadeCount.toDouble(), 1, 4, (v) {
          settings.shadowCascadeCount = v.round();
        }, decimals: 0),
        _slider('Max distance', settings.shadowMaxDistance, 10, 500, (v) {
          settings.shadowMaxDistance = v;
        }, decimals: 0),
        _slider('Split lambda', settings.shadowCascadeSplitLambda, 0, 1, (v) {
          settings.shadowCascadeSplitLambda = v;
        }),
        Row(
          children: [
            const Text('Resolution'),
            const Spacer(),
            DropdownButton<int>(
              value: settings.shadowMapResolution,
              onChanged: (value) {
                if (value != null) {
                  setState(() => settings.shadowMapResolution = value);
                }
              },
              items: [
                for (final resolution in const [256, 512, 1024, 2048, 4096])
                  DropdownMenuItem(
                    value: resolution,
                    child: Text('$resolution'),
                  ),
              ],
            ),
          ],
        ),
        _slider('Depth bias', settings.shadowDepthBias, 0, 0.1, (v) {
          settings.shadowDepthBias = v;
        }, decimals: 3),
        _slider('Normal bias', settings.shadowNormalBias, 0, 0.1, (v) {
          settings.shadowNormalBias = v;
        }, decimals: 3),
        _slider('Ambient str.', settings.shadowAmbientStrength, 0, 1, (v) {
          settings.shadowAmbientStrength = v;
        }),
        Row(
          children: [
            const Text('Caster faces'),
            const Spacer(),
            DropdownButton<ShadowCasterFaces>(
              value: settings.shadowCasterFaces,
              onChanged: (value) {
                if (value != null) {
                  setState(() => settings.shadowCasterFaces = value);
                }
              },
              items: [
                for (final faces in ShadowCasterFaces.values)
                  DropdownMenuItem(value: faces, child: Text(faces.name)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAmbientOcclusion() {
    final settings = exampleSettings.ambientOcclusion;
    return ExpansionTile(
      title: const Text('Ambient occlusion'),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.enabled,
          onChanged: (value) => setState(() => settings.enabled = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ground-truth method'),
          value: settings.method == AmbientOcclusionMethod.groundTruth,
          onChanged: (value) => setState(() {
            settings.method = value
                ? AmbientOcclusionMethod.groundTruth
                : AmbientOcclusionMethod.obscurance;
          }),
        ),
        _slider('Radius', settings.radius, 0.05, 2, (v) {
          settings.radius = v;
        }),
        _slider('Intensity', settings.intensity, 0, 3, (v) {
          settings.intensity = v;
        }),
        if (settings.method == AmbientOcclusionMethod.groundTruth) ...[
          _slider('Slices', settings.sliceCount.toDouble(), 1, 8, (v) {
            settings.sliceCount = v.round();
          }),
          _slider('Steps per slice', settings.stepsPerSlice.toDouble(), 1, 8, (
            v,
          ) {
            settings.stepsPerSlice = v.round();
          }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visibility bitmask'),
            value: settings.visibilityBitmask,
            onChanged: (value) =>
                setState(() => settings.visibilityBitmask = value),
          ),
          if (settings.visibilityBitmask)
            _slider('Thickness', settings.thickness, 0.05, 2, (v) {
              settings.thickness = v;
            })
          else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bent normals'),
              value: settings.bentNormals,
              onChanged: (value) =>
                  setState(() => settings.bentNormals = value),
            ),
        ] else ...[
          _slider('Bias', settings.bias, 0, 0.1, (v) {
            settings.bias = v;
          }),
          _slider('Samples', settings.sampleCount.toDouble(), 4, 32, (v) {
            settings.sampleCount = v.round();
          }),
        ],
        _slider('Multi bounce', settings.multiBounce, 0, 1, (v) {
          settings.multiBounce = v;
        }),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Half resolution'),
          value: settings.halfResolution,
          onChanged: (value) => setState(() => settings.halfResolution = value),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Specular occlusion'),
          trailing: DropdownButton<SpecularAmbientOcclusionMode>(
            value: settings.specularMode,
            onChanged: (mode) => setState(() {
              settings.specularMode = mode ?? SpecularAmbientOcclusionMode.none;
            }),
            items: [
              for (final mode in SpecularAmbientOcclusionMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.name)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorGrading() {
    final grading = exampleSettings.colorGrading;
    return ExpansionTile(
      title: const Text('Color grading'),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: grading.enabled,
          onChanged: (value) => setState(() => grading.enabled = value),
        ),
        _slider('Brightness', grading.brightness, 0, 2, (v) {
          grading.brightness = v;
        }),
        _slider('Contrast', grading.contrast, 0, 2, (v) {
          grading.contrast = v;
        }),
        _slider('Saturation', grading.saturation, 0, 2, (v) {
          grading.saturation = v;
        }),
        _slider('Temperature', grading.temperature, -1, 1, (v) {
          grading.temperature = v;
        }),
        _slider('Tint', grading.tint, -1, 1, (v) {
          grading.tint = v;
        }),
      ],
    );
  }

  Widget _buildChromaticAberration() {
    final settings = exampleSettings.chromaticAberration;
    return ExpansionTile(
      title: const Text('Chromatic aberration'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.enabled,
          onChanged: (value) => setState(() => settings.enabled = value),
        ),
        _slider('Intensity', settings.intensity, 0, 1, (v) {
          settings.intensity = v;
        }),
      ],
    );
  }

  Widget _buildVignette() {
    final settings = exampleSettings.vignette;
    return ExpansionTile(
      title: const Text('Vignette'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.enabled,
          onChanged: (value) => setState(() => settings.enabled = value),
        ),
        _slider('Intensity', settings.intensity, 0, 1, (v) {
          settings.intensity = v;
        }),
        _slider('Radius', settings.radius, 0, 1.5, (v) {
          settings.radius = v;
        }),
        _slider('Smoothness', settings.smoothness, 0, 1, (v) {
          settings.smoothness = v;
        }),
      ],
    );
  }

  Widget _buildFilmGrain() {
    final settings = exampleSettings.filmGrain;
    return ExpansionTile(
      title: const Text('Film grain'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.enabled,
          onChanged: (value) => setState(() => settings.enabled = value),
        ),
        _slider('Intensity', settings.intensity, 0, 1, (v) {
          settings.intensity = v;
        }),
      ],
    );
  }

  Widget _buildBloom() {
    final settings = exampleSettings.bloom;
    return ExpansionTile(
      title: const Text('Bloom'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.enabled,
          onChanged: (value) => setState(() => settings.enabled = value),
        ),
        _slider('Threshold', settings.threshold, 0, 4, (v) {
          settings.threshold = v;
        }),
        _slider('Intensity', settings.intensity, 0, 2, (v) {
          settings.intensity = v;
        }),
        _slider('Scatter', settings.scatter, 0, 1, (v) {
          settings.scatter = v;
        }),
      ],
    );
  }

  Widget _buildGodRays() {
    final settings = exampleSettings.godRays;
    return ExpansionTile(
      title: const Text('God rays'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.enabled,
          onChanged: (value) => setState(() => settings.enabled = value),
        ),
        _slider('Intensity', settings.intensity, 0, 4, (v) {
          settings.intensity = v;
        }),
        _slider('Density', settings.density, 0, 2, (v) {
          settings.density = v;
        }),
        _slider('Anisotropy', settings.anisotropy, -0.95, 0.95, (v) {
          settings.anisotropy = v;
        }),
        _slider('Steps', settings.stepCount.toDouble(), 1, 64, (v) {
          settings.stepCount = v.round();
        }),
        _slider('Max distance', settings.maxDistance, 1, 400, (v) {
          settings.maxDistance = v;
        }),
        _slider('Jitter', settings.jitter, 0, 1, (v) {
          settings.jitter = v;
        }),
        _slider('Color R', settings.color.r, 0, 1, (v) {
          settings.color.r = v;
        }),
        _slider('Color G', settings.color.g, 0, 1, (v) {
          settings.color.g = v;
        }),
        _slider('Color B', settings.color.b, 0, 1, (v) {
          settings.color.b = v;
        }),
      ],
    );
  }

  Widget _buildDepthOfField() {
    final settings = exampleSettings.depthOfField;
    return ExpansionTile(
      title: const Text('Depth of field'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: settings.enabled,
          onChanged: (value) => setState(() => settings.enabled = value),
        ),
        _slider('Focus dist.', settings.focusDistance, 0.1, 40, (v) {
          settings.focusDistance = v;
        }),
        _slider('f-stop', settings.fStop, 0.7, 22, (v) {
          settings.fStop = v;
        }),
        _slider('Focal length', settings.focalLength, 0, 0.2, (v) {
          settings.focalLength = v;
        }),
        _slider('Blur scale', settings.blurScale, 0, 3, (v) {
          settings.blurScale = v;
        }),
        _slider('Max fg blur', settings.maxForegroundBlur, 0, 64, (v) {
          settings.maxForegroundBlur = v;
        }),
        _slider('Max bg blur', settings.maxBackgroundBlur, 0, 64, (v) {
          settings.maxBackgroundBlur = v;
        }),
        _slider('Blades', settings.bladeCount.toDouble(), 0, 8, (v) {
          settings.bladeCount = v.round();
        }),
        _slider('Blade rot.', settings.bladeRotation, 0, 3.14, (v) {
          settings.bladeRotation = v;
        }),
        _slider('Blade curve', settings.bladeCurvature, 0, 1, (v) {
          settings.bladeCurvature = v;
        }),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Quality'),
          trailing: DropdownButton<DepthOfFieldQuality>(
            value: settings.quality,
            onChanged: (value) => setState(() {
              if (value != null) settings.quality = value;
            }),
            items: [
              for (final q in DepthOfFieldQuality.values)
                DropdownMenuItem(value: q, child: Text(q.name)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomEffect() {
    final effect = exampleSettings.waveEffect;
    if (effect == null) {
      return const SizedBox.shrink();
    }
    return ExpansionTile(
      title: const Text('Custom: wave'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enabled'),
          value: effect.enabled,
          onChanged: (value) => setState(() => effect.enabled = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('After tone mapping'),
          value: effect.insertion == PostInsertion.afterTonemap,
          onChanged: (value) => setState(() {
            effect.insertion = value
                ? PostInsertion.afterTonemap
                : PostInsertion.beforeTonemap;
          }),
        ),
        _slider('Amplitude', exampleSettings.waveAmplitude, 0, 0.03, (v) {
          exampleSettings.waveAmplitude = v;
        }),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int decimals = 2,
  }) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: textStyle)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => setState(() => onChanged(v)),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toStringAsFixed(decimals),
            style: textStyle,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
