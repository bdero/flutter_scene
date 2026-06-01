import 'dart:collection';
import 'dart:math' as math;

// flutter_scene's physics BoxShape clashes with Flutter's painting
// BoxShape, and flutter_scene's Material class clashes with the Flutter
// Material widget. This example uses the physics BoxShape and the
// Flutter Material widget, so each conflicting name is hidden from the
// other import.
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// A physics sandbox driven by the native Rapier backend.
///
/// Demonstrates the whole pluggable-physics surface end to end:
///
///  * dynamic rigid bodies with box and sphere colliders (the stack and
///    the projectiles),
///  * a fixed ground plane,
///  * a revolute-joint pendulum that the projectiles can knock around,
///  * a trigger volume that counts bodies passing through it,
///  * scene queries (each tap raycasts from the camera to aim), and
///  * collision / trigger events surfaced in the on-screen overlay.
///
/// Tap the scene to launch a ball from the camera toward the tap point.
class ExamplePhysics extends StatefulWidget {
  const ExamplePhysics({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  ExamplePhysicsState createState() => ExamplePhysicsState();
}

class ExamplePhysicsState extends State<ExamplePhysics> {
  final Scene scene = Scene();
  late final RapierWorld world;

  // Live counters surfaced in the overlay. The widget rebuilds every
  // frame (the parent ticker drives it), so the listener mutates these
  // directly and the next build reads them; no per-event setState.
  int _collisionCount = 0;
  int _triggerCount = 0;

  // Projectiles, oldest first, so the count can be capped by retiring
  // the oldest ball when a new one is launched.
  final Queue<Node> _balls = Queue<Node>();
  static const int _maxBalls = 24;

  // The boxes making up the stack, tracked so a reset can rebuild them.
  final List<Node> _stack = [];

  // Camera and viewport captured during the last paint, so a tap can
  // reconstruct the picking ray against the exact view that was shown.
  PerspectiveCamera? _lastCamera;
  Size _lastViewport = Size.zero;

  // The trigger volume's node, so trigger events can tell which side of
  // the pair is the ball (the other node) and recolor it.
  Node? _triggerNode;

  // Ball albedo when idle and while overlapping the trigger volume.
  static final vm.Vector4 _ballColor = vm.Vector4(0.95, 0.78, 0.16, 1);
  static final vm.Vector4 _ballHighlightColor = vm.Vector4(0.1, 1.0, 0.95, 1);

  @override
  void initState() {
    super.initState();

    // A key light that casts shadows, plus a touch of exposure, for
    // readable depth and punchy color. The default studio environment
    // still provides ambient fill.
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.5, -1.0, -0.35),
      intensity: 4.5,
      castsShadow: true,
    );
    scene.exposure = 1.4;

    world = RapierWorld(gravity: vm.Vector3(0, -9.81, 0));
    scene.root.addComponent(world);

    world.collisions.listen((event) {
      if (event is CollisionBegan) {
        _collisionCount++;
      } else if (event is TriggerEntered) {
        _triggerCount++;
        _recolorOther(event, _ballHighlightColor);
      } else if (event is TriggerExited) {
        _recolorOther(event, _ballColor);
      }
    });

    _buildGround();
    _buildStack();
    _buildPendulum();
    _buildTriggerZone();
  }

  // Recolors whichever node in a trigger event pair is not the trigger
  // volume (the overlapping ball), so an overlap is visible at a glance.
  void _recolorOther(CollisionEvent event, vm.Vector4 color) {
    final ball = identical(event.nodeA, _triggerNode)
        ? event.nodeB
        : event.nodeA;
    final material = ball.mesh?.primitives.first.material;
    if (material is PhysicallyBasedMaterial) {
      material.baseColorFactor = color;
    }
  }

  // --- Scene construction -------------------------------------------------

  Mesh _boxMesh(vm.Vector3 size, vm.Vector4 color) {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..roughnessFactor = 0.45
      ..metallicFactor = 0.0;
    return Mesh(CuboidGeometry(size), material);
  }

  Mesh _sphereMesh(double radius, vm.Vector4 color) {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..roughnessFactor = 0.25
      ..metallicFactor = 0.2;
    return Mesh(SphereGeometry(radius: radius), material);
  }

