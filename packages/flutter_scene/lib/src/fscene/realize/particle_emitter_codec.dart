import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/particle_emitter_component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/geometry/billboard_geometry.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_scene/src/material/sprite_material.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';

// Defaults shared by the schema (what an absent property falls back to) and the
// property->system builder, so the two never drift.
const int _kMaxParticles = 512;
const double _kEmitRate = 32.0;
const double _kLifetime = 1.5;
const double _kStartSpeed = 1.5;
const double _kStartSize = 0.3;
const String _kShapeType = 'cone';
const double _kShapeRadius = 0.25;
const double _kShapeAngle = 0.3;

/// Codec for a [ParticleEmitterComponent]: serializes the emitter's
/// [ParticleSystem] configuration, blend mode, billboard facing, and optional
/// texture into a `particleEmitter` component spec, and realizes it back into a
/// live emitter.
///
/// The schema exposes the common authoring knobs flatly, plus the
/// `distribution`, `curve`, and `gradient` property kinds for the per-particle
/// start values and the size/color-over-life shaping. The realize path builds a
/// pure [ParticleSystem] (see [particleSystemFromProperties]) and wraps it in a
/// billboard-rendering component.
///
/// TODO(particles-codec): bursts, per-axis box extents, sphere surface/
/// hemisphere flags, and arbitrary module stacks are not represented yet
/// (emitters using them serialize lossily); extend the schema as those become
/// editable.
class ParticleEmitterCodec extends ComponentCodec {
  @override
  String get type => 'particleEmitter';

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'maxParticles',
      ComponentPropertyKind.integer,
      const IntValue(_kMaxParticles),
      doc: 'Hard cap on simultaneous particles.',
      min: 1,
    ),
    ComponentPropertyDef(
      'emitRate',
      ComponentPropertyKind.number,
      const DoubleValue(_kEmitRate),
      doc: 'Steady emission rate in particles per second.',
      min: 0,
    ),
    ComponentPropertyDef(
      'shapeType',
      ComponentPropertyKind.string,
      const StringValue(_kShapeType),
      doc: 'Where particles spawn and which way they head.',
      options: const ['point', 'sphere', 'cone', 'box'],
    ),
    ComponentPropertyDef(
      'shapeRadius',
      ComponentPropertyKind.number,
      const DoubleValue(_kShapeRadius),
      doc: 'Sphere/cone radius, or box half-extent.',
      min: 0,
    ),
    ComponentPropertyDef(
      'shapeAngle',
      ComponentPropertyKind.number,
      const DoubleValue(_kShapeAngle),
      doc: 'Cone half-angle in radians.',
      min: 0,
    ),
    ComponentPropertyDef(
      'lifetime',
      ComponentPropertyKind.distribution,
      encodeFloatDistribution(const ConstantFloat(_kLifetime)),
      doc: 'Seconds each particle lives.',
    ),
    ComponentPropertyDef(
      'startSpeed',
      ComponentPropertyKind.distribution,
      encodeFloatDistribution(const ConstantFloat(_kStartSpeed)),
      doc: 'Initial speed along the emission direction.',
    ),
    ComponentPropertyDef(
      'startSize',
      ComponentPropertyKind.distribution,
      encodeFloatDistribution(const ConstantFloat(_kStartSize)),
      doc: 'Initial billboard size in world units.',
    ),
    ComponentPropertyDef(
      'startRotation',
      ComponentPropertyKind.distribution,
      encodeFloatDistribution(const ConstantFloat(0)),
      doc: 'Initial in-plane rotation in radians.',
    ),
    ComponentPropertyDef(
      'startAngularVelocity',
      ComponentPropertyKind.distribution,
      encodeFloatDistribution(const ConstantFloat(0)),
      doc: 'Initial rotation rate in radians per second.',
    ),
    ComponentPropertyDef(
      'sizeOverLife',
      ComponentPropertyKind.curve,
      encodeParticleCurve(ParticleCurve.constant(1.0)),
      doc: 'Size multiplier over normalized age.',
    ),
    ComponentPropertyDef(
      'colorOverLife',
      ComponentPropertyKind.gradient,
      encodeColorGradient(ColorGradient.constant(Vector4(1, 1, 1, 1))),
      doc: 'Color over normalized age.',
    ),
    ComponentPropertyDef(
      'drag',
      ComponentPropertyKind.number,
      const DoubleValue(0),
      doc: 'Linear drag coefficient (per second); 0 disables drag.',
      min: 0,
    ),
    ComponentPropertyDef(
      'gravity',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3.zero()),
      doc: 'Constant acceleration applied each step.',
    ),
    ComponentPropertyDef(
      'blendMode',
      ComponentPropertyKind.string,
      const StringValue('alpha'),
      doc: 'How particles composite into the scene.',
      options: const ['alpha', 'additive'],
    ),
    ComponentPropertyDef(
      'facing',
      ComponentPropertyKind.string,
      const StringValue('spherical'),
      doc: 'How billboards orient toward the camera.',
      options: const ['spherical', 'axisLocked', 'velocityStretched'],
    ),
    ComponentPropertyDef(
      'velocityStretch',
      ComponentPropertyKind.number,
      const DoubleValue(0),
      doc: 'Extra length per unit speed for velocity-stretched facing.',
      min: 0,
    ),
    ComponentPropertyDef(
      'looping',
      ComponentPropertyKind.boolean,
      const BoolValue(true),
      doc: 'Whether the emitter emits forever.',
    ),
    ComponentPropertyDef(
      'duration',
      ComponentPropertyKind.number,
      const DoubleValue(5.0),
      doc: 'Run length in seconds (emit cutoff when not looping).',
      min: 0,
    ),
    ComponentPropertyDef(
      'seed',
      ComponentPropertyKind.integer,
      const IntValue(0),
      doc: 'Seed for all spawn randomness.',
    ),
    ComponentPropertyDef(
      'texture',
      ComponentPropertyKind.resourceRef,
      null,
      doc: 'Sprite texture sampled per particle (optional).',
      resourceKind: 'texture',
    ),
  ];

  // The texture resource each realized emitter came from, so serialize can
  // recover the reference (the live material holds only the realized texture).
  static final Expando<LocalId> _textureId = Expando(
    'particle emitter texture',
  );

  @override
  bool claims(Component component) => component is ParticleEmitterComponent;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    final system = particleSystemFromProperties(p);
    final material = SpriteMaterial()
      ..blendMode = _blendFromName(_str(p, 'blendMode', 'alpha'));

    final textureRef = p['texture'];
    final resources = context.resources;
    if (textureRef is ResourceRefValue && resources != null) {
      material.colorTexture = GpuTextureSource(
        resources.texture(textureRef.id),
      );
    }

    final component =
        ParticleEmitterComponent(system: system, material: material)
          ..facing = _facingFromName(_str(p, 'facing', 'spherical'))
          ..velocityStretch = _num(p, 'velocityStretch', 0);
    if (textureRef is ResourceRefValue) {
      _textureId[component] = textureRef.id;
    }
    return component;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! ParticleEmitterComponent) return null;
    return ComponentSpec(
      type,
      properties: particleSystemToProperties(
        component.system,
        blendMode: component.material.blendMode,
        facing: component.facing,
        velocityStretch: component.velocityStretch,
        textureId: _textureId[component],
      ),
    );
  }
}

