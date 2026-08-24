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
import 'package:flutter_scene/src/components/irradiance_volume_component.dart';
import 'package:flutter_scene/src/components/materials_variants_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/rect_area_light_component.dart';
import 'package:flutter_scene/src/components/reflection_probe_component.dart';
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
import 'package:flutter_scene/src/fscene/realize/render_extras_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/resource_copy.dart';
import 'package:flutter_scene/src/fscene/realize/ui_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/mesh.dart';

/// Registers the component codecs the format ships with (mesh, directional
/// light, camera) into [registry].
void registerBuiltinComponentCodecs(FsceneComponentRegistry registry) {
  registry
    // Registered before the mesh codec so serialize claims a particle
    // emitter, trail, LOD, or splat component (all subclass the mesh
    // component) before the mesh codec sees it.
    ..register(ParticleEmitterCodec())
    ..register(MeshParticleEmitterCodec())
    ..register(TrailCodec())
    ..register(LodCodec())
    ..register(SplatCodec())
    // TODO(instanced-mesh-codec): InstancedMeshComponent stays code-driven
    // (its bulk instance arrays have no document form yet); add a codec once
    // instance data can ride payloads.
    ..register(MeshCodec())
    ..register(MaterialsVariantsCodec())
    ..register(DirectionalLightCodec())
    ..register(PointLightCodec())
    ..register(RectAreaLightCodec())
    ..register(ReflectionProbeCodec())
    ..register(SpotLightCodec())
    ..register(CameraCodec())
    ..register(EnvironmentVolumeCodec())
    ..register(IrradianceVolumeCodec())
    ..register(WidgetCodec())
    ..register(SemanticsCodec())
    ..register(AudioSourceCodec())
    ..register(AudioListenerCodec())
    ..register(AudioEngineCodec());
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

  // The teal the editor's old hard-coded volume overlay used, solid for the
  // region and faint for the blend shell.
  static const _regionColor = GizmoColor(0.204, 0.839, 0.784);
  static const _blendColor = GizmoColor(0.204, 0.839, 0.784, 0.33);

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'environment',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(),
      GizmoWireBox(
        halfExtentsBind: 'extents',
        color: _regionColor,
        when: GizmoCondition('shape', 'box'),
      ),
      GizmoWireBox(
        halfExtentsBind: 'extents',
        inflate: GizmoScalar.bind('blendDistance'),
        color: _blendColor,
        when: GizmoCondition('shape', 'box'),
      ),
      GizmoWireSphere(
        radius: GizmoScalar.bind('radius'),
        color: _regionColor,
        when: GizmoCondition('shape', 'sphere'),
      ),
      GizmoWireSphere(
        radius: GizmoScalar.bind('radius'),
        inflate: GizmoScalar.bind('blendDistance'),
        color: _blendColor,
        when: GizmoCondition('shape', 'sphere'),
      ),
    ]),
  );

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
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
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
    var settings = envId == null
        ? null
        : props.context.resources?.environment(envId);
    if (settings == null) {
      settings = EnvironmentSettings();
      if (envId != null) {
        // Keep the authored reference on the fallback so a save made while
        // the resource is unavailable does not drop it.
        tagResourceOrigin(settings, props.context.document, envId);
      }
    }
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
    ComponentPropertyDef(
      'morphWeights',
      ComponentPropertyKind.list,
      doc:
          'Per-instance morph target weights overriding the geometry '
          'defaults, in target order.',
      itemDef: ComponentPropertyDef('weight', ComponentPropertyKind.number),
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
    // TODO(fscene): serialize MeshPrimitive.visible/castsShadow (property
    // defs above, plus the write side in serialize()). Every realized
    // primitive keeps the field defaults for now.
    final component = MeshComponent(
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
    final weights = spec.properties['morphWeights'];
    if (weights is ListValue) {
      component.initialMorphWeights = [
        for (final value in weights.values)
          if (value is DoubleValue) value.value,
      ];
    }
    return component;
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
    final weights = _serializedMorphWeights(component);
    if (pairs.length == 1) {
      return ComponentSpec(
        type,
        properties: {
          'geometry': ResourceRefValue(pairs.first.$1),
          'material': ResourceRefValue(pairs.first.$2),
          if (weights != null) 'morphWeights': weights,
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
        if (weights != null) 'morphWeights': weights,
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

  // The owning node's live morph weights, when they differ from the
  // geometry's defaults; null keeps the component free of the property.
  ListValue? _serializedMorphWeights(MeshComponent component) {
    if (!component.isAttached) return null;
    final node = component.node;
    final live = node.internalMorphWeights;
    final defaults = node.mesh?.morphTargets?.defaultWeights;
    if (live == null || defaults == null) return null;
    var differs = live.length != defaults.length;
    for (var i = 0; !differs && i < live.length; i++) {
      differs = live[i] != defaults[i];
    }
    if (!differs) return null;
    return ListValue([for (final w in live) DoubleValue(w)]);
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
        // Infinity (no attenuation) cannot encode; absent means infinity.
        if (m.attenuationDistance.isFinite)
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

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'light-sun',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(color: GizmoColor.bind('color')),
      // Travel direction; the node's rotation aims the light along local +Z.
      // TODO(gizmo-aimed): a code-constructed .aimed light travels along
      // localDirection instead; bind it once optional binds exist.
      GizmoArrow(length: GizmoScalar(1.4)),
      // Eight sun rays in the local XY plane, behind the arrow.
      GizmoLines([
        0.30, 0, 0, 0.50, 0, 0, //
        0.21, 0.21, 0, 0.35, 0.35, 0, //
        0, 0.30, 0, 0, 0.50, 0, //
        -0.21, 0.21, 0, -0.35, 0.35, 0, //
        -0.30, 0, 0, -0.50, 0, 0, //
        -0.21, -0.21, 0, -0.35, -0.35, 0, //
        0, -0.30, 0, 0, -0.50, 0, //
        0.21, -0.21, 0, 0.35, -0.35, 0,
      ], visibility: GizmoVisibility.selected),
    ]),
  );

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
      constraints: const [Range.nonNegative(), SoftRange(0, 20)],
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
      constraints: const [Range.nonNegative(), SoftRange(10, 500)],
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
      constraints: const [Range.nonNegative(), SoftRange(0, 0.2), Step(0.001)],
      get: (c) => c.light.shadowDepthBias,
      set: (c, v) => c.light.shadowDepthBias = v,
    ),
    ComponentField.number(
      'shadowNormalBias',
      defaultValue: 0.02,
      doc: 'Normal bias applied when sampling the shadow map.',
      group: 'Shadows',
      constraints: const [Range.nonNegative(), SoftRange(0, 0.2), Step(0.001)],
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
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'light-point',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(color: GizmoColor.bind('color')),
      // Zero range means infinite and draws nothing.
      GizmoWireSphere(
        radius: GizmoScalar.bind('range'),
        visibility: GizmoVisibility.selected,
      ),
    ]),
  );

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
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'light-spot',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(color: GizmoColor.bind('color')),
      GizmoArrow(axisBind: 'direction', length: GizmoScalar(0.8)),
      // Unranged cones draw a representative reach in the editor.
      GizmoWireCone(
        angle: GizmoScalar.bind('outerConeAngle'),
        range: GizmoScalar.bind('range'),
        axisBind: 'direction',
        visibility: GizmoVisibility.selected,
      ),
      GizmoWireCone(
        angle: GizmoScalar.bind('innerConeAngle'),
        range: GizmoScalar.bind('range'),
        axisBind: 'direction',
        visibility: GizmoVisibility.selected,
        color: GizmoColor(1, 1, 1, 0.35),
      ),
    ]),
  );

  @override
  List<ComponentField<SpotLightComponent>> get fields => [
    ComponentField.vec3(
      'direction',
      defaultValue: () => Vector3(0, -1, 0),
      doc: 'Cone aim in the node\'s local space.',
      constraints: const [Normalized()],
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
      constraints: const [Range.nonNegative(), SoftRange(0, 0.1), Step(0.001)],
      get: (c) => c.light.shadowDepthBias,
      set: (c, v) => c.light.shadowDepthBias = v,
    ),
    ComponentField.number(
      'shadowNormalBias',
      defaultValue: 0.1,
      doc: 'World-space normal offset used by shadow sampling.',
      group: 'Shadows',
      constraints: const [Range.nonNegative(), SoftRange(0, 1), Step(0.01)],
      get: (c) => c.light.shadowNormalBias,
      set: (c, v) => c.light.shadowNormalBias = v,
    ),
    ComponentField.number(
      'shadowSoftness',
      defaultValue: 1.0,
      doc: 'Shadow filter radius, in texels.',
      group: 'Shadows',
      constraints: const [Range.nonNegative(), SoftRange(0, 8)],
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
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'camera',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(),
      GizmoFrustum(
        fovY: GizmoScalar.bind('fovRadiansY'),
        near: GizmoScalar.bind('near'),
        far: GizmoScalar.bind('far'),
        visibility: GizmoVisibility.selected,
      ),
    ]),
  );

  @override
  List<ComponentField<CameraComponent>> get fields => [
    // Single-option until orthographic exists (the projection-union TODO
    // above); options render as a dropdown rather than free text.
    ComponentField(
      const ComponentPropertyDef(
        'projection',
        ComponentPropertyKind.string,
        defaultValue: StringValue('perspective'),
        doc: 'The projection model.',
        options: ['perspective'],
      ),
      read: (c, _) => const StringValue('perspective'),
    ),
    ComponentField.number(
      'fovRadiansY',
      defaultValue: 45 * degrees2Radians,
      doc: 'Vertical field of view, in radians.',
      constraints: [
        Range(1 * degrees2Radians, 179 * degrees2Radians),
        const AngleRadians(),
      ],
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
      constraints: const [Range(0.0001, null)],
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
      constraints: const [Range(0.0001, null)],
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
          final materialsByVariant = <int, Material>{};
          final variantIds = <LocalId>{};
          for (final mapping in materials.values.entries) {
            final variantIndex = int.tryParse(mapping.key);
            final ref = mapping.value;
            if (variantIndex == null || ref is! ResourceRefValue) continue;
            variantIds.add(ref.id);
            materialsByVariant[variantIndex] = realizer.material(ref.id);
          }
          // The serialized default keeps authored defaults stable across
          // saves and reloads made while a variant was selected; older
          // documents without one fall back to the realized mesh material.
          // An explicitly assigned mesh material (one that is neither the
          // recorded default nor any variant mapping) wins over the recorded
          // default, so assigning a material to a variants-carrying mesh is
          // not silently reverted; the binding rebases onto it. That
          // includes untagged code-assigned materials, and the id match is
          // document-aware (ids from another document's space, a
          // prefab-realized material, can collide numerically).
          final current = mesh.primitives[primitiveIndex.value].material;
          final currentOrigin = resourceOrigin(current);
          final Material defaultMaterial;
          if (defaultRef is! ResourceRefValue) {
            defaultMaterial = current;
          } else {
            final matchesRecorded =
                currentOrigin != null &&
                identical(currentOrigin.document, context.document) &&
                (currentOrigin.resourceId == defaultRef.id ||
                    variantIds.contains(currentOrigin.resourceId));
            defaultMaterial = matchesRecorded
                ? realizer.material(defaultRef.id)
                : current;
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

/// Codec for [ReflectionProbeComponent]. The captured environment is not
/// persisted; a realized probe re-captures on activation.
class ReflectionProbeCodec
    extends DeclarativeComponentCodec<ReflectionProbeComponent> {
  @override
  String get type => 'reflectionProbe';

  // Violet, distinct from the environment volume's teal.
  static const _boxColor = GizmoColor(0.71, 0.48, 0.95);
  static const _blendColor = GizmoColor(0.71, 0.48, 0.95, 0.33);

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'environment',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(color: _boxColor),
      GizmoWireBox(halfExtentsBind: 'extents', color: _boxColor),
      GizmoWireBox(
        halfExtentsBind: 'extents',
        inflate: GizmoScalar.bind('blendDistance'),
        color: _blendColor,
      ),
    ]),
  );

  @override
  List<ComponentField<ReflectionProbeComponent>> get fields => [
    ComponentField.vec3(
      'extents',
      defaultValue: () => Vector3.all(5),
      doc: 'World-space half-size of the influence and parallax box.',
      get: (c) => c.extents,
      set: (c, v) => c.extents = v,
    ),
    ComponentField.number(
      'blendDistance',
      defaultValue: 1.0,
      doc: 'Fade band outside the box, in world units.',
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
      get: (c) => c.blendDistance,
      set: (c, v) => c.blendDistance = v,
    ),
    ComponentField.number(
      'priority',
      defaultValue: 10.0,
      doc: 'Cross-fade order; higher applies on top.',
      get: (c) => c.priority,
      set: (c, v) => c.priority = v,
    ),
    ComponentField.number(
      'weight',
      defaultValue: 1.0,
      doc: 'Master contribution scale.',
      constraints: const [Range(0, 1)],
      get: (c) => c.weight,
      set: (c, v) => c.weight = v,
    ),
    ComponentField.integer(
      'faceResolution',
      defaultValue: 128,
      doc: 'Resolution of each captured cube face, in pixels.',
      constraints: const [IntRange(16, null)],
      get: (c) => c.faceResolution,
      set: (c, v) => c.faceResolution = v,
    ),
    ComponentField.boolean(
      'captureOnActivate',
      defaultValue: true,
      doc: 'Capture automatically before the first rendered frame.',
      get: (c) => c.captureOnActivate,
      set: (c, v) => c.captureOnActivate = v,
    ),
  ];

  @override
  ReflectionProbeComponent create(PropertyReader props) =>
      ReflectionProbeComponent();
}