  /// Adds a node carrying a body and a single collider, in the order
  /// the backend requires (body before collider), and inserts it into
  /// the scene so both components mount.
  Node _addBody({
    required vm.Vector3 position,
    required BodyType type,
    required Mesh mesh,
    required Shape shape,
    double? mass,
    bool isTrigger = false,
    PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
  }) {
    final node = Node(
      mesh: mesh,
      localTransform: vm.Matrix4.translation(position),
    );
    node.addComponent(RapierRigidBody(type: type, mass: mass));
    node.addComponent(
      RapierCollider(shape: shape, material: material, isTrigger: isTrigger),
    );
    scene.add(node);
    return node;
  }

  void _buildGround() {
    _addBody(
      position: vm.Vector3(0, -0.5, 0),
      type: BodyType.fixed,
      mesh: _boxMesh(vm.Vector3(40, 1, 40), vm.Vector4(0.30, 0.33, 0.38, 1)),
      shape: BoxShape(halfExtents: vm.Vector3(20, 0.5, 20)),
      // Some restitution so projectiles bounce off the floor.
      material: const PhysicsMaterial(friction: 0.8, restitution: 0.6),
    );
  }

  void _buildStack() {
    // A 4-3-2-1 pyramid of unit boxes centered on the origin. Colors are
    // saturated linear values so the lit result reads as vibrant.
    const spacing = 1.04;
    final palette = <vm.Vector4>[
      vm.Vector4(0.90, 0.10, 0.12, 1),
      vm.Vector4(0.98, 0.55, 0.05, 1),
      vm.Vector4(0.05, 0.45, 0.90, 1),
      vm.Vector4(0.10, 0.70, 0.25, 1),
    ];
    for (var row = 0; row < 4; row++) {
      final count = 4 - row;
      final y = 0.5 + row * 1.0;
      final startX = -(count - 1) / 2 * spacing;
      for (var i = 0; i < count; i++) {
        final node = _addBody(
          position: vm.Vector3(startX + i * spacing, y, 0),
          type: BodyType.dynamic_,
          mesh: _boxMesh(vm.Vector3(1, 1, 1), palette[row % palette.length]),
          shape: BoxShape(halfExtents: vm.Vector3(0.5, 0.5, 0.5)),
          mass: 1,
        );
        _stack.add(node);
      }
    }
  }

  void _buildPendulum() {
    // A fixed anchor with a dynamic bob hanging from a revolute hinge.
    // The hinge axis is +Z, so the bob swings in the XY plane and can be
    // batted around by projectiles coming from the camera.
    final pivot = vm.Vector3(-5, 5.5, 0);
    const armLength = 2.5;

    final anchorNode = _addBody(
      position: pivot,
      type: BodyType.fixed,
      mesh: _boxMesh(vm.Vector3(0.4, 0.4, 0.4), vm.Vector4(0.55, 0.55, 0.6, 1)),
      shape: BoxShape(halfExtents: vm.Vector3(0.2, 0.2, 0.2)),
    );

    // The bob hangs [armLength] below the pivot. The swing radius lives
    // on the bob's own anchor (pointing from the bob center up to the
    // pivot); the anchor body's anchor sits at its center. With the
    // offset on the wrong anchor the bob's center would be pinned at the
    // pivot and could only spin in place, which is why it looked absent.
    final bobNode = _addBody(
      position: pivot + vm.Vector3(0, -armLength, 0),
      type: BodyType.dynamic_,
      mesh: _boxMesh(
        vm.Vector3(0.8, 0.8, 0.8),
        vm.Vector4(0.80, 0.15, 0.65, 1),
      ),
      shape: BoxShape(halfExtents: vm.Vector3(0.4, 0.4, 0.4)),
      mass: 2,
    );

    final joint = RapierRevoluteJoint(
      otherNode: anchorNode,
      axis: vm.Vector3(0, 0, 1),
      localAnchorA: vm.Vector3(0, armLength, 0),
      localAnchorB: vm.Vector3.zero(),
    );
    bobNode.addComponent(joint);

    // A sideways nudge so the pendulum is visibly swinging on load,
    // rather than hanging dead-still at the bottom of its arc.
    bobNode.getComponent<RapierRigidBody>()!.linearVelocity = vm.Vector3(
      4,
      0,
      0,
    );
  }