/// Builds a [ParticleSystem] from a `particleEmitter` spec's [properties].
///
/// Pure (no GPU), so it is unit-testable on its own; the codec wraps the result
/// in a [ParticleEmitterComponent]. Absent or malformed properties fall back to
/// the schema defaults.
ParticleSystem particleSystemFromProperties(
  Map<String, PropertyValue> properties,
) {
  return ParticleSystem(
    maxParticles: _int(properties, 'maxParticles', _kMaxParticles),
    shape: _shapeFromProperties(properties),
    spawner: Spawner(rate: _num(properties, 'emitRate', _kEmitRate)),
    modules: _modulesFromProperties(properties),
    lifetime: _dist(properties, 'lifetime', _kLifetime),
    startSpeed: _dist(properties, 'startSpeed', _kStartSpeed),
    startSize: _dist(properties, 'startSize', _kStartSize),
    startRotation: _dist(properties, 'startRotation', 0),
    startAngularVelocity: _dist(properties, 'startAngularVelocity', 0),
    gravity: _vec3(properties, 'gravity'),
    looping: _bool(properties, 'looping', true),
    duration: _num(properties, 'duration', 5.0),
    seed: _int(properties, 'seed', 0),
  );
}

/// Reads a [ParticleSystem] (plus the component-level [blendMode], [facing],
/// [velocityStretch], and optional [textureId]) back into a property map. The
/// inverse of [particleSystemFromProperties]; pure and unit-testable.
Map<String, PropertyValue> particleSystemToProperties(
  ParticleSystem system, {
  required SpriteBlendMode blendMode,
  required BillboardFacing facing,
  required double velocityStretch,
  LocalId? textureId,
}) {
  final size = _moduleOf<SizeOverLifeModule>(system.modules);
  final color = _moduleOf<ColorOverLifeModule>(system.modules);
  final drag = _moduleOf<LinearDragModule>(system.modules);

  final sizeCurve = size?.scale;
  final colorDist = color?.color;

  return {
    'maxParticles': IntValue(system.storage.capacity),
    'emitRate': DoubleValue(system.spawner.rate),
    'shapeType': StringValue(_shapeTypeName(system.shape)),
    'shapeRadius': DoubleValue(_shapeRadius(system.shape)),
    'shapeAngle': DoubleValue(_shapeAngle(system.shape)),
    'lifetime': encodeFloatDistribution(system.lifetime),
    'startSpeed': encodeFloatDistribution(system.startSpeed),
    'startSize': encodeFloatDistribution(system.startSize),
    'startRotation': encodeFloatDistribution(system.startRotation),
    'startAngularVelocity': encodeFloatDistribution(
      system.startAngularVelocity,
    ),
    'sizeOverLife': sizeCurve is CurveFloat
        ? encodeParticleCurve(sizeCurve.curve)
        : encodeParticleCurve(ParticleCurve.constant(1.0)),
    'colorOverLife': colorDist is GradientColor
        ? encodeColorGradient(colorDist.gradient)
        : encodeColorGradient(ColorGradient.constant(Vector4(1, 1, 1, 1))),
    'drag': DoubleValue(drag?.coefficient ?? 0.0),
    'gravity': Vec3Value(system.gravity.clone()),
    'blendMode': StringValue(
      blendMode == SpriteBlendMode.additive ? 'additive' : 'alpha',
    ),
    'facing': StringValue(facing.name),
    'velocityStretch': DoubleValue(velocityStretch),
    'looping': BoolValue(system.looping),
    'duration': DoubleValue(system.duration),
    'seed': IntValue(system.seed),
    if (textureId != null) 'texture': ResourceRefValue(textureId),
  };
}

