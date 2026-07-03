import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Point and spot lights orbiting a small set of matte shapes. The ambient
/// (image-based) light is turned down and there is no directional sun, so the
/// colored point lights and the overhead spot are what light the scene.
class ExampleLights extends StatefulWidget {
  const ExampleLights({super.key});

  @override
  ExampleLightsState createState() => ExampleLightsState();
}

/// Moves the owning node around a horizontal circle, so a light attached to
/// the node orbits the scene.
class _OrbitComponent extends Component {
  _OrbitComponent({
    required this.radius,
    required this.height,
    required this.speed,
    required this.phase,
  });

  final double radius;
  final double height;
  final double speed;
  final double phase;
  double _elapsed = 0.0;

  @override
  void update(double deltaSeconds) {
    _elapsed += deltaSeconds;
    final angle = _elapsed * speed + phase;
    node.localTransform = vm.Matrix4.translation(
      vm.Vector3(cos(angle) * radius, height, sin(angle) * radius),
    );
  }
}

class ExampleLightsState extends State<ExampleLights> {
  Scene scene = Scene();

  @override
  void initState() {
    // Dim the image-based ambient and drop the sun so the punctual lights are
    // what the eye reads.
    scene.environmentIntensity = 0.1;
    scene.directionalLight = null;

    // A matte floor to catch the light pools.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(24, 0.2, 24)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.6, 0.6, 0.62, 1)
            ..roughnessFactor = 0.85
            ..metallicFactor = 0.0,
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.2, 0)),
      ),
    );

    // A ring of shapes for the lights to sweep across.
    for (var i = 0; i < 6; i++) {
      final angle = i / 6 * 2 * pi;
      scene.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.7),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.85, 1)
              ..roughnessFactor = 0.5
              ..metallicFactor = 0.0,
          ),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(cos(angle) * 4, 0, sin(angle) * 4),
          ),
        ),
      );
    }

    // Three colored point lights orbiting at different phases, each marked by
    // a small unlit sphere so its position is visible.
    final colors = <vm.Vector3>[
      vm.Vector3(1.0, 0.2, 0.2),
      vm.Vector3(0.2, 1.0, 0.3),
      vm.Vector3(0.3, 0.4, 1.0),
    ];
    for (var i = 0; i < colors.length; i++) {
      final node = Node()
        ..addComponent(
          PointLightComponent(
            PointLight(color: colors[i], intensity: 22.0, range: 14.0),
          ),
        )
        ..addComponent(
          _OrbitComponent(
            radius: 5.5,
            height: 1.5,
            speed: 0.6,
            phase: i / colors.length * 2 * pi,
          ),
        );
      node.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 0.12),
            UnlitMaterial()
              ..baseColorFactor = vm.Vector4(
                colors[i].x,
                colors[i].y,
                colors[i].z,
                1,
              ),
          ),
        ),
      );
      scene.add(node);
    }

    // A warm overhead spot light pointing straight down at the center.
    scene.add(
      Node(localTransform: vm.Matrix4.translation(vm.Vector3(0, 8, 0)))
        ..addComponent(
          SpotLightComponent(
            SpotLight(
              color: vm.Vector3(1.0, 0.9, 0.7),
              intensity: 60.0,
              range: 20.0,
              direction: vm.Vector3(0, -1, 0),
              innerConeAngle: 0.15,
              outerConeAngle: 0.5,
            ),
          ),
        ),
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6 * 0.25;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t) * 11, 6, cos(t) * 11),
          target: vm.Vector3(0, -0.5, 0),
        );
      },
    );
  }
}
