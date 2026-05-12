// Toon-shader example: loads a glTF model and renders it through a
// caller-authored fragment shader bound by name.
//
// Demonstrates the ShaderMaterial workflow end-to-end:
//   1. Author a fragment shader (shaders/example_toon.frag) that
//      consumes the engine's standard vertex outputs.
//   2. Compile it offline through `flutter_gpu_shaders` build hook
//      into `build/shaderbundles/example.shaderbundle`.
//   3. Load the bundle at runtime and pull out the fragment shader.
//   4. Construct a ShaderMaterial, set its uniform block + texture by
//      name, attach it to the model's mesh primitives.

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ExampleToon extends StatefulWidget {
  const ExampleToon({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  State<ExampleToon> createState() => _ExampleToonState();
}

class _ExampleToonState extends State<ExampleToon> {
  Scene scene = Scene();
  bool loaded = false;

  // Wrapper around the loaded Dash node. Spinning this instead of the
  // camera keeps the world-space light direction (which we use for
  // shading) stable relative to the viewer.
  final Node _dashGroup = Node();

  // Shader parameters surfaced as UI sliders below. The base color is
  // a saturated cool blue with a brighter sky-blue rim, so the toon
  // bands read clearly as a cohesive blue palette.
  double bandCount = 3;
  double rimStrength = 0.9;
  double rimWidth = 0.55;
  double ambient = 0.25;
  vm.Vector4 baseColor = vm.Vector4(0.32, 0.55, 0.95, 1.0);
  vm.Vector4 rimColor = vm.Vector4(0.55, 0.85, 1.0, 1.0);

  ShaderMaterial? _toonMaterial;

  @override
  void initState() {
    // Load the toon shader bundle the example app's build hook
    // produces.
    final shaderLibrary = gpu.ShaderLibrary.fromAsset(
      'build/shaderbundles/example.shaderbundle',
    );
    final toonShader = shaderLibrary?['ToonFragment'];
    if (toonShader == null) {
      throw StateError(
        'Toon shader missing from example.shaderbundle. The build hook '
        'should have produced it; rerun `flutter run` with a clean build.',
      );
    }

    Node.fromAsset('build/models/dash.model').then((dash) {
      dash.name = 'Dash';

      // Build one ShaderMaterial; every skinned primitive on the model
      // shares it so parameter tweaks are reflected everywhere.
      final material = ShaderMaterial(fragmentShader: toonShader);
      _refreshUniforms(material);
      // Default white placeholder so the texture sampler is bound even
      // when the model itself doesn't carry a base color texture.
      material.setTexture(
        'base_color_texture',
        Material.getWhitePlaceholderTexture(),
      );
      _toonMaterial = material;

      _applyMaterialToAllPrimitives(dash, material);

      // Start the Walk animation looping. Dash walks in place, so the
      // root transform doesn't drift; we drive the visible rotation
      // via `_dashGroup.localTransform` in build() instead.
      dash.createAnimationClip(dash.findAnimationByName('Walk')!)
        ..loop = true
        ..play();

      _dashGroup.add(dash);
      scene.add(_dashGroup);
      scene.exposure = 1.5;
      setState(() {
        loaded = true;
      });
    });

    super.initState();
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

  void _refreshUniforms(ShaderMaterial material) {
    // Layout must match the `ToonInfo` uniform block in
    // example_toon.frag, packed std140:
    //   vec4 base_color           (offset 0,  16 bytes)
    //   vec4 rim_color            (offset 16, 16 bytes)
    //   vec4 light_direction      (offset 32, 16 bytes; w padded)
    //   float band_count          (offset 48, 4 bytes)
    //   float rim_strength        (offset 52, 4 bytes)
    //   float rim_width           (offset 56, 4 bytes)
    //   float ambient             (offset 60, 4 bytes)
    final light = vm.Vector3(0.4, 0.8, -0.5).normalized();
    material.setUniformBlock(
      'ToonInfo',
      ByteData.sublistView(
        Float32List.fromList([
          // base_color
          baseColor.r, baseColor.g, baseColor.b, baseColor.a,
          // rim_color
          rimColor.r, rimColor.g, rimColor.b, rimColor.a,
          // light_direction (vec4 with w=0)
          light.x, light.y, light.z, 0,
          // band_count, rim_strength, rim_width, ambient
          bandCount, rimStrength, rimWidth, ambient,
        ]),
      ),
    );
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
                    onChanged:
                        (v) => setState(() {
                          bandCount = v.roundToDouble();
                          _refreshUniforms(_toonMaterial!);
                        }),
                  ),
                  _SliderRow(
                    label: 'Rim strength',
                    value: rimStrength,
                    min: 0,
                    max: 2,
                    onChanged:
                        (v) => setState(() {
                          rimStrength = v;
                          _refreshUniforms(_toonMaterial!);
                        }),
                  ),
                  _SliderRow(
                    label: 'Rim width',
                    value: rimWidth,
                    min: 0,
                    max: 1,
                    onChanged:
                        (v) => setState(() {
                          rimWidth = v;
                          _refreshUniforms(_toonMaterial!);
                        }),
                  ),
                  _SliderRow(
                    label: 'Ambient',
                    value: ambient,
                    min: 0,
                    max: 1,
                    onChanged:
                        (v) => setState(() {
                          ambient = v;
                          _refreshUniforms(_toonMaterial!);
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
    // Camera is fixed so the toon shader's world-space light stays
    // stable from the viewer's perspective. Dash spins in place
    // instead (see `_ExampleToonState.build`). Distance matches the
    // animation example.
    final camera = PerspectiveCamera(
      position: vm.Vector3(0, 2, -6),
      target: vm.Vector3(0, 1.5, 0),
    );
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
