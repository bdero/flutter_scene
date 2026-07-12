// Toon example, authored with the `.fmat` custom-material format. This is the
// `.fmat` counterpart to example_toon.dart (which hand-binds a raw
// ShaderMaterial); rendering the same Dash model with the same controls makes
// the two a before/after comparison of the two material workflows.
//
// Demonstrates the `.fmat` workflow end-to-end:
//   1. Declare typed parameters and a small `Surface()` function in
//      assets/toon.fmat (no hand-packed std140 uniform block).
//   2. Compile it offline with the `buildMaterials` build hook into
//      `build/shaderbundles/materials.shaderbundle` plus a parameter sidecar
//      `materials.fmat.json`.
//   3. Load the bundle + sidecar at runtime and build a PreprocessedMaterial.
//   4. Set parameters by name through `material.parameters`; the setters are
//      type-checked and the std140 offsets come from shader reflection, so
//      there is no manual packing and a wrong-typed value throws.

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_settings.dart';

class ExampleToonFmat extends StatefulWidget {
  const ExampleToonFmat({super.key});

  @override
  State<ExampleToonFmat> createState() => _ExampleToonFmatState();
}

class _ExampleToonFmatState extends State<ExampleToonFmat> {
  Scene scene = Scene();
  bool loaded = false;
  bool _controlsOpen = true;
  Object? _loadError;

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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Load the .fmat material through the registry: it resolves the generated
      // shader bundle and parameter sidecar by source path and registers the
      // material for in-place hot reload, so editing assets/toon.fmat (culling,
      // GLSL body, defaults, etc.) updates it live without a restart.
      final material = await loadFmatMaterial('assets/toon.fmat');

      // The scene hot reloads in place; onReload re-applies the material to the
      // freshly patched-in primitives.
      final dash = await loadScene(
        'assets_src/dash.glb',
        onReload: _reapplyMaterial,
      );
      if (!mounted) {
        return;
      }
      dash.name = 'Dash';

      // Every skinned primitive on the model shares one material, so parameter
      // tweaks are reflected everywhere. The base_color_texture sampler is
      // declared with a `default_white` hint, so it falls back to a white
      // placeholder when unset (no manual bind needed).
      _toonMaterial = material;
      _refreshParameters(material);
      _applyMaterialToAllPrimitives(dash, material);

      // Start the Walk animation looping. Dash walks in place, so the root
      // transform doesn't drift; the visible rotation is driven via
      // `_dashGroup.localTransform` in build(). The clip re-binds across a model
      // reload, so it keeps playing.
      dash.createAnimationClip(dash.findAnimationByName('Walk')!)
        ..loop = true
        ..play();

      _dashGroup.add(dash);
      scene.add(_dashGroup);
      scene.exposure = 1.5;
      setState(() {
        loaded = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Toon (.fmat) could not load: $error\n$stackTrace');
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Re-applies the toon material to [dash]'s primitives after a hot reload
  /// swaps in fresh ones. (Editing the `.fmat` itself reloads the material in
  /// place separately, via loadFmatMaterial's registration.)
  void _reapplyMaterial(Node dash) {
    final material = _toonMaterial;
    if (material != null) _applyMaterialToAllPrimitives(dash, material);
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
    final loadError = _loadError;
    if (loadError != null) {
      return _LoadFailure(
        title: 'Toon (.fmat) could not load',
        detail: '$loadError',
      );
    }
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Positioned.fill(
          // Camera is fixed so the toon material's world-space light stays
          // stable from the viewer's perspective. Dash spins in place
          // instead (see the onTick below). Distance matches the animation
          // example.
          child: SceneView(
            scene,
            camera: PerspectiveCamera(
              position: vm.Vector3(0, 2, -6),
              target: vm.Vector3(0, 1.5, 0),
            ),
            onTick: (elapsed, deltaSeconds) {
              // Rotate Dash in place. Keeping the camera fixed and the
              // world-space light direction constant means the toon bands
              // stay anchored to the viewer's perspective: the bright side
              // sweeps around her body as she turns, the way a real
              // character under a stable spotlight would look.
              _dashGroup.localTransform = vm.Matrix4.rotationY(
                elapsed.inMicroseconds / 1e6 * 0.6,
              );
              _dashGroup.markBoundsDirty();
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          child: Card(
            color: Colors.black54,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => setState(() => _controlsOpen = !_controlsOpen),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.palette_outlined, color: Colors.white),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Toon controls',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          _controlsOpen ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_controlsOpen) ...[
                  const Divider(height: 1, color: Colors.white24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
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
                ],
              ],
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

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.title, required this.detail});

  final String title;
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
              Text(title, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              Text(detail, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    ),
  );
}
