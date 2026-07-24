import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' hide Sphere;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart'
    show fmatSourcePathOf;
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/environment_volume_component.dart';
import 'package:flutter_scene/src/components/materials_variants_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/environment_settings.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/views.dart';
import 'package:flutter_scene/src/render_texture.dart';
import 'package:flutter_scene/src/fscene/realize/audio_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/particle_emitter_codec.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/realize/resource_copy.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/mesh.dart';

/// Registers the component codecs the format ships with (mesh, directional
/// light, camera) into [registry].
void registerBuiltinComponentCodecs(FsceneComponentRegistry registry) {
  registry
    // Registered before the mesh codec so serialize claims a particle emitter
    // (which subclasses the mesh component) before the mesh codec sees it.
    ..register(ParticleEmitterCodec())
    ..register(MeshCodec())
    ..register(MaterialsVariantsCodec())
    ..register(DirectionalLightCodec())
    ..register(PointLightCodec())
    ..register(SpotLightCodec())
    ..register(CameraCodec())
    ..register(EnvironmentVolumeCodec())
    ..register(AudioSourceCodec())
    ..register(AudioListenerCodec());
}

// The environment resource each realized volume came from, so serialize can
// recover the reference (the live component holds only the realized settings).
final Expando<LocalId> _volumeEnvironmentId = Expando(
  'environment volume source resource',
);

/// Codec for [EnvironmentVolumeComponent]. Realizes the look from a referenced
/// [EnvironmentResource] (preloaded by the resource realizer) and the region
/// from the local-space shape fields; the node transform places it.
class EnvironmentVolumeCodec extends ComponentCodec {
  @override
  String get type => 'environmentVolume';

  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'environment',
      ComponentPropertyKind.resourceRef,
      null,
      doc: 'The environment resource this volume blends toward.',
      resourceKind: 'environment',
    ),
    ComponentPropertyDef(
      'shape',
      ComponentPropertyKind.string,
      const StringValue('box'),
      doc: 'Region shape.',
      options: const ['box', 'sphere'],
    ),
    ComponentPropertyDef(
      'extents',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3.all(5)),
      doc: 'Box half-size in the node\'s local space.',
    ),
    ComponentPropertyDef(
      'radius',
      ComponentPropertyKind.number,
      const DoubleValue(5.0),
      doc: 'Sphere radius in the node\'s local space.',
      min: 0,
    ),
    ComponentPropertyDef(
      'blendDistance',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Local-space fade band outside the region.',
      min: 0,
    ),
    ComponentPropertyDef(
      'priority',
      ComponentPropertyKind.number,
      const DoubleValue(0.0),
      doc: 'Blend order; higher applies on top.',
    ),
    ComponentPropertyDef(
      'weight',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Master contribution scale.',
      min: 0,
      max: 1,
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) => component is EnvironmentVolumeComponent;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    final envProp = p['environment'];
    final envId = envProp is ResourceRefValue ? envProp.id : null;
    final settings =
        (envId == null ? null : context.resources?.environment(envId)) ??
        EnvironmentSettings();
    final shape = readString(p, 'shape', stringDefault('shape')) == 'sphere'
        ? EnvironmentVolumeShape.sphere
        : EnvironmentVolumeShape.box;
    final component = EnvironmentVolumeComponent(
      settings: settings,
      shape: shape,
      extents: readVec3(p, 'extents', vec3Default('extents')),
      radius: readDouble(p, 'radius', numberDefault('radius')),
      blendDistance: readDouble(
        p,
        'blendDistance',
        numberDefault('blendDistance'),
      ),
      priority: readDouble(p, 'priority', numberDefault('priority')),
      weight: readDouble(p, 'weight', numberDefault('weight')),
    );
    if (envId != null) _volumeEnvironmentId[component] = envId;
    return component;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! EnvironmentVolumeComponent) return null;
    final envId = _volumeEnvironmentId[component];
    return ComponentSpec(
      type,
      properties: {
        if (envId != null) 'environment': ResourceRefValue(envId),
        'shape': StringValue(component.shape.name),
        'extents': Vec3Value(component.extents.clone()),
        'radius': DoubleValue(component.radius),
        'blendDistance': DoubleValue(component.blendDistance),
        'priority': DoubleValue(component.priority),
        'weight': DoubleValue(component.weight),
      },
    );
  }
}

