import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/fscene/realize/views.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/texture/compressed_texture.dart';

/// Turns a document's resources into live, GPU-backed [Geometry] and
/// [Material] objects, memoizing each so a resource shared by many nodes is
/// realized once.
///
/// Procedural and payload-backed geometry, parameter materials, and embedded
/// `rgba8` textures realize synchronously. External image assets, encoded
/// (PNG/JPEG) image payloads, and `fmat` materials need decoding or asset
/// loading, so they are resolved by [preload] (await it before realizing);
/// the synchronous path falls back to a placeholder for them.
class ResourceRealizer {
  /// Creates a realizer over [document]. [bundle] (default [rootBundle])
  /// resolves external image assets and `fmat` materials during [preload].
  ResourceRealizer(this.document, {AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  /// The document whose resources are realized.
  final SceneDocument document;

  /// The asset bundle external assets and `fmat` materials load from.
  final AssetBundle bundle;

  final Map<LocalId, Geometry> _geometries = {};
  final Map<LocalId, Material> _materials = {};
  final Map<LocalId, gpu.Texture> _textures = {};

  /// The live geometry for resource [id], realized and memoized on first use.
  /// The result is stamped with its origin so the serializer can recover it.
  Geometry geometry(LocalId id) =>
      _geometries[id] ??= tagResourceOrigin(_buildGeometry(id), document, id);

  /// The live material for resource [id], realized and memoized on first use.
  Material material(LocalId id) =>
      _materials[id] ??= tagResourceOrigin(_buildMaterial(id), document, id);

  /// The live texture for resource [id], realized and memoized on first use.
  gpu.Texture texture(LocalId id) =>
      _textures[id] ??= tagResourceOrigin(_buildTexture(id), document, id);

  /// Resolves the resources that need asynchronous work (external image
  /// assets, encoded image payloads, and `fmat` materials), caching them so
  /// the synchronous realize path finds them ready.
  ///
  /// Await this before realizing a document that may reference such resources
  /// (the async loaders do). A resource that fails to load degrades to a
  /// placeholder (textures) or an unlit material (`fmat`) with a warning,
  /// rather than failing the whole scene.
  Future<void> preload() async {
    // Textures first: an fmat material's parameter overrides may reference a
    // texture resource, which must be decoded before the override resolves it.
    final textures = <Future<void>>[];
    for (final resource in document.resources.values) {
      if (resource is TextureResource && _needsAsyncTexture(resource)) {
        textures.add(_preloadTexture(resource));
      }
    }
    await Future.wait(textures);

    final materials = <Future<void>>[];
    for (final resource in document.resources.values) {
      if (resource is MaterialResource && resource.type == 'fmat') {
        materials.add(_preloadFmat(resource));
      }
    }
    await Future.wait(materials);
  }

  bool _needsAsyncTexture(TextureResource res) {
    if (res.asset != null) return true;
    final payload = res.payload;
    if (payload == null) return false;
    // Only raw rgba8 payloads realize synchronously (a plain upload). Encoded
    // (PNG/JPEG) images decode asynchronously, and KTX2 block payloads
    // transcode on a background isolate, so both go through preload.
    return document.payload(payload)?.format != 'rgba8';
  }

  Future<void> _preloadTexture(TextureResource res) async {
    try {
      _textures[res.id] = tagResourceOrigin(
        await _loadTextureAsync(res),
        document,
        res.id,
      );
    } catch (e) {
      debugPrint('fscene: failed to load texture ${res.id}: $e; placeholder');
      _textures[res.id] = _placeholderTexture();
    }
  }

  Future<gpu.Texture> _loadTextureAsync(TextureResource res) async {
    final asset = res.asset;
    if (asset != null) {
      return gpuTextureFromImage(
        await imageFromAsset(asset.key, bundle: bundle),
      );
    }
    final bytes = _payloadBytes(res.payload!, 'image');
    // KTX2 block payloads transcode off the main isolate; other encoded images
    // decode via dart:ui.
    if (document.payload(res.payload!)?.format == 'ktx2') {
      return gpuTextureFromKtx2Async(bytes);
    }
    return gpuTextureFromImage(await imageFromBytes(bytes));
  }

  Future<void> _preloadFmat(MaterialResource res) async {
    final asset = res.asset;
    if (asset == null) {
      debugPrint('fscene: fmat material ${res.id} has no asset; using unlit');
      _materials[res.id] = tagResourceOrigin(
        _unlit(res.properties),
        document,
        res.id,
      );
      return;
    }
    try {
      final material = await loadFmatMaterial(asset.key, bundle: bundle);
      // Apply the document's parameter overrides (scalars, vectors, colors,
      // and texture-resource references) over the sidecar defaults.
      applyFmatParameterOverrides(
        material.parameters,
        res.properties,
        resolveTexture: texture,
      );
      _materials[res.id] = tagResourceOrigin(material, document, res.id);
    } catch (e) {
      debugPrint('fscene: failed to load fmat ${res.id} ("${asset.key}"): $e');
      _materials[res.id] = tagResourceOrigin(
        _unlit(res.properties),
        document,
        res.id,
      );
    }
  }

  gpu.Texture _placeholderTexture() {
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      1,
      1,
    );
    texture.overwrite(
      ByteData.sublistView(Uint8List.fromList(const [255, 255, 255, 255])),
    );
    return texture;
  }

  Geometry _buildGeometry(LocalId id) {
    final res = document.resource(id);
    if (res is! GeometryResource) {
      throw FsceneFormatException('Resource $id is not a geometry');
    }
    final procedural = res.procedural;
    if (procedural != null) return _buildProcedural(procedural);
    return _buildPayloadGeometry(res);
  }

  /// Builds a live geometry from a resource's payload chunks, matching how
  /// the scene importer stores it: the interleaved vertex bytes and optional
  /// index bytes are uploaded straight into a GPU buffer.
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
    geometry.primitiveType = _topology(res.topology);
    return geometry;
  }

