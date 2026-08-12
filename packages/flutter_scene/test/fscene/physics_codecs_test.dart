// Covers the physics component codecs: backend registry resolution, per-codec
// delta round-trips (all defaults serialize to an empty bag), every collider
// shape variant including payload-backed bulk data, joint configuration
// including the generic axis table and node references, and the character
// controller's constructor-only flow. GPU-free throughout; components are
// created but never mounted (mounting happens on scene attach).

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/builtin_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/physics_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/physics/character_controller.dart';
import 'package:flutter_scene/src/physics/collider.dart';
import 'package:flutter_scene/src/physics/joint.dart';
import 'package:flutter_scene/src/physics/physics_world.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/physics.dart' as sim;
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

// Serializes [component] through [codec] into [document] and realizes the
// spec back, the codec-level round trip.
T _roundTrip<T extends Component>(
  ComponentCodec codec,
  Component component, {
  SceneDocument? document,
}) {
  final doc = document ?? SceneDocument();
  final spec = codec.serialize(component, SerializeContext(doc));
  expect(spec, isNotNull);
  final realized = codec.realize(spec!, RealizeContext(doc));
  expect(realized, isA<T>());
  return realized as T;
}

Map<String, PropertyValue> _serialized(
  ComponentCodec codec,
  Component component, {
  SceneDocument? document,
}) {
  final spec = codec.serialize(
    component,
    SerializeContext(document ?? SceneDocument()),
  );
  expect(spec, isNotNull);
  return spec!.properties;
}

