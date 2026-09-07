import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/mesh_particle_emitter_component.dart';
import 'package:flutter_scene/src/components/particle_emitter_component.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
import 'package:flutter_scene/src/fscene/realize/property_map.dart';
import 'package:flutter_scene/src/fscene/realize/resource_copy.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/geometry/billboard_geometry.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/sprite_material.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_collision.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

// Authored texture refs that could not be resolved at realize time (no
// resource realizer); serialize falls back to these.
final Expando<ResourceOrigin> _pendingTextureRefs = Expando(
  'fscene.pendingParticleTexture',
);

// Defaults shared by the schema (what an absent property falls back to) and
// the property->system builder, so the two never drift. The lifetime/speed/
// size/rate defaults intentionally differ from the ParticleSystem constructor
// defaults; they are the format's authoring defaults and existing documents
// rely on them.
const int _kMaxParticles = 512;
const double _kEmitRate = 32.0;
const double _kLifetime = 1.5;
const double _kStartSpeed = 1.5;
const double _kStartSize = 0.3;
const double _kDefaultShapeRadius = 0.25;
const double _kDefaultShapeAngle = 0.3;
const double _kDuration = 5.0;
const double _kFixedStep = 1.0 / 60.0;
const double _kMaxFrameTime = 0.25;

EmitterShape _defaultShape() => const ConeEmitterShape(
  angle: _kDefaultShapeAngle,
  radius: _kDefaultShapeRadius,
);

Vector4 _opaqueWhite() => Vector4(1, 1, 1, 1);

// The module stack an emitter gets when a spec declares no `modules`; matches
// what the older fixed-stack format always built, so legacy documents and
// default-constructed emitters behave identically.
List<ParticleModule> _defaultModules() => [
  SizeOverLifeModule(CurveFloat(ParticleCurve.constant(1.0))),
  ColorOverLifeModule(GradientColor(ColorGradient.constant(_opaqueWhite()))),
  const RotationModule(),
];

// --- EmitterShape <-> property value ---

/// Encodes [shape] as a tagged map keyed on its variant. An unknown shape
/// subclass encodes as the default cone (it carries no readable fields).
// TODO(particles-custom-shapes): third-party EmitterShape subclasses
// serialize as the default cone; grow a codec seam if they become a thing.
MapValue encodeEmitterShape(EmitterShape shape) {
  if (shape is PointEmitterShape) {
    return MapValue({
      'kind': const StringValue('point'),
      'direction': Vec3Value(shape.direction.clone()),
    });
  }
  if (shape is SphereEmitterShape) {
    return MapValue({
      'kind': const StringValue('sphere'),
      'radius': DoubleValue(shape.radius),
      'surfaceOnly': BoolValue(shape.surfaceOnly),
      'hemisphere': BoolValue(shape.hemisphere),
    });
  }
  if (shape is BoxEmitterShape) {
    return MapValue({
      'kind': const StringValue('box'),
      'halfExtents': Vec3Value(shape.halfExtents.clone()),
      'direction': Vec3Value(shape.direction.clone()),
    });
  }
  if (shape is ConeEmitterShape) {
    return MapValue({
      'kind': const StringValue('cone'),
      'radius': DoubleValue(shape.radius),
      'angle': DoubleValue(shape.angle),
    });
  }
  return encodeEmitterShape(_defaultShape());
}

/// Decodes an [EmitterShape] from [value]; an unrecognized or absent value
/// yields the default cone.
EmitterShape decodeEmitterShape(PropertyValue? value) {
  if (value is! MapValue) return _defaultShape();
  final m = value.values;
  return switch (m.stringAt('kind', 'cone')) {
    'point' => PointEmitterShape(
      direction: m.vec3At('direction', Vector3(0, 1, 0)),
    ),
    'sphere' => SphereEmitterShape(
      radius: _nonNegative(m.numberAt('radius', 1.0)),
      surfaceOnly: m.boolAt('surfaceOnly', false),
      hemisphere: m.boolAt('hemisphere', false),
    ),
    'box' => BoxEmitterShape(
      halfExtents: m.vec3At('halfExtents', Vector3.all(0.5)),
      direction: m.vec3At('direction', Vector3(0, 1, 0)),
    ),
    _ => ConeEmitterShape(
      radius: _nonNegative(m.numberAt('radius', 0.0)),
      angle: _nonNegative(m.numberAt('angle', 0.5)),
    ),
  };
}

// --- ParticleModule <-> property value ---

