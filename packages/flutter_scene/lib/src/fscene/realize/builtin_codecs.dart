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
import 'package:flutter_scene/src/components/rect_area_light_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/environment_settings.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/views.dart';
import 'package:flutter_scene/src/render_texture.dart';
import 'package:flutter_scene/src/fscene/realize/audio_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/physics_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/fscene/realize/particle_emitter_codec.dart';
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
    ..register(MeshParticleEmitterCodec())
    ..register(MeshCodec())
    ..register(MaterialsVariantsCodec())
    ..register(DirectionalLightCodec())
    ..register(PointLightCodec())
    ..register(RectAreaLightCodec())
    ..register(SpotLightCodec())
    ..register(CameraCodec())
    ..register(EnvironmentVolumeCodec())
    ..register(AudioSourceCodec())
    ..register(AudioListenerCodec());
  registerPhysicsComponentCodecs(registry);
}

/// Codec for [EnvironmentVolumeComponent]. Realizes the look from a referenced
/// [EnvironmentResource] (preloaded by the resource realizer, which stamps the
/// realized settings with their origin so serialize can recover the
/// reference) and the region from the local-space shape fields; the node
/// transform places it.
class EnvironmentVolumeCodec
    extends DeclarativeComponentCodec<EnvironmentVolumeComponent> {
  @override
  String get type => 'environmentVolume';

  @override
  List<ComponentField<EnvironmentVolumeComponent>> get fields => [
    ComponentField.resourceRef(
      'environment',
      resourceKind: 'environment',
      doc: 'The environment resource this volume blends toward.',
      get: (c, _) => resourceOrigin(c.settings)?.resourceId,
      set: (c, id, context) {
        final settings = context.resources?.environment(id);
        if (settings != null) c.settings = settings;
      },
    ),
    ComponentField.enumString(
      'shape',
      values: EnvironmentVolumeShape.values,
      defaultValue: EnvironmentVolumeShape.box,
      doc: 'Region shape.',
      get: (c) => c.shape,
      set: (c, v) => c.shape = v,
    ),
    ComponentField.vec3(
      'extents',
      defaultValue: () => Vector3.all(5),
      doc: 'Box half-size in the node\'s local space.',
      get: (c) => c.extents,
      set: (c, v) => c.extents = v,
    ),
    ComponentField.number(
      'radius',
      defaultValue: 5.0,
      doc: 'Sphere radius in the node\'s local space.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.radius,
      set: (c, v) => c.radius = v,
    ),
    ComponentField.number(
      'blendDistance',
      defaultValue: 1.0,
      doc: 'Local-space fade band outside the region.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.blendDistance,
      set: (c, v) => c.blendDistance = v,
    ),
    ComponentField.number(
      'priority',
      defaultValue: 0.0,
      doc: 'Blend order; higher applies on top.',
      get: (c) => c.priority,
      set: (c, v) => c.priority = v,
    ),
    ComponentField.number(
      'weight',
      defaultValue: 1.0,
      doc: 'Master contribution scale.',
      constraints: const [Range(0, 1), SoftRange(0, 1)],
      get: (c) => c.weight,
      set: (c, v) => c.weight = v,
    ),
  ];

  @override
  EnvironmentVolumeComponent create(PropertyReader props) {
    final envId = props.resourceId('environment');
    final settings =
        (envId == null ? null : props.context.resources?.environment(envId)) ??
        EnvironmentSettings();
    return EnvironmentVolumeComponent(settings: settings);
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

  // The single-primitive form, plus the multi-primitive `primitives` list
  // described as a list of {geometry, material} pairs.
  @override
  List<ComponentPropertyDef> get propertySchema => const [
    ComponentPropertyDef(
      'geometry',
      ComponentPropertyKind.resourceRef,
      doc: 'The geometry resource this mesh draws.',
      resourceKind: 'geometry',
    ),
    ComponentPropertyDef(
      'material',
      ComponentPropertyKind.resourceRef,
      doc: 'The material the geometry is drawn with.',
      resourceKind: 'material',
    ),
    ComponentPropertyDef(
      'primitives',
      ComponentPropertyKind.list,
      doc:
          'Geometry/material pairs for a multi-primitive mesh (replaces the '
          'single geometry/material form when present).',
      itemDef: ComponentPropertyDef(
        'primitive',
        ComponentPropertyKind.object,
        objectFields: [
          ComponentPropertyDef(
            'geometry',
            ComponentPropertyKind.resourceRef,
            resourceKind: 'geometry',
          ),
          ComponentPropertyDef(
            'material',
            ComponentPropertyKind.resourceRef,
            resourceKind: 'material',
          ),
        ],
      ),
    ),
  ];

  @override
  Type get componentType => MeshComponent;

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
            properties: {
              ...serializeFmatParameterOverrides(
                m.parameters.assignedValues,
                resolveTexture: (texture) =>
                    _serializeTexture(texture, context),
              ),
              if (m.depthBias != 0) 'depthBias': DoubleValue(m.depthBias),
            },
          ),
        )
        .id;
  }

  LocalId? _serializePbr(PhysicallyBasedMaterial m, SerializeContext context) {
    final physical = m.hasPhysicalConfiguration;
    final properties = <String, PropertyValue>{
      'baseColor': _color(m.baseColorFactor),
      'emissive': _color(m.emissiveFactor),
      'emissiveStrength': DoubleValue(m.emissiveStrength),
      'metallic': DoubleValue(m.metallicFactor),
      'roughness': DoubleValue(m.roughnessFactor),
      'occlusionStrength': DoubleValue(m.occlusionStrength),
      'normalScale': DoubleValue(m.normalScale),
      'doubleSided': BoolValue(m.doubleSided),
      'alphaMode': StringValue(m.alphaMode.name),
      'alphaCutoff': DoubleValue(m.alphaCutoff),
      if (m.depthBias != 0) 'depthBias': DoubleValue(m.depthBias),
      if (physical) ...{
        'specular': DoubleValue(m.specular),
        'specularColor': _color(m.specularColor),
        'ior': DoubleValue(m.ior),
        'clearcoat': DoubleValue(m.clearcoat),
        'clearcoatRoughness': DoubleValue(m.clearcoatRoughness),
        'clearcoatNormalScale': Vec2Value(m.clearcoatNormalScale.clone()),
        'sheenColor': _color(m.sheenColor),
        'sheenRoughness': DoubleValue(m.sheenRoughness),
        'transmission': DoubleValue(m.transmission),
        'diffuseTransmission': DoubleValue(m.diffuseTransmission),
        'diffuseTransmissionColor': _color(m.diffuseTransmissionColor),
        'thickness': DoubleValue(m.thickness),
        'attenuationDistance': DoubleValue(m.attenuationDistance),
        'attenuationColor': _color(m.attenuationColor),
        'dispersion': DoubleValue(m.dispersion),
        'iridescence': DoubleValue(m.iridescence),
        'iridescenceIor': DoubleValue(m.iridescenceIor),
        'iridescenceThicknessMinimum': DoubleValue(
          m.iridescenceThicknessMinimum,
        ),
        'iridescenceThicknessMaximum': DoubleValue(
          m.iridescenceThicknessMaximum,
        ),
        'anisotropy': DoubleValue(m.anisotropy),
        'anisotropyRotation': DoubleValue(m.anisotropyRotation),
      },
    };
    _textureProperty(
      properties,
      'baseColorTexture',
      m.baseColorTextureSource,
      context,
    );
    _textureTransformProperty(
      properties,
      'baseColorTextureTransform',
      m.baseColorTextureTransform,
      m.baseColorTextureTexCoord,
    );
    _textureProperty(
      properties,
      'metallicRoughnessTexture',
      m.metallicRoughnessTextureSource,
      context,
    );
    _textureTransformProperty(
      properties,
      'metallicRoughnessTextureTransform',
      m.metallicRoughnessTextureTransform,
      m.metallicRoughnessTextureTexCoord,
    );
    _textureProperty(
      properties,
      'normalTexture',
      m.normalTextureSource,
      context,
    );
    _textureTransformProperty(
      properties,
      'normalTextureTransform',
      m.normalTextureTransform,
      m.normalTextureTexCoord,
    );
    _textureProperty(
      properties,
      'occlusionTexture',
      m.occlusionTextureSource,
      context,
    );
    _textureTransformProperty(
      properties,
      'occlusionTextureTransform',
      m.occlusionTextureTransform,
      m.occlusionTextureTexCoord,
    );
    _textureProperty(
      properties,
      'emissiveTexture',
      m.emissiveTextureSource,
      context,
    );
    _textureTransformProperty(
      properties,
      'emissiveTextureTransform',
      m.emissiveTextureTransform,
      m.emissiveTextureTexCoord,
    );
    if (physical) {
      _physicalTextureProperty(
        properties,
        'specularTexture',
        m.specularTexture,
        m.specularTextureTransform,
        m.specularTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'specularColorTexture',
        m.specularColorTexture,
        m.specularColorTextureTransform,
        m.specularColorTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'clearcoatTexture',
        m.clearcoatTexture,
        m.clearcoatTextureTransform,
        m.clearcoatTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'clearcoatRoughnessTexture',
        m.clearcoatRoughnessTexture,
        m.clearcoatRoughnessTextureTransform,
        m.clearcoatRoughnessTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'clearcoatNormalTexture',
        m.clearcoatNormalTexture,
        m.clearcoatNormalTextureTransform,
        m.clearcoatNormalTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'sheenColorTexture',
        m.sheenColorTexture,
        m.sheenColorTextureTransform,
        m.sheenColorTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'sheenRoughnessTexture',
        m.sheenRoughnessTexture,
        m.sheenRoughnessTextureTransform,
        m.sheenRoughnessTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'transmissionTexture',
        m.transmissionTexture,
        m.transmissionTextureTransform,
        m.transmissionTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'diffuseTransmissionTexture',
        m.diffuseTransmissionTexture,
        m.diffuseTransmissionTextureTransform,
        m.diffuseTransmissionTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'diffuseTransmissionColorTexture',
        m.diffuseTransmissionColorTexture,
        m.diffuseTransmissionColorTextureTransform,
        m.diffuseTransmissionColorTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'thicknessTexture',
        m.thicknessTexture,
        m.thicknessTextureTransform,
        m.thicknessTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'iridescenceTexture',
        m.iridescenceTexture,
        m.iridescenceTextureTransform,
        m.iridescenceTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'iridescenceThicknessTexture',
        m.iridescenceThicknessTexture,
        m.iridescenceThicknessTextureTransform,
        m.iridescenceThicknessTextureTexCoord,
        context,
      );
      _physicalTextureProperty(
        properties,
        'anisotropyTexture',
        m.anisotropyTexture,
        m.anisotropyTextureTransform,
        m.anisotropyTextureTexCoord,
        context,
      );
    }
    return context.document
        .addResource(
          MaterialResource(
            context.document.newId(),
            type: physical ? 'physical' : 'physicallyBased',
            name: m.name,
            properties: properties,
          ),
        )
        .id;
  }

  void _physicalTextureProperty(
    Map<String, PropertyValue> properties,
    String key,
    Object? source,
    TextureTransform transform,
    int texCoord,
    SerializeContext context,
  ) {
    _textureProperty(properties, key, source, context);
    _textureTransformProperty(
      properties,
      '${key}Transform',
      transform,
      texCoord,
    );
  }

  LocalId? _serializeUnlit(UnlitMaterial m, SerializeContext context) {
    final properties = <String, PropertyValue>{
      'baseColor': _color(m.baseColorFactor),
      'doubleSided': BoolValue(m.doubleSided),
      if (m.depthBias != 0) 'depthBias': DoubleValue(m.depthBias),
    };
    _textureProperty(
      properties,
      'baseColorTexture',
      m.baseColorTextureSource,
      context,
    );
    _textureTransformProperty(
      properties,
      'baseColorTextureTransform',
      m.baseColorTextureTransform,
      m.baseColorTextureTexCoord,
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

  void _textureTransformProperty(
    Map<String, PropertyValue> properties,
    String key,
    TextureTransform transform,
    int texCoord,
  ) {
    if (transform.isIdentity && texCoord == 0) return;
    properties[key] = MapValue({
      'offset': Vec2Value(transform.offset.clone()),
      'scale': Vec2Value(transform.scale.clone()),
      'rotation': DoubleValue(transform.rotation),
      'texCoord': IntValue(texCoord.clamp(0, 1)),
    });
  }

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

/// Codec for [DirectionalLightComponent]. The owning node's rotation aims the
/// light along native local +Z, or along a serialized `localDirection` for
/// components created with [DirectionalLightComponent.aimed].
class DirectionalLightCodec
    extends DeclarativeComponentCodec<DirectionalLightComponent> {
  @override
  String get type => 'directionalLight';

  // Declared in serialize order so serialization matches the format's
  // existing key order. Defaults are the single source for realize fallbacks.
  @override
  List<ComponentField<DirectionalLightComponent>> get fields => [
    ComponentField.vec3(
      'color',
      defaultValue: () => Vector3(1, 1, 1),
      doc: 'Linear RGB light color.',
      constraints: const [RgbColor()],
      get: (c) => c.light.color,
      set: (c, v) => c.light.color = v,
    ),
    ComponentField.number(
      'intensity',
      defaultValue: 3.0,
      doc: 'Light brightness.',
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
      get: (c) => c.light.intensity,
      set: (c, v) => c.light.intensity = v,
    ),
    ComponentField.integer(
      'priority',
      defaultValue: 0,
      doc: 'Priority for primary directional-light features.',
      get: (c) => c.light.priority,
      set: (c, v) => c.light.priority = v,
    ),
    ComponentField.boolean(
      'castsShadow',
      defaultValue: false,
      doc: 'Whether this light renders a shadow map.',
      group: 'Shadows',
      get: (c) => c.light.castsShadow,
      set: (c, v) => c.light.castsShadow = v,
    ),
    ComponentField.boolean(
      'cacheStaticShadows',
      defaultValue: true,
      doc: 'Whether static shadow casters are cached between frames.',
      group: 'Shadows',
      get: (c) => c.light.cacheStaticShadows,
      set: (c, v) => c.light.cacheStaticShadows = v,
    ),
    ComponentField.number(
      'shadowFadeRange',
      defaultValue: 2.0,
      doc: 'Distance over which shadows fade out.',
      group: 'Shadows',
      constraints: const [Range.nonNegative()],
      get: (c) => c.light.shadowFadeRange,
      set: (c, v) => c.light.shadowFadeRange = v,
    ),
    ComponentField.number(
      'shadowSoftness',
      defaultValue: 0.08,
      doc: 'Shadow edge softness.',
      group: 'Shadows',
      constraints: const [Range.nonNegative(), SoftRange(0, 0.5)],
      get: (c) => c.light.shadowSoftness,
      set: (c, v) => c.light.shadowSoftness = v,
    ),
    ComponentField.integer(
      'shadowCascadeCount',
      defaultValue: 4,
      doc: 'Number of shadow cascades.',
      group: 'Shadows',
      constraints: const [IntRange(1, 4)],
      get: (c) => c.light.shadowCascadeCount,
      set: (c, v) => c.light.shadowCascadeCount = v,
    ),
    ComponentField.number(
      'shadowMaxDistance',
      defaultValue: 150.0,
      doc: 'Far distance shadows are rendered to.',
      group: 'Shadows',
      constraints: const [Range.nonNegative()],
      get: (c) => c.light.shadowMaxDistance,
      set: (c, v) => c.light.shadowMaxDistance = v,
    ),
    ComponentField.number(
      'shadowCascadeSplitLambda',
      defaultValue: 0.6,
      doc: 'Blend between uniform and logarithmic cascade splits.',
      group: 'Shadows',
      constraints: const [Range(0, 1), SoftRange(0, 1)],
      get: (c) => c.light.shadowCascadeSplitLambda,
      set: (c, v) => c.light.shadowCascadeSplitLambda = v,
    ),
    ComponentField.integer(
      'shadowMapResolution',
      defaultValue: 1024,
      doc: 'Shadow map resolution per cascade, in texels.',
      group: 'Shadows',
      constraints: const [IntRange(1, null), PowerOfTwo(min: 128, max: 8192)],
      get: (c) => c.light.shadowMapResolution,
      set: (c, v) => c.light.shadowMapResolution = v,
    ),
    ComponentField.number(
      'shadowDepthBias',
      defaultValue: 0.02,
      doc: 'Depth bias applied when sampling the shadow map.',
      group: 'Shadows',
      get: (c) => c.light.shadowDepthBias,
      set: (c, v) => c.light.shadowDepthBias = v,
    ),
    ComponentField.number(
      'shadowNormalBias',
      defaultValue: 0.02,
      doc: 'Normal bias applied when sampling the shadow map.',
      group: 'Shadows',
      get: (c) => c.light.shadowNormalBias,
      set: (c, v) => c.light.shadowNormalBias = v,
    ),
    ComponentField.number(
      'shadowAmbientStrength',
      defaultValue: 0.0,
      doc: 'How strongly shadows darken image-based ambient lighting.',
      group: 'Shadows',
      constraints: const [Range(0, 1), SoftRange(0, 1)],
      get: (c) => c.light.shadowAmbientStrength,
      set: (c, v) => c.light.shadowAmbientStrength = v,
    ),
    ComponentField.enumString(
      'shadowFilter',
      values: DirectionalShadowFilter.values,
      defaultValue: DirectionalShadowFilter.rotatedPoisson,
      doc: 'Shadow-map sampling pattern.',
      group: 'Shadows',
      get: (c) => c.light.shadowFilter,
      set: (c, v) => c.light.shadowFilter = v,
    ),
    ComponentField.enumString(
      'shadowCasterFaces',
      values: ShadowCasterFaces.values,
      defaultValue: ShadowCasterFaces.front,
      doc: 'Caster faces rendered into the shadow map.',
      group: 'Shadows',
      get: (c) => c.light.shadowCasterFaces,
      set: (c, v) => c.light.shadowCasterFaces = v,
    ),
    // Constructor-only (DirectionalLightComponent.aimed); absent means the
    // node's rotation aims the light.
    ComponentField(
      const ComponentPropertyDef(
        'localDirection',
        ComponentPropertyKind.vec3,
        doc:
            'Fixed node-local travel direction for aimed lights; absent '
            'aims along the node\'s local +Z.',
      ),
      read: (c, _) {
        final direction = c.localDirection;
        return direction == null ? null : Vec3Value(direction);
      },
    ),
  ];

  @override
  DirectionalLightComponent create(PropertyReader props) {
    final aim = props.value('localDirection');
    final light = DirectionalLight();
    return aim is Vec3Value
        ? DirectionalLightComponent.aimed(light, aim.value)
        : DirectionalLightComponent(light);
  }
}

/// Codec for [PointLightComponent].
class PointLightCodec extends DeclarativeComponentCodec<PointLightComponent> {
  @override
  String get type => 'pointLight';

  @override
  List<ComponentField<PointLightComponent>> get fields => [
    ComponentField.vec3(
      'color',
      defaultValue: () => Vector3(1, 1, 1),
      doc: 'Linear RGB light color.',
      constraints: const [RgbColor()],
      get: (c) => c.light.color,
      set: (c, v) => c.light.color = v,
    ),
    ComponentField.number(
      'intensity',
      defaultValue: 1.0,
      doc: 'Light brightness (radiance at unit distance).',
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
      get: (c) => c.light.intensity,
      set: (c, v) => c.light.intensity = v,
    ),
    ComponentField.number(
      'range',
      defaultValue: 0.0,
      doc: 'Distance the light reaches, or 0 for infinite range.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.light.range,
      set: (c, v) => c.light.range = v,
    ),
    ComponentField.number(
      'falloffExponent',
      defaultValue: 2.0,
      doc: 'Distance falloff exponent.',
      constraints: const [Range.nonNegative(), SoftRange(0, 4)],
      get: (c) => c.light.falloffExponent,
      set: (c, v) => c.light.falloffExponent = v,
    ),
  ];

  @override
  PointLightComponent create(PropertyReader props) =>
      PointLightComponent(PointLight());
}

/// Codec for [SpotLightComponent].
class SpotLightCodec extends DeclarativeComponentCodec<SpotLightComponent> {
  @override
  String get type => 'spotLight';

  @override
  List<ComponentField<SpotLightComponent>> get fields => [
    ComponentField.vec3(
      'direction',
      defaultValue: () => Vector3(0, -1, 0),
      doc: 'Cone aim in the node\'s local space.',
      get: (c) => c.light.direction,
      set: (c, v) => c.light.direction = v,
    ),
    ComponentField.vec3(
      'color',
      defaultValue: () => Vector3(1, 1, 1),
      doc: 'Linear RGB light color.',
      constraints: const [RgbColor()],
      get: (c) => c.light.color,
      set: (c, v) => c.light.color = v,
    ),
    ComponentField.number(
      'intensity',
      defaultValue: 1.0,
      doc: 'Light brightness (radiance at unit distance).',
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
      get: (c) => c.light.intensity,
      set: (c, v) => c.light.intensity = v,
    ),
    ComponentField.number(
      'range',
      defaultValue: 0.0,
      doc: 'Distance the light reaches, or 0 for infinite range.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.light.range,
      set: (c, v) => c.light.range = v,
    ),
    ComponentField.number(
      'falloffExponent',
      defaultValue: 2.0,
      doc: 'Distance falloff exponent.',
      constraints: const [Range.nonNegative(), SoftRange(0, 4)],
      get: (c) => c.light.falloffExponent,
      set: (c, v) => c.light.falloffExponent = v,
    ),
    ComponentField.number(
      'innerConeAngle',
      defaultValue: 0.0,
      doc: 'Half-angle (radians) of the full-brightness inner cone.',
      constraints: const [Range(0, 1.5533430342749532), AngleRadians()],
      get: (c) => c.light.innerConeAngle,
      set: (c, v) => c.light.innerConeAngle = v,
    ),
    ComponentField.number(
      'outerConeAngle',
      defaultValue: 0.7853981633974483,
      doc: 'Half-angle (radians) at which the cone falls to zero.',
      constraints: const [Range(0, 1.5533430342749532), AngleRadians()],
      get: (c) => c.light.outerConeAngle,
      set: (c, v) => c.light.outerConeAngle = v,
    ),
    ComponentField.boolean(
      'castsShadow',
      defaultValue: false,
      doc: 'Whether this light renders a shadow map.',
      group: 'Shadows',
      get: (c) => c.light.castsShadow,
      set: (c, v) => c.light.castsShadow = v,
    ),
    ComponentField.integer(
      'shadowMapResolution',
      defaultValue: 1024,
      doc: 'Shadow map resolution, in texels.',
      group: 'Shadows',
      constraints: const [IntRange(1, null), PowerOfTwo(min: 128, max: 8192)],
      get: (c) => c.light.shadowMapResolution,
      set: (c, v) => c.light.shadowMapResolution = v,
    ),
    ComponentField.number(
      'shadowNear',
      defaultValue: 0.1,
      doc: 'Near clip distance of the shadow frustum.',
      group: 'Shadows',
      constraints: const [Range.nonNegative()],
      get: (c) => c.light.shadowNear,
      set: (c, v) => c.light.shadowNear = v,
    ),
    ComponentField.number(
      'shadowDepthBias',
      defaultValue: 0.0,
      doc: 'Depth bias used by shadow sampling.',
      group: 'Shadows',
      get: (c) => c.light.shadowDepthBias,
      set: (c, v) => c.light.shadowDepthBias = v,
    ),
    ComponentField.number(
      'shadowNormalBias',
      defaultValue: 0.1,
      doc: 'World-space normal offset used by shadow sampling.',
      group: 'Shadows',
      get: (c) => c.light.shadowNormalBias,
      set: (c, v) => c.light.shadowNormalBias = v,
    ),
    ComponentField.number(
      'shadowSoftness',
      defaultValue: 1.0,
      doc: 'Shadow filter radius, in texels.',
      group: 'Shadows',
      constraints: const [Range.nonNegative()],
      get: (c) => c.light.shadowSoftness,
      set: (c, v) => c.light.shadowSoftness = v,
    ),
    ComponentField.enumString(
      'shadowCasterFaces',
      values: ShadowCasterFaces.values,
      defaultValue: ShadowCasterFaces.front,
      doc: 'Caster faces rendered into the shadow map.',
      group: 'Shadows',
      get: (c) => c.light.shadowCasterFaces,
      set: (c, v) => c.light.shadowCasterFaces = v,
    ),
  ];

  @override
  SpotLightComponent create(PropertyReader props) =>
      SpotLightComponent(SpotLight());
}

/// Codec for [CameraComponent]. Handles perspective projections; the node
/// transform supplies the view.
// TODO(camera-projection-union): describe orthographic/off-axis projections
// as a tagged union once they exist on CameraProjection (the flat keys stay
// for document compatibility).
class CameraCodec extends DeclarativeComponentCodec<CameraComponent> {
  @override
  String get type => 'camera';

  @override
  List<ComponentField<CameraComponent>> get fields => [
    ComponentField.string(
      'projection',
      defaultValue: 'perspective',
      doc: 'The projection model.',
      get: (_) => 'perspective',
    ),
    ComponentField.number(
      'fovRadiansY',
      defaultValue: 45 * degrees2Radians,
      doc: 'Vertical field of view, in radians.',
      constraints: const [Range.nonNegative(), AngleRadians()],
      get: (c) => _perspective(c).fovRadiansY,
      set: (c, v) {
        final projection = c.projection;
        if (projection is PerspectiveProjection) projection.fovRadiansY = v;
      },
    ),
    ComponentField.number(
      'near',
      defaultValue: 0.1,
      doc: 'Near clip distance.',
      constraints: const [Range.nonNegative()],
      get: (c) => _perspective(c).near,
      set: (c, v) {
        final projection = c.projection;
        if (projection is PerspectiveProjection) projection.near = v;
      },
    ),
    ComponentField.number(
      'far',
      defaultValue: 1000.0,
      doc: 'Far clip distance.',
      constraints: const [Range.nonNegative()],
      get: (c) => _perspective(c).far,
      set: (c, v) {
        final projection = c.projection;
        if (projection is PerspectiveProjection) projection.far = v;
      },
    ),
    // Constructor-only; a serialized true restores this camera as the
    // scene's primary on realize.
    ComponentField(
      const ComponentPropertyDef(
        'activateOnMount',
        ComponentPropertyKind.boolean,
        defaultValue: BoolValue(false),
        doc: 'Whether this camera becomes the primary when it mounts.',
      ),
      read: (c, _) => BoolValue(c.active || c.activateOnMount),
    ),
  ];

  static PerspectiveProjection _perspective(CameraComponent c) =>
      c.projection as PerspectiveProjection;

  @override
  bool claims(Component component) =>
      component is CameraComponent &&
      component.projection is PerspectiveProjection;

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) =>
      claims(component) ? super.serialize(component, context) : null;

  @override
  CameraComponent create(PropertyReader props) => CameraComponent(
    projection: PerspectiveProjection(
      fovRadiansY: props.number('fovRadiansY'),
      near: props.number('near'),
      far: props.number('far'),
    ),
    activateOnMount: props.boolean('activateOnMount'),
  );
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

/// Codec for [RectAreaLightComponent].
class RectAreaLightCodec extends ComponentCodec {
  @override
  String get type => 'rectAreaLight';

  static final List<ComponentPropertyDef> _schema = [
    ComponentPropertyDef(
      'color',
      ComponentPropertyKind.vec3,
      Vec3Value(Vector3(1, 1, 1)),
      doc: 'Linear RGB light color.',
      read: (c) => Vec3Value((c as RectAreaLightComponent).light.color.clone()),
    ),
    ComponentPropertyDef(
      'intensity',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Emitted radiance of the panel surface.',
      min: 0,
      read: (c) => DoubleValue((c as RectAreaLightComponent).light.intensity),
    ),
    ComponentPropertyDef(
      'width',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Panel width along the node local X axis.',
      min: 0,
      read: (c) => DoubleValue((c as RectAreaLightComponent).light.width),
    ),
    ComponentPropertyDef(
      'height',
      ComponentPropertyKind.number,
      const DoubleValue(1.0),
      doc: 'Panel height along the node local Y axis.',
      min: 0,
      read: (c) => DoubleValue((c as RectAreaLightComponent).light.height),
    ),
    ComponentPropertyDef(
      'range',
      ComponentPropertyKind.number,
      const DoubleValue(0.0),
      doc: 'Distance the light reaches, or 0 for infinite range.',
      min: 0,
      read: (c) => DoubleValue((c as RectAreaLightComponent).light.range),
    ),
  ];

  @override
  List<ComponentPropertyDef> get propertySchema => _schema;

  @override
  bool claims(Component component) => component is RectAreaLightComponent;

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return RectAreaLightComponent(
      RectAreaLight(
        color: readVec3(p, 'color', vec3Default('color')),
        intensity: readDouble(p, 'intensity', numberDefault('intensity')),
        width: readDouble(p, 'width', numberDefault('width')),
        height: readDouble(p, 'height', numberDefault('height')),
        range: readDouble(p, 'range', numberDefault('range')),
      ),
    );
  }
}