/// Codec for [MeshComponent]. Realizes a mesh from geometry/material resource
/// references through the context's resource realizer, and serializes a mesh
/// back by recovering the resources it was realized from.
///
/// A single primitive is carried as `geometry` and `material` references; a
/// multi-primitive mesh uses a `primitives` list of `{geometry, material}`
/// entries.
class MeshCodec extends ComponentCodec {
  @override
  String get type => 'mesh';

  // The single-primitive form. The multi-primitive `primitives` list is not yet
  // schema-described; editing it stays a TODO(mesh-multiprimitive).
  @override
  List<ComponentPropertyDef> get propertySchema => const [
    ComponentPropertyDef(
      'geometry',
      ComponentPropertyKind.resourceRef,
      null,
      doc: 'The geometry resource this mesh draws.',
      resourceKind: 'geometry',
    ),
    ComponentPropertyDef(
      'material',
      ComponentPropertyKind.resourceRef,
      null,
      doc: 'The material the geometry is drawn with.',
      resourceKind: 'material',
    ),
  ];

  @override
  bool claims(Component component) => component is MeshComponent;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final realizer = context.resources;
    if (realizer == null) {
      debugPrint('fscene: mesh component skipped (no resource realizer)');
      return null;
    }
    final pairs = _primitivePairs(spec);
    if (pairs.isEmpty) {
      debugPrint('fscene: mesh component has no geometry/material references');
      return null;
    }
    return MeshComponent(
      Mesh.primitives(
        primitives: [
          for (final (geometryId, materialId) in pairs)
            MeshPrimitive(
              realizer.geometry(geometryId),
              realizer.material(materialId),
            ),
        ],
      ),
    );
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! MeshComponent) return null;
    final pairs = <(LocalId, LocalId)>[];
    for (final primitive in component.mesh.primitives) {
      final geometryId = _serializeResource(primitive.geometry, context);
      final materialId = _serializeResource(primitive.material, context);
      if (geometryId == null || materialId == null) {
        debugPrint(
          'fscene: mesh primitive not serialized; its geometry or material '
          'is not recoverable (see the warnings above)',
        );
        continue;
      }
      pairs.add((geometryId, materialId));
    }
    if (pairs.isEmpty) return null;
    if (pairs.length == 1) {
      return ComponentSpec(
        type,
        properties: {
          'geometry': ResourceRefValue(pairs.first.$1),
          'material': ResourceRefValue(pairs.first.$2),
        },
      );
    }
    return ComponentSpec(
      type,
      properties: {
        'primitives': ListValue([
          for (final (geometryId, materialId) in pairs)
            MapValue({
              'geometry': ResourceRefValue(geometryId),
              'material': ResourceRefValue(materialId),
            }),
        ]),
      },
    );
  }

  // Reads the mesh's primitive references, accepting both the single-primitive
  // shorthand (`geometry`/`material`) and the `primitives` list.
  List<(LocalId, LocalId)> _primitivePairs(ComponentSpec spec) {
    final primitives = spec.properties['primitives'];
    if (primitives is ListValue) {
      final out = <(LocalId, LocalId)>[];
      for (final entry in primitives.values) {
        if (entry is MapValue) {
          final pair = _pair(entry.values);
          if (pair != null) out.add(pair);
        }
      }
      return out;
    }
    final pair = _pair(spec.properties);
    return pair == null ? const [] : [pair];
  }

  (LocalId, LocalId)? _pair(Map<String, PropertyValue> props) {
    final geometry = props['geometry'];
    final material = props['material'];
    if (geometry is ResourceRefValue && material is ResourceRefValue) {
      return (geometry.id, material.id);
    }
    return null;
  }

  // Serializes a live geometry or material into the destination document.
  // Realizer-produced objects are recovered from their origin tags; hand-built
  // ones are re-packed from their retained data: a MeshGeometry's interleaved
  // streams, a parameter material's factor fields, or an fmat material's
  // source path plus assigned parameters. Caller-managed buffers (a raw
  // Geometry with setVertices) are not recoverable.
  LocalId? _serializeResource(Object live, SerializeContext context) {
    final dest = context.document;
    final origin = resourceOrigin(live);
    if (origin != null) {
      return copyResourceInto(dest, origin.document, origin.resourceId);
    }
    final cached = context.serializedResources[live];
    if (cached != null) return cached;
    LocalId? id;
    if (live is MeshGeometry) {
      id = _serializeMeshGeometry(live, dest);
    } else if (live is PreprocessedMaterial) {
      id = _serializeFmat(live, context);
    } else if (live is PhysicallyBasedMaterial) {
      id = _serializePbr(live, context);
    } else if (live is UnlitMaterial) {
      id = _serializeUnlit(live, context);
    }
    if (id != null) context.serializedResources[live] = id;
    return id;
  }

  LocalId? _serializeMeshGeometry(MeshGeometry geometry, SceneDocument dest) {
    // Emit the de-interleaved (structure-of-arrays) vertex payload so the
    // realizer uploads each attribute straight to its GPU buffer.
    final packed = geometry.soaData;
    final vertices = dest.addPayload(
      PayloadSpec(
        dest.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: InterleavedLayoutAdapter.unskinnedSoaLayout,
        length: packed.vertexBytes.length,
        bytes: packed.vertexBytes,
      ),
    );
    LocalId? indices;
    final indexBytes = packed.indexBytes;
    if (indexBytes != null) {
      indices = dest
          .addPayload(
            PayloadSpec(
              dest.newId(),
              encoding: PayloadEncoding.indexBuffer,
              format: packed.indices32Bit ? 'uint32' : 'uint16',
              length: indexBytes.length,
              bytes: indexBytes,
            ),
          )
          .id;
    }
    final bounds = geometry.localBounds;
    return dest
        .addResource(
          GeometryResource(
            dest.newId(),
            vertices: vertices.id,
            indices: indices,
            bounds: bounds == null
                ? null
                : BoundsSpec(min: bounds.min.clone(), max: bounds.max.clone()),
            topology: geometry.primitiveType.name,
          ),
        )
        .id;
  }

  LocalId? _serializeFmat(PreprocessedMaterial m, SerializeContext context) {
    final sourcePath = fmatSourcePathOf(m);
    if (sourcePath == null) {
      debugPrint(
        'fscene: an fmat material with no known source path cannot be '
        'serialized; load materials with loadFmatMaterial',
      );
      return null;
    }
    return context.document
        .addResource(
          MaterialResource(
            context.document.newId(),
            type: 'fmat',
            asset: AssetRef(sourcePath),
            properties: serializeFmatParameterOverrides(
              m.parameters.assignedValues,
              resolveTexture: (texture) => _serializeTexture(texture, context),
            ),
          ),
        )
        .id;
  }

  LocalId? _serializePbr(PhysicallyBasedMaterial m, SerializeContext context) {
    final properties = <String, PropertyValue>{
      'baseColor': _color(m.baseColorFactor),
      'emissive': _color(m.emissiveFactor),
      'metallic': DoubleValue(m.metallicFactor),
      'roughness': DoubleValue(m.roughnessFactor),
      'occlusionStrength': DoubleValue(m.occlusionStrength),
      'normalScale': DoubleValue(m.normalScale),
      'doubleSided': BoolValue(m.doubleSided),
      'alphaMode': StringValue(m.alphaMode.name),
      'alphaCutoff': DoubleValue(m.alphaCutoff),
    };
    _textureProperty(
      properties,
      'baseColorTexture',
      m.baseColorTextureSource,
      context,
    );
    _textureProperty(
      properties,
      'metallicRoughnessTexture',
      m.metallicRoughnessTextureSource,
      context,
    );
    _textureProperty(
      properties,
      'normalTexture',
      m.normalTextureSource,
      context,
    );
    _textureProperty(
      properties,
      'occlusionTexture',
      m.occlusionTextureSource,
      context,
    );
    _textureProperty(
      properties,
      'emissiveTexture',
      m.emissiveTextureSource,
      context,
    );
    return context.document
        .addResource(
          MaterialResource(
            context.document.newId(),
            type: 'physicallyBased',
            properties: properties,
          ),
        )
        .id;
  }

  LocalId? _serializeUnlit(UnlitMaterial m, SerializeContext context) {
    final properties = <String, PropertyValue>{
      'baseColor': _color(m.baseColorFactor),
      'doubleSided': BoolValue(m.doubleSided),
    };
    _textureProperty(
      properties,
      'baseColorTexture',
      m.baseColorTextureSource,
      context,
    );
    return context.document
        .addResource(
          MaterialResource(
            context.document.newId(),
            type: 'unlit',
            properties: properties,
          ),
        )
        .id;
  }

  ColorValue _color(Vector4 v) => ColorValue(v.x, v.y, v.z, v.w);

  // [source] is the slot's raw value: a gpu.Texture, a live RenderTexture
  // (serialized from its live state by id), or null.
  void _textureProperty(
    Map<String, PropertyValue> properties,
    String key,
    Object? source,
    SerializeContext context,
  ) {
    if (source == null) return;
    if (source is RenderTexture) {
      properties[key] = ResourceRefValue(
        serializeRenderTexture(source, context),
      );
      return;
    }
    final id = _serializeTexture(source as gpu.Texture, context);
    if (id == null) {
      debugPrint('fscene: material texture "$key" not serialized');
      return;
    }
    properties[key] = ResourceRefValue(id);
  }

  // A texture is recoverable only when the realizer produced it (origin tag);
  // hand-uploaded textures carry no source to re-emit.
  LocalId? _serializeTexture(gpu.Texture texture, SerializeContext context) {
    final origin = resourceOrigin(texture);
    if (origin == null) return null;
    return copyResourceInto(
      context.document,
      origin.document,
      origin.resourceId,
    );
  }
}

