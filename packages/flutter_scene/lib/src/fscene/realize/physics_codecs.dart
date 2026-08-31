/// Codecs for the physics components (world, rigid body, collider, joints,
/// character controller), plus the backend registry that lets a document name
/// the simulation backend its world runs on.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/character_controller.dart';
import 'package:flutter_scene/src/physics/collider.dart';
import 'package:flutter_scene/src/physics/joint.dart';
import 'package:flutter_scene/src/physics/physics_world.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:scene/physics.dart' as sim;
import 'package:scene/scene.dart';

// --- Backend registry ---

/// Creates a fresh simulation backend for a realized [PhysicsWorld].
/// {@category Physics}
typedef PhysicsBackendFactory = sim.PhysicsSimulation Function();

final Map<String, PhysicsBackendFactory> _physicsBackends = {
  'basic': sim.BasicSimulation.new,
};

/// Registers [factory] under backend [id], replacing any existing entry.
///
/// A document's `physicsWorld` component names its backend by id; backend
/// packages register their factory at app startup (`registerPhysicsBackend(
/// 'rapier3d', RapierWorld.new)`) so documents authored against them realize.
/// The pure-Dart `basic` backend is preregistered.
/// {@category Physics}
void registerPhysicsBackend(String id, PhysicsBackendFactory factory) {
  _physicsBackends[id] = factory;
}

/// The registered factory for backend [id], or null.
/// {@category Physics}
PhysicsBackendFactory? physicsBackendFactory(String id) => _physicsBackends[id];

// --- Small tolerant readers over MapValue maps ---

T _enum<T extends Enum>(
  Map<String, PropertyValue> p,
  String key,
  List<T> values,
  T fallback,
) {
  final raw = p[key];
  if (raw is! StringValue) return fallback;
  return values.asNameMap()[raw.value] ?? fallback;
}

// --- Bulk payloads (hull points, mesh buffers, heightfield samples) ---

StringValue _addFloatsPayload(SceneDocument document, Float32List floats) {
  final bytes = floats.buffer.asUint8List(
    floats.offsetInBytes,
    floats.lengthInBytes,
  );
  final payload = document.addPayload(
    PayloadSpec(
      document.newId(),
      encoding: PayloadEncoding.floats,
      length: bytes.length,
      bytes: bytes,
    ),
  );
  return StringValue(payload.id.toToken());
}

StringValue _addIndicesPayload(SceneDocument document, Uint32List indices) {
  final bytes = indices.buffer.asUint8List(
    indices.offsetInBytes,
    indices.lengthInBytes,
  );
  final payload = document.addPayload(
    PayloadSpec(
      document.newId(),
      encoding: PayloadEncoding.bytes,
      format: 'uint32',
      length: bytes.length,
      bytes: bytes,
    ),
  );
  return StringValue(payload.id.toToken());
}

Uint8List? _payloadBytes(SceneDocument document, PropertyValue? token) {
  if (token is! StringValue) return null;
  final LocalId id;
  try {
    id = LocalId.parse(token.value);
  } on FormatException {
    return null;
  }
  return document.payload(id)?.bytes;
}

Float32List? _readFloatsPayload(SceneDocument document, PropertyValue? token) {
  final bytes = _payloadBytes(document, token);
  if (bytes == null) return null;
  // Copy to guarantee 4-byte alignment for the typed view.
  final copy = Uint8List.fromList(bytes);
  return copy.buffer.asFloat32List(0, copy.length ~/ 4);
}

Uint32List? _readIndicesPayload(SceneDocument document, PropertyValue? token) {
  final bytes = _payloadBytes(document, token);
  if (bytes == null) return null;
  final copy = Uint8List.fromList(bytes);
  return copy.buffer.asUint32List(0, copy.length ~/ 4);
}

// --- Shape <-> property value ---

sim.Shape _defaultColliderShape() =>
    sim.BoxShape(halfExtents: Vector3.all(0.5));

MapValue _defaultShapeValue() => MapValue({
  'kind': const StringValue('box'),
  'halfExtents': Vec3Value(Vector3.all(0.5)),
});

/// Encodes [shape] as a tagged map keyed on its variant, writing bulk data
/// (hull points, mesh buffers, heightfield samples) into [document] payloads
/// referenced by id token.
MapValue encodePhysicsShape(sim.Shape shape, SceneDocument document) {
  switch (shape) {
    case sim.SphereShape():
      return MapValue({
        'kind': const StringValue('sphere'),
        'radius': DoubleValue(shape.radius),
      });
    case sim.BoxShape():
      return MapValue({
        'kind': const StringValue('box'),
        'halfExtents': Vec3Value(shape.halfExtents.clone()),
      });
    case sim.CapsuleShape():
      return MapValue({
        'kind': const StringValue('capsule'),
        'radius': DoubleValue(shape.radius),
        'halfHeight': DoubleValue(shape.halfHeight),
      });
    case sim.CylinderShape():
      return MapValue({
        'kind': const StringValue('cylinder'),
        'radius': DoubleValue(shape.radius),
        'halfHeight': DoubleValue(shape.halfHeight),
      });
    case sim.ConvexHullShape():
      return MapValue({
        'kind': const StringValue('convexHull'),
        'points': _addFloatsPayload(document, shape.points),
      });
    case sim.TriMeshShape():
      return MapValue({
        'kind': const StringValue('triMesh'),
        'vertices': _addFloatsPayload(document, shape.vertices),
        'indices': _addIndicesPayload(document, shape.indices),
      });
    case sim.HeightFieldShape():
      return MapValue({
        'kind': const StringValue('heightField'),
        'width': IntValue(shape.width),
        'depth': IntValue(shape.depth),
        'heights': _addFloatsPayload(document, shape.heights),
        'scale': Vec3Value(shape.scale.clone()),
      });
    case sim.CompoundShape():
      return MapValue({
        'kind': const StringValue('compound'),
        'children': ListValue([
          for (final child in shape.children)
            MapValue({
              'shape': encodePhysicsShape(child.shape, document),
              'localPose': Matrix4Value(child.localPose.clone()),
            }),
        ]),
      });
  }
}

