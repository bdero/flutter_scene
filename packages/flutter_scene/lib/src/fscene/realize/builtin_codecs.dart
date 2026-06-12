import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart' hide Sphere;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart'
    show fmatSourcePathOf;
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/views.dart';
import 'package:flutter_scene/src/render_texture.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/realize/resource_copy.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/mesh.dart';

/// Registers the component codecs the format ships with (mesh, directional
/// light, camera) into [registry].
void registerBuiltinComponentCodecs(FsceneComponentRegistry registry) {
  registry
    ..register(MeshCodec())
    ..register(DirectionalLightCodec())
    ..register(CameraCodec());
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
    final packed = geometry.packedData;
    final vertices = dest.addPayload(
      PayloadSpec(
        dest.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: 'unskinned',
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

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return DirectionalLightComponent(
      DirectionalLight(
        direction: readVec3(p, 'direction', Vector3(-0.3, -1.0, -0.2)),
        color: readVec3(p, 'color', Vector3(1, 1, 1)),
        intensity: readDouble(p, 'intensity', 3.0),
        castsShadow: readBool(p, 'castsShadow', false),
        shadowFadeRange: readDouble(p, 'shadowFadeRange', 2.0),
        shadowSoftness: readDouble(p, 'shadowSoftness', 0.08),
        shadowCascadeCount: readInt(p, 'shadowCascadeCount', 4),
        shadowMaxDistance: readDouble(p, 'shadowMaxDistance', 150.0),
        shadowCascadeSplitLambda: readDouble(
          p,
          'shadowCascadeSplitLambda',
          0.6,
        ),
        shadowMapResolution: readInt(p, 'shadowMapResolution', 1024),
        shadowDepthBias: readDouble(p, 'shadowDepthBias', 0.02),
        shadowNormalBias: readDouble(p, 'shadowNormalBias', 0.02),
      ),
    );
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! DirectionalLightComponent) return null;
    final l = component.light;
    return ComponentSpec(
      type,
      properties: {
        'direction': Vec3Value(l.direction.clone()),
        'color': Vec3Value(l.color.clone()),
        'intensity': DoubleValue(l.intensity),
        'castsShadow': BoolValue(l.castsShadow),
        'shadowFadeRange': DoubleValue(l.shadowFadeRange),
        'shadowSoftness': DoubleValue(l.shadowSoftness),
        'shadowCascadeCount': IntValue(l.shadowCascadeCount),
        'shadowMaxDistance': DoubleValue(l.shadowMaxDistance),
        'shadowCascadeSplitLambda': DoubleValue(l.shadowCascadeSplitLambda),
        'shadowMapResolution': IntValue(l.shadowMapResolution),
        'shadowDepthBias': DoubleValue(l.shadowDepthBias),
        'shadowNormalBias': DoubleValue(l.shadowNormalBias),
      },
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

  @override
  Component realize(ComponentSpec spec, RealizeContext context) {
    final p = spec.properties;
    return CameraComponent(
      projection: PerspectiveProjection(
        fovRadiansY: readDouble(p, 'fovRadiansY', 45 * degrees2Radians),
        near: readDouble(p, 'near', 0.1),
        far: readDouble(p, 'far', 1000.0),
      ),
    );
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! CameraComponent) return null;
    final proj = component.projection;
    if (proj is! PerspectiveProjection) {
      return ComponentSpec(type);
    }
    return ComponentSpec(
      type,
      properties: {
        'projection': const StringValue('perspective'),
        'fovRadiansY': DoubleValue(proj.fovRadiansY),
        'near': DoubleValue(proj.near),
        'far': DoubleValue(proj.far),
      },
    );
  }
}