/// Codec for [DirectionalLightComponent]: serializes the light's parameters,
/// including its local direction (the node transform orients it at render
/// time).
class DirectionalLightCodec extends ComponentCodec {
  @override
  String get type => 'directionalLight';

  // Declared in serialize order so the derived serialize matches the format's
  // existing key order (byte-stable round-trips). Defaults are the single source
  // for realize's fallbacks.
  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'direction',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3(-0.3, -1.0, -0.2)),
      doc: 'Light direction in the node\'s local space.',
      read: (c) =>
          Vec3Value((c as DirectionalLightComponent).light.direction.clone()),
    ),
    ComponentPropertyDef(
      'color',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3(1, 1, 1)),
      doc: 'Linear RGB light color.',
      read: (c) =>
          Vec3Value((c as DirectionalLightComponent).light.color.clone()),
    ),
    ComponentPropertyDef(
      'intensity',
      ComponentPropertyKind.number,
      const DoubleValue(3.0),
      doc: 'Light brightness.',
      min: 0,
      read: (c) =>
          DoubleValue((c as DirectionalLightComponent).light.intensity),
    ),
    ComponentPropertyDef(
      'castsShadow',
      ComponentPropertyKind.boolean,
      const BoolValue(false),
      doc: 'Whether this light renders a shadow map.',
      read: (c) =>
          BoolValue((c as DirectionalLightComponent).light.castsShadow),
    ),
    ComponentPropertyDef(
      'shadowFadeRange',
      ComponentPropertyKind.number,
      const DoubleValue(2.0),
      doc: 'Distance over which shadows fade out.',
      min: 0,
      read: (c) =>
          DoubleValue((c as DirectionalLightComponent).light.shadowFadeRange),
    ),
    ComponentPropertyDef(
      'shadowSoftness',
      ComponentPropertyKind.number,
      const DoubleValue(0.08),
      doc: 'Shadow edge softness.',
      min: 0,
      read: (c) =>
          DoubleValue((c as DirectionalLightComponent).light.shadowSoftness),
    ),
    ComponentPropertyDef(
      'shadowCascadeCount',
      ComponentPropertyKind.integer,
      const IntValue(4),
      doc: 'Number of shadow cascades.',
      min: 1,
      read: (c) =>
          IntValue((c as DirectionalLightComponent).light.shadowCascadeCount),
    ),
    ComponentPropertyDef(
      'shadowMaxDistance',
      ComponentPropertyKind.number,
      const DoubleValue(150.0),
      doc: 'Far distance shadows are rendered to.',
      min: 0,
      read: (c) =>
          DoubleValue((c as DirectionalLightComponent).light.shadowMaxDistance),
    ),
    ComponentPropertyDef(
      'shadowCascadeSplitLambda',
      ComponentPropertyKind.number,
      const DoubleValue(0.6),
      doc: 'Blend between uniform and logarithmic cascade splits.',
      min: 0,
      max: 1,
      read: (c) => DoubleValue(
        (c as DirectionalLightComponent).light.shadowCascadeSplitLambda,
      ),
    ),
    ComponentPropertyDef(
      'shadowMapResolution',
      ComponentPropertyKind.integer,
      const IntValue(1024),
      doc: 'Shadow map resolution per cascade, in texels.',
      min: 1,
      read: (c) =>
          IntValue((c as DirectionalLightComponent).light.shadowMapResolution),
    ),
    ComponentPropertyDef(
      'shadowDepthBias',
      ComponentPropertyKind.number,
      const DoubleValue(0.02),
      doc: 'Depth bias applied when sampling the shadow map.',
      read: (c) =>
          DoubleValue((c as DirectionalLightComponent).light.shadowDepthBias),
    ),
    ComponentPropertyDef(
      'shadowNormalBias',
      ComponentPropertyKind.number,
      const DoubleValue(0.02),
      doc: 'Normal bias applied when sampling the shadow map.',
      read: (c) =>
          DoubleValue((c as DirectionalLightComponent).light.shadowNormalBias),
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) => component is DirectionalLightComponent;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return DirectionalLightComponent(
      DirectionalLight(
        direction: readVec3(p, 'direction', vec3Default('direction')),
        color: readVec3(p, 'color', vec3Default('color')),
        intensity: readDouble(p, 'intensity', numberDefault('intensity')),
        castsShadow: readBool(p, 'castsShadow', boolDefault('castsShadow')),
        shadowFadeRange: readDouble(
          p,
          'shadowFadeRange',
          numberDefault('shadowFadeRange'),
        ),
        shadowSoftness: readDouble(
          p,
          'shadowSoftness',
          numberDefault('shadowSoftness'),
        ),
        shadowCascadeCount: readInt(
          p,
          'shadowCascadeCount',
          intDefault('shadowCascadeCount'),
        ),
        shadowMaxDistance: readDouble(
          p,
          'shadowMaxDistance',
          numberDefault('shadowMaxDistance'),
        ),
        shadowCascadeSplitLambda: readDouble(
          p,
          'shadowCascadeSplitLambda',
          numberDefault('shadowCascadeSplitLambda'),
        ),
        shadowMapResolution: readInt(
          p,
          'shadowMapResolution',
          intDefault('shadowMapResolution'),
        ),
        shadowDepthBias: readDouble(
          p,
          'shadowDepthBias',
          numberDefault('shadowDepthBias'),
        ),
        shadowNormalBias: readDouble(
          p,
          'shadowNormalBias',
          numberDefault('shadowNormalBias'),
        ),
      ),
    );
  }
}