/// Decodes a [sim.Shape] from [value], resolving payload references against
/// [document]. Returns null when the value is malformed or references a
/// missing payload.
sim.Shape? decodePhysicsShape(PropertyValue? value, SceneDocument document) {
  if (value is! MapValue) return null;
  final m = value.values;
  switch (readString(m, 'kind', '')) {
    case 'sphere':
      return sim.SphereShape(radius: readDouble(m, 'radius', 0.5));
    case 'box':
      return sim.BoxShape(
        halfExtents: readVec3(m, 'halfExtents', Vector3.all(0.5)),
      );
    case 'capsule':
      return sim.CapsuleShape(
        radius: readDouble(m, 'radius', 0.5),
        halfHeight: readDouble(m, 'halfHeight', 0.5),
      );
    case 'cylinder':
      return sim.CylinderShape(
        radius: readDouble(m, 'radius', 0.5),
        halfHeight: readDouble(m, 'halfHeight', 0.5),
      );
    case 'convexHull':
      final points = _readFloatsPayload(document, m['points']);
      return points == null ? null : sim.ConvexHullShape(points: points);
    case 'triMesh':
      final vertices = _readFloatsPayload(document, m['vertices']);
      final indices = _readIndicesPayload(document, m['indices']);
      if (vertices == null || indices == null) return null;
      return sim.TriMeshShape(vertices: vertices, indices: indices);
    case 'heightField':
      final heights = _readFloatsPayload(document, m['heights']);
      if (heights == null) return null;
      return sim.HeightFieldShape(
        width: readInt(m, 'width', 2),
        depth: readInt(m, 'depth', 2),
        heights: heights,
        scale: readVec3(m, 'scale', Vector3.all(1)),
      );
    case 'compound':
      final children = m['children'];
      if (children is! ListValue) return null;
      final decoded = <sim.CompoundChild>[];
      for (final entry in children.values) {
        if (entry is! MapValue) continue;
        final shape = decodePhysicsShape(entry.values['shape'], document);
        if (shape == null) continue;
        final pose = entry.values['localPose'];
        decoded.add(
          sim.CompoundChild(
            shape: shape,
            localPose: pose is Matrix4Value
                ? pose.value.clone()
                : Matrix4.identity(),
          ),
        );
      }
      return decoded.isEmpty ? null : sim.CompoundShape(children: decoded);
  }
  return null;
}

// --- PhysicsMaterial <-> property value ---

MapValue _encodePhysicsMaterial(sim.PhysicsMaterial material) => MapValue({
  'friction': DoubleValue(material.friction),
  'restitution': DoubleValue(material.restitution),
  'density': DoubleValue(material.density),
  'frictionCombine': StringValue(material.frictionCombine.name),
  'restitutionCombine': StringValue(material.restitutionCombine.name),
});

sim.PhysicsMaterial _decodePhysicsMaterial(PropertyValue? value) {
  if (value is! MapValue) return sim.PhysicsMaterial.defaultMaterial;
  final m = value.values;
  return sim.PhysicsMaterial(
    friction: readDouble(m, 'friction', 0.5),
    restitution: readDouble(m, 'restitution', 0.0),
    density: readDouble(m, 'density', 1.0),
    frictionCombine: _enum(
      m,
      'frictionCombine',
      sim.CombineRule.values,
      sim.CombineRule.average,
    ),
    restitutionCombine: _enum(
      m,
      'restitutionCombine',
      sim.CombineRule.values,
      sim.CombineRule.average,
    ),
  );
}

// --- Schema descriptors ---

ComponentPropertyDef _radiusDef(String doc) => ComponentPropertyDef(
  'radius',
  ComponentPropertyKind.number,
  defaultValue: const DoubleValue(0.5),
  doc: doc,
  constraints: const [Range.nonNegative()],
);

const ComponentPropertyDef _halfHeightDef = ComponentPropertyDef(
  'halfHeight',
  ComponentPropertyKind.number,
  defaultValue: DoubleValue(0.5),
  doc: 'Half length of the section along local Y.',
  constraints: [Range.nonNegative()],
);