EmitterShape _shapeFromProperties(Map<String, PropertyValue> p) {
  final radius = _num(p, 'shapeRadius', _kShapeRadius);
  final angle = _num(p, 'shapeAngle', _kShapeAngle);
  return switch (_str(p, 'shapeType', _kShapeType)) {
    'point' => PointShape(),
    'sphere' => SphereShape(radius: radius),
    'box' => BoxShape(halfExtents: Vector3.all(radius)),
    _ => ConeShape(angle: angle, radius: radius),
  };
}

List<ParticleModule> _modulesFromProperties(Map<String, PropertyValue> p) {
  final drag = _num(p, 'drag', 0);
  // An absent curve/gradient means "no shaping", not the decoders' empty-input
  // fallbacks (decodeParticleCurve(null) is a constant-zero curve, which would
  // shrink every particle to nothing). Apply the schema's semantic default
  // (size x1, opaque white) when the property is missing.
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
            : ColorGradient.constant(Vector4(1, 1, 1, 1)),
      ),
    ),
    const RotationModule(),
  ];
}

String _shapeTypeName(EmitterShape shape) => switch (shape) {
  PointShape() => 'point',
  SphereShape() => 'sphere',
  BoxShape() => 'box',
  ConeShape() => 'cone',
  _ => 'cone',
};

double _shapeRadius(EmitterShape shape) => switch (shape) {
  SphereShape(:final radius) => radius,
  ConeShape(:final radius) => radius,
  _ => _kShapeRadius,
};

double _shapeAngle(EmitterShape shape) =>
    shape is ConeShape ? shape.angle : _kShapeAngle;

T? _moduleOf<T extends ParticleModule>(List<ParticleModule> modules) {
  for (final module in modules) {
    if (module is T) return module;
  }
  return null;
}

SpriteBlendMode _blendFromName(String name) =>
    name == 'additive' ? SpriteBlendMode.additive : SpriteBlendMode.alpha;

BillboardFacing _facingFromName(String name) => switch (name) {
  'axisLocked' => BillboardFacing.axisLocked,
  'velocityStretched' => BillboardFacing.velocityStretched,
  _ => BillboardFacing.spherical,
};

double _num(Map<String, PropertyValue> p, String key, double fallback) {
  final v = p[key];
  return v is DoubleValue
      ? v.value
      : v is IntValue
      ? v.value.toDouble()
      : fallback;
}

int _int(Map<String, PropertyValue> p, String key, int fallback) {
  final v = p[key];
  return v is IntValue
      ? v.value
      : v is DoubleValue
      ? v.value.round()
      : fallback;
}

bool _bool(Map<String, PropertyValue> p, String key, bool fallback) {
  final v = p[key];
  return v is BoolValue ? v.value : fallback;
}

String _str(Map<String, PropertyValue> p, String key, String fallback) {
  final v = p[key];
  return v is StringValue ? v.value : fallback;
}

Vector3 _vec3(Map<String, PropertyValue> p, String key) {
  final v = p[key];
  return v is Vec3Value ? v.value.clone() : Vector3.zero();
}

FloatDistribution _dist(
  Map<String, PropertyValue> p,
  String key,
  double fallback,
) => decodeFloatDistribution(p[key], fallback: fallback);