/// Encodes [module] as a tagged map keyed on its variant, or null when the
/// module type is not representable (a custom subclass).
MapValue? encodeParticleModule(ParticleModule module) {
  if (module is AccelerationModule) {
    return MapValue({
      'kind': const StringValue('acceleration'),
      'acceleration': Vec3Value(module.acceleration.clone()),
    });
  }
  if (module is LinearDragModule) {
    return MapValue({
      'kind': const StringValue('linearDrag'),
      'coefficient': DoubleValue(module.coefficient),
    });
  }
  if (module is SizeOverLifeModule) {
    return MapValue({
      'kind': const StringValue('sizeOverLife'),
      'scale': encodeFloatDistribution(module.scale),
    });
  }
  if (module is ColorOverLifeModule) {
    return MapValue({
      'kind': const StringValue('colorOverLife'),
      'color': encodeColorDistribution(module.color),
    });
  }
  if (module is FlipbookModule) {
    final fps = module.framesPerSecond;
    return MapValue({
      'kind': const StringValue('flipbook'),
      'frameCount': IntValue(module.frameCount),
      if (fps != null) 'framesPerSecond': DoubleValue(fps),
      'randomStartFrame': BoolValue(module.randomStartFrame),
    });
  }
  if (module is TurbulenceModule) {
    return MapValue({
      'kind': const StringValue('turbulence'),
      'strength': DoubleValue(module.strength),
      'frequency': DoubleValue(module.frequency),
      'scroll': Vec3Value(module.scroll.clone()),
      'seed': IntValue(module.seed),
    });
  }
  if (module is RotationModule) {
    return MapValue({'kind': const StringValue('rotation')});
  }
  if (module is CollisionModule) {
    return MapValue({
      'kind': const StringValue('collision'),
      'response': StringValue(module.response.name),
      'restitution': DoubleValue(module.restitution),
      'friction': DoubleValue(module.friction),
      'radius': DoubleValue(module.radius),
      'lifetimeLoss': DoubleValue(module.lifetimeLoss),
      'colliders': ListValue([
        for (final collider in module.colliders)
          if (encodeParticleCollider(collider) case final encoded?) encoded,
      ]),
    });
  }
  return null;
}

/// Encodes one collider as a tagged map, or null for a shape the format does
/// not carry (a project's own subclass).
MapValue? encodeParticleCollider(ParticleCollider collider) =>
    switch (collider) {
      ParticlePlane() => MapValue({
        'kind': const StringValue('plane'),
        'normal': Vec3Value(collider.normal),
        'distance': DoubleValue(collider.distance),
      }),
      ParticleSphere() => MapValue({
        'kind': const StringValue('sphere'),
        'centre': Vec3Value(collider.centre),
        'radius': DoubleValue(collider.radius),
      }),
      ParticleBox() => MapValue({
        'kind': const StringValue('box'),
        'centre': Vec3Value(collider.centre),
        'halfExtents': Vec3Value(collider.halfExtents),
      }),
    };

/// Decodes one collider, or null when the entry names no known shape.
ParticleCollider? decodeParticleCollider(PropertyValue? value) {
  if (value is! MapValue) return null;
  final m = value.values;
  return switch (m.stringAt('kind', '')) {
    'plane' => ParticlePlane(
      normal: m.vec3At('normal', Vector3(0, 1, 0)),
      distance: m.numberAt('distance', 0.0),
    ),
    'sphere' => ParticleSphere(
      centre: m.vec3At('centre', Vector3.zero()),
      radius: m.numberAt('radius', 1.0),
    ),
    'box' => ParticleBox(
      centre: m.vec3At('centre', Vector3.zero()),
      halfExtents: m.vec3At('halfExtents', Vector3.all(0.5)),
    ),
    _ => null,
  };
}

/// Decodes a [ParticleModule] from [value], or null when the entry is
/// malformed or names an unknown kind.
ParticleModule? decodeParticleModule(PropertyValue? value) {
  if (value is! MapValue) return null;
  final m = value.values;
  return switch (m.stringAt('kind', '')) {
    'acceleration' => AccelerationModule(
      m.vec3At('acceleration', Vector3.zero()),
    ),
    'linearDrag' => LinearDragModule(
      _nonNegative(m.numberAt('coefficient', 0.0)),
    ),
    'sizeOverLife' => SizeOverLifeModule(
      decodeFloatDistribution(m['scale'], fallback: 1.0),
    ),
    'colorOverLife' => ColorOverLifeModule(decodeColorDistribution(m['color'])),
    'flipbook' => _decodeFlipbook(m),
    'turbulence' => TurbulenceModule(
      strength: m.numberAt('strength', 1.0),
      frequency: m.numberAt('frequency', 1.0),
      scroll: m.vec3At('scroll', Vector3.zero()),
      seed: m.intAt('seed', 1337),
    ),
    'rotation' => const RotationModule(),
    'collision' => _decodeCollision(m),
    _ => null,
  };
}

CollisionModule _decodeCollision(Map<String, PropertyValue> m) {
  final raw = m['colliders'];
  final colliders = <ParticleCollider>[
    if (raw is ListValue)
      for (final entry in raw.values)
        if (decodeParticleCollider(entry) case final collider?) collider,
  ];
  final response = m.stringAt('response', 'bounce');
  return CollisionModule(
    colliders: colliders,
    response: ParticleCollisionResponse.values.firstWhere(
      (value) => value.name == response,
      orElse: () => ParticleCollisionResponse.bounce,
    ),
    restitution: m.numberAt('restitution', 0.35),
    friction: m.numberAt('friction', 0.2),
    radius: m.numberAt('radius', 0.0),
    lifetimeLoss: m.numberAt('lifetimeLoss', 0.0),
  );
}

