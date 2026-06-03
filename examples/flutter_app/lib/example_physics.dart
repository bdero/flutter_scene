import 'dart:math' as math;

// flutter_scene's physics BoxShape clashes with Flutter's painting
// BoxShape, and flutter_scene's Material class clashes with the Flutter
// Material widget. This example uses the physics BoxShape and the Flutter
// Material widget, so each conflicting name is hidden from the other
// import.
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'character/character_controller.dart';
import 'character/character_controls.dart';
import 'character/character_input.dart';
import 'character/third_person_camera.dart';
import 'example_settings.dart';

/// A third-person physics playground. Drive Dash with WASD / arrow keys
/// (or the on-screen joystick) and jump with space (or the button). Dash
/// is a Rapier kinematic character: it walks and slides along the world,
/// autosteps low ledges, climbs the staircase, and can jump onto the
/// platforms and the dynamic box stack.
class ExamplePhysics extends StatefulWidget {
  const ExamplePhysics({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  ExamplePhysicsState createState() => ExamplePhysicsState();
}

class ExamplePhysicsState extends State<ExamplePhysics> {
  final Scene scene = Scene();
  late final RapierWorld world;

  final CharacterInput _input = CharacterInput();
  final ThirdPersonCamera _camera = ThirdPersonCamera(
    distance: 9.0,
    lookHeight: 1.3,
  );
  late final CharacterController _character;

  static final vm.Vector3 _spawn = vm.Vector3(0, 1.2, 0);

  double _lastElapsed = 0;

  @override
  void initState() {
    super.initState();

    // A key light that casts shadows across the playfield. Pull the shadow
    // distance in from the default (150) so the cascades concentrate on
    // this compact playground and the cast shadows stay crisp.
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.6, -1.0, -0.45),
      intensity: 3.0,
      castsShadow: true,
      shadowMaxDistance: 35.0,
    );
    scene.environmentIntensity = 0.6;

    world = RapierWorld(gravity: vm.Vector3(0, -9.81, 0));
    scene.root.addComponent(world);

    _buildGround();
    _buildStaircase();
    _buildPlatforms();
    _buildStack();
    _spawnCharacter();
  }

  // --- Scene construction ---------------------------------------------------

  Mesh _boxMesh(vm.Vector3 size, vm.Vector4 color) {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..roughnessFactor = 0.5
      ..metallicFactor = 0.0;
    return Mesh(CuboidGeometry(size), material);
  }

  /// Adds a node carrying a body and a single collider, in the order the
  /// backend requires (body before collider), and inserts it into the
  /// scene so both components mount.
  Node _addBody({
    required vm.Vector3 position,
    required BodyType type,
    required Mesh mesh,
    required Shape shape,
    vm.Quaternion? rotation,
    double? mass,
    PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
  }) {
    final transform = rotation == null
        ? vm.Matrix4.translation(position)
        : vm.Matrix4.compose(position, rotation, vm.Vector3.all(1.0));
    final node = Node(mesh: mesh, localTransform: transform);
    node.addComponent(RapierRigidBody(type: type, mass: mass));
    node.addComponent(RapierCollider(shape: shape, material: material));
    scene.add(node);
    return node;
  }

  void _addStaticBox(
    vm.Vector3 center,
    vm.Vector3 halfExtents,
    vm.Vector4 color, {
    vm.Quaternion? rotation,
  }) {
    _addBody(
      position: center,
      type: BodyType.fixed,
      mesh: _boxMesh(halfExtents * 2.0, color),
      shape: BoxShape(halfExtents: halfExtents),
      rotation: rotation,
      material: const PhysicsMaterial(friction: 0.9, restitution: 0.0),
    );
  }

  void _buildGround() {
    _addStaticBox(
      vm.Vector3(0, -0.5, 0),
      vm.Vector3(24, 0.5, 24),
      vm.Vector4(0.60, 0.63, 0.68, 1),
    );
  }

  // A run of short steps (auto-stepped) rising to a tall ledge that has to
  // be jumped, off to one side of the spawn.
  void _buildStaircase() {
    final color = vm.Vector4(0.86, 0.72, 0.42, 1);
    for (var i = 0; i < 4; i++) {
      final height = 0.3 * (i + 1);
      _addStaticBox(
        vm.Vector3(8.0 + i * 1.4, height / 2, -4.0),
        vm.Vector3(0.7, height / 2, 2.0),
        color,
      );
    }
    // A tall block at the top of the stairs that must be jumped onto.
    _addStaticBox(
      vm.Vector3(14.5, 1.0, -4.0),
      vm.Vector3(1.6, 1.0, 2.0),
      vm.Vector4(0.80, 0.55, 0.30, 1),
    );
  }