/// Codec for [PointLightComponent].
class PointLightCodec extends ComponentCodec {
  @override
  String get type => 'pointLight';

  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'color',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3(1, 1, 1)),
      doc: 'Linear RGB light color.',
      read: (c) => Vec3Value((c as PointLightComponent).light.color.clone()),
    ),
    ComponentPropertyDef(
      'intensity',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Light brightness (radiance at unit distance).',
      min: 0,
      read: (c) => DoubleValue((c as PointLightComponent).light.intensity),
    ),
    ComponentPropertyDef(
      'range',
      ComponentPropertyKind.number,
      const DoubleValue(0.0),
      doc: 'Distance the light reaches, or 0 for infinite range.',
      min: 0,
      read: (c) => DoubleValue((c as PointLightComponent).light.range),
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) => component is PointLightComponent;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return PointLightComponent(
      PointLight(
        color: readVec3(p, 'color', vec3Default('color')),
        intensity: readDouble(p, 'intensity', numberDefault('intensity')),
        range: readDouble(p, 'range', numberDefault('range')),
      ),
    );
  }
}

/// Codec for [SpotLightComponent].
class SpotLightCodec extends ComponentCodec {
  @override
  String get type => 'spotLight';

  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'direction',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3(0, -1, 0)),
      doc: 'Cone aim in the node\'s local space.',
      read: (c) => Vec3Value((c as SpotLightComponent).light.direction.clone()),
    ),
    ComponentPropertyDef(
      'color',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3(1, 1, 1)),
      doc: 'Linear RGB light color.',
      read: (c) => Vec3Value((c as SpotLightComponent).light.color.clone()),
    ),
    ComponentPropertyDef(
      'intensity',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Light brightness (radiance at unit distance).',
      min: 0,
      read: (c) => DoubleValue((c as SpotLightComponent).light.intensity),
    ),
    ComponentPropertyDef(
      'range',
      ComponentPropertyKind.number,
      const DoubleValue(0.0),
      doc: 'Distance the light reaches, or 0 for infinite range.',
      min: 0,
      read: (c) => DoubleValue((c as SpotLightComponent).light.range),
    ),
    ComponentPropertyDef(
      'innerConeAngle',
      ComponentPropertyKind.number,
      const DoubleValue(0.0),
      doc: 'Half-angle (radians) of the full-brightness inner cone.',
      min: 0,
      read: (c) => DoubleValue((c as SpotLightComponent).light.innerConeAngle),
    ),
    ComponentPropertyDef(
      'outerConeAngle',
      ComponentPropertyKind.number,
      const DoubleValue(0.7853981633974483),
      doc: 'Half-angle (radians) at which the cone falls to zero.',
      min: 0,
      read: (c) => DoubleValue((c as SpotLightComponent).light.outerConeAngle),
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) => component is SpotLightComponent;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return SpotLightComponent(
      SpotLight(
        direction: readVec3(p, 'direction', vec3Default('direction')),
        color: readVec3(p, 'color', vec3Default('color')),
        intensity: readDouble(p, 'intensity', numberDefault('intensity')),
        range: readDouble(p, 'range', numberDefault('range')),
        innerConeAngle: readDouble(
          p,
          'innerConeAngle',
          numberDefault('innerConeAngle'),
        ),
        outerConeAngle: readDouble(
          p,
          'outerConeAngle',
          numberDefault('outerConeAngle'),
        ),
      ),
    );
  }
}