/// Codec for [RectAreaLightComponent].
class RectAreaLightCodec
    extends DeclarativeComponentCodec<RectAreaLightComponent> {
  @override
  String get type => 'rectAreaLight';

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'light-area',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(color: GizmoColor.bind('color')),
      // The emitting panel: width along local X, height along local Y,
      // radiating along +Z.
      GizmoWireRect(
        width: GizmoScalar.bind('width'),
        height: GizmoScalar.bind('height'),
      ),
      GizmoArrow(length: GizmoScalar(0.6)),
    ]),
  );

  @override
  List<ComponentField<RectAreaLightComponent>> get fields => [
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
      doc: 'Emitted radiance of the panel surface.',
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
      get: (c) => c.light.intensity,
      set: (c, v) => c.light.intensity = v,
    ),
    ComponentField.number(
      'width',
      defaultValue: 1.0,
      doc: 'Panel width along the node local X axis.',
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
      get: (c) => c.light.width,
      set: (c, v) => c.light.width = v,
    ),
    ComponentField.number(
      'height',
      defaultValue: 1.0,
      doc: 'Panel height along the node local Y axis.',
      constraints: const [Range.nonNegative(), SoftRange(0, 10)],
      get: (c) => c.light.height,
      set: (c, v) => c.light.height = v,
    ),
    ComponentField.number(
      'range',
      defaultValue: 0.0,
      doc: 'Distance the light reaches, or 0 for infinite range.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.light.range,
      set: (c, v) => c.light.range = v,
    ),
  ];

  @override
  RectAreaLightComponent create(PropertyReader props) =>
      RectAreaLightComponent(RectAreaLight());
}

