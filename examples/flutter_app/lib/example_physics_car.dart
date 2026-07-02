import 'dart:math' as math;

// flutter_scene's physics BoxShape clashes with Flutter's painting BoxShape,
// and flutter_scene's Material class clashes with the Flutter Material widget.
// This example uses the physics BoxShape and the Flutter Material widget, so
// each conflicting name is hidden from the other import.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'character/character_controls.dart';
import 'character/character_input.dart';
import 'character/third_person_camera.dart';
import 'example_settings.dart';
import 'raycast_vehicle.dart';

/// Drive a car with raycast wheels. WASD / arrow keys (or the on-screen
/// joystick) steer and drive; the space bar (or the button) is the
/// handbrake, and Shift boosts. The car is a single dynamic Rapier chassis;
/// it can plow through the dynamic crates. Each wheel is a
/// downward ray that applies suspension and tire forces, and the model's
/// wheel nodes are posed to follow the suspension, steering, and roll.
class ExamplePhysicsCar extends StatefulWidget {
  const ExamplePhysicsCar({super.key});

  @override
  ExamplePhysicsCarState createState() => ExamplePhysicsCarState();
}

class ExamplePhysicsCarState extends State<ExamplePhysicsCar> {
  final Scene scene = Scene();
  late final RapierWorld world;

  final CharacterInput _input = CharacterInput();
  final ThirdPersonCamera _camera = ThirdPersonCamera(
    distance: 16.0,
    lookHeight: 1.5,
    pitch: 0.34,
  );

  // The dynamic chassis body and its controller.
  Node? _carNode;
  RaycastVehicle? _vehicle;
  bool _loaded = false;

  // Where the car (re)spawns, a little above the ground.
  static final vm.Vector3 _spawn = vm.Vector3(0, 0.9, 0);

  // Speedometer readout, refreshed each frame without rebuilding the tree.
  final ValueNotifier<double> _speed = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();

    scene.root.addComponent(
      DirectionalLightComponent(
        DirectionalLight(
          direction: vm.Vector3(-0.5, -1.0, -0.35),
          intensity: 3.0,
          castsShadow: true,
          shadowMaxDistance: 60.0,
        ),
      ),
    );

    world = RapierWorld(gravity: vm.Vector3(0, -9.81, 0));
    scene.root.addComponent(world);