/// Codec for [CameraComponent]. Handles perspective projections; the node
/// transform supplies the view.
// TODO(fscene): serialize orthographic and off-axis projections once they
// exist on CameraProjection.
class CameraCodec extends ComponentCodec {
  @override
  String get type => 'camera';

  // Declared in serialize order. Only perspective projections are claimed; an
  // orthographic projection (none exists yet) is not serialized.
  // TODO(fscene): describe orthographic/off-axis projections once they exist.
  static final List<ComponentPropertyDef> _schema = [
    const ComponentPropertyDef(
      'projection',
      ComponentPropertyKind.string,
      StringValue('perspective'),
      doc: 'The projection model.',
      options: ['perspective'],
      read: _readProjection,
    ),
    ComponentPropertyDef(
      'fovRadiansY',
      ComponentPropertyKind.number,
      DoubleValue(45 * degrees2Radians),
      doc: 'Vertical field of view, in radians.',
      min: 0,
      read: (c) => DoubleValue(_perspective(c).fovRadiansY),
    ),
    const ComponentPropertyDef(
      'near',
      ComponentPropertyKind.number,
      DoubleValue(0.1),
      doc: 'Near clip distance.',
      min: 0,
      read: _readNear,
    ),
    const ComponentPropertyDef(
      'far',
      ComponentPropertyKind.number,
      DoubleValue(1000.0),
      doc: 'Far clip distance.',
      min: 0,
      read: _readFar,
    ),
  ];