FlipbookModule _decodeFlipbook(Map<String, PropertyValue> m) {
  final frameCount = m.intAt('frameCount', 1);
  final fps = m.numberAt('framesPerSecond', 0.0);
  return FlipbookModule(
    frameCount: frameCount < 1 ? 1 : frameCount,
    framesPerSecond: fps > 0 ? fps : null,
    randomStartFrame: m.boolAt('randomStartFrame', false),
  );
}

// --- ParticleBurst <-> property value ---

/// Encodes [burst] as `{time, count, interval?, cycles?}` (single-shot bursts
/// omit `interval`; repeat-forever bursts omit `cycles`).
MapValue encodeParticleBurst(ParticleBurst burst) => MapValue({
  'time': DoubleValue(burst.time),
  'count': IntValue(burst.count),
  if (burst.interval > 0) 'interval': DoubleValue(burst.interval),
  if (burst.cycles != null) 'cycles': IntValue(burst.cycles!),
});

/// Decodes a [ParticleBurst] from [value], or null when malformed.
ParticleBurst? decodeParticleBurst(PropertyValue? value) {
  if (value is! MapValue) return null;
  final m = value.values;
  final cycles = m['cycles'];
  return ParticleBurst(
    time: _nonNegative(m.numberAt('time', 0.0)),
    count: m.intAt('count', 0) < 0 ? 0 : m.intAt('count', 0),
    interval: m.numberAt('interval', 0.0),
    cycles: cycles is IntValue ? (cycles.value < 1 ? 1 : cycles.value) : null,
  );
}

// --- Property map <-> ParticleSystem ---

/// Builds a [ParticleSystem] from a particle emitter spec's [properties].
///
/// Pure (no GPU), so it is unit-testable on its own; the codecs wrap the
/// result in an emitter component. Absent or malformed properties fall back to
/// the schema defaults. Accepts the legacy flat shape keys
/// (`shapeType`/`shapeRadius`/`shapeAngle`) when no `shape` union is present,
/// and the legacy fixed module keys (`drag`/`sizeOverLife`/`colorOverLife`)
/// when no `modules` list is present.
ParticleSystem particleSystemFromProperties(
  Map<String, PropertyValue> properties,
) {
  final fixedStep = switch (properties.numberAt('fixedStep', _kFixedStep)) {
    final step when step > 0 => step,
    _ => _kFixedStep,
  };
  var maxFrameTime = properties.numberAt('maxFrameTime', _kMaxFrameTime);
  if (maxFrameTime < fixedStep) maxFrameTime = fixedStep;
  final duration = properties.numberAt('duration', _kDuration);
  final maxParticles = properties.intAt('maxParticles', _kMaxParticles);
  return ParticleSystem(
    maxParticles: maxParticles < 1 ? 1 : maxParticles,
    shape: _shapeFromProperties(properties),
    spawner: Spawner(
      rate: _nonNegative(properties.numberAt('emitRate', _kEmitRate)),
      bursts: _burstsFromProperties(properties),
    ),
    modules: _modulesFromProperties(properties),
    lifetime: _dist(properties, 'lifetime', _kLifetime),
    startSpeed: _dist(properties, 'startSpeed', _kStartSpeed),
    startSize: _dist(properties, 'startSize', _kStartSize),
    startRotation: _dist(properties, 'startRotation', 0),
    startAngularVelocity: _dist(properties, 'startAngularVelocity', 0),
    startColor: decodeColorDistribution(properties['startColor']),
    gravity: properties.vec3At('gravity', Vector3.zero()),
    looping: properties.boolAt('looping', true),
    duration: duration > 0 ? duration : _kDuration,
    fixedStep: fixedStep,
    maxFrameTime: maxFrameTime,
    seed: properties.intAt('seed', 0),
    prewarm: _nonNegative(properties.numberAt('prewarm', 0)),
  );
}

/// Reads a [ParticleSystem] back into its property map, the inverse of
/// [particleSystemFromProperties]. Pure and unit-testable; emits every
/// property (the codecs apply delta-vs-default omission on top).
Map<String, PropertyValue> particleSystemToProperties(ParticleSystem system) {
  final bursts = system.spawner.bursts;
  return {
    'maxParticles': IntValue(system.storage.capacity),
    'emitRate': DoubleValue(system.spawner.rate),
    if (bursts.isNotEmpty)
      'bursts': ListValue([
        for (final burst in bursts) encodeParticleBurst(burst),
      ]),
    'shape': encodeEmitterShape(system.shape),
    'modules': encodeParticleModules(system.modules),
    'lifetime': encodeFloatDistribution(system.lifetime),
    'startSpeed': encodeFloatDistribution(system.startSpeed),
    'startSize': encodeFloatDistribution(system.startSize),
    'startRotation': encodeFloatDistribution(system.startRotation),
    'startAngularVelocity': encodeFloatDistribution(
      system.startAngularVelocity,
    ),
    'startColor': encodeColorDistribution(system.startColor),
    'gravity': Vec3Value(system.gravity.clone()),
    'looping': BoolValue(system.looping),
    'duration': DoubleValue(system.duration),
    'fixedStep': DoubleValue(system.fixedStep),
    'maxFrameTime': DoubleValue(system.maxFrameTime),
    'seed': IntValue(system.seed),
    'prewarm': DoubleValue(system.prewarm),
  };
}