  void _buildTriggerZone() {
    // A translucent "goal" volume floating above the ground. Bodies that
    // pass through it bump the trigger counter and get recolored while
    // overlapping, via the collisions stream.
    _triggerNode = _addBody(
      position: vm.Vector3(0, 3, 7),
      type: BodyType.fixed,
      mesh: _boxMesh(vm.Vector3(4, 4, 0.3), vm.Vector4(0.2, 0.9, 0.6, 0.25)),
      shape: BoxShape(halfExtents: vm.Vector3(2, 2, 0.15)),
      isTrigger: true,
    );
  }

  // --- Interaction --------------------------------------------------------

  void _launchBall(Offset localPosition) {
    final camera = _lastCamera;
    if (camera == null || _lastViewport.isEmpty) return;

    final dir = _rayDirection(camera, localPosition, _lastViewport);
    final origin = camera.position + dir * 1.5;

    final node = _addBody(
      position: origin,
      type: BodyType.dynamic_,
      mesh: _sphereMesh(0.35, _ballColor),
      shape: SphereShape(radius: 0.35),
      mass: 1.5,
      // Bouncy: combined with the floor's restitution this gives a
      // lively rebound.
      material: const PhysicsMaterial(friction: 0.4, restitution: 0.8),
    );

    final body = node.getComponent<RapierRigidBody>()!;
    body.applyImpulse(dir * 42.0);

    _balls.addLast(node);
    if (_balls.length > _maxBalls) {
      scene.remove(_balls.removeFirst());
    }
  }

  // Reconstructs the world-space ray through a screen point, matching the
  // basis PerspectiveCamera builds for its view transform.
  vm.Vector3 _rayDirection(PerspectiveCamera camera, Offset point, Size size) {
    final forward = (camera.target - camera.position).normalized();
    final right = camera.up.cross(forward).normalized();
    final up = forward.cross(right).normalized();

    final ndcX = (2 * point.dx / size.width) - 1;
    final ndcY = 1 - (2 * point.dy / size.height);
    final tanY = math.tan(camera.fovRadiansY * 0.5);
    final tanX = tanY * (size.width / size.height);

    return (forward + right * (ndcX * tanX) + up * (ndcY * tanY)).normalized();
  }

  void _reset() {
    for (final node in _balls) {
      scene.remove(node);
    }
    _balls.clear();
    for (final node in _stack) {
      scene.remove(node);
    }
    _stack.clear();
    _buildStack();
    _collisionCount = 0;
    _triggerCount = 0;
  }

  // --- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _launchBall(details.localPosition),
          child: CustomPaint(
            painter: _PhysicsPainter(this, widget.elapsedSeconds),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: _Overlay(
            balls: _balls.length,
            collisions: _collisionCount,
            triggers: _triggerCount,
            onReset: () => setState(_reset),
          ),
        ),
      ],
    );
  }
}

class _PhysicsPainter extends CustomPainter {
  _PhysicsPainter(this.state, this.elapsedSeconds);

  final ExamplePhysicsState state;
  final double elapsedSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    // A gentle orbit so the stack reads as three-dimensional. The same
    // camera is stashed on the state so taps aim at what is on screen.
    final angle = elapsedSeconds * 0.15;
    final camera = PerspectiveCamera(
      position: vm.Vector3(math.sin(angle) * 12, 7, math.cos(angle) * 12 + 2),
      target: vm.Vector3(0, 1.5, 1),
    );
    state._lastCamera = camera;
    state._lastViewport = size;

    exampleSettings.applyTo(state.scene);
    state.scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant _PhysicsPainter oldDelegate) => true;
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.balls,
    required this.collisions,
    required this.triggers,
    required this.onReset,
  });

  final int balls;
  final int collisions;
  final int triggers;
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
            Text('Tap to launch a ball', style: textStyle),
            const SizedBox(height: 4),
            Text('Balls: $balls', style: textStyle),
            Text('Collisions: $collisions', style: textStyle),
            Text('Trigger hits: $triggers', style: textStyle),
            const SizedBox(height: 4),
            FilledButton.tonal(
              onPressed: onReset,
              child: const Text('Reset stack'),
            ),
          ],
        ),
      ),
    );
  }
}