// One shape union level. The compound variant nests the same set minus
// itself; runtime encode/decode recurse to any depth regardless.
// TODO(nested-compound): describe compound-in-compound in the schema once
// descriptors can reference themselves; the codec already round-trips it.
Map<String, List<ComponentPropertyDef>> _shapeVariants({
  required bool withCompound,
}) => {
  'sphere': [_radiusDef('Sphere radius.')],
  'box': [
    ComponentPropertyDef(
      'halfExtents',
      ComponentPropertyKind.vec3,
      defaultValue: Vec3Value(Vector3.all(0.5)),
      doc: 'Box half-size on each axis.',
    ),
  ],
  'capsule': [
    _radiusDef('Capsule radius, including the hemispherical caps.'),
    _halfHeightDef,
  ],
  'cylinder': [_radiusDef('Cylinder radius.'), _halfHeightDef],
  'convexHull': const [
    ComponentPropertyDef(
      'points',
      ComponentPropertyKind.string,
      doc: 'Payload id token of packed xyz hull points (float32).',
    ),
  ],
  'triMesh': const [
    ComponentPropertyDef(
      'vertices',
      ComponentPropertyKind.string,
      doc: 'Payload id token of packed xyz vertices (float32).',
    ),
    ComponentPropertyDef(
      'indices',
      ComponentPropertyKind.string,
      doc: 'Payload id token of triangle vertex indices (uint32).',
    ),
  ],
  'heightField': [
    const ComponentPropertyDef(
      'width',
      ComponentPropertyKind.integer,
      defaultValue: IntValue(2),
      doc: 'Sample columns.',
      constraints: [IntRange(2, null)],
    ),
    const ComponentPropertyDef(
      'depth',
      ComponentPropertyKind.integer,
      defaultValue: IntValue(2),
      doc: 'Sample rows.',
      constraints: [IntRange(2, null)],
    ),
    const ComponentPropertyDef(
      'heights',
      ComponentPropertyKind.string,
      doc: 'Payload id token of row-major height samples (float32).',
    ),
    ComponentPropertyDef(
      'scale',
      ComponentPropertyKind.vec3,
      defaultValue: Vec3Value(Vector3.all(1)),
      doc: 'World size per sample on X/Z, height multiplier on Y.',
    ),
  ],
  if (withCompound)
    'compound': [
      ComponentPropertyDef(
        'children',
        ComponentPropertyKind.list,
        doc: 'Child shapes, each positioned by its own local pose.',
        constraints: const [MinCount(1)],
        itemDef: ComponentPropertyDef(
          'child',
          ComponentPropertyKind.object,
          objectFields: [
            ComponentPropertyDef(
              'shape',
              ComponentPropertyKind.union,
              doc: 'The child shape.',
              unionVariants: _shapeVariants(withCompound: false),
            ),
            ComponentPropertyDef(
              'localPose',
              ComponentPropertyKind.matrix4,
              defaultValue: Matrix4Value(Matrix4.identity()),
              doc: 'Pose relative to the compound origin.',
            ),
          ],
        ),
      ),
    ],
};

final List<ComponentPropertyDef> _physicsMaterialFields = [
  const ComponentPropertyDef(
    'friction',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0.5),
    doc: 'Coulomb friction coefficient.',
    constraints: [Range.nonNegative(), SoftRange(0, 1)],
  ),
  const ComponentPropertyDef(
    'restitution',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0.0),
    doc: 'Bounciness; 0 inelastic, 1 preserves energy.',
    constraints: [Range(0, 1), SoftRange(0, 1)],
  ),
  const ComponentPropertyDef(
    'density',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(1.0),
    doc: 'Mass per unit volume for derived body mass.',
    constraints: [Range.nonNegative()],
  ),
  ComponentPropertyDef(
    'frictionCombine',
    ComponentPropertyKind.string,
    defaultValue: const StringValue('average'),
    doc: 'How the two contacting frictions merge.',
    options: [for (final rule in sim.CombineRule.values) rule.name],
  ),
  ComponentPropertyDef(
    'restitutionCombine',
    ComponentPropertyKind.string,
    defaultValue: const StringValue('average'),
    doc: 'How the two contacting restitutions merge.',
    options: [for (final rule in sim.CombineRule.values) rule.name],
  ),
];

// --- PhysicsWorld ---

/// Codec for [PhysicsWorld]. The `backend` id names the simulation through
/// the backend registry ([registerPhysicsBackend]); an unregistered backend
/// skips the component so the scene still loads, without physics.
class PhysicsWorldCodec extends DeclarativeComponentCodec<PhysicsWorld> {
  @override
  String get type => 'physicsWorld';

  @override
  String? get category => 'Physics';

  // The document backend id, stamped at realize so serialize writes the
  // registry key rather than the backend's self-reported name (the two can
  // differ). Hand-built worlds fall back to backendName.
  static final Expando<String> _backendId = Expando('physics world backend');

  @override
  List<ComponentField<PhysicsWorld>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'backend',
        ComponentPropertyKind.string,
        defaultValue: StringValue('basic'),
        doc: 'Registered id of the simulation backend this world runs on.',
      ),
      read: (c, _) => StringValue(_backendId[c] ?? c.backendName),
    ),
    ComponentField.vec3(
      'gravity',
      defaultValue: () => Vector3(0, -9.81, 0),
      doc: 'World-space acceleration applied to every dynamic body.',
      get: (c) => c.gravity,
      set: (c, v) => c.gravity = v,
    ),
    ComponentField.number(
      'fixedTimestep',
      defaultValue: 1.0 / 60.0,
      doc: 'Length of one physics step, in seconds.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.fixedTimestep,
      set: (c, v) {
        if (v > 0) c.fixedTimestep = v;
      },
    ),
    ComponentField.integer(
      'maxSubsteps',
      defaultValue: 8,
      doc: 'Maximum fixed steps consumed per frame before time is dropped.',
      constraints: const [IntRange(1, null)],
      get: (c) => c.maxSubsteps,
      set: (c, v) => c.maxSubsteps = v,
    ),
  ];

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final backend = spec.properties['backend'];
    final id = backend is StringValue ? backend.value : 'basic';
    if (physicsBackendFactory(id) == null) {
      debugPrint(
        'fscene: physicsWorld skipped (backend "$id" is not registered; '
        'call registerPhysicsBackend at startup)',
      );
      return null;
    }
    return super.realize(spec, context);
  }

  @override
  PhysicsWorld create(PropertyReader props) {
    final id = props.string('backend');
    final world = PhysicsWorld(physicsBackendFactory(id)!());
    _backendId[world] = id;
    return world;
  }
}

// --- RigidBody ---

const List<String> _bodyTypeNames = ['fixed', 'kinematic', 'dynamic'];