/// Encodes [modules] as a list of tagged maps, skipping unrepresentable
/// (custom) module types.
ListValue encodeParticleModules(List<ParticleModule> modules) {
  final encoded = <PropertyValue>[];
  for (final module in modules) {
    final value = encodeParticleModule(module);
    if (value == null) {
      debugPrint(
        'fscene: particle module ${module.runtimeType} not serialized '
        '(unknown module type)',
      );
      continue;
    }
    encoded.add(value);
  }
  return ListValue(encoded);
}

EmitterShape _shapeFromProperties(Map<String, PropertyValue> p) {
  final shape = p['shape'];
  if (shape is MapValue) return decodeEmitterShape(shape);
  // Legacy flat keys, from before the shape union.
  final radius = _nonNegative(p.numberAt('shapeRadius', _kDefaultShapeRadius));
  final angle = _nonNegative(p.numberAt('shapeAngle', _kDefaultShapeAngle));
  return switch (p.stringAt('shapeType', 'cone')) {
    'point' => PointEmitterShape(),
    'sphere' => SphereEmitterShape(radius: radius),
    'box' => BoxEmitterShape(halfExtents: Vector3.all(radius)),
    _ => ConeEmitterShape(angle: angle, radius: radius),
  };
}

List<ParticleModule> _modulesFromProperties(Map<String, PropertyValue> p) {
  final modules = p['modules'];
  if (modules is ListValue) {
    return [
      for (final entry in modules.values)
        if (decodeParticleModule(entry) case final module?) module,
    ];
  }
  // Legacy fixed stack, from before arbitrary module lists. An absent
  // curve/gradient means "no shaping", not the decoders' empty-input fallbacks
  // (decodeParticleCurve(null) is a constant-zero curve, which would shrink
  // every particle to nothing). Apply the semantic default (size x1, opaque
  // white) when the property is missing.
  final drag = p.numberAt('drag', 0);
  final sizeOverLife = p['sizeOverLife'];
  final colorOverLife = p['colorOverLife'];
  return [
    if (drag > 0) LinearDragModule(drag),
    SizeOverLifeModule(
      CurveFloat(
        sizeOverLife != null
            ? decodeParticleCurve(sizeOverLife)
            : ParticleCurve.constant(1.0),
      ),
    ),
    ColorOverLifeModule(
      GradientColor(
        colorOverLife != null
            ? decodeColorGradient(colorOverLife)
            : ColorGradient.constant(_opaqueWhite()),
      ),
    ),
    const RotationModule(),
  ];
}

List<ParticleBurst> _burstsFromProperties(Map<String, PropertyValue> p) {
  final bursts = p['bursts'];
  if (bursts is! ListValue) return const [];
  return [
    for (final entry in bursts.values)
      if (decodeParticleBurst(entry) case final burst?) burst,
  ];
}

// --- Shared schema descriptors ---

final ComponentPropertyDef _shapeDef = ComponentPropertyDef(
  'shape',
  ComponentPropertyKind.union,
  defaultValue: encodeEmitterShape(_defaultShape()),
  doc: 'Where particles spawn and which way they head.',
  unionVariants: {
    'point': [
      ComponentPropertyDef(
        'direction',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3(0, 1, 0)),
        doc: 'Unit emission direction shared by every particle.',
        constraints: const [Normalized()],
      ),
    ],
    'sphere': const [
      ComponentPropertyDef(
        'radius',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(1.0),
        doc: 'Sphere radius.',
        constraints: [Range.nonNegative()],
      ),
      ComponentPropertyDef(
        'surfaceOnly',
        ComponentPropertyKind.boolean,
        defaultValue: BoolValue(false),
        doc: 'Spawn only on the shell rather than throughout the volume.',
      ),
      ComponentPropertyDef(
        'hemisphere',
        ComponentPropertyKind.boolean,
        defaultValue: BoolValue(false),
        doc: 'Restrict to the +Y half.',
      ),
    ],
    'cone': const [
      ComponentPropertyDef(
        'radius',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.0),
        doc: 'Base disc radius.',
        constraints: [Range.nonNegative()],
      ),
      ComponentPropertyDef(
        'angle',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.5),
        doc: 'Cone half-angle in radians.',
        constraints: [Range.nonNegative(), AngleRadians()],
      ),
    ],
    'box': [
      ComponentPropertyDef(
        'halfExtents',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3.all(0.5)),
        doc: 'Box half-size on each axis.',
      ),
      ComponentPropertyDef(
        'direction',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3(0, 1, 0)),
        doc: 'Unit emission direction shared by every particle.',
        constraints: const [Normalized()],
      ),
    ],
  },
);

