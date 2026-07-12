import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_settings.dart';

class ExampleCar extends StatefulWidget {
  const ExampleCar({super.key});

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
  bool _controlsOpen = true;

  double wheelRotation = 0;

  // Shows the scene's environment as the background. Its blurriness is driven
  // live by a slider; the scene reads it each frame.
  final EnvironmentSkySource _skySource = EnvironmentSkySource();

  Map<String, NodeState> nodes = {};

  // All posable car parts, and the subset driven by the door/lid sliders
  // (the rest are wheels, posed each frame by _updateWheels).
  static const List<String> _partNames = [
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
  ];
  static const List<String> _doorNames = [
    'DoorFront.L',
    'DoorFront.R',
    'DoorBack.L',
    'DoorBack.R',
    'Frunk',
    'Trunk',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The scene hot reloads in place; onReload re-grabs the door/wheel nodes
    // (preserving slider positions) since the patch replaces the node
    // instances.
    final value = await loadScene(
      'assets_src/fcar.glb',
      onReload: _onCarReloaded,
    );
    final environment = await EnvironmentMap.fromAssets(
      radianceImagePath: 'assets/little_paris_eiffel_tower.png',
    );
    if (!mounted) {
      return;
    }

    value.name = 'Car';
    scene.add(value);
    _grabNodes(value);

    scene.environment = environment;
    scene.exposure = 2.5;
    scene.skybox = Skybox(_skySource);

    setState(() {
      loaded = true;
    });
  }

  void _onCarReloaded(Node car) {
    _grabNodes(car);
    if (mounted) setState(() {});
  }

  // (Re-)resolves the posable car parts by name, preserving each part's
  // current slider amount, and re-applies the door/lid poses (wheels re-pose
  // each frame in _updateWheels).
  void _grabNodes(Node car) {
    for (final name in _partNames) {
      final node = car.getChildByNamePath([name])!;
      final amount = nodes[name]?.amount ?? 0.0;
      nodes[name] = NodeState(node, node.localTransform.clone())
        ..amount = amount;
    }
    for (final name in _doorNames) {
      _applyDoorPose(name, nodes[name]!.amount);
    }
  }

  // Opens a door/lid to [amount] (0..1) about its hinge axis.
  void _applyDoorPose(String name, double amount) {
    final state = nodes[name]!;
    final axis = switch (name) {
      'Frunk' => vm.Vector3(0, 0, 1),
      'Trunk' => vm.Vector3(0, 0, -1),
      _ => vm.Vector3(0, -1, 0),
    };
    state.amount = amount;
    state.node.localTransform = state.startTransform.clone()
      ..rotate(axis, amount * pi / 2);
  }

  @override
  void dispose() {
    // Optional: the scene is dropped with this State. `Node.fromAsset` caches
    // the imported model template (shared across clones), so its GPU resources
    // persist for the session regardless.
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
            cameraBuilder: (elapsed) {
              final rotationAmount = elapsed.inMicroseconds / 1e6 * 0.2;
              return PerspectiveCamera(
                position:
                    vm.Vector3(
                      sin(rotationAmount) * 5,
                      2,
                      cos(rotationAmount) * 5,
                    ) *
                    2,
                target: vm.Vector3(0, 0, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) {
              _updateWheels();
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        ExampleOverlay.bottomLeftPanel(child: _buildControls()),
      ],
    );
  }

  Widget _buildControls() => SizedBox(
    width: 280,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bodyHeight = constraints.hasBoundedHeight
            ? min(360.0, max(0.0, constraints.maxHeight - 57.0))
            : 360.0;

        return Card(
          color: Colors.black54,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Keep the title available while the long control list scrolls.
              InkWell(
                onTap: () => setState(() => _controlsOpen = !_controlsOpen),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Car controls',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        _controlsOpen
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              if (_controlsOpen) ...[
                const Divider(height: 1, color: Colors.white24),
                SizedBox(
                  height: bodyHeight,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _slider('Sky blur', _skySource.blurriness, 0, 1, (
                          value,
                        ) {
                          setState(() => _skySource.blurriness = value);
                        }),
                        for (final (label, name) in const [
                          ('Front door L', 'DoorFront.L'),
                          ('Front door R', 'DoorFront.R'),
                          ('Back door L', 'DoorBack.L'),
                          ('Back door R', 'DoorBack.R'),
                          ('Frunk', 'Frunk'),
                          ('Trunk', 'Trunk'),
                        ])
                          _slider(label, nodes[name]!.amount, 0, 1, (value) {
                            setState(() => _applyDoorPose(name, value));
                          }),
                        _slider(
                          'Rear wheel speed',
                          nodes['WheelBack.L']!.amount,
                          0,
                          1,
                          (value) {
                            setState(
                              () => nodes['WheelBack.L']!.amount = value,
                            );
                          },
                        ),
                        _slider(
                          'Front wheel steer',
                          nodes['WheelFront.L']!.amount,
                          -1,
                          1,
                          (value) {
                            setState(
                              () => nodes['WheelFront.L']!.amount = value,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '$label: ${value.toStringAsFixed(2)}',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ],
  );

  // Advances the wheel spin/steer each frame from the slider-driven amounts.
  void _updateWheels() {
    final wheelSpeed = nodes['WheelBack.L']!.amount;
    wheelRotation += wheelSpeed / 10;

    for (final wheelName in ['WheelBack.L', 'WheelBack.R']) {
      final wheel = nodes[wheelName]!;
      wheel.node.localTransform = wheel.startTransform.clone()
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
  }
}