String _bodyTypeName(sim.BodyType type) => switch (type) {
  sim.BodyType.fixed => 'fixed',
  sim.BodyType.kinematic => 'kinematic',
  sim.BodyType.dynamic_ => 'dynamic',
};

sim.BodyType _bodyTypeFromName(String name) => switch (name) {
  'fixed' => sim.BodyType.fixed,
  'kinematic' => sim.BodyType.kinematic,
  _ => sim.BodyType.dynamic_,
};

/// Codec for [RigidBody]. Velocities are live simulation state and do not
/// persist.
// TODO(requires-sibling): the schema model has no sibling-requirement
// metadata yet; mount-order rules (collider after body, controller after
// collider, all under a physicsWorld ancestor) are enforced at mount only.
class RigidBodyCodec extends DeclarativeComponentCodec<RigidBody> {
  @override
  String get type => 'rigidBody';

  @override
  String? get category => 'Physics';

  @override
  List<ComponentField<RigidBody>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'type',
        ComponentPropertyKind.string,
        defaultValue: StringValue('dynamic'),
        doc: 'Simulation mode (fixed, kinematic, or dynamic).',
        options: _bodyTypeNames,
      ),
      read: (c, _) => StringValue(_bodyTypeName(c.type)),
      write: (c, v, _) {
        if (v is StringValue) c.type = _bodyTypeFromName(v.value);
      },
    ),
    // No default; absent means the backend derives mass from the colliders.
    ComponentField(
      const ComponentPropertyDef(
        'mass',
        ComponentPropertyKind.number,
        doc: 'Mass in kilograms; absent derives it from the colliders.',
        constraints: [Range.nonNegative()],
      ),
      read: (c, _) {
        final mass = c.mass;
        return mass == null ? null : DoubleValue(mass);
      },
      write: (c, v, _) {
        final mass = switch (v) {
          DoubleValue(:final value) => value,
          IntValue(:final value) => value.toDouble(),
          _ => null,
        };
        if (mass != null) c.mass = mass;
      },
    ),
    ComponentField.number(
      'linearDamping',
      defaultValue: 0.0,
      doc: 'Per-step linear velocity damping.',
      constraints: const [Range(0, 1), SoftRange(0, 1)],
      get: (c) => c.linearDamping,
      set: (c, v) => c.linearDamping = v,
    ),
    ComponentField.number(
      'angularDamping',
      defaultValue: 0.0,
      doc: 'Per-step angular velocity damping.',
      constraints: const [Range(0, 1), SoftRange(0, 1)],
      get: (c) => c.angularDamping,
      set: (c, v) => c.angularDamping = v,
    ),
    ComponentField.boolean(
      'useGravity',
      defaultValue: true,
      doc: 'Whether world gravity accelerates this body.',
      get: (c) => c.useGravity,
      set: (c, v) => c.useGravity = v,
    ),
    ComponentField.boolean(
      'ccdEnabled',
      defaultValue: false,
      doc: 'Continuous collision detection, for fast thin-wall contacts.',
      get: (c) => c.ccdEnabled,
      set: (c, v) => c.ccdEnabled = v,
    ),
    ComponentField.vec3(
      'linearAxisLocks',
      defaultValue: () => Vector3(1, 1, 1),
      doc: 'Per-axis linear motion factors, 1 free and 0 locked.',
      get: (c) => c.linearAxisLocks,
      set: (c, v) => c.linearAxisLocks = v,
    ),
    ComponentField.vec3(
      'angularAxisLocks',
      defaultValue: () => Vector3(1, 1, 1),
      doc: 'Per-axis angular motion factors, 1 free and 0 locked.',
      get: (c) => c.angularAxisLocks,
      set: (c, v) => c.angularAxisLocks = v,
    ),
  ];

  @override
  RigidBody create(PropertyReader props) => RigidBody();
}

// --- Collider ---

/// Codec for [Collider]. The shape is a tagged union; bulk shape data (hull
/// points, mesh buffers, heightfield samples) rides in document payloads.
// TODO(requires-sibling): a collider needs a RigidBody sibling added first
// (or none, for static geometry); no schema metadata declares that yet.
class ColliderCodec extends DeclarativeComponentCodec<Collider> {
  @override
  String get type => 'collider';

  @override
  String? get category => 'Physics';

  // Collision-shape green.
  static const _shapeColor = GizmoColor(0.45, 0.89, 0.45, 0.9);