final ComponentPropertyDef _moduleItemDef = ComponentPropertyDef(
  'module',
  ComponentPropertyKind.union,
  doc: 'One unit of per-particle behaviour.',
  unionVariants: {
    'acceleration': [
      ComponentPropertyDef(
        'acceleration',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3.zero()),
        doc: 'Constant acceleration added each step.',
      ),
    ],
    'linearDrag': const [
      ComponentPropertyDef(
        'coefficient',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.0),
        doc: 'Drag coefficient (per second).',
        constraints: [Range.nonNegative()],
      ),
    ],
    'sizeOverLife': [
      ComponentPropertyDef(
        'scale',
        ComponentPropertyKind.distribution,
        defaultValue: encodeFloatDistribution(
          CurveFloat(ParticleCurve.constant(1.0)),
        ),
        doc: 'Size multiplier sampled over normalized age.',
      ),
    ],
    'colorOverLife': [
      ComponentPropertyDef(
        'color',
        ComponentPropertyKind.distribution,
        defaultValue: encodeColorDistribution(
          GradientColor(ColorGradient.constant(_opaqueWhite())),
        ),
        doc: 'Color sampled over normalized age.',
      ),
    ],
    'flipbook': const [
      ComponentPropertyDef(
        'frameCount',
        ComponentPropertyKind.integer,
        defaultValue: IntValue(1),
        doc: 'Number of cells in the atlas (columns x rows).',
        constraints: [IntRange(1, null)],
      ),
      ComponentPropertyDef(
        'framesPerSecond',
        ComponentPropertyKind.number,
        doc: 'Fixed playback rate; absent plays once over each life.',
        constraints: [Range.nonNegative()],
      ),
      ComponentPropertyDef(
        'randomStartFrame',
        ComponentPropertyKind.boolean,
        defaultValue: BoolValue(false),
        doc: 'Start each particle at a stable random frame offset.',
      ),
    ],
    'turbulence': [
      const ComponentPropertyDef(
        'strength',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(1.0),
        doc: 'Velocity change per second at unit curl magnitude.',
      ),
      const ComponentPropertyDef(
        'frequency',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(1.0),
        doc: 'Spatial scale applied before sampling the noise.',
      ),
      ComponentPropertyDef(
        'scroll',
        ComponentPropertyKind.vec3,
        defaultValue: Vec3Value(Vector3.zero()),
        doc: 'Field drift in world units per second.',
      ),
      const ComponentPropertyDef(
        'seed',
        ComponentPropertyKind.integer,
        defaultValue: IntValue(1337),
        doc: 'Curl field seed.',
      ),
    ],
    'rotation': const [],
    'collision': const [
      ComponentPropertyDef(
        'response',
        ComponentPropertyKind.string,
        defaultValue: StringValue('bounce'),
        options: ['bounce', 'slide', 'stick', 'kill'],
        doc:
            'What a hit does: reflect, run along the surface, stop dead, or '
            'die on contact.',
      ),
      ComponentPropertyDef(
        'restitution',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.35),
        doc: 'How much of the speed into the surface a bounce keeps.',
        constraints: [Range(0, 1), SoftRange(0, 1)],
      ),
      ComponentPropertyDef(
        'friction',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.2),
        doc: 'How much of the speed along the surface a hit sheds.',
        constraints: [Range(0, 1), SoftRange(0, 1)],
      ),
      ComponentPropertyDef(
        'radius',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.0),
        doc:
            'The radius a particle collides with, so a puff stops short of a '
            'wall rather than half inside it.',
        constraints: [Range.nonNegative(), SoftRange(0, 2)],
      ),
      ComponentPropertyDef(
        'lifetimeLoss',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.0),
        doc: 'How much of the remaining life a hit costs.',
        constraints: [Range(0, 1), SoftRange(0, 1)],
      ),
      ComponentPropertyDef(
        'colliders',
        ComponentPropertyKind.list,
        doc:
            'Surfaces tested, in the emitter\'s own space. Cost is the live '
            'particle count times this, so a handful is the design point.',
        itemDef: ComponentPropertyDef(
          'collider',
          ComponentPropertyKind.union,
          unionVariants: {
            'plane': [
              ComponentPropertyDef(
                'normal',
                ComponentPropertyKind.vec3,
                doc: 'Outward normal; everything on this side is clear.',
              ),
              ComponentPropertyDef(
                'distance',
                ComponentPropertyKind.number,
                defaultValue: DoubleValue(0),
                doc: 'How far along the normal the plane sits.',
              ),
            ],
            'sphere': [
              ComponentPropertyDef('centre', ComponentPropertyKind.vec3),
              ComponentPropertyDef(
                'radius',
                ComponentPropertyKind.number,
                defaultValue: DoubleValue(1),
                constraints: [Range.nonNegative()],
              ),
            ],
            'box': [
              ComponentPropertyDef('centre', ComponentPropertyKind.vec3),
              ComponentPropertyDef('halfExtents', ComponentPropertyKind.vec3),
            ],
          },
        ),
      ),
    ],
  },
);

final ComponentPropertyDef _modulesDef = ComponentPropertyDef(
  'modules',
  ComponentPropertyKind.list,
  defaultValue: encodeParticleModules(_defaultModules()),
  doc: 'Ordered behaviour stack (forces and over-life evaluators).',
  itemDef: _moduleItemDef,
);

