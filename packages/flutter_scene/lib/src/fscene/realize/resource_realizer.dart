import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/environment_settings.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/fmat_overrides.dart';
import 'package:flutter_scene/src/fscene/realize/stage.dart'
    show EnvironmentAssetLoader, realizeEnvironmentSettings;
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/fscene/realize/views.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/texture/compressed_texture.dart';
import 'package:flutter_scene/src/render/mip_sampling_probe.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';

/// Loads a decoded [ui.Image] for a [TextureResource.asset] from outside the
/// asset bundle (the editor loads a user-imported image from disk). Returns
/// null to fall back to the asset bundle (the in-bundle example assets).
typedef TextureAssetLoader = Future<ui.Image?> Function(AssetRef asset);

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
  /// [environmentLoader] builds an [AssetEnvironment] from outside the bundle
  /// (the editor loads a user-picked file from disk). [textureLoader] decodes a
  /// [TextureResource.asset] from outside the bundle the same way.
  ResourceRealizer(
    this.document, {
    AssetBundle? bundle,
    this.environmentLoader,
    this.textureLoader,
  }) : bundle = bundle ?? rootBundle;

  /// The document whose resources are realized.
  final SceneDocument document;

  /// The asset bundle external assets and `fmat` materials load from.
  final AssetBundle bundle;

  /// Loads an [AssetEnvironment] from outside the asset bundle, or null to use
  /// the bundle. See [EnvironmentAssetLoader].
  final EnvironmentAssetLoader? environmentLoader;

  /// Decodes a [TextureResource.asset] from outside the asset bundle, or null
  /// to use the bundle. See [TextureAssetLoader].
  final TextureAssetLoader? textureLoader;

  final Map<LocalId, Geometry> _geometries = {};
  final Map<LocalId, Material> _materials = {};
  final Map<LocalId, gpu.Texture> _textures = {};
  final Map<LocalId, EnvironmentSettings> _environments = {};

  /// The live geometry for resource [id], realized and memoized on first use.
  /// The result is stamped with its origin so the serializer can recover it.
  Geometry geometry(LocalId id) => _geometries[id] ??= tagResourceOrigin(
    _buildGeometryOrPlaceholder(id),
    document,
    id,
  );

  // Builds geometry [id], degrading to a small placeholder cuboid (with a
  // warning) rather than failing the whole scene realize when the resource is
  // malformed. The common case is a `.fscene` (JSON) reopened without the
  // binary payload chunks its geometry referenced (those live in a `.fsceneb`
  // container), so one lost mesh should not break the entire scene.
  Geometry _buildGeometryOrPlaceholder(LocalId id) {
    try {
      return _buildGeometry(id);
    } on FsceneFormatException catch (e) {
      debugPrint(
        'fscene: geometry $id could not be realized ($e); using a placeholder',
      );
      return CuboidGeometry(Vector3.all(0.25));
    }
  }

  /// The live material for resource [id], realized and memoized on first use.
  Material material(LocalId id) =>
      _materials[id] ??= tagResourceOrigin(_buildMaterial(id), document, id);

  /// The live texture for resource [id], realized and memoized on first use.
  gpu.Texture texture(LocalId id) => _textures[id] ??= tagResourceOrigin(
    _buildTextureOrPlaceholder(id),
    document,
    id,
  );

  // Builds texture [id], degrading to a placeholder (with a warning) rather
  // than failing the whole realize when the resource is malformed (the common
  // case is a `.fscene` reopened without its binary payload chunks).
  gpu.Texture _buildTextureOrPlaceholder(LocalId id) {
    try {
      return _buildTexture(id);
    } on FsceneFormatException catch (e) {
      debugPrint(
        'fscene: texture $id could not be realized ($e); using a placeholder',
      );
      return _placeholderTexture();
    }
  }

  /// The realized look for an [EnvironmentResource] [id], or null when [id] is
  /// not an environment resource. Environments are GPU-bound and async, so they
  /// are built in [preload]; this returns the cached result.
  EnvironmentSettings? environment(LocalId id) => _environments[id];

  /// Resolves the resources that want asynchronous work (every texture, and
  /// `fmat` materials), caching them so the synchronous realize path finds
  /// them ready.
  ///
  /// External image assets and encoded payloads have no synchronous path at
  /// all; an embedded `rgba8` payload does, but preloading it builds its mip
  /// chain on a background isolate instead of the calling thread.
  ///
  /// Await this before realizing a document that may reference such resources
  /// (the async loaders do). A resource that fails to load degrades to a
  /// placeholder (textures) or an unlit material (`fmat`) with a warning,
  /// rather than failing the whole scene.
  ///
  /// Set [includeEnvironments] false to skip realizing [EnvironmentResource]s
  /// (which build GPU prefilter cubes, the expensive part). The editor uses this
  /// to re-realize just a changed material without re-baking environments.
  Future<void> preload({bool includeEnvironments = true}) async {
    // Textures first: an fmat material's parameter overrides may reference a
    // texture resource, which must be decoded before the override resolves it.
    final textures = <Future<void>>[];
    for (final resource in document.resources.values) {
      // Every texture preloads, not only the ones the sync path cannot do at
      // all: an rgba8 payload realizes synchronously but builds its mip chain
      // on the calling thread, and preloading moves that off it.
      if (resource is TextureResource) {
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

    // Environments are GPU-bound and async (they build prefilter cubes and may
    // load image assets), so realize them here and cache the result for the
    // synchronous component realize path.
    if (!includeEnvironments) return;
    for (final resource in document.resources.values) {
      if (resource is EnvironmentResource) {
        _environments[resource.id] = await realizeEnvironmentSettings(
          environment: resource.environment,
          environmentIntensity: resource.environmentIntensity,
          exposure: resource.exposure,
          toneMapping: resource.toneMapping,
          radianceCubeSize: resource.radianceCubeSize,
          skybox: resource.skybox,
          skyEnvironment: resource.skyEnvironment,
          bundle: bundle,
          environmentLoader: environmentLoader,
          payloadLookup: document.payload,
        );
      }
    }
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
    final content = textureContentFromName(res.content);
    final asset = res.asset;
    if (asset != null) {
      // Prefer a disk-loaded image (an editor-imported texture under
      // `imported/`); fall back to the asset bundle for in-bundle assets.
      final loaded = await textureLoader?.call(asset);
      final image = loaded ?? await imageFromAsset(asset.key, bundle: bundle);
      return _mippedTextureFromImage(image, content);
    }
    final payload = document.payload(res.payload!);
    final bytes = _payloadBytes(res.payload!, 'image');
    // KTX2 block payloads carry their own mip chain and transcode off the main
    // isolate; the rest build one here, also off the main isolate.
    if (payload?.format == 'ktx2') {
      return gpuTextureFromKtx2Async(bytes);
    }
    if (payload?.format == 'rgba8') {
      final width = payload!.width;
      final height = payload.height;
      if (width == null || height == null) {
        throw FsceneFormatException(
          'Image payload ${res.payload} is missing its width/height',
        );
      }
      return _mippedTexture(
        Uint8List.sublistView(bytes),
        width,
        height,
        content,
      );
    }
    return _mippedTextureFromImage(await imageFromBytes(bytes), content);
  }

  // Decodes [image] to straight-alpha RGBA and uploads it with a mip chain
  // built off the main isolate.
  Future<gpu.Texture> _mippedTextureFromImage(
    ui.Image image,
    TextureContent content,
  ) async {
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (bytes == null) {
      throw FsceneFormatException('Failed to read RGBA data from an image');
    }
    return _mippedTexture(
      bytes.buffer.asUint8List(),
      image.width,
      image.height,
      content,
    );
  }

  Future<gpu.Texture> _mippedTexture(
    Uint8List pixels,
    int width,
    int height,
    TextureContent content,
  ) async => uploadMipLevels(
    mipChainsAreSampled
        ? await generateMipChainAsync(pixels, width, height, content)
        : <MipLevel>[MipLevel(width, height, pixels)],
    width,
    height,
  );

  Future<void> _preloadFmat(MaterialResource res) async {
    final asset = res.asset;
    if (asset == null) {
      debugPrint('fscene: fmat material ${res.id} has no asset; using unlit');
      _materials[res.id] = tagResourceOrigin(
        _unlit(res.properties)..name = res.name,
        document,
        res.id,
      );
      return;
    }
    try {
      final material = await loadFmatMaterial(asset.key, bundle: bundle);
      material.name = res.name;
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
        _unlit(res.properties)..name = res.name,
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
    final layout = vertexPayload.layout;
    final soa = layout == InterleavedLayoutAdapter.unskinnedSoaLayout;
    final skinned = layout == 'skinned';
    // The de-interleaved and interleaved unskinned payloads carry the same
    // 48 bytes per vertex, just reordered; skinned is 80.
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
    // bounds, the upload scans unskinned positions (and leaves skinned
    // geometry unbounded, matching the importer).
    final bounds = res.bounds;
    if (bounds != null) {
      final aabb = Aabb3.minMax(bounds.min.clone(), bounds.max.clone());
      geometry.setLocalBounds(aabb, _circumscribedSphere(aabb));
    }

    if (soa) {
      // De-interleaved payload: upload each attribute stream straight to its
      // GPU buffer, no realize-time reshuffle.
      (geometry as UnskinnedGeometry).uploadUnskinnedAttributeStreams(
        InterleavedLayoutAdapter.sliceUnskinnedStreams(
          vertexBytes,
          vertexCount,
        ),
        vertexCount,
        indices: indexBytes,
        indexType: indexType,
      );
    } else {
      // Interleaved payload (skinned, or a pre-SoA unskinned document): the
      // unskinned path de-interleaves once here.
      geometry.uploadVertexData(
        ByteData.sublistView(vertexBytes),
        vertexCount,
        indexBytes,
        indexType: indexType,
      );
    }
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
    return _materialForType(res)..name = res.name;
  }

  Material _materialForType(MaterialResource res) {
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
    // Through Texture2D so the upload carries a role-aware mip chain; only
    // the compressed (ktx2) payloads ship their own. This builds the chain on
    // the calling thread, which only a synchronous realize reaches: preload()
    // takes every texture through the isolate first.
    return Texture2D.fromPixels(
      Uint8List.sublistView(bytes),
      width,
      height,
      content: textureContentFromName(res.content),
    ).gpuTexture;
  }

  // Resolves a texture property to either a gpu.Texture or, when the ref
  // points at a render-texture resource, the live RenderTexture handle
  // (material slots accept both).
  TextureSource? _textureRef(Map<String, PropertyValue> p, String key) {
    final v = p[key];
    if (v is! ResourceRefValue) return null;
    if (document.resource(v.id) is RenderTextureResource) {
      return realizeRenderTexture(document, v.id);
    }
    return GpuTextureSource(texture(v.id));
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