  // TODO(gizmo-local-pose): the wires ignore the collider's localPose;
  // compose it into the primitive transform once specs can carry it.
  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'physics',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoWireSphere(
        radius: GizmoScalar.bind('shape.radius'),
        color: _shapeColor,
        when: GizmoCondition('shape.kind', 'sphere'),
      ),
      GizmoWireBox(
        halfExtentsBind: 'shape.halfExtents',
        color: _shapeColor,
        when: GizmoCondition('shape.kind', 'box'),
      ),
      GizmoWireCapsule(
        radius: GizmoScalar.bind('shape.radius'),
        halfHeight: GizmoScalar.bind('shape.halfHeight'),
        color: _shapeColor,
        when: GizmoCondition('shape.kind', 'capsule'),
      ),
      GizmoWireCylinder(
        radius: GizmoScalar.bind('shape.radius'),
        halfHeight: GizmoScalar.bind('shape.halfHeight'),
        color: _shapeColor,
        when: GizmoCondition('shape.kind', 'cylinder'),
      ),
      // Mesh-derived shapes have no declarative wireframe (code tier later);
      // an icon keeps them findable and clickable.
      GizmoIcon(when: GizmoCondition('shape.kind', 'convexHull')),
      GizmoIcon(when: GizmoCondition('shape.kind', 'triMesh')),
      GizmoIcon(when: GizmoCondition('shape.kind', 'heightField')),
      GizmoIcon(when: GizmoCondition('shape.kind', 'compound')),
    ]),
  );

  @override
  List<ComponentField<Collider>> get fields => [
    ComponentField(
      ComponentPropertyDef(
        'shape',
        ComponentPropertyKind.union,
        defaultValue: _defaultShapeValue(),
        doc: 'The collision volume.',
        unionVariants: _shapeVariants(withCompound: true),
      ),
      read: (c, context) => encodePhysicsShape(c.shape, context.document),
      write: (c, v, context) {
        final shape = decodePhysicsShape(v, context.document);
        if (shape != null) c.shape = shape;
      },
    ),
    ComponentField(
      ComponentPropertyDef(
        'material',
        ComponentPropertyKind.object,
        defaultValue: _encodePhysicsMaterial(
          sim.PhysicsMaterial.defaultMaterial,
        ),
        doc: 'Surface properties at contacts.',
        objectFields: _physicsMaterialFields,
      ),
      read: (c, _) => _encodePhysicsMaterial(c.material),
      write: (c, v, _) {
        if (v is MapValue) c.material = _decodePhysicsMaterial(v);
      },
    ),
    ComponentField.integer(
      'collisionLayer',
      defaultValue: 0xFFFFFFFF,
      doc: 'Bitmask identifying this collider\'s layer.',
      constraints: const [LayerMask32()],
      get: (c) => c.collisionLayer,
      set: (c, v) => c.collisionLayer = v,
    ),
    ComponentField.integer(
      'collisionMask',
      defaultValue: 0xFFFFFFFF,
      doc: 'Bitmask of layers this collider responds to.',
      constraints: const [LayerMask32()],
      get: (c) => c.collisionMask,
      set: (c, v) => c.collisionMask = v,
    ),
    ComponentField.boolean(
      'isTrigger',
      defaultValue: false,
      doc: 'Emit trigger events instead of contact response.',
      get: (c) => c.isTrigger,
      set: (c, v) => c.isTrigger = v,
    ),
    ComponentField(
      ComponentPropertyDef(
        'localPose',
        ComponentPropertyKind.matrix4,
        defaultValue: Matrix4Value(Matrix4.identity()),
        doc: 'Pose relative to the owning node.',
      ),
      read: (c, _) => Matrix4Value(c.localPose.clone()),
      write: (c, v, _) {
        if (v is Matrix4Value) c.localPose = v.value.clone();
      },
    ),
  ];

  @override
  Collider create(PropertyReader props) {
    final raw = props.value('shape');
    var shape = decodePhysicsShape(raw, props.context.document);
    if (shape == null && raw != null) {
      debugPrint('fscene: collider shape malformed; using the default box');
    }
    shape ??= _defaultColliderShape();
    return Collider(shape: shape);
  }
}

// --- Joints ---

Node? _resolveOtherNode(PropertyReader props) {
  final id = props.nodeId('otherNode');
  if (id == null) return null;
  final node = props.context.resolveNode?.call(id);
  if (node == null) {
    debugPrint(
      'fscene: joint otherNode $id did not resolve; anchoring to the world',
    );
  }
  return node;
}

ComponentField<C> _otherNodeField<C extends Joint>() => ComponentField(
  const ComponentPropertyDef(
    'otherNode',
    ComponentPropertyKind.nodeRef,
    doc:
        'Node whose body sits on the other side; absent anchors to the '
        'world.',
  ),
  read: (c, _) {
    final other = c.otherNode;
    if (other == null) return null;
    final id = nodeFsceneId(other);
    if (id == null) {
      debugPrint(
        'fscene: joint otherNode has no document id; it reloads as a world '
        'anchor',
      );
      return null;
    }
    return NodeRefValue(id);
  },
);

ComponentField<C> _collisionsEnabledField<C extends Joint>() =>
    ComponentField.boolean(
      'collisionsEnabled',
      defaultValue: false,
      doc: 'Whether the joined bodies still collide with each other.',
      get: (c) => c.collisionsEnabled,
      set: (c, v) => c.collisionsEnabled = v,
    );

ComponentField<C> _anchorField<C extends Joint>(
  String name, {
  required Vector3 Function(C component) get,
  required void Function(C component, Vector3 value) set,
}) => ComponentField.vec3(
  name,
  defaultValue: Vector3.zero,
  doc: 'Attachment point in that body\'s local space.',
  get: get,
  set: set,
);

ComponentField<C> _axisField<C extends Joint>(
  String name, {
  required Vector3 Function(C component) get,
  required void Function(C component, Vector3 value) set,
}) => ComponentField.vec3(
  name,
  defaultValue: () => Vector3(1, 0, 0),
  doc: 'Joint axis in that body\'s local space.',
  constraints: const [Normalized()],
  get: get,
  set: set,
);

// Nullable configuration (limits, motor targets); no default, so absence
// round-trips as null.
ComponentField<C> _optionalNumberField<C extends Component>(
  String name, {
  required double? Function(C component) get,
  required void Function(C component, double value) set,
  String? doc,
}) => ComponentField(
  ComponentPropertyDef(name, ComponentPropertyKind.number, doc: doc),
  read: (c, _) {
    final value = get(c);
    return value == null ? null : DoubleValue(value);
  },
  write: (c, v, _) {
    final value = switch (v) {
      DoubleValue(:final value) => value,
      IntValue(:final value) => value.toDouble(),
      _ => null,
    };
    if (value != null) set(c, value);
  },
);

/// Codec for [FixedJoint].
class FixedJointCodec extends DeclarativeComponentCodec<FixedJoint> {
  @override
  String get type => 'fixedJoint';

  @override
  String? get category => 'Physics';