final ComponentPropertyDef _burstsDef = ComponentPropertyDef(
  'bursts',
  ComponentPropertyKind.list,
  defaultValue: ListValue(const []),
  doc: 'Scheduled burst emissions, fired by system time.',
  itemDef: const ComponentPropertyDef(
    'burst',
    ComponentPropertyKind.object,
    objectFields: [
      ComponentPropertyDef(
        'time',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.0),
        doc: 'System time (seconds) of the first occurrence.',
        constraints: [Range.nonNegative()],
      ),
      ComponentPropertyDef(
        'count',
        ComponentPropertyKind.integer,
        defaultValue: IntValue(0),
        doc: 'Particles emitted per occurrence.',
        constraints: [IntRange(0, null)],
      ),
      ComponentPropertyDef(
        'interval',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(0.0),
        doc: 'Seconds between occurrences; 0 is a single shot.',
        constraints: [Range.nonNegative()],
      ),
      ComponentPropertyDef(
        'cycles',
        ComponentPropertyKind.integer,
        doc: 'Occurrences when repeating; absent repeats forever.',
        constraints: [IntRange(1, null)],
      ),
    ],
  ),
);

ComponentField<C> _distributionField<C extends Component>(
  String name,
  double defaultValue,
  String doc,
  FloatDistribution Function(C component) get,
) => ComponentField(
  ComponentPropertyDef(
    name,
    ComponentPropertyKind.distribution,
    defaultValue: encodeFloatDistribution(ConstantFloat(defaultValue)),
    doc: doc,
  ),
  read: (c, _) => encodeFloatDistribution(get(c)),
);

/// The [ParticleSystem] configuration fields shared by the sprite and mesh
/// particle emitter codecs. All are constructor-only: they read from the live
/// system (via [systemOf]) for serialization, and realize flows them through
/// [particleSystemFromProperties] in the codec's `create`.
List<ComponentField<C>> particleSystemFields<C extends Component>(
  ParticleSystem Function(C component) systemOf,
) => [
  ComponentField.integer(
    'maxParticles',
    defaultValue: _kMaxParticles,
    doc: 'Hard cap on simultaneous particles.',
    constraints: const [IntRange(1, null)],
    get: (c) => systemOf(c).storage.capacity,
  ),
  ComponentField.number(
    'emitRate',
    defaultValue: _kEmitRate,
    doc: 'Steady emission rate in particles per second.',
    constraints: const [Range.nonNegative()],
    get: (c) => systemOf(c).spawner.rate,
  ),
  ComponentField(
    _burstsDef,
    read: (c, _) => ListValue([
      for (final burst in systemOf(c).spawner.bursts)
        encodeParticleBurst(burst),
    ]),
  ),
  ComponentField(
    _shapeDef,
    read: (c, _) => encodeEmitterShape(systemOf(c).shape),
  ),
  ComponentField(
    _modulesDef,
    read: (c, _) => encodeParticleModules(systemOf(c).modules),
  ),
  _distributionField(
    'lifetime',
    _kLifetime,
    'Seconds each particle lives.',
    (c) => systemOf(c).lifetime,
  ),
  _distributionField(
    'startSpeed',
    _kStartSpeed,
    'Initial speed along the emission direction.',
    (c) => systemOf(c).startSpeed,
  ),
  _distributionField(
    'startSize',
    _kStartSize,
    'Initial particle size in world units.',
    (c) => systemOf(c).startSize,
  ),
  _distributionField(
    'startRotation',
    0,
    'Initial rotation in radians.',
    (c) => systemOf(c).startRotation,
  ),
  _distributionField(
    'startAngularVelocity',
    0,
    'Initial rotation rate in radians per second.',
    (c) => systemOf(c).startAngularVelocity,
  ),
  ComponentField(
    ComponentPropertyDef(
      'startColor',
      ComponentPropertyKind.distribution,
      defaultValue: encodeColorDistribution(ConstantColor(_opaqueWhite())),
      doc: 'Color assigned at spawn.',
    ),
    read: (c, _) => encodeColorDistribution(systemOf(c).startColor),
  ),
  ComponentField.vec3(
    'gravity',
    defaultValue: Vector3.zero,
    doc: 'Constant acceleration applied each step.',
    get: (c) => systemOf(c).gravity,
  ),
  ComponentField.boolean(
    'looping',
    defaultValue: true,
    doc: 'Whether the emitter emits forever.',
    get: (c) => systemOf(c).looping,
  ),
  ComponentField.number(
    'duration',
    defaultValue: _kDuration,
    doc: 'Run length in seconds (emit cutoff when not looping).',
    constraints: const [Range.nonNegative()],
    get: (c) => systemOf(c).duration,
  ),
  ComponentField.number(
    'fixedStep',
    defaultValue: _kFixedStep,
    doc: 'Fixed simulation timestep in seconds.',
    constraints: const [Range.nonNegative()],
    get: (c) => systemOf(c).fixedStep,
  ),
  ComponentField.number(
    'maxFrameTime',
    defaultValue: _kMaxFrameTime,
    doc: 'Largest frame delta honored per step.',
    constraints: const [Range.nonNegative()],
    get: (c) => systemOf(c).maxFrameTime,
  ),
  ComponentField.integer(
    'seed',
    defaultValue: 0,
    doc: 'Seed for all spawn randomness.',
    get: (c) => systemOf(c).seed,
  ),
  ComponentField.number(
    'prewarm',
    defaultValue: 0,
    doc: 'Seconds simulated before the emitter first renders.',
    constraints: const [Range.nonNegative()],
    get: (c) => systemOf(c).prewarm,
  ),
];

