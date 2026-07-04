import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A single shadow-casting spot light orbiting above a few occluders on a
/// floor, so their shadows sweep across it as the light moves.
class ExampleSpotShadow extends StatefulWidget {
  const ExampleSpotShadow({super.key});

  @override
  ExampleSpotShadowState createState() => ExampleSpotShadowState();
}

/// Orbits the owning node around a horizontal circle above the scene, aiming a
/// spot light straight down, so its cone (and the occluders' shadows) sweep.
class _OrbitAimDownComponent extends Component {
  _OrbitAimDownComponent(this.radius, this.height, this.speed);

  final double radius;
  final double height;
  final double speed;
  double _elapsed = 0.0;

  @override
  void update(double deltaSeconds) {
    _elapsed += deltaSeconds;
    final a = _elapsed * speed;
    node.localTransform = vm.Matrix4.translation(
      vm.Vector3(cos(a) * radius, height, sin(a) * radius),
    );
  }
}

class ExampleSpotShadowState extends State<ExampleSpotShadow> {
  Scene scene = Scene();

  @override
  void initState() {
    // A dim ambient so shadowed areas are dark but not pitch black; no sun.
    scene.environmentIntensity = 0.12;
    scene.directionalLight = null;

    // Floor.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(30, 0.4, 30)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.55, 0.55, 0.58, 1)
            ..roughnessFactor = 0.85
            ..metallicFactor = 0.0,
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.2, 0)),
      ),
    );

    // A ring of occluders for the spot to cast shadows from.
    final palette = <vm.Vector4>[
      vm.Vector4(0.9, 0.4, 0.35, 1),
      vm.Vector4(0.4, 0.8, 0.5, 1),
      vm.Vector4(0.45, 0.55, 0.95, 1),
      vm.Vector4(0.9, 0.8, 0.4, 1),
      vm.Vector4(0.8, 0.5, 0.9, 1),
    ];
    for (var i = 0; i < palette.length; i++) {
      final a = i / palette.length * 2 * pi;
      scene.add(
        Node(
          mesh: Mesh(
            i.isEven
                ? CuboidGeometry(vm.Vector3(1.4, 2.4, 1.4))
                : SphereGeometry(radius: 1.0),
            PhysicallyBasedMaterial()
              ..baseColorFactor = palette[i]
              ..roughnessFactor = 0.6
              ..metallicFactor = 0.0,
          ),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(cos(a) * 4.5, 0.0, sin(a) * 4.5),
          ),
        ),
      );
    }

    // The shadow-casting spot: high overhead, aimed straight down, orbiting so
    // the occluders' shadows sweep across the floor.
    scene.add(
      Node()
        ..addComponent(
          SpotLightComponent(
            SpotLight(
              color: vm.Vector3(1.0, 0.97, 0.9),
              intensity: 120.0,
              range: 40.0,
              direction: vm.Vector3(0, -1, 0),
              innerConeAngle: 0.35,
              outerConeAngle: 0.6,
              castsShadow: true,
              shadowMapResolution: 1024,
            ),
          ),
        )
        ..addComponent(_OrbitAimDownComponent(3.5, 12.0, 0.5)),
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6 * 0.2;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t) * 16, 11, cos(t) * 16),
          target: vm.Vector3(0, -0.5, 0),
        );
      },
    );
  }
}
