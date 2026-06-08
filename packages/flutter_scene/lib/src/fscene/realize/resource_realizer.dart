import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';

/// Turns a document's resources into live, GPU-backed [Geometry] and
/// [Material] objects, memoizing each so a resource shared by many nodes is
/// realized once.
///
/// Procedural and payload-backed geometry, parameter materials, and image
/// textures from embedded payloads are realized here. External image assets
/// (async) and `fmat` materials are the renderer-facing seams still to fill.
// TODO(fscene): realize external image-asset textures (async) and fmat
// materials.
class ResourceRealizer {
  /// Creates a realizer over [document].
  ResourceRealizer(this.document);

  /// The document whose resources are realized.
  final SceneDocument document;

  final Map<LocalId, Geometry> _geometries = {};
  final Map<LocalId, Material> _materials = {};
  final Map<LocalId, gpu.Texture> _textures = {};

  /// The live geometry for resource [id], realized and memoized on first use.
  Geometry geometry(LocalId id) => _geometries[id] ??= _buildGeometry(id);

  /// The live material for resource [id], realized and memoized on first use.
  Material material(LocalId id) => _materials[id] ??= _buildMaterial(id);

  /// The live texture for resource [id], realized and memoized on first use.
  gpu.Texture texture(LocalId id) => _textures[id] ??= _buildTexture(id);

  Geometry _buildGeometry(LocalId id) {
    final res = document.resource(id);
    if (res is! GeometryResource) {
      throw FsceneFormatException('Resource $id is not a geometry');
    }
    final procedural = res.procedural;
    if (procedural != null) return _buildProcedural(procedural);
    return _buildPayloadGeometry(res);
  }

  /// Builds a live geometry from a resource's payload chunks, mirroring the
  /// `.model` import path: the interleaved vertex bytes and optional index
  /// bytes are uploaded straight into a GPU buffer.
  Geometry _buildPayloadGeometry(GeometryResource res) {
    final vertexId = res.vertices;
    if (vertexId == null) {
      throw FsceneFormatException(
        'Geometry ${res.id} has neither a procedural descriptor nor a vertex '
        'payload',
      );
    }
    final vertexBytes = _payloadBytes(vertexId, 'vertex');
    final vertexPayload = document.payload(vertexId)!;
    final skinned = vertexPayload.layout == 'skinned';
    final perVertexBytes = skinned
        ? kSkinnedPerVertexSize
        : kUnskinnedPerVertexSize;
    final vertexCount = vertexBytes.lengthInBytes ~/ perVertexBytes;
    final geometry = skinned ? SkinnedGeometry() : UnskinnedGeometry();

    ByteData? indexBytes;
    var indexType = gpu.IndexType.int16;
    final indexId = res.indices;
    if (indexId != null) {
      indexBytes = ByteData.sublistView(_payloadBytes(indexId, 'index'));
      indexType = document.payload(indexId)!.format == 'uint32'
          ? gpu.IndexType.int32
          : gpu.IndexType.int16;
    }

    // Set baked bounds before upload so the position scan is skipped; without
    // bounds, uploadVertexData scans unskinned positions (and leaves skinned
    // geometry unbounded, matching the importer).
    final bounds = res.bounds;
    if (bounds != null) {
      final aabb = Aabb3.minMax(bounds.min.clone(), bounds.max.clone());
      geometry.setLocalBounds(aabb, _circumscribedSphere(aabb));
    }

    geometry.uploadVertexData(
      ByteData.sublistView(vertexBytes),
      vertexCount,
      indexBytes,
      indexType: indexType,
    );
    return geometry;
  }

  Uint8List _payloadBytes(LocalId id, String role) {
    final payload = document.payload(id);
    if (payload == null) {
      throw FsceneFormatException(
        'Geometry references missing $role payload $id',
      );
    }
    final bytes = payload.bytes;
    if (bytes == null) {
      throw FsceneFormatException(
        'The $role payload $id has no bytes; load the document from a '
        '.fsceneb container so its chunks are attached',
      );
    }
    return bytes;
  }

  static Sphere _circumscribedSphere(Aabb3 aabb) {
    final center = (aabb.min + aabb.max)..scale(0.5);
    return Sphere.centerRadius(center, (aabb.max - aabb.min).length * 0.5);
  }