    _buildGround();
    _buildCourse();
    _buildProps();
    _load();
  }

  Future<void> _load() async {
    final car = await loadScene('assets_src/fcar.glb');
    final environment = await EnvironmentMap.fromAssets(
      radianceImagePath: 'assets/little_paris_eiffel_tower.png',
    );
    if (!mounted) return;

    scene.environment = environment;
    scene.exposure = 2.5;
    scene.skybox = Skybox(EnvironmentSkySource()..blurriness = 0.25);

    _carNode = _buildCar(car);
    scene.add(_carNode!);

    // Point the chase camera at the car straight away.
    _camera.yaw = 0.0;

    setState(() => _loaded = true);
  }

  // --- Scene construction ---------------------------------------------------

  Mesh _boxMesh(vm.Vector3 size, vm.Vector4 color, {double roughness = 0.7}) {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..roughnessFactor = roughness
      ..metallicFactor = 0.0;
    return Mesh(CuboidGeometry(size), material);
  }

  Node _addStaticBox(
    vm.Vector3 center,
    vm.Vector3 halfExtents,
    vm.Vector4 color, {
    vm.Quaternion? rotation,
    double friction = 1.0,
  }) {
    final transform = rotation == null
        ? vm.Matrix4.translation(center)
        : vm.Matrix4.compose(center, rotation, vm.Vector3.all(1.0));
    final node = Node(
      mesh: _boxMesh(halfExtents * 2.0, color),
      localTransform: transform,
    );
    node.addComponent(RapierRigidBody(type: BodyType.fixed));
    node.addComponent(
      RapierCollider(
        shape: BoxShape(halfExtents: halfExtents),
        material: PhysicsMaterial(friction: friction, restitution: 0.0),
      ),
    );
    scene.add(node);
    return node;
  }

  // A dynamic crate the car can shove and scatter. Its density sets the mass,
  // so lighter crates fly further.
  Node _addDynamicBox(
    vm.Vector3 center,
    vm.Vector3 halfExtents,
    vm.Vector4 color, {
    double density = 2.0,
  }) {
    final node = Node(
      mesh: _boxMesh(halfExtents * 2.0, color, roughness: 0.85),
      localTransform: vm.Matrix4.translation(center),
    );
    node.addComponent(RapierRigidBody(type: BodyType.dynamic_));
    node.addComponent(
      RapierCollider(
        shape: BoxShape(halfExtents: halfExtents),
        material: PhysicsMaterial(
          friction: 0.7,
          restitution: 0.0,
          density: density,
        ),
      ),
    );
    scene.add(node);
    return node;
  }

  void _buildGround() {
    _addStaticBox(
      vm.Vector3(0, -0.5, 0),
      vm.Vector3(120, 0.5, 120),
      vm.Vector4(0.42, 0.46, 0.40, 1),
    );
  }

  // A short course: a launch ramp, a couple of speed bumps, and low walls to
  // bump into so the suspension and chassis physics are visible.
  void _buildCourse() {
    // Launch ramp ahead of the spawn (+X is the car's forward).
    _addStaticBox(
      vm.Vector3(34, 1.6, 0),
      vm.Vector3(7, 0.4, 8),
      vm.Vector4(0.80, 0.55, 0.30, 1),
      rotation: vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), 0.32),
    );

    // A run of speed bumps off to one side.
    for (var i = 0; i < 4; i++) {
      _addStaticBox(
        vm.Vector3(6.0 + i * 9.0, 0.18, -26),
        vm.Vector3(4.5, 0.35, 5.0),
        vm.Vector4(0.70, 0.72, 0.30, 1),
      );
    }

    // A boundary of low walls, offset so it frames the play area.
    const arena = 70.0;
    final wallColor = vm.Vector4(0.55, 0.35, 0.35, 1);
    _addStaticBox(
      vm.Vector3(arena, 1.2, 0),
      vm.Vector3(1.5, 1.2, arena),
      wallColor,
    );
    _addStaticBox(
      vm.Vector3(-arena, 1.2, 0),
      vm.Vector3(1.5, 1.2, arena),
      wallColor,
    );
    _addStaticBox(
      vm.Vector3(0, 1.2, arena),
      vm.Vector3(arena, 1.2, 1.5),
      wallColor,
    );
    _addStaticBox(
      vm.Vector3(0, 1.2, -arena),
      vm.Vector3(arena, 1.2, 1.5),
      wallColor,
    );
  }

  // Scatterable dynamic obstacles the car can plow through: a crate pyramid, a
  // tall stack, a row of skittles across the driving line, and loose crates.
  void _buildProps() {
    final crate = vm.Vector4(0.72, 0.52, 0.30, 1);
    final crate2 = vm.Vector4(0.62, 0.44, 0.26, 1);
    const half = 0.9; // Crate half-extent (1.8 units cubed).

    vm.Vector3 crateHalf() => vm.Vector3.all(half);

    // A 4-3-2-1 pyramid off to the right.
    for (var level = 0; level < 4; level++) {
      final count = 4 - level;
      final y = half + level * (half * 2);
      final z0 = -(count - 1) * half;
      for (var i = 0; i < count; i++) {
        _addDynamicBox(
          vm.Vector3(17.0, y, 9.0 + z0 + i * (half * 2)),
          crateHalf(),
          i.isEven ? crate : crate2,
        );
      }
    }

    // A tall stack straight ahead to topple.
    for (var i = 0; i < 5; i++) {
      _addDynamicBox(
        vm.Vector3(26.0, half + i * (half * 2), -7.0),
        crateHalf(),
        i.isEven ? crate : crate2,
      );
    }

    // A row of tall skittles across the forward driving line.
    final pin = vm.Vector4(0.85, 0.85, 0.88, 1);
    for (var i = 0; i < 6; i++) {
      _addDynamicBox(
        vm.Vector3(14.0, 1.4, -4.5 + i * 1.8),
        vm.Vector3(0.35, 1.4, 0.35),
        pin,
        density: 1.2,
      );
    }

    // Loose crates scattered around the arena.
    const scatter = [
      [9.0, -12.0],
      [12.0, -16.0],
      [20.0, 2.0],
      [22.0, 14.0],
      [-14.0, 8.0],
      [-20.0, -10.0],
      [-9.0, -18.0],
      [6.0, 20.0],
    ];
    for (var i = 0; i < scatter.length; i++) {
      final s = scatter[i];
      _addDynamicBox(
        vm.Vector3(s[0], half, s[1]),
        crateHalf(),
        i.isEven ? crate : crate2,
      );
    }
  }

  // Builds the chassis body node with the car model parented under it, wires
  // the four wheels to the vehicle controller, and returns the chassis node.
  Node _buildCar(Node carModel) {
    final chassis = Node(
      name: 'CarChassis',
      localTransform: vm.Matrix4.translation(_spawn),
    );
    chassis.add(carModel);

    chassis.addComponent(
      RapierRigidBody(
        type: BodyType.dynamic_,
        linearDamping: 0.08,
        angularDamping: 0.85,
        ccdEnabled: true,
      ),
    );
    // A box wrapping the lower body, sitting just above the wheels so only the
    // raycasts touch the ground. Kept low and shallow so the center of mass is
    // low: a high COM makes lateral tire forces (applied at the contacts) roll
    // the car over in turns. Its density sets the chassis mass.
    chassis.addComponent(
      RapierCollider(
        shape: BoxShape(halfExtents: vm.Vector3(3.6, 0.55, 1.6)),
        material: const PhysicsMaterial(
          friction: 0.4,
          restitution: 0.0,
          density: 42.0,
        ),
        localPose: vm.Matrix4.translation(vm.Vector3(-0.2, 0.8, 0)),
      ),
    );

    VehicleWheel wheel(
      String name, {
      required bool powered,
      required bool steered,
    }) {
      final node = carModel.getChildByNamePath([name])!;
      return VehicleWheel(node: node, powered: powered, steered: steered);
    }

    _vehicle = RaycastVehicle(
      wheels: [
        wheel('WheelFront.L', powered: false, steered: true),
        wheel('WheelFront.R', powered: false, steered: true),
        wheel('WheelBack.L', powered: true, steered: false),
        wheel('WheelBack.R', powered: true, steered: false),
      ],
    );
    chassis.addComponent(_vehicle!);
    return chassis;
  }

  void _reset() {
    final car = _carNode;
    if (car == null) return;
    // Unmount to destroy the dynamic body, replant it at the spawn pose, and
    // remount so a fresh body is created there at rest.
    scene.remove(car);
    car.localTransform = vm.Matrix4.translation(_spawn);
    scene.add(car);
  }

  @override
  void dispose() {
    _speed.dispose();
    scene.removeAll();
    super.dispose();
  }

  // --- Per-frame ------------------------------------------------------------

  static const double _dragYawPerPixel = 0.006;
  static const double _keyYawRate = 2.2;

  void _onTick(Duration elapsed, double deltaSeconds) {
    final dt = deltaSeconds.clamp(0.0, 0.05);
    final vehicle = _vehicle;
    final car = _carNode;
    if (vehicle == null || car == null) return;

    // Feed control intent to the vehicle. Forward on the stick drives, right
    // steers right, space is the handbrake.
    vehicle.throttle = _input.move.y.clamp(-1.0, 1.0);
    vehicle.steer = _input.move.x.clamp(-1.0, 1.0);
    vehicle.handbrake = _input.jump;
    // Hold Shift to boost (harder acceleration).
    vehicle.boost = HardwareKeyboard.instance.isShiftPressed;

    // Manual camera orbit from a drag or the arrow keys.
    final drag = _input.lookDelta.clone();
    _input.lookDelta.setZero();
    final manualYaw =
        drag.x * _dragYawPerPixel + _input.lookRate.x * _keyYawRate * dt;
    _camera.yaw += manualYaw;

    scene.update(dt);

    // Chase the car. When it is driving and the player is not orbiting, ease
    // the camera behind the car's heading.
    final carTransform = car.globalTransform;
    final carPos = carTransform.getTranslation();
    final forward = carTransform.transformed3(vm.Vector3(1, 0, 0))..sub(carPos);
    final speed = vehicle.forwardSpeed;
    if (manualYaw == 0 && speed.abs() > 1.5) {
      final headingYaw = math.atan2(forward.x, forward.z);
      // Face the way the car travels (reverse looks over the hood).
      final target = speed >= 0 ? headingYaw : headingYaw + math.pi;
      var delta = target - _camera.yaw;
      delta = math.atan2(math.sin(delta), math.cos(delta)); // wrap to [-pi, pi]
      _camera.yaw += delta * (1.0 - math.exp(-2.5 * dt));
    }
    _camera.follow(carPos, dt);

    _speed.value = speed.abs();
    exampleSettings.applyTo(scene);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        CharacterControls(
          input: _input,
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) => _camera.camera,
            onTick: _onTick,
          ),
        ),
        Positioned(top: 16, right: 16, child: _Speedometer(_speed)),
        Positioned(
          top: 16,
          right: 140,
          child: FloatingActionButton.small(
            heroTag: 'car-reset',
            onPressed: _reset,
            child: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}

class _Speedometer extends StatelessWidget {
  const _Speedometer(this.speed);

  final ValueListenable<double> speed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: speed,
        builder: (context, value, _) => Text(
          // Roughly mph: units/s treated as m/s, converted and rounded for a
          // lively readout.
          '${(value * 2.23694).round()} mph',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
