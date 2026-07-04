import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A grid of colored point lights over a grid of shapes. There are far more
/// lights than the per-object budget, but each light has a finite range and
/// reaches only nearby shapes, so per-object culling keeps every fragment cheap
/// while the scene as a whole holds an unlimited number of lights.
class ExampleLights extends StatefulWidget {
  const ExampleLights({super.key});

  @override
  ExampleLightsState createState() => ExampleLightsState();
}

/// Bobs the owning node up and down about a base position, so its light drifts
/// and the culling (and light pools) update every frame.
class _BobComponent extends Component {
  _BobComponent(this.base, this.amplitude, this.speed, this.phase);

  final vm.Vector3 base;
  final double amplitude;
  final double speed;
  final double phase;
  double _elapsed = 0.0;

  @override
  void update(double deltaSeconds) {
    _elapsed += deltaSeconds;
    node.localTransform = vm.Matrix4.translation(
      vm.Vector3(
        base.x,
        base.y + sin(_elapsed * speed + phase) * amplitude,
        base.z,
      ),
    );
  }
}

const int _grid = 5; // _grid * _grid lights and shapes
const double _spacing = 6.0;

class ExampleLightsState extends State<ExampleLights> {
  Scene scene = Scene();

  @override
  void initState() {
    // Dim the image-based ambient and drop the sun so the colored point lights
    // are what the eye reads. Reflect the lit scene off the floor.
    scene.environmentIntensity = 0.1;
    scene.directionalLight = null;
    scene.screenSpaceReflections.enabled = true;

    final extent = (_grid - 1) * _spacing / 2;

    // A dark, near-polished floor large enough to hold the grid, so the light
    // pools and shapes reflect in it.
    final floorSize = _grid * _spacing + 6;
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(floorSize, 0.2, floorSize)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.05, 0.05, 0.06, 1)
            ..roughnessFactor = 0.1
            ..metallicFactor = 0.0,
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.2, 0)),
      ),
    );

    var index = 0;
    for (var i = 0; i < _grid; i++) {
      for (var j = 0; j < _grid; j++) {
        final x = i * _spacing - extent;
        final z = j * _spacing - extent;
        final t = index / (_grid * _grid);

        // A shape at the grid cell, its material sweeping metal/dielectric and
        // roughness across the grid.
        scene.add(
          Node(
            mesh: Mesh(
              SphereGeometry(radius: 1.0),
              PhysicallyBasedMaterial()
                ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.87, 1)
                ..metallicFactor = index.isEven ? 1.0 : 0.0
                ..roughnessFactor = 0.1 + t * 0.6,
            ),
            localTransform: vm.Matrix4.translation(vm.Vector3(x, 0, z)),
          ),
        );

        // A colored point light above the cell. Its range (7) reaches only the
        // neighboring cells, so no shape is lit by more than a handful of the
        // grid's lights even though the whole grid has many.
        final color = HSVColor.fromAHSV(1.0, t * 360.0, 0.9, 1.0).toColor();
        final rgb = vm.Vector3(
          color.r.toDouble(),
          color.g.toDouble(),
          color.b.toDouble(),
        );
        final lightNode = Node()
          ..addComponent(
            PointLightComponent(
              PointLight(color: rgb, intensity: 14.0, range: 7.0),
            ),
          )
          ..addComponent(
            _BobComponent(vm.Vector3(x, 2.0, z), 0.8, 1.2, index.toDouble()),
          );
        // A small unlit sphere marks each light's position.
        lightNode.add(
          Node(
            mesh: Mesh(
              SphereGeometry(radius: 0.12),
              UnlitMaterial()
                ..baseColorFactor = vm.Vector4(rgb.x, rgb.y, rgb.z, 1),
            ),
          ),
        );
        scene.add(lightNode);
        index++;
      }
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final radius = _grid * _spacing * 0.9;
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6 * 0.15;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t) * radius, radius * 0.7, cos(t) * radius),
          target: vm.Vector3(0, -0.5, 0),
        );
      },
    );
  }
}