  static PerspectiveProjection _perspective(Component c) =>
      (c as CameraComponent).projection as PerspectiveProjection;
  static PropertyValue _readProjection(Component c) =>
      const StringValue('perspective');
  static PropertyValue _readNear(Component c) =>
      DoubleValue(_perspective(c).near);
  static PropertyValue _readFar(Component c) =>
      DoubleValue(_perspective(c).far);

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) =>
      component is CameraComponent &&
      component.projection is PerspectiveProjection;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return CameraComponent(
      projection: PerspectiveProjection(
        fovRadiansY: readDouble(p, 'fovRadiansY', numberDefault('fovRadiansY')),
        near: readDouble(p, 'near', numberDefault('near')),
        far: readDouble(p, 'far', numberDefault('far')),
      ),
    );
  }
}

/// Codec for [MaterialsVariantsComponent] (`KHR_materials_variants`).
///
/// Spec shape:
///
/// ```text
/// variants: [String, ...]                    variant names, in order
/// selected: String                           active variant, absent = default
/// bindings: [{node: NodeRef,                 the node whose mesh is bound
///             primitive: int,                index into the mesh's primitives
///             default: ResourceRef,          the default material
///             materials: {"<variantIndex>": ResourceRef, ...}}, ...]
/// ```
///
/// The default material is serialized explicitly so a document saved while a
/// variant is selected keeps its authored defaults (the mesh's serialized
/// material is the selected one in that case); documents without a `default`
/// entry fall back to the mesh primitive's realized material. The selection
/// itself round-trips through `selected`. Bindings resolve after the whole
/// tree realizes (they reference other nodes' mesh components), through
/// [RealizeContext.afterRealize].
class MaterialsVariantsCodec extends ComponentCodec {
  @override
  String get type => 'materialsVariants';

