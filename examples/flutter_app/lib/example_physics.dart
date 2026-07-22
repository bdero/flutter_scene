import 'dart:async';
import 'dart:math' as math;

// flutter_scene's physics BoxShape clashes with Flutter's painting
// BoxShape, and flutter_scene's Material class clashes with the Flutter
// Material widget. This example uses the physics BoxShape and the Flutter
// Material widget, so each conflicting name is hidden from the other
// import.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'character/character_controller.dart';
import 'character/character_controls.dart';
import 'character/character_input.dart';
import 'character/third_person_camera.dart';
import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_settings.dart';

/// A third-person physics playground. Drive Dash with WASD / arrow keys
/// (or the on-screen joystick) and jump with space (or the button). Dash
/// is a Rapier kinematic character: it walks and slides along the world,
/// autosteps low ledges, climbs the staircase, and can jump onto the
/// platforms and the dynamic box stack.
class ExamplePhysics extends StatefulWidget {
  const ExamplePhysics({super.key});

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
  Node? _characterNode;

  // A translucent trigger volume Dash can walk into. While Dash is inside,
  // the box glows and a vignette closes in around the view.
  late final Node _triggerNode;
  late final PhysicallyBasedMaterial _triggerMaterial;
  StreamSubscription<CollisionEvent>? _collisionSub;
  bool _inTrigger = false;
  // Eased 0..1 follows [_inTrigger]; drives the box glow and the vignette.
  double _triggerGlow = 0.0;
  double _vignette = 0.0;

  // A kinematic lift: it rides up while Dash stands on its pressure-plate
  // deck (a sensor) and descends when he steps off. Driven each frame from
  // [_elevatorOccupied] in the painter.
  Node? _elevatorNode;
  RapierRigidBody? _elevatorBody;
  bool _elevatorOccupied = false;
  double _elevatorY = _elevatorBottomY;
  // Keeps the lift parked at the top briefly after Dash steps off, so it
  // does not drop out from under him the instant he reaches the edge.
  double _elevatorDwell = 0.0;

  static const double _elevatorX = 16.0;
  static const double _elevatorZ = 10.0;
  static const double _elevatorBottomY = 0.2;
  static const double _elevatorTopY = 3.1;
  static const double _elevatorLiftSpeed = 1.8;
  static const double _elevatorDwellMax = 1.2;

  // A kinematic bar that sweeps a horizontal circle, rotated by code each
  // frame. Kinematic (not a dynamic motor) so it shoves the kinematic
  // character aside instead of stalling against his infinite mass.
  Node? _spinnerNode;
  double _spinnerAngle = 0.0;
  static final vm.Vector3 _spinnerCenter = vm.Vector3(-10, 0.7, -10);
  static const double _spinnerSpeed = 1.4; // rad/s

  static final vm.Vector3 _spawn = vm.Vector3(0, 1.2, 0);

  // Drives the 2D vignette overlay painted on top of the scene; updated each
  // frame from [_vignette] so the overlay repaints without rebuilding.
  final ValueNotifier<double> _vignetteListenable = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();

    // A key light that casts shadows across the playfield. Pull the shadow
    // distance in from the default (150) so the cascades concentrate on
    // this compact playground and the cast shadows stay crisp.
    scene.root.addComponent(
      DirectionalLightComponent(
        DirectionalLight(
          direction: vm.Vector3(-0.6, -1.0, -0.45),
          intensity: 3.0,
          castsShadow: true,
          shadowMaxDistance: 35.0,
        ),
      ),
    );
    scene.environmentIntensity = 0.6;

    world = RapierWorld(gravity: vm.Vector3(0, -9.81, 0));
    scene.root.addComponent(world);

    _buildGround();
    _buildStaircase();
    _buildPlatforms();
    _buildSlopes();
    _buildStack();
    _buildTrigger();
    _buildSpinner();
    _buildBridge();
    _buildElevator();
    _buildSeesaw();
    _buildCurtain();
    _buildRopes();
    _spawnCharacter();