/// Codec for [IrradianceVolumeComponent].
class IrradianceVolumeCodec
    extends DeclarativeComponentCodec<IrradianceVolumeComponent> {
  @override
  String get type => 'irradianceVolume';

  static const _boxColor = GizmoColor(0.2, 0.8, 0.6);

  @override
  ComponentSchema get schema => ComponentSchema(
    type,
    icon: 'light',
    properties: propertySchema,
    gizmo: const GizmoSpec([
      GizmoIcon(color: _boxColor),
      GizmoWireBox(halfExtentsBind: 'extents', color: _boxColor),
    ]),
  );

  @override
  List<ComponentField<IrradianceVolumeComponent>> get fields => [
    ComponentField.vec3(
      'extents',
      defaultValue: () => Vector3.all(10),
      doc: 'World-space half-size of the irradiance volume box.',
      get: (c) => c.extents,
      set: (c, v) => c.extents = v,
    ),
    ComponentField.vec3(
      'resolution',
      defaultValue: () => Vector3(16, 8, 16),
      doc: 'Probe count along each axis.',
      get: (c) => c.resolution,
      set: (c, v) => c.resolution = v,
    ),
    ComponentField.number(
      'priority',
      defaultValue: 0.0,
      doc: 'Volume selection order; higher applies on top.',
      get: (c) => c.priority,
      set: (c, v) => c.priority = v,
    ),
  ];

  @override
  IrradianceVolumeComponent create(PropertyReader props) =>
      IrradianceVolumeComponent();
}