/// Codec for a [ParticleEmitterComponent]: serializes the emitter's
/// [ParticleSystem] configuration (shape, spawner, module stack, start
/// distributions), the billboard rendering knobs, and the optional texture
/// into a `particleEmitter` component spec, and realizes it back into a live
/// emitter, losslessly in both directions.
///
/// The shape is a tagged union, the module stack a list of tagged unions, so
/// arbitrary shapes and module orders round-trip. Realize still accepts the
/// older flat keys (`shapeType`/`shapeRadius`/`shapeAngle` and the fixed
/// `drag`/`sizeOverLife`/`colorOverLife` stack).
class ParticleEmitterCodec
    extends DeclarativeComponentCodec<ParticleEmitterComponent> {
  @override
  String get type => 'particleEmitter';

  @override
  String? get category => 'Effects';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'particles',
    properties: propertySchema,
    gizmo: const GizmoSpec([GizmoIcon()]),
  );

  @override
  List<ComponentField<ParticleEmitterComponent>> get fields => [
    ...particleSystemFields<ParticleEmitterComponent>((c) => c.system),
    ComponentField.enumString(
      'blendMode',
      values: SpriteBlendMode.values,
      defaultValue: SpriteBlendMode.alpha,
      doc: 'How particles composite into the scene.',
      get: (c) => c.material.blendMode,
      set: (c, v) => c.material.blendMode = v,
    ),
    ComponentField.enumString(
      'facing',
      values: BillboardFacing.values,
      defaultValue: BillboardFacing.spherical,
      doc: 'How billboards orient toward the camera.',
      get: (c) => c.facing,
      set: (c, v) => c.facing = v,
    ),
    ComponentField.number(
      'velocityStretch',
      defaultValue: 0,
      doc: 'Extra length per unit speed for velocity-stretched facing.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.velocityStretch,
      set: (c, v) => c.velocityStretch = v,
    ),
    ComponentField.boolean(
      'paused',
      defaultValue: false,
      doc: 'Hold the simulation (current particles keep rendering).',
      get: (c) => c.paused,
      set: (c, v) => c.paused = v,
    ),
    ComponentField.integer(
      'flipbookColumns',
      defaultValue: 1,
      doc: 'Flipbook atlas columns in the texture.',
      constraints: const [IntRange(1, null)],
      get: (c) => c.flipbookColumns,
      set: (c, v) => c.flipbookColumns = v,
    ),
    ComponentField.integer(
      'flipbookRows',
      defaultValue: 1,
      doc: 'Flipbook atlas rows in the texture.',
      constraints: const [IntRange(1, null)],
      get: (c) => c.flipbookRows,
      set: (c, v) => c.flipbookRows = v,
    ),
    ComponentField.boolean(
      'flipbookBlend',
      defaultValue: false,
      doc: 'Crossfade fractional frames between adjacent flipbook cells.',
      get: (c) => c.flipbookBlend,
      set: (c, v) => c.flipbookBlend = v,
    ),
    ComponentField.boolean(
      'randomFlipX',
      defaultValue: false,
      doc: 'Give each particle a stable 50% chance of mirroring.',
      get: (c) => c.randomFlipX,
      set: (c, v) => c.randomFlipX = v,
    ),
    ComponentField.number(
      'aspectRatio',
      defaultValue: 1.0,
      doc: 'Billboard width as a multiple of the particle size.',
      constraints: const [Range.nonNegative(), SoftRange(0.1, 4)],
      get: (c) => c.aspectRatio,
      set: (c, v) => c.aspectRatio = v,
    ),
    ComponentField.resourceRef(
      'texture',
      resourceKind: 'texture',
      doc: 'Sprite texture sampled per particle (optional).',
      get: (c, context) {
        final source = c.material.colorTexture;
        ResourceOrigin? origin;
        if (source is GpuTextureSource) origin = resourceOrigin(source.texture);
        origin ??= _pendingTextureRefs[c];
        if (origin == null) return null;
        return copyResourceInto(
          context.document,
          origin.document,
          origin.resourceId,
        );
      },
      set: (c, id, context) {
        final resources = context.resources;
        if (resources == null) {
          // Keep the authored reference so a save made while resources are
          // unavailable does not drop it.
          _pendingTextureRefs[c] = ResourceOrigin(context.document, id);
          return;
        }
        _pendingTextureRefs[c] = null;
        c.material.colorTexture = GpuTextureSource(resources.texture(id));
      },
    ),
  ];

  @override
  ParticleEmitterComponent create(PropertyReader props) =>
      ParticleEmitterComponent(
        system: particleSystemFromProperties(props.properties),
      );
}