void main() {
  group('physics backend registry', () {
    test('basic is preregistered', () {
      final factory = physicsBackendFactory('basic');
      expect(factory, isNotNull);
      final simulation = factory!();
      expect(simulation, isA<sim.BasicSimulation>());
      simulation.dispose();
    });

    test('registerPhysicsBackend adds a resolvable factory', () {
      registerPhysicsBackend('test-registry-probe', sim.BasicSimulation.new);
      expect(physicsBackendFactory('test-registry-probe'), isNotNull);
      expect(physicsBackendFactory('never-registered'), isNull);
    });
  });

  group('PhysicsWorldCodec', () {
    final codec = PhysicsWorldCodec();

    test('an empty spec realizes the basic backend with defaults', () {
      final world =
          codec.realize(
                ComponentSpec('physicsWorld'),
                RealizeContext(SceneDocument()),
              )
              as PhysicsWorld;
      expect(world.simulation, isA<sim.BasicSimulation>());
      expect(world.gravity, Vector3(0, -9.81, 0));
      expect(world.fixedTimestep, closeTo(1 / 60, 1e-12));
      expect(world.maxSubsteps, 8);
    });

    test('all defaults serialize to an empty bag', () {
      final world = codec.realize(
        ComponentSpec('physicsWorld'),
        RealizeContext(SceneDocument()),
      )!;
      expect(_serialized(codec, world), isEmpty);
    });

    test('configured values round trip', () {
      final spec = ComponentSpec(
        'physicsWorld',
        properties: {
          'gravity': Vec3Value(Vector3(0, -1.5, 0)),
          'fixedTimestep': const DoubleValue(1 / 30),
          'maxSubsteps': const IntValue(4),
        },
      );
      final world =
          codec.realize(spec, RealizeContext(SceneDocument())) as PhysicsWorld;
      expect(world.gravity, Vector3(0, -1.5, 0));
      expect(world.fixedTimestep, closeTo(1 / 30, 1e-12));
      expect(world.maxSubsteps, 4);

      final props = _serialized(codec, world);
      expect(
        props.keys,
        unorderedEquals(['gravity', 'fixedTimestep', 'maxSubsteps']),
      );
      expect(
        (props['fixedTimestep'] as DoubleValue).value,
        closeTo(1 / 30, 1e-12),
      );
    });

    test('a non-positive fixedTimestep is ignored', () {
      final spec = ComponentSpec(
        'physicsWorld',
        properties: {'fixedTimestep': const DoubleValue(0)},
      );
      final world =
          codec.realize(spec, RealizeContext(SceneDocument())) as PhysicsWorld;
      expect(world.fixedTimestep, closeTo(1 / 60, 1e-12));
    });

    test('an unknown backend skips the component', () {
      final spec = ComponentSpec(
        'physicsWorld',
        properties: {'backend': const StringValue('not-a-backend')},
      );
      expect(codec.realize(spec, RealizeContext(SceneDocument())), isNull);
    });

    test('serialize records the registry id, not the backend name', () {
      registerPhysicsBackend('test-alias', sim.BasicSimulation.new);
      final spec = ComponentSpec(
        'physicsWorld',
        properties: {'backend': const StringValue('test-alias')},
      );
      final world = codec.realize(spec, RealizeContext(SceneDocument()))!;
      final props = _serialized(codec, world);
      // 'test-alias' differs from BasicSimulation's backendName ('basic') and
      // from the schema default, so it must persist.
      expect((props['backend'] as StringValue).value, 'test-alias');
    });

    test('a hand-built world serializes its backend name', () {
      final world = PhysicsWorld(sim.BasicSimulation());
      // 'basic' equals the schema default, so it is omitted.
      expect(_serialized(codec, world).containsKey('backend'), isFalse);
    });
  });

  group('RigidBodyCodec', () {
    final codec = RigidBodyCodec();

    test('all defaults serialize to an empty bag', () {
      expect(_serialized(codec, RigidBody()), isEmpty);
    });

    test('body types serialize without the trailing underscore', () {
      expect(
        (_serialized(codec, RigidBody(type: sim.BodyType.fixed))['type']
                as StringValue)
            .value,
        'fixed',
      );
      expect(
        (_serialized(codec, RigidBody(type: sim.BodyType.kinematic))['type']
                as StringValue)
            .value,
        'kinematic',
      );
      // dynamic is the default and is omitted; prove the name mapping through
      // a realize instead.
      final body = codec.realize(
        ComponentSpec(
          'rigidBody',
          properties: {'type': const StringValue('dynamic')},
        ),
        RealizeContext(SceneDocument()),
      );
      expect((body as RigidBody).type, sim.BodyType.dynamic_);
    });

    test('a full configuration round trips', () {
      final body = _roundTrip<RigidBody>(
        codec,
        RigidBody(
          type: sim.BodyType.kinematic,
          mass: 2.5,
          linearDamping: 0.25,
          angularDamping: 0.5,
          useGravity: false,
          ccdEnabled: true,
          linearAxisLocks: Vector3(1, 0, 1),
          angularAxisLocks: Vector3(0, 1, 0),
        ),
      );
      expect(body.type, sim.BodyType.kinematic);
      expect(body.mass, 2.5);
      expect(body.linearDamping, 0.25);
      expect(body.angularDamping, 0.5);
      expect(body.useGravity, isFalse);
      expect(body.ccdEnabled, isTrue);
      expect(body.linearAxisLocks, Vector3(1, 0, 1));
      expect(body.angularAxisLocks, Vector3(0, 1, 0));
    });

    test('an absent mass stays null (backend-derived)', () {
      final body = _roundTrip<RigidBody>(codec, RigidBody());
      expect(body.mass, isNull);
      expect(_serialized(codec, RigidBody()).containsKey('mass'), isFalse);
    });

    test('velocities are not serialized', () {
      final body = RigidBody(
        linearVelocity: Vector3(1, 2, 3),
        angularVelocity: Vector3(4, 5, 6),
      );
      expect(_serialized(codec, body), isEmpty);
    });
  });

  group('ColliderCodec shapes', () {
    final codec = ColliderCodec();

    Collider roundTripShape(sim.Shape shape, {SceneDocument? document}) =>
        _roundTrip<Collider>(codec, Collider(shape: shape), document: document);

    test('the default box serializes to an empty bag', () {
      final collider = Collider(
        shape: sim.BoxShape(halfExtents: Vector3.all(0.5)),
      );
      expect(_serialized(codec, collider), isEmpty);
    });

    test('sphere', () {
      final shape =
          roundTripShape(const sim.SphereShape(radius: 1.25)).shape
              as sim.SphereShape;
      expect(shape.radius, 1.25);
    });

    test('box', () {
      final shape =
          roundTripShape(sim.BoxShape(halfExtents: Vector3(1, 2, 3))).shape
              as sim.BoxShape;
      expect(shape.halfExtents, Vector3(1, 2, 3));
    });

    test('capsule', () {
      final shape =
          roundTripShape(
                const sim.CapsuleShape(radius: 0.3, halfHeight: 0.9),
              ).shape
              as sim.CapsuleShape;
      expect(shape.radius, 0.3);
      expect(shape.halfHeight, 0.9);
    });

    test('cylinder', () {
      final shape =
          roundTripShape(
                const sim.CylinderShape(radius: 0.4, halfHeight: 1.1),
              ).shape
              as sim.CylinderShape;
      expect(shape.radius, 0.4);
      expect(shape.halfHeight, 1.1);
    });

    test('convex hull points survive byte for byte', () {
      final points = Float32List.fromList([
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0.25,
        0.5,
        0.75,
      ]);
      final doc = SceneDocument();
      final shape =
          roundTripShape(
                sim.ConvexHullShape(points: points),
                document: doc,
              ).shape
              as sim.ConvexHullShape;
      expect(shape.points, orderedEquals(points));
      expect(doc.payloads, isNotEmpty);
    });

    test('triangle mesh vertices and indices survive byte for byte', () {
      final vertices = Float32List.fromList([
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
      ]);
      final indices = Uint32List.fromList([0, 1, 2, 2, 1, 3]);
      final shape =
          roundTripShape(
                sim.TriMeshShape(vertices: vertices, indices: indices),
              ).shape
              as sim.TriMeshShape;
      expect(shape.vertices, orderedEquals(vertices));
      expect(shape.indices, orderedEquals(indices));
    });

    test('heightfield samples survive byte for byte', () {
      final heights = Float32List.fromList([0, 0.5, 1, 0.25, 0.75, 0.125]);
      final shape =
          roundTripShape(
                sim.HeightFieldShape(
                  width: 3,
                  depth: 2,
                  heights: heights,
                  scale: Vector3(2, 1, 2),
                ),
              ).shape
              as sim.HeightFieldShape;
      expect(shape.width, 3);
      expect(shape.depth, 2);
      expect(shape.heights, orderedEquals(heights));
      expect(shape.scale, Vector3(2, 1, 2));
    });

    test('compound children keep their shapes and local poses', () {
      final pose = Matrix4.translationValues(0, 1.5, 0);
      final shape =
          roundTripShape(
                sim.CompoundShape(
                  children: [
                    sim.CompoundChild(
                      shape: sim.BoxShape(halfExtents: Vector3.all(0.5)),
                      localPose: Matrix4.identity(),
                    ),
                    sim.CompoundChild(
                      shape: const sim.SphereShape(radius: 0.5),
                      localPose: pose,
                    ),
                  ],
                ),
              ).shape
              as sim.CompoundShape;
      expect(shape.children, hasLength(2));
      expect(shape.children[0].shape, isA<sim.BoxShape>());
      expect(shape.children[1].shape, isA<sim.SphereShape>());
      expect(shape.children[1].localPose, pose);
    });

    test('a malformed shape falls back to the default box', () {
      final collider = codec.realize(
        ComponentSpec(
          'collider',
          properties: {
            'shape': MapValue({'kind': const StringValue('dodecahedron')}),
          },
        ),
        RealizeContext(SceneDocument()),
      );
      final shape = (collider as Collider).shape as sim.BoxShape;
      expect(shape.halfExtents, Vector3.all(0.5));
    });

    test('payload-backed shapes survive an fsceneb round trip', () {
      final vertices = Float32List.fromList([0, 0, 0, 2, 0, 0, 0, 2, 0]);
      final indices = Uint32List.fromList([0, 1, 2]);
      final doc = SceneDocument();
      final spec = codec.serialize(
        Collider(
          shape: sim.TriMeshShape(vertices: vertices, indices: indices),
        ),
        SerializeContext(doc),
      )!;
      doc.createNode(name: 'ground', components: [spec], root: true);

      final read = readFsceneb(writeFsceneb(doc));
      final readSpec = read.rootNodes.single.components.single;
      final collider =
          codec.realize(readSpec, RealizeContext(read)) as Collider;
      final shape = collider.shape as sim.TriMeshShape;
      expect(shape.vertices, orderedEquals(vertices));
      expect(shape.indices, orderedEquals(indices));
    });
  });

  group('ColliderCodec configuration', () {
    final codec = ColliderCodec();

    test('material round trips', () {
      final collider = _roundTrip<Collider>(
        codec,
        Collider(
          shape: const sim.SphereShape(radius: 1),
          material: const sim.PhysicsMaterial(
            friction: 0.9,
            restitution: 0.4,
            density: 2.0,
            frictionCombine: sim.CombineRule.min,
            restitutionCombine: sim.CombineRule.max,
          ),
        ),
      );
      final material = collider.material;
      expect(material.friction, 0.9);
      expect(material.restitution, 0.4);
      expect(material.density, 2.0);
      expect(material.frictionCombine, sim.CombineRule.min);
      expect(material.restitutionCombine, sim.CombineRule.max);
    });

    test('layers, mask, trigger, and local pose round trip', () {
      final pose = Matrix4.translationValues(1, 2, 3);
      final collider = _roundTrip<Collider>(
        codec,
        Collider(
          shape: const sim.SphereShape(radius: 1),
          collisionLayer: 0x0000000F,
          collisionMask: 0x00FF00FF,
          isTrigger: true,
          localPose: pose,
        ),
      );
      expect(collider.collisionLayer, 0x0000000F);
      expect(collider.collisionMask, 0x00FF00FF);
      expect(collider.isTrigger, isTrue);
      expect(collider.localPose, pose);
    });
  });

  group('joint codecs', () {
    test('fixed joint defaults serialize to an empty bag', () {
      expect(_serialized(FixedJointCodec(), FixedJoint()), isEmpty);
    });

    test('fixed joint anchors and collisions round trip', () {
      final joint = _roundTrip<FixedJoint>(
        FixedJointCodec(),
        FixedJoint(
          localAnchorA: Vector3(0, 1, 0),
          localAnchorB: Vector3(0, -1, 0),
          collisionsEnabled: true,
        ),
      );
      expect(joint.localAnchorA, Vector3(0, 1, 0));
      expect(joint.localAnchorB, Vector3(0, -1, 0));
      expect(joint.collisionsEnabled, isTrue);
      expect(joint.otherNode, isNull);
    });

    test('spherical joint anchors round trip', () {
      final joint = _roundTrip<SphericalJoint>(
        SphericalJointCodec(),
        SphericalJoint(
          localAnchorA: Vector3(1, 0, 0),
          localAnchorB: Vector3(-1, 0, 0),
        ),
      );
      expect(joint.localAnchorA, Vector3(1, 0, 0));
      expect(joint.localAnchorB, Vector3(-1, 0, 0));
    });

    test('revolute joint limits and motor round trip', () {
      final joint = _roundTrip<RevoluteJoint>(
        RevoluteJointCodec(),
        RevoluteJoint(
          axis: Vector3(0, 0, 1),
          localAnchorA: Vector3(0.5, 0, 0),
          lowerLimit: -pi / 2,
          upperLimit: pi / 2,
          motorTargetVelocity: 2.0,
          motorMaxForce: 40.0,
        ),
      );
      expect(joint.localAxisA, Vector3(0, 0, 1));
      expect(joint.localAxisB, Vector3(0, 0, 1));
      expect(joint.localAnchorA, Vector3(0.5, 0, 0));
      expect(joint.lowerLimit, closeTo(-pi / 2, 1e-12));
      expect(joint.upperLimit, closeTo(pi / 2, 1e-12));
      expect(joint.motorTargetVelocity, 2.0);
      expect(joint.motorMaxForce, 40.0);
    });

    test('revolute joint absent limits stay null', () {
      final joint = _roundTrip<RevoluteJoint>(
        RevoluteJointCodec(),
        RevoluteJoint(axis: Vector3(0, 1, 0)),
      );
      expect(joint.lowerLimit, isNull);
      expect(joint.upperLimit, isNull);
      expect(joint.motorTargetVelocity, isNull);
      expect(joint.motorMaxForce, isNull);
    });

    test('prismatic joint limits round trip', () {
      final joint = _roundTrip<PrismaticJoint>(
        PrismaticJointCodec(),
        PrismaticJoint(
          axis: Vector3(0, 1, 0),
          lowerLimit: 0,
          upperLimit: 2.5,
          motorTargetVelocity: -1.0,
        ),
      );
      expect(joint.localAxisA, Vector3(0, 1, 0));
      expect(joint.lowerLimit, 0);
      expect(joint.upperLimit, 2.5);
      expect(joint.motorTargetVelocity, -1.0);
      expect(joint.motorMaxForce, isNull);
    });

    test('generic joint defaults serialize to an empty bag', () {
      expect(_serialized(GenericJointCodec(), GenericJoint()), isEmpty);
    });

    test('generic joint axis table round trips', () {
      final basis = Quaternion.axisAngle(Vector3(0, 1, 0), 0.5);
      final joint = _roundTrip<GenericJoint>(
        GenericJointCodec(),
        GenericJoint(
          localAnchorA: Vector3(0, 0.5, 0),
          localBasisA: basis,
          axes: {
            sim.JointAxis.linearY: sim.JointAxisConfig.limited(
              -1,
              1,
              motor: const sim.JointMotor(
                targetPosition: 0.5,
                stiffness: 100,
                damping: 10,
                maxForce: 500,
                model: sim.JointMotorModel.force,
              ),
            ),
            sim.JointAxis.angularX: const sim.JointAxisConfig.locked(),
          },
        ),
      );
      expect(joint.localAnchorA, Vector3(0, 0.5, 0));
      expect(joint.localBasisA.x, closeTo(basis.x, 1e-12));
      expect(joint.localBasisA.w, closeTo(basis.w, 1e-12));

      final linearY = joint.configForAxis(sim.JointAxis.linearY);
      expect(linearY.motion, sim.JointAxisMotion.limited);
      expect(linearY.lowerLimit, -1);
      expect(linearY.upperLimit, 1);
      final motor = linearY.motor!;
      expect(motor.targetPosition, 0.5);
      expect(motor.stiffness, 100);
      expect(motor.damping, 10);
      expect(motor.maxForce, 500);
      expect(motor.model, sim.JointMotorModel.force);

      expect(
        joint.configForAxis(sim.JointAxis.angularX).motion,
        sim.JointAxisMotion.locked,
      );
      expect(
        joint.configForAxis(sim.JointAxis.linearX).motion,
        sim.JointAxisMotion.free,
      );
    });

    test('an infinite motor maxForce round trips through absence', () {
      final joint = _roundTrip<GenericJoint>(
        GenericJointCodec(),
        GenericJoint(
          axes: {
            sim.JointAxis.angularZ: const sim.JointAxisConfig.free(
              motor: sim.JointMotor(targetVelocity: 3),
            ),
          },
        ),
      );
      final motor = joint.configForAxis(sim.JointAxis.angularZ).motor!;
      expect(motor.targetVelocity, 3);
      expect(motor.maxForce, double.infinity);
    });
  });

  group('joint otherNode through a realized scene', () {
    SceneDocument jointScene({required bool anchorToWorld}) {
      final doc = SceneDocument();
      final arena = doc.createNode(
        name: 'arena',
        root: true,
        components: [ComponentSpec('physicsWorld')],
      );
      final anchor = doc.createNode(
        name: 'anchor',
        components: [ComponentSpec('rigidBody')],
      );
      final swinger = doc.createNode(
        name: 'swinger',
        components: [
          ComponentSpec('rigidBody'),
          ComponentSpec(
            'fixedJoint',
            properties: {
              if (!anchorToWorld) 'otherNode': NodeRefValue(anchor.id),
            },
          ),
        ],
      );
      arena.children.addAll([anchor.id, swinger.id]);
      return doc;
    }

    test('a node reference resolves to the realized node', () {
      final root = realizeScene(jointScene(anchorToWorld: false));
      final arena = root.children.single;
      final swinger = arena.getChildByName('swinger')!;
      final anchor = arena.getChildByName('anchor')!;
      final joint = swinger.getComponent<FixedJoint>()!;
      expect(identical(joint.otherNode, anchor), isTrue);
      expect(swinger.getComponent<RigidBody>(), isNotNull);
      expect(arena.getComponent<PhysicsWorld>(), isNotNull);
    });

    test('an absent reference stays a world anchor', () {
      final root = realizeScene(jointScene(anchorToWorld: true));
      final joint = root.children.single
          .getChildByName('swinger')!
          .getComponent<FixedJoint>()!;
      expect(joint.otherNode, isNull);
    });

    test('serializeScene recovers the node reference by id', () {
      final source = jointScene(anchorToWorld: false);
      final root = realizeScene(source);
      final saved = serializeScene(root);

      NodeSpec byName(String name) =>
          saved.nodes.values.singleWhere((n) => n.name == name);
      final jointSpec = byName(
        'swinger',
      ).components.singleWhere((c) => c.type == 'fixedJoint');
      final ref = jointSpec.properties['otherNode'];
      expect(ref, isA<NodeRefValue>());
      expect((ref as NodeRefValue).id, byName('anchor').id);
    });

    test('a world-anchored joint serializes without otherNode', () {
      final root = realizeScene(jointScene(anchorToWorld: true));
      final saved = serializeScene(root);
      final jointSpec = saved.nodes.values
          .singleWhere((n) => n.name == 'swinger')
          .components
          .singleWhere((c) => c.type == 'fixedJoint');
      expect(jointSpec.properties.containsKey('otherNode'), isFalse);
    });
  });

  group('KinematicCharacterControllerCodec', () {
    final codec = KinematicCharacterControllerCodec();

    test('constructor defaults serialize to just the snap distance', () {
      // snapToGround has no schema default (absence means disabled), so the
      // constructor's 0.1 always persists; everything else is delta-omitted.
      final props = _serialized(codec, KinematicCharacterController());
      expect(props.keys, ['snapToGround']);
      expect((props['snapToGround'] as DoubleValue).value, 0.1);
    });

    test('a full configuration round trips', () {
      final controller = _roundTrip<KinematicCharacterController>(
        codec,
        KinematicCharacterController(
          up: Vector3(0, 0, 1),
          offset: 0.05,
          slide: false,
          maxSlopeClimbAngle: pi / 3,
          minSlopeSlideAngle: pi / 6,
          snapToGround: 0.25,
          autostep: true,
          autostepMaxHeight: 0.4,
          autostepMinWidth: 0.2,
          autostepIncludeDynamicBodies: false,
          mass: 70,
        ),
      );
      expect(controller.up, Vector3(0, 0, 1));
      expect(controller.offset, 0.05);
      expect(controller.slide, isFalse);
      expect(controller.maxSlopeClimbAngle, closeTo(pi / 3, 1e-12));
      expect(controller.minSlopeSlideAngle, closeTo(pi / 6, 1e-12));
      expect(controller.snapToGround, 0.25);
      expect(controller.autostep, isTrue);
      expect(controller.autostepMaxHeight, 0.4);
      expect(controller.autostepMinWidth, 0.2);
      expect(controller.autostepIncludeDynamicBodies, isFalse);
      expect(controller.mass, 70);
    });

    test('a disabled snapToGround round trips through absence', () {
      final controller = _roundTrip<KinematicCharacterController>(
        codec,
        KinematicCharacterController(snapToGround: null),
      );
      expect(controller.snapToGround, isNull);
    });
  });

  group('registration', () {
    test('the builtin registration includes the physics codecs', () {
      final registry = FsceneComponentRegistry();
      registerBuiltinComponentCodecs(registry);
      for (final type in [
        'physicsWorld',
        'rigidBody',
        'collider',
        'fixedJoint',
        'sphericalJoint',
        'revoluteJoint',
        'prismaticJoint',
        'genericJoint',
        'characterController',
      ]) {
        expect(registry.codecFor(type), isNotNull, reason: type);
      }
    });

    test('registerPhysicsComponentCodecs targets a passed registry', () {
      final registry = FsceneComponentRegistry();
      registerPhysicsComponentCodecs(registry);
      expect(registry.codecFor('collider'), isNotNull);
      expect(registry.codecFor('mesh'), isNull);
    });
  });
}
