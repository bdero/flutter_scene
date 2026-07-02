// Vertex-stage customization example: a `.fmat` material whose `Vertex()` hook
// bends the world down over a false horizon (the Animal Crossing "round world"
// look). A tessellated ground plane and rows of pillars scroll toward the
// camera and sink away over the horizon; the slider drives the material's
// `curvature` parameter live.
//
// Demonstrates that a `.fmat` `vertex { }` block:
//   1. displaces geometry per vertex (the whole world curves), and
//   2. composes with the engine's physically based lighting in `Surface()`,
// with the author writing one `Vertex()` the engine runs on every mesh.

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

class ExampleVertexCurve extends StatefulWidget {
  const ExampleVertexCurve({super.key});

  @override
  State<ExampleVertexCurve> createState() => _ExampleVertexCurveState();
}

// Spacing between pillar rows, in world units. The scrolling group wraps its
// offset by this distance so the infinite road loops seamlessly.
const double _rowSpacing = 6.0;
const int _rowCount = 26;

class _ExampleVertexCurveState extends State<ExampleVertexCurve> {
  final Scene scene = Scene();
  bool loaded = false;

  // The pillars, scrolled toward the camera as one group.
  final Node _road = Node();

  double curvature = 0.008;
  PreprocessedMaterial? _material;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final material = await loadFmatMaterial('assets/vertex_curve.fmat');
    if (!mounted) return;
    _material = material;
    material.parameters.setFloat('curvature', curvature);

    // A large, finely tessellated ground plane so the per-vertex bend reads as
    // a smooth curve rather than moving only the corners.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 80, depth: 160, segmentsX: 80, segmentsZ: 160),
          material,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0, -50)),
    );

    // Rows of pillars receding down the road. As they scroll toward the camera
    // they rise up out of the horizon; as they recede they sink below it.
    for (var row = 0; row < _rowCount; row++) {
      final z = -row * _rowSpacing;
      for (final x in const [-6.0, -3.0, 3.0, 6.0]) {
        _road.add(
          Node(mesh: Mesh(CuboidGeometry(vm.Vector3(1.0, 2.0, 1.0)), material))
            ..localTransform = vm.Matrix4.translation(vm.Vector3(x, 1.0, z)),
        );
      }
    }
    scene.add(_road);

    setState(() => loaded = true);
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
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
            // Fixed camera looking down the road; the world scrolls toward it,
            // so the curve (which is relative to the camera) stays stable.
            camera: PerspectiveCamera(
              position: vm.Vector3(0, 4.0, 8.0),
              target: vm.Vector3(0, 1.2, -12.0),
            ),
            onTick: (elapsed, deltaSeconds) {
              // Scroll the pillars toward the camera, wrapping by one row so the
              // road loops seamlessly.
              final offset = (elapsed.inMicroseconds / 1e6 * 6.0) % _rowSpacing;
              _road.localTransform = vm.Matrix4.translation(
                vm.Vector3(0, 0, offset),
              );
              _road.markBoundsDirty();
              exampleSettings.applyTo(scene);
            },
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
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      'Curvature: ${curvature.toStringAsFixed(4)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: curvature,
                      min: 0.0,
                      max: 0.02,
                      onChanged: (v) => setState(() {
                        curvature = v;
                        _material?.parameters.setFloat('curvature', v);
                      }),
                    ),
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