  // TODO(materials-variants-schema): the nested bindings list is not
  // schema-described (like the mesh codec's multi-primitive form), so the
  // editor inspector cannot edit it; describe it once the schema system
  // grows nested-list support.
  @override
  List<ComponentPropertyDef> get propertySchema => const [];

  // Shares the mesh codec's resource-recovery path (origin tags, hand-built
  // re-packing) for the variant materials.
  static final MeshCodec _resourceSerializer = MeshCodec();

  @override
  bool claims(Component component) => component is MaterialsVariantsComponent;

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final realizer = context.resources;
    if (realizer == null) {
      debugPrint(
        'fscene: materialsVariants component skipped (no resource realizer)',
      );
      return null;
    }
    final variants = <String>[
      for (final value in _stringList(spec.properties['variants'])) value,
    ];
    final rawBindings = spec.properties['bindings'];
    final selectedProp = spec.properties['selected'];
    final selected = selectedProp is StringValue ? selectedProp.value : null;
    final bindings = <MaterialsVariantBinding>[];
    final component = MaterialsVariantsComponent.internal(variants, bindings);
    context.afterRealize.add(() {
      final resolveNode = context.resolveNode;
      if (resolveNode == null) {
        debugPrint(
          'fscene: materialsVariants bindings unresolved (no node resolver)',
        );
        return;
      }
      if (rawBindings is ListValue) {
        for (final entry in rawBindings.values) {
          if (entry is! MapValue) continue;
          final nodeRef = entry.values['node'];
          final primitiveIndex = entry.values['primitive'];
          final materials = entry.values['materials'];
          final defaultRef = entry.values['default'];
          if (nodeRef is! NodeRefValue ||
              primitiveIndex is! IntValue ||
              materials is! MapValue) {
            continue;
          }
          final node = resolveNode(nodeRef.id);
          final mesh = node?.mesh;
          if (node == null ||
              mesh == null ||
              primitiveIndex.value < 0 ||
              primitiveIndex.value >= mesh.primitives.length) {
            debugPrint(
              'fscene: materialsVariants binding dropped (missing node or '
              'primitive ${primitiveIndex.value})',
            );
            continue;
          }
          // The serialized default keeps authored defaults stable across
          // saves and reloads made while a variant was selected; older
          // documents without one fall back to the realized mesh material.
          final defaultMaterial = defaultRef is ResourceRefValue
              ? realizer.material(defaultRef.id)
              : mesh.primitives[primitiveIndex.value].material;
          final materialsByVariant = <int, Material>{};
          for (final mapping in materials.values.entries) {
            final variantIndex = int.tryParse(mapping.key);
            final ref = mapping.value;
            if (variantIndex == null || ref is! ResourceRefValue) continue;
            materialsByVariant[variantIndex] = realizer.material(ref.id);
          }
          bindings.add(
            MaterialsVariantBinding(
              node: node,
              primitiveIndex: primitiveIndex.value,
              defaultMaterial: defaultMaterial,
              materialsByVariant: materialsByVariant,
            ),
          );
        }
      }
      if (selected != null && variants.contains(selected)) {
        component.select(selected);
      } else {
        // Bindings may target primitives that currently carry a stale
        // material (a reload while selected); re-apply the defaults.
        component.reapply();
      }
    });
    return component;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! MaterialsVariantsComponent) return null;
    final bindings = <PropertyValue>[];
    for (final binding in component.internalBindings) {
      final nodeId = nodeFsceneId(binding.node);
      if (nodeId == null || binding.resolvePrimitive() == null) {
        debugPrint(
          'fscene: materialsVariants binding not serialized; its node was '
          'not realized from this document',
        );
        continue;
      }
      final materials = <String, PropertyValue>{};
      for (final entry in binding.materialsByVariant.entries) {
        final materialId = _resourceSerializer._serializeResource(
          entry.value,
          context,
        );
        if (materialId == null) continue;
        materials['${entry.key}'] = ResourceRefValue(materialId);
      }
      final defaultId = _resourceSerializer._serializeResource(
        binding.defaultMaterial,
        context,
      );
      bindings.add(
        MapValue({
          'node': NodeRefValue(nodeId),
          'primitive': IntValue(binding.primitiveIndex),
          if (defaultId != null) 'default': ResourceRefValue(defaultId),
          'materials': MapValue(materials),
        }),
      );
    }
    final selected = component.selected;
    return ComponentSpec(
      type,
      properties: {
        'variants': ListValue([
          for (final name in component.variants) StringValue(name),
        ]),
        if (selected != null) 'selected': StringValue(selected),
        'bindings': ListValue(bindings),
      },
    );
  }

  static List<String> _stringList(PropertyValue? value) => [
    if (value is ListValue)
      for (final entry in value.values)
        if (entry is StringValue) entry.value,
  ];
}