  @override
  List<ComponentField<FixedJoint>> get fields => [
    _otherNodeField(),
    _anchorField(
      'localAnchorA',
      get: (c) => c.localAnchorA,
      set: (c, v) => c.localAnchorA = v,
    ),
    _anchorField(
      'localAnchorB',
      get: (c) => c.localAnchorB,
      set: (c, v) => c.localAnchorB = v,
    ),
    _collisionsEnabledField(),
  ];

  @override
  FixedJoint create(PropertyReader props) =>
      FixedJoint(otherNode: _resolveOtherNode(props));
}

/// Codec for [SphericalJoint].
class SphericalJointCodec extends DeclarativeComponentCodec<SphericalJoint> {
  @override
  String get type => 'sphericalJoint';

  @override
  String? get category => 'Physics';

  @override
  List<ComponentField<SphericalJoint>> get fields => [
    _otherNodeField(),
    _anchorField(
      'localAnchorA',
      get: (c) => c.localAnchorA,
      set: (c, v) => c.localAnchorA = v,
    ),
    _anchorField(
      'localAnchorB',
      get: (c) => c.localAnchorB,
      set: (c, v) => c.localAnchorB = v,
    ),
    _collisionsEnabledField(),
  ];

  @override
  SphericalJoint create(PropertyReader props) =>
      SphericalJoint(otherNode: _resolveOtherNode(props));
}

/// Codec for [RevoluteJoint].
class RevoluteJointCodec extends DeclarativeComponentCodec<RevoluteJoint> {
  @override
  String get type => 'revoluteJoint';

  @override
  String? get category => 'Physics';

  @override
  List<ComponentField<RevoluteJoint>> get fields => [
    _otherNodeField(),
    _anchorField(
      'localAnchorA',
      get: (c) => c.localAnchorA,
      set: (c, v) => c.localAnchorA = v,
    ),
    _anchorField(
      'localAnchorB',
      get: (c) => c.localAnchorB,
      set: (c, v) => c.localAnchorB = v,
    ),
    _axisField(
      'localAxisA',
      get: (c) => c.localAxisA,
      set: (c, v) => c.localAxisA = v,
    ),
    _axisField(
      'localAxisB',
      get: (c) => c.localAxisB,
      set: (c, v) => c.localAxisB = v,
    ),
    _optionalNumberField(
      'lowerLimit',
      doc: 'Lower angle limit in radians; absent is unlimited.',
      get: (c) => c.lowerLimit,
      set: (c, v) => c.lowerLimit = v,
    ),
    _optionalNumberField(
      'upperLimit',
      doc: 'Upper angle limit in radians; absent is unlimited.',
      get: (c) => c.upperLimit,
      set: (c, v) => c.upperLimit = v,
    ),
    _optionalNumberField(
      'motorTargetVelocity',
      doc: 'Motor target angular velocity; absent disables the motor.',
      get: (c) => c.motorTargetVelocity,
      set: (c, v) => c.motorTargetVelocity = v,
    ),
    _optionalNumberField(
      'motorMaxForce',
      doc: 'Maximum motor force; absent is unbounded.',
      get: (c) => c.motorMaxForce,
      set: (c, v) => c.motorMaxForce = v,
    ),
    _collisionsEnabledField(),
  ];

  @override
  RevoluteJoint create(PropertyReader props) => RevoluteJoint(
    otherNode: _resolveOtherNode(props),
    axis: props.vec3('localAxisA'),
  );
}

/// Codec for [PrismaticJoint].
class PrismaticJointCodec extends DeclarativeComponentCodec<PrismaticJoint> {
  @override
  String get type => 'prismaticJoint';

  @override
  String? get category => 'Physics';

  @override
  List<ComponentField<PrismaticJoint>> get fields => [
    _otherNodeField(),
    _anchorField(
      'localAnchorA',
      get: (c) => c.localAnchorA,
      set: (c, v) => c.localAnchorA = v,
    ),
    _anchorField(
      'localAnchorB',
      get: (c) => c.localAnchorB,
      set: (c, v) => c.localAnchorB = v,
    ),
    _axisField(
      'localAxisA',
      get: (c) => c.localAxisA,
      set: (c, v) => c.localAxisA = v,
    ),
    _axisField(
      'localAxisB',
      get: (c) => c.localAxisB,
      set: (c, v) => c.localAxisB = v,
    ),
    _optionalNumberField(
      'lowerLimit',
      doc: 'Lower travel limit along the axis; absent is unlimited.',
      get: (c) => c.lowerLimit,
      set: (c, v) => c.lowerLimit = v,
    ),
    _optionalNumberField(
      'upperLimit',
      doc: 'Upper travel limit along the axis; absent is unlimited.',
      get: (c) => c.upperLimit,
      set: (c, v) => c.upperLimit = v,
    ),
    _optionalNumberField(
      'motorTargetVelocity',
      doc: 'Motor target linear velocity; absent disables the motor.',
      get: (c) => c.motorTargetVelocity,
      set: (c, v) => c.motorTargetVelocity = v,
    ),
    _optionalNumberField(
      'motorMaxForce',
      doc: 'Maximum motor force; absent is unbounded.',
      get: (c) => c.motorMaxForce,
      set: (c, v) => c.motorMaxForce = v,
    ),
    _collisionsEnabledField(),
  ];

  @override
  PrismaticJoint create(PropertyReader props) => PrismaticJoint(
    otherNode: _resolveOtherNode(props),
    axis: props.vec3('localAxisA'),
  );
}

// --- GenericJoint axis table ---