    // React to Dash entering / leaving the trigger volume. Subscribing
    // adds a listener, which is what makes the world drain its events.
    _collisionSub = world.collisions.listen(_onCollision);
  }

  @override
  void dispose() {
    _collisionSub?.cancel();
    _vignetteListenable.dispose();
    super.dispose();
  }

  void _onCollision(CollisionEvent event) {
    // Only the character entering / leaving our sensor volumes matters;
    // ignore solid contacts (the dynamic boxes, the lift deck) and any
    // pair that does not involve Dash.
    final character = _characterNode;
    if (character == null) return;
    if (event is! TriggerEntered && event is! TriggerExited) return;
    final involvesCharacter =
        event.nodeA == character || event.nodeB == character;
    if (!involvesCharacter) return;
    final entered = event is TriggerEntered;
    final other = event.nodeA == character ? event.nodeB : event.nodeA;
    if (other == _triggerNode) {
      _inTrigger = entered;
    } else if (other == _elevatorNode) {
      // The lift's pressure-plate sensor: ride up while occupied.
      _elevatorOccupied = entered;
    }
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
  }

  // A row of wedge ramps at increasing angles, from nearly flat to nearly
  // vertical, to test how the character controller handles slopes. The
  // shallow ones are walkable; the steep ones (past the controller's
  // max-climb angle) block Dash.
  void _buildSlopes() {
    const z = 12.0, width = 2.4, height = 2.0;
    const anglesDeg = [15.0, 30.0, 45.0, 60.0, 70.0, 80.0];
    for (var i = 0; i < anglesDeg.length; i++) {
      final angle = anglesDeg[i] * math.pi / 180.0;
      final run = height / math.tan(angle); // depth Z
      final x = (i - (anglesDeg.length - 1) / 2) * 3.6;
      final size = vm.Vector3(width, height, run);
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.34, (0.45 + 0.07 * i), 0.40, 1)
        ..roughnessFactor = 0.6
        ..metallicFactor = 0.0;
      final node = Node(
        mesh: Mesh(WedgeGeometry(size), material),
        localTransform: vm.Matrix4.translation(vm.Vector3(x, 0, z)),
      );
      node.addComponent(RapierRigidBody(type: BodyType.fixed));
      node.addComponent(
        RapierCollider(
          shape: ConvexHullShape(points: _wedgePoints(width, height, run)),
          material: const PhysicsMaterial(friction: 0.9, restitution: 0.0),
        ),
      );
      scene.add(node);
    }
  }

  // The six corner points of a wedge (matching [WedgeGeometry]), as a flat
  // x,y,z list, for a convex-hull collider.
  Float32List _wedgePoints(double width, double height, double run) {
    final hx = width / 2, hz = run / 2;
    return Float32List.fromList([
      -hx, 0, -hz, //
      hx, 0, -hz,
      -hx, 0, hz,
      hx, 0, hz,
      -hx, height, hz,
      hx, height, hz,
    ]);
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

  // Idle (cool, faint) and active (warm, brighter) tints the trigger box
  // lerps between as Dash enters. Alpha keeps the box translucent.
  static final vm.Vector4 _triggerIdleColor = vm.Vector4(
    0.30,
    0.65,
    0.95,
    0.20,
  );
  static final vm.Vector4 _triggerActiveColor = vm.Vector4(
    0.98,
    0.45,
    0.22,
    0.42,
  );
  static final vm.Vector4 _triggerIdleEmissive = vm.Vector4(
    0.02,
    0.05,
    0.09,
    1.0,
  );
  static final vm.Vector4 _triggerActiveEmissive = vm.Vector4(
    0.70,
    0.22,
    0.05,
    1.0,
  );

  // A translucent box wired up as a Rapier sensor (trigger). It has a
  // fixed body and a sensor collider, so it reports overlaps without
  // pushing anything around.
  void _buildTrigger() {
    final half = vm.Vector3(2.2, 1.4, 2.2);
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = _triggerIdleColor.clone()
      ..emissiveFactor = _triggerIdleEmissive.clone()
      ..roughnessFactor = 0.25
      ..metallicFactor = 0.0
      ..alphaMode = AlphaMode.blend;
    _triggerMaterial = material;

    // Clear of the green ramp (centred at z = 10, reaching back to z = 7).
    final center = vm.Vector3(6.5, half.y, 3.5);
    final node = Node(
      mesh: Mesh(CuboidGeometry(half * 2.0), material),
      localTransform: vm.Matrix4.translation(center),
    );
    node.addComponent(RapierRigidBody(type: BodyType.fixed));
    node.addComponent(
      RapierCollider(shape: BoxShape(halfExtents: half), isTrigger: true),
    );
    _triggerNode = node;
    scene.add(node);
  }

  // A bar that sweeps in a horizontal circle, driven by a revolute joint
  // with a velocity motor anchored to the world. Dash gets shoved if he
  // stands in its path; the bar sweeps low enough to jump over.
  void _buildSpinner() {
    // A decorative hub post just below the bar (no collider, so it never
    // intersects the sweeping bar).
    scene.add(
      Node(
        mesh: _boxMesh(
          vm.Vector3(0.6, 0.46, 0.6),
          vm.Vector4(0.40, 0.40, 0.46, 1),
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(-10, 0.23, -10)),
      ),
    );
    final arm = Node(
      mesh: _boxMesh(
        vm.Vector3(6.0, 0.45, 0.45),
        vm.Vector4(0.88, 0.22, 0.26, 1),
      ),
      localTransform: vm.Matrix4.translation(_spinnerCenter),
    );
    arm.addComponent(RapierRigidBody(type: BodyType.kinematic));
    arm.addComponent(
      RapierCollider(
        shape: BoxShape(halfExtents: vm.Vector3(3.0, 0.225, 0.225)),
        material: const PhysicsMaterial(friction: 0.4, restitution: 0.0),
      ),
    );
    scene.add(arm);
    _spinnerNode = arm;
  }

  // A wobbly plank bridge: a chain of dynamic planks hinged end-to-end by
  // revolute joints, slung between two fixed towers. A short stair climbs
  // up to one end; stepping off the far end is a real fall.
  void _buildBridge() {
    const bx = -16.0;
    const topY = 1.6;
    const halfW = 1.6; // half-width across the bridge (X)
    const towerHalfY = 0.8;
    const towerHalfZ = 1.2;
    const aZ = 6.0; // near tower (stair side)
    const bZ = -6.0; // far tower (fall-off side)
    final towerColor = vm.Vector4(0.58, 0.52, 0.45, 1);
    final plankColor = vm.Vector4(0.62, 0.45, 0.30, 1);
    const towerYCenter = topY - towerHalfY;

    final towerA = _addBody(
      position: vm.Vector3(bx, towerYCenter, aZ),
      type: BodyType.fixed,
      mesh: _boxMesh(
        vm.Vector3(halfW * 2, towerHalfY * 2, towerHalfZ * 2),
        towerColor,
      ),
      shape: BoxShape(halfExtents: vm.Vector3(halfW, towerHalfY, towerHalfZ)),
      material: const PhysicsMaterial(friction: 0.9, restitution: 0.0),
    );
    final towerB = _addBody(
      position: vm.Vector3(bx, towerYCenter, bZ),
      type: BodyType.fixed,
      mesh: _boxMesh(
        vm.Vector3(halfW * 2, towerHalfY * 2, towerHalfZ * 2),
        towerColor,
      ),
      shape: BoxShape(halfExtents: vm.Vector3(halfW, towerHalfY, towerHalfZ)),
      material: const PhysicsMaterial(friction: 0.9, restitution: 0.0),
    );

    // A short stair climbing up to the near tower from the +Z side: the
    // tallest step sits against the tower and they get shorter heading out
    // to the ground, so Dash walks up them toward the bridge.
    const nSteps = 3;
    for (var i = 0; i < nSteps; i++) {
      final h = topY * (i + 1) / nSteps; // i == nSteps-1 is the tallest
      _addStaticBox(
        vm.Vector3(bx, h / 2, aZ + towerHalfZ + 0.7 + (nSteps - 1 - i) * 1.2),
        vm.Vector3(halfW, h / 2, 0.7),
        towerColor,
      );
    }

    // Hang the planks along a shallow circular arc. The arc is longer than
    // the straight gap between the towers, so the chain has real slack and
    // keeps a visible sag; placing each plank on the arc (oriented along
    // it, with its length matching the arc segment) means the joints start
    // satisfied, so it settles gently instead of snapping taut.
    final spanStart = aZ - towerHalfZ; // inner face of tower A (+Z end)
    final spanEnd = bZ + towerHalfZ; // inner face of tower B (-Z end)
    const nPlanks = 12;
    const plankHalfY = 0.07;
    // Deep enough that the chain is meaningfully longer than the gap, so it
    // genuinely curves down between the towers.
    const sagDepth = 1.7;

    final chord = spanStart - spanEnd;
    final zMid = (spanStart + spanEnd) / 2;
    final radius = (chord * chord / 4 + sagDepth * sagDepth) / (2 * sagDepth);
    final phi = math.asin((chord / 2) / radius); // arc half-angle
    final yArcCenter = topY - plankHalfY + radius * math.cos(phi);
    final segLen = 2 * radius * math.sin(phi / nPlanks);
    final plankHalfZ = segLen / 2 - 0.02;

    // Boundary point j (j == 0 at tower A, j == nPlanks at tower B).
    vm.Vector3 boundary(int j) {
      final a = phi - 2 * phi * (j / nPlanks);
      return vm.Vector3(
        bx,
        yArcCenter - radius * math.cos(a),
        zMid + radius * math.sin(a),
      );
    }

    final planks = <Node>[];
    for (var i = 0; i < nPlanks; i++) {
      final p0 = boundary(i);
      final p1 = boundary(i + 1);
      final center = (p0 + p1)..scale(0.5);
      final dy = p1.y - p0.y;
      final dz = p1.z - p0.z;
      // Rotate about X so the plank's local +Z runs from p0 toward p1.
      final rot = vm.Quaternion.axisAngle(
        vm.Vector3(1, 0, 0),
        math.atan2(-dy, dz),
      );
      final node = Node(
        mesh: _boxMesh(
          vm.Vector3(halfW * 2, plankHalfY * 2, plankHalfZ * 2),
          plankColor,
        ),
        localTransform: vm.Matrix4.compose(center, rot, vm.Vector3.all(1.0)),
      );
      node.addComponent(
        RapierRigidBody(
          type: BodyType.dynamic_,
          mass: 0.9,
          // A little damping so the bridge settles instead of jiggling
          // like Jell-O, without making it feel stiff.
          linearDamping: 0.4,
          angularDamping: 0.6,
        ),
      );
      node.addComponent(
        RapierCollider(
          shape: BoxShape(
            halfExtents: vm.Vector3(halfW, plankHalfY, plankHalfZ),
          ),
          material: const PhysicsMaterial(friction: 0.95, restitution: 0.0),
        ),
      );
      scene.add(node);
      planks.add(node);
    }

    // Hinge axis runs across the bridge (X), so planks fold up and down.
    // A plank's local -Z end is its tower-A side, +Z end its tower-B side.
    final axis = vm.Vector3(1, 0, 0);
    planks.first.addComponent(
      RapierRevoluteJoint(
        otherNode: towerA,
        axis: axis,
        localAnchorA: vm.Vector3(0, 0, -plankHalfZ),
        localAnchorB: vm.Vector3(0, towerHalfY, -towerHalfZ),
      ),
    );
    for (var i = 1; i < nPlanks; i++) {
      planks[i].addComponent(
        RapierRevoluteJoint(
          otherNode: planks[i - 1],
          axis: axis,
          localAnchorA: vm.Vector3(0, 0, -plankHalfZ),
          localAnchorB: vm.Vector3(0, 0, plankHalfZ),
        ),
      );
    }
    planks.last.addComponent(
      RapierRevoluteJoint(
        otherNode: towerB,
        axis: axis,
        localAnchorA: vm.Vector3(0, 0, plankHalfZ),
        localAnchorB: vm.Vector3(0, towerHalfY, towerHalfZ),
      ),
    );
  }

  // A kinematic lift driven by a pressure-plate sensor on its own deck.
  // Standing on it raises it; stepping off lowers it (see the painter,
  // which eases [_elevatorY] toward the occupied target each frame). At the
  // top it meets a lookout platform Dash can step onto (and fall off).
  void _buildElevator() {
    final deckHalf = vm.Vector3(1.8, 0.2, 1.8);
    final deck = Node(
      mesh: _boxMesh(deckHalf * 2.0, vm.Vector4(0.45, 0.50, 0.56, 1)),
      localTransform: vm.Matrix4.translation(
        vm.Vector3(_elevatorX, _elevatorBottomY, _elevatorZ),
      ),
    );
    final body = RapierRigidBody(type: BodyType.kinematic);
    deck.addComponent(body);
    _elevatorBody = body;
    deck.addComponent(
      RapierCollider(
        shape: BoxShape(halfExtents: deckHalf),
        material: const PhysicsMaterial(friction: 0.9, restitution: 0.0),
      ),
    );
    // The pressure plate: a sensor sitting just above the deck. Dash
    // standing here counts as occupying the lift.
    deck.addComponent(
      RapierCollider(
        shape: BoxShape(
          halfExtents: vm.Vector3(deckHalf.x * 0.9, 0.5, deckHalf.z * 0.9),
        ),
        isTrigger: true,
        localPose: vm.Matrix4.translation(vm.Vector3(0, deckHalf.y + 0.5, 0)),
      ),
    );
    scene.add(deck);
    _elevatorNode = deck;

    // Lookout platform flush with the lift at the top, just past it.
    final lookoutTop = _elevatorTopY + deckHalf.y;
    const lookoutHalfY = 1.0;
    _addStaticBox(
      vm.Vector3(_elevatorX, lookoutTop - lookoutHalfY, _elevatorZ + 3.4),
      vm.Vector3(1.8, lookoutHalfY, 1.6),
      vm.Vector4(0.50, 0.55, 0.50, 1),
    );
  }

  // A plank balanced on a free revolute hinge with a heavy ball resting on
  // it: the ball rolls to the low side and rocks the seesaw, and Dash can
  // shove the ball (or bump the plank ends) to tip it the other way.
  void _buildSeesaw() {
    const sx = 6.0, sz = -14.0; // open ground, far +x / -z
    const plankHalfZ = 3.2; // plank runs along Z
    const plankHalfX = 1.3;
    const plankHalfY = 0.12;
    const pivotY = 0.9;

    final plank = Node(
      mesh: _boxMesh(
        vm.Vector3(plankHalfX * 2, plankHalfY * 2, plankHalfZ * 2),
        vm.Vector4(0.70, 0.62, 0.40, 1),
      ),
      localTransform: vm.Matrix4.translation(vm.Vector3(sx, pivotY, sz)),
    );
    plank.addComponent(RapierRigidBody(type: BodyType.dynamic_, mass: 2.0));
    plank.addComponent(
      RapierCollider(
        shape: BoxShape(
          halfExtents: vm.Vector3(plankHalfX, plankHalfY, plankHalfZ),
        ),
        material: const PhysicsMaterial(friction: 0.8, restitution: 0.0),
      ),
    );
    scene.add(plank);
    // World-anchored hinge across the plank (X axis), with limits so it
    // tips but never flips over.
    plank.addComponent(
      RapierRevoluteJoint(
        axis: vm.Vector3(1, 0, 0),
        localAnchorA: vm.Vector3.zero(),
        localAnchorB: vm.Vector3(sx, pivotY, sz),
        lowerLimit: -0.42,
        upperLimit: 0.42,
      ),
    );

    // A heavy ball resting near one end to start it tipped and rolling.
    final ball = Node(
      mesh: Mesh(
        SphereGeometry(radius: 0.5),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.90, 1)
          ..roughnessFactor = 0.3
          ..metallicFactor = 0.1,
      ),
      localTransform: vm.Matrix4.translation(
        vm.Vector3(sx, pivotY + 0.7, sz - 2.0),
      ),
    );
    ball.addComponent(RapierRigidBody(type: BodyType.dynamic_, mass: 3.0));
    ball.addComponent(
      RapierCollider(
        shape: const SphereShape(radius: 0.5),
        material: const PhysicsMaterial(friction: 0.6, restitution: 0.1),
      ),
    );
    scene.add(ball);

    // Low fixed fulcrum, purely visual. Kept short and narrow so its top
    // sits below the plank's underside (no z-fighting with the plank).
    scene.add(
      Node(
        mesh: _boxMesh(
          vm.Vector3(1.0, 0.6, 0.8),
          vm.Vector4(0.40, 0.40, 0.46, 1),
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(sx, 0.3, sz)),
      ),
    );
  }

  // A curtain of hanging cloth-like banners: several adjacent vertical
  // strips, each a chain of slats hinged about the horizontal width axis
  // and anchored to the world at the top. Dash parts them as he runs
  // through; they swing back and settle (lightly damped, like the bridge).
  void _buildCurtain() {
    const cx = 0.0, cz = -6.0, topY = 3.0;
    const nStrips = 5, nSlats = 4;
    const stripW = 0.5, slatHalfY = 0.25, slatHalfZ = 0.03;
    const pitch = stripW + 0.04;
    final color = vm.Vector4(0.85, 0.33, 0.42, 1);

    // Decorative top rail the banners hang from.
    scene.add(
      Node(
        mesh: _boxMesh(
          vm.Vector3(nStrips * pitch + 0.3, 0.12, 0.2),
          vm.Vector4(0.40, 0.40, 0.46, 1),
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(cx, topY + 0.06, cz)),
      ),
    );

    final axis = vm.Vector3(1, 0, 0);
    for (var s = 0; s < nStrips; s++) {
      final x = cx + (s - (nStrips - 1) / 2) * pitch;
      Node? prev;
      for (var i = 0; i < nSlats; i++) {
        final y = topY - slatHalfY - i * (slatHalfY * 2);
        final node = Node(
          mesh: _boxMesh(
            vm.Vector3(stripW, slatHalfY * 2, slatHalfZ * 2),
            color,
          ),
          localTransform: vm.Matrix4.translation(vm.Vector3(x, y, cz)),
        );
        node.addComponent(
          RapierRigidBody(
            type: BodyType.dynamic_,
            // Light and fairly damped so the banners flutter and settle
            // quickly rather than swinging like heavy slabs.
            mass: 0.2,
            linearDamping: 0.9,
            angularDamping: 1.8,
          ),
        );
        node.addComponent(
          RapierCollider(
            shape: BoxShape(
              halfExtents: vm.Vector3(stripW / 2, slatHalfY, slatHalfZ),
            ),
            material: const PhysicsMaterial(friction: 0.6, restitution: 0.0),
          ),
        );
        scene.add(node);
        node.addComponent(
          i == 0
              ? RapierRevoluteJoint(
                  axis: axis,
                  localAnchorA: vm.Vector3(0, slatHalfY, 0),
                  localAnchorB: vm.Vector3(x, topY, cz),
                )
              : RapierRevoluteJoint(
                  otherNode: prev,
                  axis: axis,
                  localAnchorA: vm.Vector3(0, slatHalfY, 0),
                  localAnchorB: vm.Vector3(0, -slatHalfY, 0),
                ),
        );
        prev = node;
      }
    }
  }

  // A cluster of free-swinging rope columns: chains of beads linked by
  // spherical joints, anchored to the world at the top. Dash runs through
  // and they swing out of the way.
  void _buildRopes() {
    const topY = 3.0, nBeads = 7, spacing = 0.34, beadR = 0.16;
    const halfSpacing = spacing / 2;
    // Just behind the banner curtain (which is at z = -6), spread across
    // the same width so Dash hits the banners first, then the ropes.
    final anchors = <vm.Vector3>[
      for (final x in [-1.4, -0.7, 0.0, 0.7, 1.4]) vm.Vector3(x, topY, -7.6),
    ];
    // Shared geometry / material across every bead.
    final beadGeometry = SphereGeometry(radius: beadR);
    final beadMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.55, 0.50, 0.42, 1)
      ..roughnessFactor = 0.5
      ..metallicFactor = 0.0;

    for (final anchor in anchors) {
      Node? prev;
      for (var i = 0; i < nBeads; i++) {
        final y = topY - halfSpacing - i * spacing;
        final node = Node(
          mesh: Mesh(beadGeometry, beadMaterial),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(anchor.x, y, anchor.z),
          ),
        );
        node.addComponent(
          RapierRigidBody(
            type: BodyType.dynamic_,
            // Light and fairly damped: reacts readily to Dash but settles
            // quickly with small swings, like a lightweight dangling cord
            // rather than a heavy slow pendulum.
            mass: 0.1,
            linearDamping: 0.9,
            angularDamping: 1.8,
          ),
        );
        node.addComponent(
          RapierCollider(
            shape: const SphereShape(radius: beadR),
            material: const PhysicsMaterial(friction: 0.5, restitution: 0.05),
          ),
        );
        scene.add(node);
        node.addComponent(
          i == 0
              ? RapierSphericalJoint(
                  localAnchorA: vm.Vector3(0, halfSpacing, 0),
                  localAnchorB: anchor.clone(),
                )
              : RapierSphericalJoint(
                  otherNode: prev,
                  localAnchorA: vm.Vector3(0, halfSpacing, 0),
                  localAnchorB: vm.Vector3(0, -halfSpacing, 0),
                ),
        );
        prev = node;
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
        // Give Dash enough heft to shove the 1 kg stack boxes around and
        // topple them instead of treating them as immovable walls.
        mass: 3.0,
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
    _characterNode = node;
    scene.add(node);
  }

  void _reset() => _character.teleport(_spawn);

  // Drives the code-animated kinematic bodies (the lift and the spinner)
  // each frame before the scene updates, so their new poses are carried
  // into the physics step (and so they carry / shove Dash).
  void _driveKinematics(double dt) {
    final elevator = _elevatorNode;
    final elevatorBody = _elevatorBody;
    if (elevator != null && elevatorBody != null) {
      // Refresh the dwell while occupied; once empty, hold at the top until
      // it runs out so Dash can step off cleanly instead of being dropped.
      if (_elevatorOccupied) {
        _elevatorDwell = _elevatorDwellMax;
      } else if (_elevatorDwell > 0.0) {
        _elevatorDwell = math.max(0.0, _elevatorDwell - dt);
      }
      final goUp = _elevatorOccupied || _elevatorDwell > 0.0;
      final target = goUp ? _elevatorTopY : _elevatorBottomY;
      if ((target - _elevatorY).abs() > 1e-4) {
        // Moving: drive it as a kinematic body so it carries Dash.
        elevatorBody.type = BodyType.kinematic;
        final step = _elevatorLiftSpeed * dt;
        if ((target - _elevatorY).abs() <= step) {
          _elevatorY = target;
        } else {
          _elevatorY += target > _elevatorY ? step : -step;
        }
        elevator.localTransform = vm.Matrix4.translation(
          vm.Vector3(_elevatorX, _elevatorY, _elevatorZ),
        );
      } else {
        // Parked: switch to a fixed body. A stopped kinematic platform
        // pins a kinematic character standing on it (the controller's
        // kinematic-platform friction cancels his input); a fixed body
        // does not, so Dash can walk off freely.
        elevatorBody.type = BodyType.fixed;
      }
    }

    final spinner = _spinnerNode;
    if (spinner != null) {
      _spinnerAngle += _spinnerSpeed * dt;
      spinner.localTransform = vm.Matrix4.compose(
        _spinnerCenter,
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _spinnerAngle),
        vm.Vector3.all(1.0),
      );
    }
  }

  // --- Build ----------------------------------------------------------------

  static const double _dragYawPerPixel = 0.006;
  static const double _dragPitchPerPixel = 0.005;
  static const double _keyYawRate = 2.2;
  static const double _keyPitchRate = 1.6;

  // Advances the camera, physics, and trigger easing each frame. SceneView
  // supplies the frame delta; clamp it so a long first frame (or a tab
  // regaining focus) does not snap the camera or take a huge physics step.
  void _onTick(Duration elapsed, double deltaSeconds) {
    final dt = deltaSeconds.clamp(0.0, 0.05);

    // Orbit the camera from a drag (pixels) and held arrow keys (rate).
    final drag = _input.lookDelta.clone();
    _input.lookDelta.setZero();
    _camera.orbit(
      drag.x * _dragYawPerPixel + _input.lookRate.x * _keyYawRate * dt,
      drag.y * _dragPitchPerPixel - _input.lookRate.y * _keyPitchRate * dt,
    );

    // Advance physics + per-frame component updates with the ticker delta,
    // then follow the character's now-current interpolated pose.
    _driveKinematics(dt);
    scene.update(dt);
    _camera.follow(_character.footPosition, dt);

    // Ease the glow / vignette toward whether Dash is inside the trigger,
    // and push the eased color onto the box material.
    final target = _inTrigger ? 1.0 : 0.0;
    final k = 1.0 - math.exp(-6.0 * dt);
    _triggerGlow += (target - _triggerGlow) * k;
    _vignette += (target - _vignette) * k;
    _vignetteListenable.value = _vignette;
    final glow = _triggerGlow;
    _triggerMaterial
      ..baseColorFactor = _lerpV4(
        ExamplePhysicsState._triggerIdleColor,
        ExamplePhysicsState._triggerActiveColor,
        glow,
      )
      ..emissiveFactor = _lerpV4(
        ExamplePhysicsState._triggerIdleEmissive,
        ExamplePhysicsState._triggerActiveEmissive,
        glow,
      );

    exampleSettings.applyTo(scene);
  }

  @override
  Widget build(BuildContext context) {
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
        // The trigger vignette, composited on top of the rendered scene.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _VignettePainter(_vignetteListenable)),
          ),
        ),
        // Below the picker so the character remains visible in the scene
        // center, with no overlap with system chrome.
        ExampleOverlay.topCenterAction(
          child: _PhysicsHeaderActions(onReset: () => setState(_reset)),
        ),
      ],
    );
  }
}

