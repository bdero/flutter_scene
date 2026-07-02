import 'dart:math' as math;

// flutter_scene's physics BoxShape clashes with Flutter's painting BoxShape,
// and flutter_scene's Material clashes with the Flutter Material widget, so
// each conflicting name is hidden from the other import.
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_box3d/flutter_scene_box3d.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';
import 'quake_camera.dart';

/// A box3d physics playground. A stack of boxes, a swinging pendulum rope
/// (spherical joints), and a code-driven kinematic spinner sit on the
/// ground. Tap to drop a random shape from above, drag to look, and WASD/QE
/// to fly the camera.
class ExamplePhysicsBox3d extends StatefulWidget {
  const ExamplePhysicsBox3d({super.key});

  @override
  State<ExamplePhysicsBox3d> createState() => _ExamplePhysicsBox3dState();
}

class _ExamplePhysicsBox3dState extends State<ExamplePhysicsBox3d> {
  final Scene scene = Scene();
  late final Box3dPhysicsWorld world;

  final QuakeCamera _camera = QuakeCamera(
    position: vm.Vector3(0, 5, 14),
    pitch: -0.3,
  )..speed = 8.0;
  final FocusNode _sceneFocus = FocusNode(debugLabel: 'box3d-scene');
  PerspectiveCamera? _perspective;
  Size _viewSize = Size.zero;

  // Bodies dropped by tapping, retired oldest-first past the cap.
  static const int _maxDropped = 40;
  final List<Node> _dropped = [];
  final math.Random _rng = math.Random(11);

  // The code-driven kinematic spinner bar.
  Node? _spinner;
  double _spinnerAngle = 0.0;
  static final vm.Vector3 _spinnerCenter = vm.Vector3(-6, 0.7, 0);

  static final List<vm.Vector4> _palette = [
    vm.Vector4(0.91, 0.30, 0.35, 1),
    vm.Vector4(0.95, 0.61, 0.24, 1),
    vm.Vector4(0.96, 0.82, 0.25, 1),
    vm.Vector4(0.42, 0.74, 0.40, 1),
    vm.Vector4(0.30, 0.62, 0.86, 1),
    vm.Vector4(0.56, 0.42, 0.80, 1),
  ];

  @override
  void initState() {
    super.initState();
    scene.root.addComponent(
      DirectionalLightComponent(
        DirectionalLight(
          direction: vm.Vector3(-0.6, -1.0, -0.45),
          intensity: 3.0,
          castsShadow: true,
          shadowMaxDistance: 40.0,
        ),
      ),
    );
    scene.environmentIntensity = 0.6;

    world = Box3dPhysicsWorld(gravity: vm.Vector3(0, -9.81, 0));
    scene.root.addComponent(world);

    _buildGround();
    _buildStack();
    _buildPendulum();
    _buildSpinner();
  }

  @override
  void dispose() {
    _sceneFocus.dispose();
    super.dispose();
  }

  // --- Scene construction ---------------------------------------------------

  Mesh _boxMesh(vm.Vector3 size, vm.Vector4 color, {double roughness = 0.5}) {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..roughnessFactor = roughness
      ..metallicFactor = 0.0;
    return Mesh(CuboidGeometry(size), material);
  }

  Node _addBody({
    required vm.Vector3 position,
    required BodyType type,
    required Mesh mesh,
    required Shape shape,
    vm.Quaternion? rotation,
    PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
    double linearDamping = 0,
    double angularDamping = 0,
  }) {
    final transform = rotation == null
        ? vm.Matrix4.translation(position)
        : vm.Matrix4.compose(position, rotation, vm.Vector3.all(1.0));
    final node = Node(mesh: mesh, localTransform: transform);
    node.addComponent(
      Box3dRigidBody(
        type: type,
        linearDamping: linearDamping,
        angularDamping: angularDamping,
      ),
    );
    node.addComponent(Box3dCollider(shape: shape, material: material));
    scene.add(node);
    return node;
  }