  Geometry _buildProcedural(ProceduralGeometry p) => switch (p) {
    CuboidGeometrySpec(:final extents, :final debugColors) => CuboidGeometry(
      extents,
      debugColors: debugColors,
    ),
    PlaneGeometrySpec(
      :final width,
      :final depth,
      :final segmentsX,
      :final segmentsZ,
    ) =>
      PlaneGeometry(
        width: width,
        depth: depth,
        segmentsX: segmentsX,
        segmentsZ: segmentsZ,
      ),
    SphereGeometrySpec(:final radius, :final segments, :final rings) =>
      SphereGeometry(radius: radius, segments: segments, rings: rings),
  };

  Material _buildMaterial(LocalId id) {
    final res = document.resource(id);
    if (res is! MaterialResource) {
      throw FsceneFormatException('Resource $id is not a material');
    }
    switch (res.type) {
      case 'unlit':
        return _unlit(res.properties);
      case 'physicallyBased':
        return _pbr(res.properties);
      default:
        debugPrint(
          'fscene: material type "${res.type}" not realized; using unlit',
        );
        return _unlit(res.properties);
    }
  }

  gpu.Texture _buildTexture(LocalId id) {
    final res = document.resource(id);
    if (res is! TextureResource) {
      throw FsceneFormatException('Resource $id is not a texture');
    }
    final payloadId = res.payload;
    if (payloadId == null) {
      // External image assets need an async load path; only embedded payloads
      // realize here.
      // TODO(fscene): async-load external image-asset textures
      // (TextureResource.asset).
      throw FsceneFormatException(
        'Texture $id references an external asset; only embedded image '
        'payloads are realized',
      );
    }
    final payload = document.payload(payloadId);
    final bytes = payload?.bytes;
    if (payload == null || bytes == null) {
      throw FsceneFormatException(
        'Image payload $payloadId has no bytes; load the document from a '
        '.fsceneb container so its chunks are attached',
      );
    }
    if (payload.encoding != PayloadEncoding.image) {
      throw FsceneFormatException('Payload $payloadId is not an image');
    }
    final width = payload.width;
    final height = payload.height;
    if (width == null || height == null) {
      throw FsceneFormatException(
        'Image payload $payloadId is missing its width/height',
      );
    }
    if (payload.format != 'rgba8') {
      // Encoded images (png/jpg) would need an async decode step.
      // TODO(fscene): decode encoded image payloads via instantiateImageCodec.
      throw FsceneFormatException(
        'Image payload format "${payload.format}" is not supported; expected '
        'rgba8',
      );
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
    );
    texture.overwrite(ByteData.sublistView(bytes));
    return texture;
  }

  gpu.Texture? _textureRef(Map<String, PropertyValue> p, String key) {
    final v = p[key];
    return v is ResourceRefValue ? texture(v.id) : null;
  }

  UnlitMaterial _unlit(Map<String, PropertyValue> p) {
    final m = UnlitMaterial();
    final base = readColor(p, 'baseColor');
    if (base != null) m.baseColorFactor = base;
    final baseColorTexture = _textureRef(p, 'baseColorTexture');
    if (baseColorTexture != null) m.baseColorTexture = baseColorTexture;
    return m;
  }

  PhysicallyBasedMaterial _pbr(Map<String, PropertyValue> p) {
    final m = PhysicallyBasedMaterial();
    final base = readColor(p, 'baseColor');
    if (base != null) m.baseColorFactor = base;
    final emissive = readColor(p, 'emissive');
    if (emissive != null) m.emissiveFactor = emissive;
    m.metallicFactor = readDouble(p, 'metallic', m.metallicFactor);
    m.roughnessFactor = readDouble(p, 'roughness', m.roughnessFactor);
    m.occlusionStrength = readDouble(
      p,
      'occlusionStrength',
      m.occlusionStrength,
    );
    final baseColorTexture = _textureRef(p, 'baseColorTexture');
    if (baseColorTexture != null) m.baseColorTexture = baseColorTexture;
    final metallicRoughnessTexture = _textureRef(p, 'metallicRoughnessTexture');
    if (metallicRoughnessTexture != null) {
      m.metallicRoughnessTexture = metallicRoughnessTexture;
    }
    final normalTexture = _textureRef(p, 'normalTexture');
    if (normalTexture != null) m.normalTexture = normalTexture;
    final occlusionTexture = _textureRef(p, 'occlusionTexture');
    if (occlusionTexture != null) m.occlusionTexture = occlusionTexture;
    final emissiveTexture = _textureRef(p, 'emissiveTexture');
    if (emissiveTexture != null) m.emissiveTexture = emissiveTexture;
    return m;
  }
}
