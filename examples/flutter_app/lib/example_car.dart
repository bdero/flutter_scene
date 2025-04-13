import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ExampleCar extends StatefulWidget {
  const ExampleCar({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  ExampleCarState createState() => ExampleCarState();
}

class NodeState {
  NodeState(this.node, this.startTransform);

  Node node;
  vm.Matrix4 startTransform;
  double amount = 0;
}

class ExampleCarState extends State<ExampleCar> {
  Scene scene = Scene();
  bool loaded = false;

  double wheelRotation = 0;

  Map<String, NodeState> nodes = {};

  @override
  void initState() {
    final loadModel = Node.fromAsset('build/models/fcar.model').then((value) {
      value.name = 'Car';
      scene.add(value);
      debugPrint('Model loaded: ${value.name}');

      for (final doorName in [
        'DoorFront.L',
        'DoorFront.R',
        'DoorBack.L',
        'DoorBack.R',
        'Frunk',
        'Trunk',
        'WheelFront.L',
        'WheelFront.R',
        'WheelBack.L',
        'WheelBack.R',
      ]) {
        final door = value.getChildByNamePath([doorName])!;
        nodes[doorName] = NodeState(door, door.localTransform.clone());
      }
    });

    EnvironmentMap.fromAssets(
      radianceImagePath: 'assets/little_paris_eiffel_tower.png',
      irradianceImagePath: 'assets/little_paris_eiffel_tower_irradiance.png',
    ).then((environment) {
      scene.environment.environmentMap = environment;
      scene.environment.exposure = 2.0;
      scene.environment.intensity = 2.0;
    });

    Future.wait([loadModel]).then((_) {
      debugPrint('Scene loaded.');
      setState(() {
        loaded = true;
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    // Technically this isn't necessary, since `Node.fromAsset` doesn't perform
    // a caching import.
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    // Rotate the wheels at a given speed.
    final wheelSpeed = nodes['WheelBack.L']!.amount;
    wheelRotation += wheelSpeed / 10;

    for (final wheelName in ['WheelBack.L', 'WheelBack.R']) {
      final wheel = nodes[wheelName]!;
      wheel.node.localTransform =
          wheel.startTransform.clone()
            ..rotate(vm.Vector3(0, 0, -1), wheelRotation);
    }

    final wheelTurn = nodes['WheelFront.L']!.amount;

    for (final wheelName in ['WheelFront.L', 'WheelFront.R']) {
      final wheel = nodes[wheelName]!;
      wheel.node.localTransform =
          wheel.startTransform.clone() *
          vm.Matrix4.rotationY(-wheelTurn / 2) *
          vm.Matrix4.rotationZ(-wheelRotation);
    }

    return Stack(
      children: [
        SizedBox.expand(
          child: CustomPaint(
            painter: _ScenePainter(scene, widget.elapsedSeconds),
          ),
        ),
        // Door open slider
        Column(
          children: [
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final doorName in [
                  'DoorFront.L',
                  'DoorFront.R',
                  'DoorBack.L',
                  'DoorBack.R',
                ])
                  Slider(
                    value: nodes[doorName]!.amount,
                    onChanged: (value) {
                      final door = nodes[doorName]!;
                      door.node.localTransform =
                          door.startTransform.clone()
                            ..rotate(vm.Vector3(0, -1, 0), value * pi / 2);
                      door.amount = value;
                    },
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Slider(
                  value: nodes['Frunk']!.amount,
                  onChanged: (value) {
                    final door = nodes['Frunk']!;
                    door.node.localTransform =
                        door.startTransform.clone()
                          ..rotate(vm.Vector3(0, 0, 1), value * pi / 2);
                    door.amount = value;
                  },
                ),
                Slider(
                  value: nodes['Trunk']!.amount,
                  onChanged: (value) {
                    final door = nodes['Trunk']!;
                    door.node.localTransform =
                        door.startTransform.clone()
                          ..rotate(vm.Vector3(0, 0, -1), value * pi / 2);
                    door.amount = value;
                  },
                ),
                Slider(
                  value: nodes['WheelBack.L']!.amount,
                  onChanged: (value) {
                    nodes['WheelBack.L']!.amount = value;
                  },
                ),
                Slider(
                  min: -1,
                  max: 1,
                  value: nodes['WheelFront.L']!.amount,
                  onChanged: (value) {
                    nodes['WheelFront.L']!.amount = value;
                  },
                ),
              ],
            ),
          ],
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
    double rotationAmount = elapsedTime * 0.2;
    final camera = PerspectiveCamera(
      position:
          vm.Vector3(sin(rotationAmount) * 5, 2, cos(rotationAmount) * 5) * 2,
      target: vm.Vector3(0, 0, 0),
    );

    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