MapValue _encodeJointMotor(sim.JointMotor motor) => MapValue({
  'targetPosition': DoubleValue(motor.targetPosition),
  'targetVelocity': DoubleValue(motor.targetVelocity),
  'stiffness': DoubleValue(motor.stiffness),
  'damping': DoubleValue(motor.damping),
  // Absent means unbounded (infinity does not travel through JSON).
  if (motor.maxForce.isFinite) 'maxForce': DoubleValue(motor.maxForce),
  'model': StringValue(motor.model.name),
});

sim.JointMotor _decodeJointMotor(Map<String, PropertyValue> m) =>
    sim.JointMotor(
      targetPosition: readDouble(m, 'targetPosition', 0),
      targetVelocity: readDouble(m, 'targetVelocity', 0),
      stiffness: readDouble(m, 'stiffness', 0),
      damping: readDouble(m, 'damping', 0),
      maxForce: readDouble(m, 'maxForce', double.infinity),
      model: _enum(
        m,
        'model',
        sim.JointMotorModel.values,
        sim.JointMotorModel.acceleration,
      ),
    );

MapValue _encodeAxisConfig(sim.JointAxisConfig config) {
  final motor = config.motor;
  return MapValue({
    'motion': StringValue(config.motion.name),
    if (config.motion == sim.JointAxisMotion.limited) ...{
      'lowerLimit': DoubleValue(config.lowerLimit),
      'upperLimit': DoubleValue(config.upperLimit),
    },
    if (motor != null) 'motor': _encodeJointMotor(motor),
  });
}

sim.JointAxisConfig _decodeAxisConfig(Map<String, PropertyValue> m) {
  final motorValue = m['motor'];
  final motor = motorValue is MapValue
      ? _decodeJointMotor(motorValue.values)
      : null;
  return switch (readString(m, 'motion', 'free')) {
    'locked' => const sim.JointAxisConfig.locked(),
    'limited' => sim.JointAxisConfig.limited(
      readDouble(m, 'lowerLimit', 0),
      readDouble(m, 'upperLimit', 0),
      motor: motor,
    ),
    _ => sim.JointAxisConfig.free(motor: motor),
  };
}

MapValue _encodeJointAxes(GenericJoint joint) => MapValue({
  for (final axis in sim.JointAxis.values)
    axis.name: _encodeAxisConfig(joint.configForAxis(axis)),
});

final MapValue _defaultJointAxes = MapValue({
  for (final axis in sim.JointAxis.values)
    axis.name: _encodeAxisConfig(const sim.JointAxisConfig.free()),
});

final List<ComponentPropertyDef> _jointMotorFields = [
  const ComponentPropertyDef(
    'targetPosition',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Target position (or angle) the motor drives toward.',
  ),
  const ComponentPropertyDef(
    'targetVelocity',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Target velocity the motor drives toward.',
  ),
  const ComponentPropertyDef(
    'stiffness',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Position gain.',
    constraints: [Range.nonNegative()],
  ),
  const ComponentPropertyDef(
    'damping',
    ComponentPropertyKind.number,
    defaultValue: DoubleValue(0),
    doc: 'Velocity gain.',
    constraints: [Range.nonNegative()],
  ),
  const ComponentPropertyDef(
    'maxForce',
    ComponentPropertyKind.number,
    doc: 'Force cap; absent is unbounded.',
    constraints: [Range.nonNegative()],
  ),
  ComponentPropertyDef(
    'model',
    ComponentPropertyKind.string,
    defaultValue: const StringValue('acceleration'),
    doc: 'How the motor strength is interpreted.',
    options: [for (final model in sim.JointMotorModel.values) model.name],
  ),
];

final List<ComponentPropertyDef> _jointAxisConfigFields = [
  ComponentPropertyDef(
    'motion',
    ComponentPropertyKind.string,
    defaultValue: const StringValue('free'),
    doc: 'How this degree of freedom is constrained.',
    options: [for (final motion in sim.JointAxisMotion.values) motion.name],
  ),
  const ComponentPropertyDef(
    'lowerLimit',
    ComponentPropertyKind.number,
    doc: 'Lower bound when limited.',
  ),
  const ComponentPropertyDef(
    'upperLimit',
    ComponentPropertyKind.number,
    doc: 'Upper bound when limited.',
  ),
  ComponentPropertyDef(
    'motor',
    ComponentPropertyKind.object,
    doc: 'Optional drive for this axis.',
    objectFields: _jointMotorFields,
  ),
];

/// Codec for [GenericJoint]. The six degrees of freedom serialize as an
/// object keyed by [sim.JointAxis] name.
class GenericJointCodec extends DeclarativeComponentCodec<GenericJoint> {
  @override
  String get type => 'genericJoint';

  @override
  String? get category => 'Physics';

  ComponentField<GenericJoint> _basisField(
    String name, {
    required Quaternion Function(GenericJoint component) get,
    required void Function(GenericJoint component, Quaternion value) set,
  }) => ComponentField(
    ComponentPropertyDef(
      name,
      ComponentPropertyKind.quaternion,
      defaultValue: QuaternionValue(Quaternion.identity()),
      doc: 'Constraint frame in that body\'s local space.',
    ),
    read: (c, _) => QuaternionValue(get(c).clone()),
    write: (c, v, _) {
      if (v is QuaternionValue) set(c, v.value.clone());
    },
  );