vm.Vector4 _lerpV4(vm.Vector4 a, vm.Vector4 b, double t) => vm.Vector4(
  a.x + (b.x - a.x) * t,
  a.y + (b.y - a.y) * t,
  a.z + (b.z - a.z) * t,
  a.w + (b.w - a.w) * t,
);

/// Darkens the edges of the frame, fading in with the listenable value (0..1).
class _VignettePainter extends CustomPainter {
  _VignettePainter(this.t) : super(repaint: t);

  final ValueListenable<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final amount = t.value;
    if (amount <= 0.001) return;
    final rect = Offset.zero & size;
    final maxAlpha = (0.72 * amount).clamp(0.0, 1.0);
    final shader = RadialGradient(
      center: Alignment.center,
      radius: 0.9,
      colors: [const Color(0x00000000), Color.fromRGBO(0, 0, 0, maxAlpha)],
      stops: const [0.5, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _VignettePainter oldDelegate) => true;
}

class _PhysicsHeaderActions extends StatelessWidget {
  const _PhysicsHeaderActions({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ExampleActionHint(message: 'Move: WASD/arrows  ·  Jump: Space'),
        const SizedBox(width: 8),
        ExampleActionButton(
          tooltip: 'Respawn character',
          onPressed: onReset,
          icon: Icons.restart_alt,
        ),
      ],
    );
  }
}
