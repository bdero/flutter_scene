import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart'
    show
        CuboidGeometry,
        Mesh,
        Node,
        PerspectiveCamera,
        PlaneGeometry,
        RectAreaLight,
        RectAreaLightComponent,
        Scene,
        SphereGeometry,
        UnlitMaterial,
        PhysicallyBasedMaterial,
        SceneView;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// A studio product shot lit by rectangular area lights: a warm key panel, a
/// cool rim panel orbiting slowly, and a glossy floor showing the stretched
/// panel reflections that point lights cannot produce.
class ExampleAreaLights extends StatefulWidget {
  const ExampleAreaLights({super.key});

  @override
  State<ExampleAreaLights> createState() => _ExampleAreaLightsState();
}

class _ExampleAreaLightsState extends State<ExampleAreaLights> {
  final Scene scene = Scene();
  final PerspectiveCamera camera = PerspectiveCamera(
    position: vm.Vector3(0, 1.6, 4.2),
    target: vm.Vector3(0, 0.45, 0),
  );
  Node? _rimRig;
  double _time = 0.0;

  // Aims a node's local +Z (the panel emission axis) at [target].
  static vm.Matrix4 _aim(vm.Vector3 position, vm.Vector3 target) {
    final forward = (target - position).normalized();
    final right = vm.Vector3(0, 1, 0).cross(forward)..normalize();
    final up = forward.cross(right).normalized();
    return vm.Matrix4.columns(
      vm.Vector4(right.x, right.y, right.z, 0),
      vm.Vector4(up.x, up.y, up.z, 0),
      vm.Vector4(forward.x, forward.y, forward.z, 0),
      vm.Vector4(position.x, position.y, position.z, 1),
    );
  }

  // A panel node pairs the light with a matching unlit quad so the source
  // itself reads in reflections and to the eye.
  Node _panel(RectAreaLight light) {
    final node = Node()..addComponent(RectAreaLightComponent(light));
    final face = Node(
      mesh: Mesh(
        PlaneGeometry(width: light.width, depth: light.height),
        UnlitMaterial()
          ..baseColorFactor = vm.Vector4(
            light.color.x * light.intensity * 0.35,
            light.color.y * light.intensity * 0.35,
            light.color.z * light.intensity * 0.35,
            1.0,
          ),
      ),
    )..localTransform = vm.Matrix4.rotationX(-math.pi * 0.5);
    node.add(face);
    return node;
  }

  @override
  void initState() {
    super.initState();
    scene.environmentIntensity = 0.04;

    final floor = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.06, 0.07, 1.0)
      ..metallicFactor = 0.4
      ..roughnessFactor = 0.16
      ..vertexColorWeight = 0.0;
    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 14, depth: 14), floor)));

    final subject = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.82, 0.80, 0.78, 1.0)
      ..metallicFactor = 0.05
      ..roughnessFactor = 0.32
      ..vertexColorWeight = 0.0;
    scene.add(
      Node(mesh: Mesh(SphereGeometry(radius: 0.55), subject))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(-0.55, 0.55, 0)),
    );
    scene.add(
      Node(mesh: Mesh(CuboidGeometry(vm.Vector3(0.7, 1.1, 0.7)), subject))
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(0.75, 0.55, -0.25)) *
            vm.Matrix4.rotationY(0.5),
    );

    // Warm key panel, angled down at the subjects from the left.
    final key = _panel(
      RectAreaLight(
        color: vm.Vector3(1.0, 0.72, 0.45),
        intensity: 9.0,
        width: 1.8,
        height: 1.2,
        range: 20.0,
      ),
    )..localTransform = _aim(vm.Vector3(-2.0, 1.9, 1.4), vm.Vector3(0, 0.5, 0));
    scene.add(key);

    // Cool rim panel on a slow orbit rig behind the subjects.
    final rim = _panel(
      RectAreaLight(
        color: vm.Vector3(0.35, 0.55, 1.0),
        intensity: 6.0,
        width: 0.5,
        height: 2.2,
        range: 20.0,
      ),
    )..localTransform = _aim(vm.Vector3(0, 1.3, -2.4), vm.Vector3(0, 0.5, 0));
    _rimRig = Node()..add(rim);
    scene.add(_rimRig!);
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      camera: camera,
      onTick: (elapsed, deltaSeconds) {
        _time = elapsed.inMicroseconds / 1e6;
        _rimRig?.localTransform = vm.Matrix4.rotationY(_time * 0.3);
        exampleSettings.applyTo(scene);
      },
    );
  }
}
