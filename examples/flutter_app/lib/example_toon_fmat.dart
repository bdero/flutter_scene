// Toon example, authored with the `.fmat` custom-material format. This is the
// `.fmat` counterpart to example_toon.dart (which hand-binds a raw
// ShaderMaterial); rendering the same Dash model with the same controls makes
// the two a before/after comparison of the two material workflows.
//
// Demonstrates the `.fmat` workflow end-to-end:
//   1. Declare typed parameters and a small `Surface()` function in
//      materials/toon.fmat (no hand-packed std140 uniform block).
//   2. Compile it offline with the `buildMaterials` build hook into
//      `build/shaderbundles/materials.shaderbundle` plus a parameter sidecar
//      `materials.fmat.json`.
//   3. Load the bundle + sidecar at runtime and build a PreprocessedMaterial.
//   4. Set parameters by name through `material.parameters`; the setters are
//      type-checked and the std140 offsets come from shader reflection, so
//      there is no manual packing and a wrong-typed value throws.

import 'dart:convert';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

class ExampleToonFmat extends StatefulWidget {
  const ExampleToonFmat({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  State<ExampleToonFmat> createState() => _ExampleToonFmatState();
}

class _ExampleToonFmatState extends State<ExampleToonFmat>
    with SceneModelReloadMixin<ExampleToonFmat> {
  Scene scene = Scene();
  bool loaded = false;

  // Wrapper around the loaded Dash node. Spinning this instead of the
  // camera keeps the world-space light direction (which we use for
  // shading) stable relative to the viewer.
  final Node _dashGroup = Node();

  // Material parameters surfaced as UI sliders below. The base color is
  // a saturated cool blue with a brighter sky-blue rim, so the toon
  // bands read clearly as a cohesive blue palette. Matches example_toon.dart
  // so the two examples are directly comparable.
  double bandCount = 3;
  double rimStrength = 0.9;
  double rimWidth = 0.55;
  double ambient = 0.25;
  vm.Vector4 baseColor = vm.Vector4(0.32, 0.55, 0.95, 1.0);
  vm.Vector4 rimColor = vm.Vector4(0.55, 0.85, 1.0, 1.0);

  PreprocessedMaterial? _toonMaterial;

  @override
  List<String> get reloadableModelSources => const ['assets_src/dash.glb'];

  @override
  Future<void> buildScene() async {
    // Load the bundle, sidecar, and model first, then swap synchronously. This
    // also runs on hot reload, so the current scene must stay valid during the
    // async load; only the final swap clears and rebuilds.

    // Load the .fmat bundle and its parameter sidecar that buildMaterials
    // produces. Use the async loader: shader bundles can't be read
    // synchronously on web (gpu.ShaderLibrary.fromAsset throws there).
    final shaderLibrary = await gpu.loadShaderLibraryAsync(
      'build/shaderbundles/materials.shaderbundle',
    );
    final toonShader = shaderLibrary?['FmatToon'];
    if (toonShader == null) {
      throw StateError(
        'FmatToon shader missing from materials.shaderbundle. The build hook '
        'should have produced it; rerun `flutter run` with a clean build.',
      );
    }
    final sidecar = await rootBundle.loadString(
      'build/shaderbundles/materials.fmat.json',
    );
    final metadata = (jsonDecode(sidecar) as Map).cast<String, Object?>();
    final toonMetadata = (metadata['FmatToon'] as Map).cast<String, Object?>();

    final dash = await loadModel('assets_src/dash.glb');
    if (!mounted) {
      return;
    }
    dash.name = 'Dash';

    // Build one PreprocessedMaterial; every skinned primitive on the model
    // shares it so parameter tweaks are reflected everywhere. The
    // base_color_texture sampler is declared with a `default_white` hint, so
    // it falls back to a white placeholder when unset (no manual bind needed).
    final material = PreprocessedMaterial(
      fragmentShader: toonShader,
      metadata: toonMetadata,
    );
    _refreshParameters(material);

    _applyMaterialToAllPrimitives(dash, material);

    // Start the Walk animation looping. Dash walks in place, so the
    // root transform doesn't drift; we drive the visible rotation
    // via `_dashGroup.localTransform` in build() instead.
    dash.createAnimationClip(dash.findAnimationByName('Walk')!)
      ..loop = true
      ..play();

    // Swap in the freshly loaded content.
    scene.removeAll();
    _dashGroup.removeAll();
    _toonMaterial = material;
    _dashGroup.add(dash);
    scene.add(_dashGroup);
    scene.exposure = 1.5;
    setState(() {
      loaded = true;
    });
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  void _applyMaterialToAllPrimitives(Node node, Material material) {
    final mesh = node.mesh;
    if (mesh != null) {
      for (final p in mesh.primitives) {
        p.material = material;
      }
    }
    for (final child in node.children) {
      _applyMaterialToAllPrimitives(child, material);
    }
  }

  void _refreshParameters(PreprocessedMaterial material) {
    final light = vm.Vector3(0.4, 0.8, -0.5).normalized();
    // Set each parameter by its declared name. No std140 offsets, no padding:
    // the runtime resolves offsets from shader reflection and the setters
    // throw on a type mismatch. base_color/rim_color are written with setVec4
    // (not setColor) so these linear values match example_toon.dart's
    // hand-packed block byte-for-byte rather than being sRGB-decoded.
    material.parameters
      ..setVec4('base_color', baseColor)
      ..setVec4('rim_color', rimColor)
      ..setVec3('light_direction', light)
      ..setFloat('band_count', bandCount)
      ..setFloat('rim_strength', rimStrength)
      ..setFloat('rim_width', rimWidth)
      ..setFloat('ambient', ambient);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    // Rotate Dash in place. Keeping the camera fixed and the world-
    // space light direction constant means the toon bands stay
    // anchored to the viewer's perspective: the bright side of Dash
    // sweeps around her body as she turns, the way a real character
    // under a stable spotlight would look.
    _dashGroup.localTransform = vm.Matrix4.rotationY(
      widget.elapsedSeconds * 0.6,
    );
    _dashGroup.markBoundsDirty();

    return Stack(
      children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _ScenePainter(scene, widget.elapsedSeconds),
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
                  _SliderRow(
                    label: 'Band count',
                    value: bandCount,
                    min: 1,
                    max: 8,
                    onChanged: (v) => setState(() {
                      bandCount = v.roundToDouble();
                      _refreshParameters(_toonMaterial!);
                    }),
                  ),
                  _SliderRow(
                    label: 'Rim strength',
                    value: rimStrength,
                    min: 0,
                    max: 2,
                    onChanged: (v) => setState(() {
                      rimStrength = v;
                      _refreshParameters(_toonMaterial!);
                    }),
                  ),
                  _SliderRow(
                    label: 'Rim width',
                    value: rimWidth,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() {
                      rimWidth = v;
                      _refreshParameters(_toonMaterial!);
                    }),
                  ),
                  _SliderRow(
                    label: 'Ambient',
                    value: ambient,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() {
                      ambient = v;
                      _refreshParameters(_toonMaterial!);
                    }),
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
          width: 110,
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

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.elapsedTime);
  Scene scene;
  double elapsedTime;

  @override
  void paint(Canvas canvas, Size size) {
    // Camera is fixed so the toon material's world-space light stays
    // stable from the viewer's perspective. Dash spins in place
    // instead (see `_ExampleToonFmatState.build`). Distance matches the
    // animation example.
    final camera = PerspectiveCamera(
      position: vm.Vector3(0, 2, -6),
      target: vm.Vector3(0, 1.5, 0),
    );
    exampleSettings.applyTo(scene);
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