  // A couple of raised platforms (one reached by jumping) and a ramp.
  void _buildPlatforms() {
    _addStaticBox(
      vm.Vector3(-8.0, 0.75, 4.0),
      vm.Vector3(2.5, 0.75, 2.5),
      vm.Vector4(0.35, 0.55, 0.85, 1),
    );
    _addStaticBox(
      vm.Vector3(-8.0, 2.0, -1.0),
      vm.Vector3(2.0, 0.4, 2.0),
      vm.Vector4(0.45, 0.65, 0.92, 1),
    );
    // A ramp the character can walk up.
    _addStaticBox(
      vm.Vector3(0, 0.9, 10.0),
      vm.Vector3(3.0, 0.25, 3.0),
      vm.Vector4(0.55, 0.78, 0.55, 1),
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.32),
    );
  }

  // A 3-2-1 pyramid of dynamic boxes Dash can clamber onto.
  void _buildStack() {
    const spacing = 1.04;
    final palette = <vm.Vector4>[
      vm.Vector4(0.90, 0.20, 0.22, 1),
      vm.Vector4(0.98, 0.62, 0.10, 1),
      vm.Vector4(0.20, 0.72, 0.35, 1),
    ];
    for (var row = 0; row < 3; row++) {
      final count = 3 - row;
      final y = 0.5 + row * 1.0;
      final startX = -(count - 1) / 2 * spacing;
      for (var i = 0; i < count; i++) {
        _addBody(
          position: vm.Vector3(startX + i * spacing, y, -10.0),
          type: BodyType.dynamic_,
          mesh: _boxMesh(vm.Vector3.all(1.0), palette[row]),
          shape: BoxShape(halfExtents: vm.Vector3.all(0.5)),
          mass: 1.0,
          material: const PhysicsMaterial(friction: 0.8, restitution: 0.0),
        );
      }
    }
  }

  void _spawnCharacter() {
    final node = Node(localTransform: vm.Matrix4.translation(_spawn));
    node.addComponent(RapierRigidBody(type: BodyType.kinematic));
    node.addComponent(
      RapierCollider(
        shape: const CapsuleShape(radius: 0.45, halfHeight: 0.45),
        material: const PhysicsMaterial(friction: 0.0),
      ),
    );
    node.addComponent(
      RapierKinematicCharacterController(
        // A larger skin gap than the default keeps the capsule from
        // catching on box edges and depenetrates a hard landing instead
        // of leaving the feet sunk in the floor.
        offset: 0.08,
        autostep: true,
        autostepMaxHeight: 0.45,
        autostepMinWidth: 0.2,
        snapToGround: 0.5,
        maxSlopeClimbAngle: math.pi / 3,
      ),
    );
    _character = CharacterController(
      input: _input,
      camera: _camera,
      footOffset: 0.9,
      // Drop the model slightly so the feet plant on the ground instead of
      // floating above it by the capsule's skin gap.
      modelHeightOffset: -0.05,
      modelScale: 1.0,
      modelYawOffset: math.pi,
    );
    node.addComponent(_character);
    scene.add(node);
  }

  void _reset() => _character.teleport(_spawn);

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CharacterControls(
          input: _input,
          child: CustomPaint(
            painter: _PlaygroundPainter(this, widget.elapsedSeconds),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: _HintCard(onReset: () => setState(_reset)),
        ),
      ],
    );
  }
}

class _PlaygroundPainter extends CustomPainter {
  _PlaygroundPainter(this.state, this.elapsedSeconds);

  final ExamplePhysicsState state;
  final double elapsedSeconds;

  static const double _dragYawPerPixel = 0.006;
  static const double _dragPitchPerPixel = 0.005;
  static const double _keyYawRate = 2.2;
  static const double _keyPitchRate = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    // Frame delta. Clamp so a long first frame (or a tab regaining focus)
    // does not snap the camera or take a huge physics step.
    final dt = (elapsedSeconds - state._lastElapsed).clamp(0.0, 0.05);
    state._lastElapsed = elapsedSeconds;

    // Orbit the camera from a drag (pixels) and held arrow keys (rate).
    final input = state._input;
    final drag = input.lookDelta.clone();
    input.lookDelta.setZero();
    state._camera.orbit(
      drag.x * _dragYawPerPixel + input.lookRate.x * _keyYawRate * dt,
      drag.y * _dragPitchPerPixel - input.lookRate.y * _keyPitchRate * dt,
    );

    // Advance physics + per-frame component updates with the ticker delta,
    // then follow the character's now-current interpolated pose.
    state.scene.update(dt);
    state._camera.follow(state._character.footPosition, dt);

    exampleSettings.applyTo(state.scene);
    state.scene.render(
      state._camera.camera,
      canvas,
      viewport: Offset.zero & size,
    );
  }

  @override
  bool shouldRepaint(covariant _PlaygroundPainter oldDelegate) => true;
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: 0.85);
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move: WASD / arrows or joystick', style: textStyle),
            Text('Jump: space or the button', style: textStyle),
            const SizedBox(height: 6),
            FilledButton.tonal(
              onPressed: onReset,
              child: const Text('Respawn'),
            ),
          ],
        ),
      ),
    );
  }
}
