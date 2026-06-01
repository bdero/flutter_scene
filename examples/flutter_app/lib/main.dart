import 'package:example_app/example_car.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart'
    show Scene, PostInsertion, SpecularAmbientOcclusionMode;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart'
    show RapierWorld;
import 'package:example_app/example_animation.dart';

import 'example_cuboid.dart';
import 'example_instancing.dart';
import 'example_logo.dart';
import 'example_nav_route.dart';
import 'example_physics.dart';
import 'example_settings.dart';
import 'example_stress_tests.dart';
import 'example_toon.dart';
import 'example_toon_fmat.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Ticker ticker;
  double elapsedSeconds = 0;
  String selectedExample = '';
  Map<String, WidgetBuilder> examples = {};
  late final Future<void> _ready;

  // The Rapier wasm module (~1 MB on the web) loads in the background as
  // soon as the app starts, but only the Physics example waits on it, so
  // the other examples are not delayed by it. A no-op on native.
  final Future<void> _physicsReady = RapierWorld.ensureInitialized();

  @override
  void initState() {
    ticker = Ticker((elapsed) {
      setState(() {
        elapsedSeconds = elapsed.inMilliseconds.toDouble() / 1000;
      });
    });
    ticker.start();

    examples = {
      'Car': (context) => ExampleCar(elapsedSeconds: elapsedSeconds),
      'Animation': (context) =>
          ExampleAnimation(elapsedSeconds: elapsedSeconds),
      'Flutter Logo': (context) => ExampleLogo(elapsedSeconds: elapsedSeconds),
      'Cuboid': (context) => ExampleCuboid(elapsedSeconds: elapsedSeconds),
      'Instancing': (context) =>
          ExampleInstancing(elapsedSeconds: elapsedSeconds),
      'Navigation Route': (context) =>
          ExampleNavRoute(elapsedSeconds: elapsedSeconds),
      'Toon': (context) => ExampleToon(elapsedSeconds: elapsedSeconds),
      'Toon (.fmat)': (context) =>
          ExampleToonFmat(elapsedSeconds: elapsedSeconds),
      'Physics': (context) => FutureBuilder<void>(
        // The Rapier backend needs its wasm module loaded before a world
        // can be built on the web; wait on it here so only this example
        // pays the cost.
        future: _physicsReady,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ExamplePhysics(elapsedSeconds: elapsedSeconds);
        },
      ),
      'Stress Tests': (context) =>
          ExampleStressTests(elapsedSeconds: elapsedSeconds),
    };
    selectedExample = examples.keys.first;

    _ready = Future.wait([
      Scene.initializeStaticResources(),
      loadExampleEffects(),
    ]);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Scene Examples',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
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
                Positioned(
                  top: 8,
                  left: 8,
                  child: _ExamplePicker(
                    examples: examples.keys.toList(growable: false),
                    selected: selectedExample,
                    onSelected: (next) {
                      setState(() {
                        ticker.stop();
                        ticker.start();
                        selectedExample = next;
                      });
                    },
                  ),
                ),
                // Settings sidebar (top-right): global post-processing
                // controls applied to whichever example is on screen.
                const Positioned(top: 8, right: 8, child: _SettingsSidebar()),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: SizedBox(
        width: 320,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height - 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                child: Row(
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
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
      ),
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
        _slider('Radius', settings.radius, 0.05, 2, (v) {
          settings.radius = v;
        }),
        _slider('Intensity', settings.intensity, 0, 3, (v) {
          settings.intensity = v;
        }),
        _slider('Bias', settings.bias, 0, 0.1, (v) {
          settings.bias = v;
        }),
        _slider('Samples', settings.sampleCount.toDouble(), 4, 32, (v) {
          settings.sampleCount = v.round();
        }),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Half resolution'),
          value: settings.halfResolution,
          onChanged: (value) => setState(() => settings.halfResolution = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Specular occlusion'),
          value: settings.specularMode == SpecularAmbientOcclusionMode.simple,
          onChanged: (value) => setState(() {
            settings.specularMode = value
                ? SpecularAmbientOcclusionMode.simple
                : SpecularAmbientOcclusionMode.none;
          }),
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
    ValueChanged<double> onChanged,
  ) {
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
            value.toStringAsFixed(2),
            style: textStyle,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