/// Codec for a [MeshParticleEmitterComponent]: the shared [ParticleSystem]
/// configuration plus the instanced geometry variants and their material,
/// carried as resource references.
class MeshParticleEmitterCodec
    extends DeclarativeComponentCodec<MeshParticleEmitterComponent> {
  @override
  String get type => 'meshParticleEmitter';

  @override
  String? get category => 'Effects';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    category: category,
    icon: 'particles',
    properties: propertySchema,
    gizmo: const GizmoSpec([GizmoIcon()]),
  );

  // The realized geometries and material, stamped per component at realize
  // time; the component holds them privately, so serialize recovers the
  // references from these stamps (plus the origin tags the realizer left on
  // the resources themselves).
  // TODO(mesh-particles-hand-built): hand-built emitters carry no stamp, so
  // they do not serialize; expose geometry/material accessors on the
  // component and recover through resourceOrigin to lift that.
  static final Expando<List<Geometry>> _geometries = Expando(
    'mesh particle emitter geometries',
  );
  static final Expando<Material> _material = Expando(
    'mesh particle emitter material',
  );

  @override
  List<ComponentField<MeshParticleEmitterComponent>> get fields => [
    ComponentField(
      const ComponentPropertyDef(
        'geometries',
        ComponentPropertyKind.list,
        doc:
            'Geometry variants; each particle picks one for life by its '
            'per-particle random.',
        constraints: [MinCount(1)],
        itemDef: ComponentPropertyDef(
          'geometry',
          ComponentPropertyKind.resourceRef,
          resourceKind: 'geometry',
        ),
      ),
      read: (c, context) {
        final geometries = _geometries[c];
        if (geometries == null) return null;
        final refs = <PropertyValue>[];
        for (final geometry in geometries) {
          final origin = resourceOrigin(geometry);
          if (origin == null) {
            debugPrint(
              'fscene: meshParticleEmitter geometry not serialized (not '
              'realized from a document)',
            );
            continue;
          }
          refs.add(
            ResourceRefValue(
              copyResourceInto(
                context.document,
                origin.document,
                origin.resourceId,
              ),
            ),
          );
        }
        return refs.isEmpty ? null : ListValue(refs);
      },
    ),
    ComponentField.resourceRef(
      'material',
      resourceKind: 'material',
      doc: 'The material every geometry variant is shaded with.',
      get: (c, context) {
        final material = _material[c];
        if (material == null) return null;
        final origin = resourceOrigin(material);
        if (origin == null) return null;
        return copyResourceInto(
          context.document,
          origin.document,
          origin.resourceId,
        );
      },
    ),
    ComponentField.enumString(
      'facing',
      values: MeshParticleFacing.values,
      defaultValue: MeshParticleFacing.tumble,
      doc: 'How instances orient (tumble, or fly point-first).',
      get: (c) => c.facing,
      set: (c, v) => c.facing = v,
    ),
    ComponentField.boolean(
      'paused',
      defaultValue: false,
      doc: 'Hold the simulation (current particles keep rendering).',
      get: (c) => c.paused,
      set: (c, v) => c.paused = v,
    ),
    ...particleSystemFields<MeshParticleEmitterComponent>((c) => c.system),
  ];

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    if (context.resources == null ||
        _geometryIds(spec.properties).isEmpty ||
        spec.properties['material'] is! ResourceRefValue) {
      debugPrint(
        'fscene: meshParticleEmitter component skipped (missing geometries, '
        'material, or resource realizer)',
      );
      return null;
    }
    return super.realize(spec, context);
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! MeshParticleEmitterComponent) return null;
    if (_geometries[component] == null || _material[component] == null) {
      debugPrint(
        'fscene: meshParticleEmitter not serialized; its geometries and '
        'material are not recoverable',
      );
      return null;
    }
    return super.serialize(component, context);
  }

  @override
  MeshParticleEmitterComponent create(PropertyReader props) {
    // realize() guarded these.
    final resources = props.context.resources!;
    final geometries = [
      for (final id in _geometryIds(props.properties)) resources.geometry(id),
    ];
    final material = resources.material(props.resourceId('material')!);
    final component = MeshParticleEmitterComponent(
      system: particleSystemFromProperties(props.properties),
      geometries: geometries,
      material: material,
    );
    _geometries[component] = geometries;
    _material[component] = material;
    return component;
  }

  static List<LocalId> _geometryIds(Map<String, PropertyValue> properties) {
    final geometries = properties['geometries'];
    if (geometries is! ListValue) return const [];
    return [
      for (final entry in geometries.values)
        if (entry is ResourceRefValue) entry.id,
    ];
  }
}

// --- Small tolerant readers over MapValue/property bags ---

double _nonNegative(double value) => value < 0 ? 0 : value;

FloatDistribution _dist(
  Map<String, PropertyValue> p,
  String key,
  double fallback,
) => decodeFloatDistribution(p[key], fallback: fallback);