  gpu.PrimitiveType _topology(String name) {
    try {
      return gpu.PrimitiveType.values.byName(name);
    } catch (_) {
      debugPrint('fscene: unknown geometry topology "$name"; using triangle');
      return gpu.PrimitiveType.triangle;
    }
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
      case 'fmat':
        // Resolved by preload(); reaching here is the synchronous path.
        debugPrint('fscene: fmat material needs the async loader; using unlit');
        return _unlit(res.properties);
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
      // An external image asset, resolved by preload(). Reaching here means
      // the synchronous path was used; fall back to a placeholder.
      debugPrint(
        'fscene: external-asset texture $id needs the async loader (loadScene '
        '/ loadFscenebAsset); using a placeholder',
      );
      return _placeholderTexture();
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
    if (payload.format == 'ktx2') {
      // KTX2 block payloads transcode off the main isolate via preload(); the
      // sync path can't await that.
      debugPrint(
        'fscene: ktx2 texture payload $payloadId needs the async loader; '
        'using a placeholder',
      );
      return _placeholderTexture();
    }
    final width = payload.width;
    final height = payload.height;
    if (width == null || height == null) {
      throw FsceneFormatException(
        'Image payload $payloadId is missing its width/height',
      );
    }
    if (payload.format != 'rgba8') {
      // Encoded (PNG/JPEG) payloads are decoded by preload(); the sync path
      // can't decode them.
      debugPrint(
        'fscene: encoded image payload $payloadId needs the async loader; '
        'using a placeholder',
      );
      return _placeholderTexture();
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
    );
    texture.overwrite(ByteData.sublistView(bytes));
    return texture;
  }

  // Resolves a texture property to either a gpu.Texture or, when the ref
  // points at a render-texture resource, the live RenderTexture handle
  // (material slots accept both).
  Object? _textureRef(Map<String, PropertyValue> p, String key) {
    final v = p[key];
    if (v is! ResourceRefValue) return null;
    if (document.resource(v.id) is RenderTextureResource) {
      return realizeRenderTexture(document, v.id);
    }
    return texture(v.id);
  }

  UnlitMaterial _unlit(Map<String, PropertyValue> p) {
    final m = UnlitMaterial();
    final base = readColor(p, 'baseColor');
    if (base != null) m.baseColorFactor = base;
    final baseColorTexture = _textureRef(p, 'baseColorTexture');
    if (baseColorTexture != null) m.baseColorTexture = baseColorTexture;
    m.doubleSided = readBool(p, 'doubleSided', m.doubleSided);
    return m;
  }

  AlphaMode _alphaMode(String name) => switch (name) {
    'mask' => AlphaMode.mask,
    'blend' => AlphaMode.blend,
    _ => AlphaMode.opaque,
  };

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
    m.normalScale = readDouble(p, 'normalScale', m.normalScale);
    m.doubleSided = readBool(p, 'doubleSided', m.doubleSided);
    m.alphaMode = _alphaMode(readString(p, 'alphaMode', 'opaque'));
    m.alphaCutoff = readDouble(p, 'alphaCutoff', m.alphaCutoff);
    return m;
  }
}