  void _buildGround() {
    final half = vm.Vector3(24, 0.5, 24);
    _addBody(
      position: vm.Vector3(0, -0.5, 0),
      type: BodyType.fixed,
      mesh: _boxMesh(
        half * 2.0,
        vm.Vector4(0.55, 0.58, 0.62, 1),
        roughness: 0.9,
      ),
      shape: BoxShape(halfExtents: half),
      material: const PhysicsMaterial(friction: 0.9),
    );
  }

  // A 3-2-1 pyramid of dynamic boxes.
  void _buildStack() {
    const spacing = 1.04;
    for (var row = 0; row < 3; row++) {
      final count = 3 - row;
      final y = 0.5 + row * 1.0;
      final startX = -(count - 1) / 2 * spacing;
      for (var i = 0; i < count; i++) {
        _addBody(
          position: vm.Vector3(startX + i * spacing, y, -6),
          type: BodyType.dynamic_,
          mesh: _boxMesh(vm.Vector3.all(1.0), _palette[row]),
          shape: BoxShape(halfExtents: vm.Vector3.all(0.5)),
          material: const PhysicsMaterial(friction: 0.8),
        );
      }
    }
  }

  // A rope of beads linked by spherical joints, anchored to the world at the
  // top so it swings freely.
  void _buildPendulum() {
    const topY = 5.0, nBeads = 6, spacing = 0.5, beadR = 0.22;
    const half = spacing / 2;
    final anchor = vm.Vector3(6, topY, 0);
    final geometry = SphereGeometry(radius: beadR);
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.75, 0.72, 0.5, 1)
      ..roughnessFactor = 0.4
      ..metallicFactor = 0.1;