  @override
  List<ComponentField<GenericJoint>> get fields => [
    _otherNodeField(),
    _anchorField(
      'localAnchorA',
      get: (c) => c.localAnchorA,
      set: (c, v) => c.localAnchorA = v,
    ),
    _anchorField(
      'localAnchorB',
      get: (c) => c.localAnchorB,
      set: (c, v) => c.localAnchorB = v,
    ),
    _basisField(
      'localBasisA',
      get: (c) => c.localBasisA,
      set: (c, v) => c.localBasisA = v,
    ),
    _basisField(
      'localBasisB',
      get: (c) => c.localBasisB,
      set: (c, v) => c.localBasisB = v,
    ),
    ComponentField(
      ComponentPropertyDef(
        'axes',
        ComponentPropertyKind.object,
        defaultValue: _defaultJointAxes,
        doc: 'Per-degree-of-freedom motion configs, keyed by axis name.',
        objectFields: [
          for (final axis in sim.JointAxis.values)
            ComponentPropertyDef(
              axis.name,
              ComponentPropertyKind.object,
              objectFields: _jointAxisConfigFields,
            ),
        ],
      ),
      read: (c, _) => _encodeJointAxes(c),
      write: (c, v, _) {
        if (v is! MapValue) return;
        for (final axis in sim.JointAxis.values) {
          final entry = v.values[axis.name];
          if (entry is MapValue) {
            c.setAxisConfig(axis, _decodeAxisConfig(entry.values));
          }
        }
      },
    ),
    _collisionsEnabledField(),
  ];

  @override
  GenericJoint create(PropertyReader props) =>
      GenericJoint(otherNode: _resolveOtherNode(props));
}

// --- Character controller ---

/// Codec for [KinematicCharacterController]. Every property is
/// constructor-only (the component's fields are final), so realize flows
/// them all through [create].
class KinematicCharacterControllerCodec
    extends DeclarativeComponentCodec<KinematicCharacterController> {
  @override
  String get type => 'characterController';

  @override
  String? get category => 'Physics';

  static const double _halfPi = 1.5707963267948966;
  static const double _quarterPi = 0.7853981633974483;

  @override
  List<ComponentField<KinematicCharacterController>> get fields => [
    ComponentField.vec3(
      'up',
      defaultValue: () => Vector3(0, 1, 0),
      doc: 'The character\'s up direction.',
      constraints: const [Normalized()],
      get: (c) => c.up,
    ),
    ComponentField.number(
      'offset',
      defaultValue: 0.01,
      doc: 'Gap kept between the character and obstacles.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.offset,
    ),
    ComponentField.boolean(
      'slide',
      defaultValue: true,
      doc: 'Whether blocked motion slides along obstacles.',
      get: (c) => c.slide,
    ),
    ComponentField.number(
      'maxSlopeClimbAngle',
      defaultValue: _quarterPi,
      doc: 'Steepest slope the character climbs, in radians.',
      constraints: const [Range(0, _halfPi), AngleRadians()],
      get: (c) => c.maxSlopeClimbAngle,
    ),
    ComponentField.number(
      'minSlopeSlideAngle',
      defaultValue: _quarterPi,
      doc: 'Shallowest slope the character slides down, in radians.',
      constraints: const [Range(0, _halfPi), AngleRadians()],
      get: (c) => c.minSlopeSlideAngle,
    ),
    // No default; absent means snapping is disabled (null).
    ComponentField(
      const ComponentPropertyDef(
        'snapToGround',
        ComponentPropertyKind.number,
        doc: 'Maximum snap-down distance at edges; absent disables snapping.',
        constraints: [Range.nonNegative()],
      ),
      read: (c, _) {
        final snap = c.snapToGround;
        return snap == null ? null : DoubleValue(snap);
      },
    ),
    ComponentField.boolean(
      'autostep',
      defaultValue: false,
      doc: 'Step over small obstacles automatically.',
      get: (c) => c.autostep,
    ),
    ComponentField.number(
      'autostepMaxHeight',
      defaultValue: 0.3,
      doc: 'Tallest obstacle autostep climbs.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.autostepMaxHeight,
    ),
    ComponentField.number(
      'autostepMinWidth',
      defaultValue: 0.1,
      doc: 'Minimum landing width autostep requires.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.autostepMinWidth,
    ),
    ComponentField.boolean(
      'autostepIncludeDynamicBodies',
      defaultValue: true,
      doc: 'Whether autostep also steps onto dynamic bodies.',
      get: (c) => c.autostepIncludeDynamicBodies,
    ),
    ComponentField.number(
      'mass',
      defaultValue: 0.0,
      doc: 'Mass applied when pushing dynamic bodies; 0 pushes nothing.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.mass,
    ),
  ];

  @override
  KinematicCharacterController create(PropertyReader props) {
    final snap = props.value('snapToGround');
    return KinematicCharacterController(
      up: props.vec3('up'),
      offset: props.number('offset'),
      slide: props.boolean('slide'),
      maxSlopeClimbAngle: props.number('maxSlopeClimbAngle'),
      minSlopeSlideAngle: props.number('minSlopeSlideAngle'),
      snapToGround: switch (snap) {
        DoubleValue(:final value) => value,
        IntValue(:final value) => value.toDouble(),
        _ => null,
      },
      autostep: props.boolean('autostep'),
      autostepMaxHeight: props.number('autostepMaxHeight'),
      autostepMinWidth: props.number('autostepMinWidth'),
      autostepIncludeDynamicBodies: props.boolean(
        'autostepIncludeDynamicBodies',
      ),
      mass: props.number('mass'),
    );
  }
}

/// Registers the physics component codecs into [registry] (the process-wide
/// default registry when omitted).
void registerPhysicsComponentCodecs([FsceneComponentRegistry? registry]) {
  (registry ?? defaultComponentRegistry())
    ..register(PhysicsWorldCodec())
    ..register(RigidBodyCodec())
    ..register(ColliderCodec())
    ..register(FixedJointCodec())
    ..register(SphericalJointCodec())
    ..register(RevoluteJointCodec())
    ..register(PrismaticJointCodec())
    ..register(GenericJointCodec())
    ..register(KinematicCharacterControllerCodec());
}
