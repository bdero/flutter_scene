import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Layer bit for content shown only in the left view.
const int _leftOnlyLayer = 1 << 1;

/// Renders one scene as split-screen via [Scene.renderViews]: a left half
/// with an orbiting free [PerspectiveCamera] and a right half driven by a
/// [CameraComponent] on a node. The right view masks out a node placed on
/// [_leftOnlyLayer], so that node appears only on the left.
class ExampleSplitScreen extends StatefulWidget {
  const ExampleSplitScreen({super.key});

  @override
  State<ExampleSplitScreen> createState() => _ExampleSplitScreenState();
}

class _ExampleSplitScreenState extends State<ExampleSplitScreen> {
  final Scene scene = Scene();
  late final CameraComponent _rightCamera;

  @override
  void initState() {
    super.initState();

    // A ring of debug-colored cuboids, so each view's angle is obvious from
    // which faces it shows.
    for (var i = 0; i < 6; i++) {
      final angle = i / 6 * 2 * pi;
      scene.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.8, 0.8, 0.8), debugColors: true),
            UnlitMaterial(),
          ),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(cos(angle) * 2.5, 0, sin(angle) * 2.5),
          ),
        ),
      );
    }

    // A tall cuboid at the center, shown only in the left view via its layer.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(0.6, 2.0, 0.6), debugColors: true),
          UnlitMaterial(),
        ),
      )..layers = _leftOnlyLayer,
    );

    // The right view's camera lives on a node: place the node by inverting
    // the view matrix of an equivalent eye/target/up placement (a static
    // side view), then drive the view from the node via the component.
    final placement = PerspectiveCamera(
      position: vm.Vector3(6, 2, 0),
      target: vm.Vector3(0, 0, 0),
    );
    final cameraNode = Node(
      localTransform: vm.Matrix4.identity()
        ..copyInverse(placement.getViewMatrix()),
    );
    _rightCamera = CameraComponent();
    cameraNode.addComponent(_rightCamera);
    scene.add(cameraNode);
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      viewsBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        final leftCamera = PerspectiveCamera(
          position: vm.Vector3(sin(t) * 6, 2.5, cos(t) * 6),
          target: vm.Vector3(0, 0, 0),
        );
        return [
          // Left half: orbiting free camera, sees every layer.
          RenderView(
            camera: leftCamera,
            viewport: const Rect.fromLTWH(0, 0, 0.5, 1),
          ),
          // Right half: static node-driven camera, hides the left-only layer.
          RenderView(
            camera: _rightCamera.toCamera(),
            viewport: const Rect.fromLTWH(0.5, 0, 0.5, 1),
            layerMask: kRenderLayerAll & ~_leftOnlyLayer,
          ),
        ];
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}