    Node? prev;
    for (var i = 0; i < nBeads; i++) {
      final node = Node(
        mesh: Mesh(geometry, material),
        localTransform: vm.Matrix4.translation(
          vm.Vector3(anchor.x, topY - half - i * spacing, anchor.z),
        ),
      );
      node.addComponent(
        Box3dRigidBody(
          type: BodyType.dynamic_,
          linearDamping: 0.2,
          angularDamping: 0.4,
        ),
      );
      node.addComponent(Box3dCollider(shape: const SphereShape(radius: beadR)));
      scene.add(node);
      node.addComponent(
        i == 0
            ? Box3dSphericalJoint(
                localAnchorA: vm.Vector3(0, half, 0),
                localAnchorB: anchor.clone(),
              )
            : Box3dSphericalJoint(
                otherNode: prev,
                localAnchorA: vm.Vector3(0, half, 0),
                localAnchorB: vm.Vector3(0, -half, 0),
              ),
      );
      prev = node;
    }
    // Give the bottom bead a shove so the pendulum starts swinging.
    prev?.getComponent<Box3dRigidBody>()?.linearVelocity = vm.Vector3(0, 0, 4);
  }

  // A kinematic bar sweeping a horizontal circle, driven by code each frame.
  void _buildSpinner() {
    _spinner = _addBody(
      position: _spinnerCenter,
      type: BodyType.kinematic,
      mesh: _boxMesh(vm.Vector3(6, 0.4, 0.4), vm.Vector4(0.88, 0.22, 0.26, 1)),
      shape: BoxShape(halfExtents: vm.Vector3(3, 0.2, 0.2)),
      material: const PhysicsMaterial(friction: 0.4),
    );
  }

  // --- Interaction ----------------------------------------------------------

  void _onTick(Duration elapsed, double deltaSeconds) {
    final dt = deltaSeconds.clamp(0.0, 0.05);
    // Spin the kinematic bar by writing its node transform; the body syncs
    // to the node each fixed step and shoves whatever it hits.
    final spinner = _spinner;
    if (spinner != null) {
      _spinnerAngle += 1.2 * dt;
      spinner.localTransform = vm.Matrix4.compose(
        _spinnerCenter,
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _spinnerAngle),
        vm.Vector3.all(1.0),
      );
    }
    scene.update(dt);
    exampleSettings.applyTo(scene);
  }

  // Drops a random shape from above wherever the tap ray meets the scene.
  void _dropAt(Offset screenPosition) {
    final camera = _perspective;
    if (camera == null || _viewSize.isEmpty) return;
    final ray = camera.screenPointToRay(screenPosition, _viewSize);
    final hit = scene.raycast(ray);
    final target = hit?.worldPoint ?? _intersectGround(ray);
    if (target == null) return;
    _drop(vm.Vector3(target.x, target.y + 7.0, target.z));
  }

  vm.Vector3? _intersectGround(vm.Ray ray) {
    final dirY = ray.direction.y;
    if (dirY.abs() < 1e-6) return null;
    final t = -ray.origin.y / dirY;
    if (t < 0) return null;
    return ray.origin + ray.direction.scaled(t);
  }

  void _drop(vm.Vector3 position) {
    final color = _palette[_rng.nextInt(_palette.length)];
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..roughnessFactor = 0.45
      ..metallicFactor = 0.05;
    final rotation = vm.Quaternion.euler(
      _rng.nextDouble() * math.pi * 2,
      _rng.nextDouble() * math.pi * 2,
      _rng.nextDouble() * math.pi * 2,
    );
    // Cycle through the shapes box3d supports as analytic colliders.
    final Geometry geometry;
    final Shape shape;
    switch (_rng.nextInt(4)) {
      case 0:
        final g = SphereGeometry(radius: 0.5);
        geometry = g;
        shape = g.collisionShape;
      case 1:
        final g = CapsuleGeometry(radius: 0.35, height: 1.2);
        geometry = g;
        shape = g.collisionShape;
      case 2:
        final g = CylinderGeometry(
          bottomRadius: 0.5,
          topRadius: 0.5,
          height: 1.0,
        );
        geometry = g;
        shape = g.collisionShape;
      default:
        final g = CuboidGeometry(vm.Vector3.all(1.0));
        geometry = g;
        shape = g.collisionShape;
    }
    final node = _addBodyMesh(
      Mesh(geometry, material),
      shape,
      position,
      rotation,
    );
    _dropped.add(node);
    if (_dropped.length > _maxDropped) {
      scene.remove(_dropped.removeAt(0));
    }
  }

  Node _addBodyMesh(
    Mesh mesh,
    Shape shape,
    vm.Vector3 position,
    vm.Quaternion rotation,
  ) {
    final node = Node(
      mesh: mesh,
      localTransform: vm.Matrix4.compose(position, rotation, vm.Vector3.all(1)),
    );
    node.addComponent(Box3dRigidBody(type: BodyType.dynamic_));
    node.addComponent(
      Box3dCollider(
        shape: shape,
        material: const PhysicsMaterial(friction: 0.6, restitution: 0.1),
      ),
    );
    scene.add(node);
    return node;
  }

  void _clear() {
    setState(() {
      for (final node in _dropped) {
        scene.remove(node);
      }
      _dropped.clear();
    });
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Focus(
            focusNode: _sceneFocus,
            autofocus: true,
            onKeyEvent: _camera.onKeyEvent,
            child: Listener(
              onPointerDown: (_) => _sceneFocus.requestFocus(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _dropAt(details.localPosition),
                onPanUpdate: (details) => _camera.look(details.delta),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _viewSize = constraints.biggest;
                    return SceneView(
                      scene,
                      cameraBuilder: (elapsed) {
                        _camera.move(elapsed.inMicroseconds / 1e6);
                        return _perspective = _camera.camera;
                      },
                      onTick: _onTick,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: Card(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tap to drop a shape  •  drag to look  •  WASD/QE to move',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.tonal(
                      onPressed: _dropped.isEmpty ? null : _clear,
                      child: const Text('Clear dropped'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
