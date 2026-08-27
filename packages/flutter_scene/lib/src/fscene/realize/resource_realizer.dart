import 'dart:ui' as ui;

import 'package:collection/collection.dart' show DeepCollectionEquality;
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
import 'package:flutter_scene/src/geometry/morph_targets.dart';
import 'package:flutter_scene/src/geometry/morphed_geometry.dart';
import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_scene/src/geometry/terrain.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_scene/src/importer/constants.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physical_material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/preprocessed_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/texture/compressed_texture.dart';
import 'package:flutter_scene/src/render/mip_sampling_probe.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/mipmap_async.dart';

/// Loads a decoded [ui.Image] for a [TextureResource.asset] from outside the
/// asset bundle (the editor loads a user-imported image from disk). Returns
/// null to fall back to the asset bundle (the in-bundle example assets).
typedef TextureAssetLoader = Future<ui.Image?> Function(AssetRef asset);

/// Loads a compiled `.fmat` material from outside the active asset bundle.
typedef FmatMaterialLoader =
    Future<PreprocessedMaterial> Function(AssetRef asset);

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
  /// [fmatMaterialLoader] loads compiled `.fmat` output from outside the bundle.
  ResourceRealizer(
    this.document, {
    AssetBundle? bundle,
    this.environmentLoader,
    this.textureLoader,
    this.fmatMaterialLoader,
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

  /// Loads a compiled `.fmat` from outside the asset bundle.
  final FmatMaterialLoader? fmatMaterialLoader;

  final Map<LocalId, Geometry> _geometries = {};
  final Map<LocalId, Material> _materials = {};
  final Map<LocalId, gpu.Texture> _textures = {};
  final Map<LocalId, EnvironmentSettings> _environments = {};

  /// Carries realized resources over from [previous] (the realizer the live
  /// scene was built with) for every resource whose spec and payload bytes
  /// are unchanged, so a hot reload rebuilds only what actually changed
  /// instead of re-uploading the whole document (seconds for a large scene).
  /// Call before [preload]; [preload] skips carried-over entries.
  ///
  /// Unchanged payload bytes are detected by object identity, which holds for
  /// sidecar-cached source loads and for documents sharing chunk buffers; a
  /// byte-equal but distinct buffer just rebuilds that resource.
  void adoptUnchanged(ResourceRealizer previous) {
    const equality = DeepCollectionEquality();
    final oldResources = _encodedResources(previous.document);
    final newResources = _encodedResources(document);

    bool payloadUnchanged(LocalId id) {
      final old = previous.document.payloads[id];
      final current = document.payloads[id];
      if (old == null || current == null) return false;
      return old.encoding == current.encoding &&
          old.layout == current.layout &&
          old.format == current.format &&
          old.width == current.width &&
          old.height == current.height &&
          old.length == current.length &&
          identical(old.bytes, current.bytes);
    }

    bool specUnchanged(LocalId id) =>
        equality.equals(oldResources[id], newResources[id]);

    final adoptedTextures = <LocalId>{};
    for (final entry in document.resources.entries) {
      final id = entry.key;
      final resource = entry.value;
      if (!specUnchanged(id)) continue;
      switch (resource) {
        case GeometryResource():
          if (resource.vertices case final vertices?
              when !payloadUnchanged(vertices)) {
            continue;
          }
          if (resource.indices case final indices?
              when !payloadUnchanged(indices)) {
            continue;
          }
          final geometry = previous._geometries[id];
          if (geometry != null) _geometries[id] = geometry;
        case TextureResource():
          if (resource.payload case final payload?
              when !payloadUnchanged(payload)) {
            continue;
          }
          final texture = previous._textures[id];
          if (texture != null) {
            _textures[id] = texture;
            adoptedTextures.add(id);
          }
        case EnvironmentResource():
          if (resource.environment case PayloadEnvironment(
            :final payload,
          ) when !payloadUnchanged(payload)) {
            continue;
          }
          final environment = previous._environments[id];
          if (environment != null) _environments[id] = environment;
        default:
          break;
      }
    }
    // A material realizes against its referenced textures, so it carries over
    // only when they all did.
    for (final entry in document.resources.entries) {
      final id = entry.key;
      final resource = entry.value;
      if (resource is! MaterialResource || !specUnchanged(id)) continue;
      final textureRefs = [
        for (final value in resource.properties.values)
          if (value case ResourceRefValue(:final id)) id,
      ];
      if (!textureRefs.every(adoptedTextures.contains)) continue;
      final material = previous._materials[id];
      if (material != null) _materials[id] = material;
    }
  }

  static Map<LocalId, Object?> _encodedResources(SceneDocument document) {
    final encoded = (encodeDocument(document)['resources'] as Map?) ?? const {};
    final byId = <LocalId, Object?>{};
    for (final entry in encoded.entries) {
      // Encoded keys are '<prefix>:<idToken>'; parse strips the prefix.
      byId[LocalId.parse(entry.key as String)] = entry.value;
    }
    return byId;
  }

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

  /// Rebuilds one material while retaining already loaded texture resources.
  ///
  /// Editors use this after changing a material descriptor. Re-running
  /// [preload] would decode every texture in the document even though the
  /// changed material normally references the same textures.
  Future<Material> reloadMaterial(LocalId id) async {
    final resource = document.resource(id);
    if (resource is! MaterialResource) {
      throw FsceneFormatException('Resource $id is not a material');
    }
    for (final value in resource.properties.values) {
      if (value case ResourceRefValue(:final id)) {
        final textureResource = document.resource(id);
        if (textureResource is TextureResource && !_textures.containsKey(id)) {
          await _preloadTexture(textureResource);
        }
      }
    }
    _materials.remove(id);
    switch (resource.type) {
      case 'fmat':
        await _preloadFmat(resource);
      case 'physical':
        await _preloadPhysical(resource);
      default:
        _materials[id] = tagResourceOrigin(_buildMaterial(id), document, id);
    }
    return _materials[id]!;
  }

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
      // on the calling thread, and preloading moves that off it. Entries
      // carried over by [adoptUnchanged] are already live.
      if (resource is TextureResource && !_textures.containsKey(resource.id)) {
        textures.add(_preloadTexture(resource));
      }
    }
    await Future.wait(textures);

    final materials = <Future<void>>[];
    for (final resource in document.resources.values) {
      if (resource is MaterialResource &&
          !_materials.containsKey(resource.id)) {
        if (resource.type == 'fmat') {
          materials.add(_preloadFmat(resource));
        } else if (resource.type == 'physical') {
          materials.add(_preloadPhysical(resource));
        }
      }
    }
    await Future.wait(materials);

    // Environments are GPU-bound and async (they build prefilter cubes and may
    // load image assets), so realize them here and cache the result for the
    // synchronous component realize path.
    if (!includeEnvironments) return;
    for (final resource in document.resources.values) {
      if (resource is EnvironmentResource &&
          !_environments.containsKey(resource.id)) {
        // Origin-tagged below so a component holding the realized settings
        // can recover the source resource at serialize time.
        _environments[resource.id] = tagResourceOrigin(
          await realizeEnvironmentSettings(
            environment: resource.environment,
            environmentIntensity: resource.environmentIntensity,
            exposure: resource.exposure,
            toneMapping: resource.toneMapping,
            agxWhite: resource.agxWhite,
            agxContrast: resource.agxContrast,
            environmentRotationY: resource.environmentRotationY,
            radianceCubeSize: resource.radianceCubeSize,
            skybox: resource.skybox,
            skyEnvironment: resource.skyEnvironment,
            effects: resource.effects,
            bundle: bundle,
            environmentLoader: environmentLoader,
            payloadLookup: document.payload,
          ),
          document,
          resource.id,
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
        _unlit(res.properties)
          ..name = res.name
          ..depthBias = readDouble(res.properties, 'depthBias', 0),
        document,
        res.id,
      );
      return;
    }
    try {
      final material = fmatMaterialLoader == null
          ? await loadFmatMaterial(asset.key, bundle: bundle)
          : await fmatMaterialLoader!(asset);
      material
        ..name = res.name
        ..depthBias = readDouble(res.properties, 'depthBias', 0);
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
        _unlit(res.properties)
          ..name = res.name
          ..depthBias = readDouble(res.properties, 'depthBias', 0),
        document,
        res.id,
      );
    }
  }

  Future<void> _preloadPhysical(MaterialResource res) async {
    try {
      final material = await PhysicallyBasedMaterial.fromDescriptor(
        _physicalDescriptor(res),
      );
      material.name = res.name;
      _materials[res.id] = tagResourceOrigin(material, document, res.id);
    } catch (e) {
      debugPrint(
        'fscene: failed to realize physical material ${res.id}: $e; using PBR',
      );
      _materials[res.id] = tagResourceOrigin(
        _pbr(res.properties)..name = res.name,
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
    late final bool soa;
    late final bool skinned;
    late final bool legacy;
    late final int perVertexBytes;
    if (layout == InterleavedLayoutAdapter.unskinnedSoaLayout) {
      soa = true;
      skinned = false;
      legacy = false;
      perVertexBytes = kUnskinnedPerVertexSize;
    } else if (layout == InterleavedLayoutAdapter.unskinnedInterleavedLayout) {
      soa = false;
      skinned = false;
      legacy = false;
      perVertexBytes = kUnskinnedPerVertexSize;
    } else if (layout == InterleavedLayoutAdapter.skinnedLayout) {
      soa = false;
      skinned = true;
      legacy = false;
      perVertexBytes = kSkinnedPerVertexSize;
    } else if (layout == 'unskinned_soa') {
      soa = true;
      skinned = false;
      legacy = true;
      perVertexBytes = InterleavedLayoutAdapter.legacyUnskinnedVertexBytes;
    } else if (layout == 'skinned') {
      soa = false;
      skinned = true;
      legacy = true;
      perVertexBytes = InterleavedLayoutAdapter.legacySkinnedVertexBytes;
    } else if (layout == 'unskinned' || layout == null) {
      soa = false;
      skinned = false;
      legacy = true;
      perVertexBytes = InterleavedLayoutAdapter.legacyUnskinnedVertexBytes;
    } else {
      throw FsceneFormatException(
        'Geometry ${res.id} uses unknown vertex layout "$layout"',
      );
    }
    if (vertexBytes.lengthInBytes % perVertexBytes != 0) {
      throw FsceneFormatException(
        'Geometry ${res.id} vertex payload has ${vertexBytes.lengthInBytes} '
        'bytes, which is not divisible by its $perVertexBytes-byte layout',
      );
    }
    final vertexCount = vertexBytes.lengthInBytes ~/ perVertexBytes;
    final morphData = res.morphTargets == null
        ? null
        : _buildMorphData(res, res.morphTargets!, vertexCount);
    final Geometry geometry = skinned
        ? (morphData != null
              ? MorphedSkinnedGeometry(morphData)
              : SkinnedGeometry())
        : (morphData != null
              ? MorphedUnskinnedGeometry(morphData)
              : UnskinnedGeometry());

    ByteData? indexBytes;
    var indexType = gpu.IndexType.int16;
    final indexId = res.indices;
    if (indexId != null) {
      final rawIndexBytes = _payloadBytes(indexId, 'index');
      final isUint32 = document.payload(indexId)!.format == 'uint32';
      indexType = isUint32 ? gpu.IndexType.int32 : gpu.IndexType.int16;
      final isTriangleTopology = res.topology == 'triangle';
      if ((res.legacyWinding || document.formatVersion < 5) &&
          isTriangleTopology) {
        final migrated = Uint8List.fromList(rawIndexBytes);
        if (isUint32) {
          final u32 = migrated.buffer.asUint32List(
            migrated.offsetInBytes,
            migrated.lengthInBytes ~/ 4,
          );
          for (var i = 0; i + 2 < u32.length; i += 3) {
            final tmp = u32[i + 1];
            u32[i + 1] = u32[i + 2];
            u32[i + 2] = tmp;
          }
        } else {
          final u16 = migrated.buffer.asUint16List(
            migrated.offsetInBytes,
            migrated.lengthInBytes ~/ 2,
          );
          for (var i = 0; i + 2 < u16.length; i += 3) {
            final tmp = u16[i + 1];
            u16[i + 1] = u16[i + 2];
            u16[i + 2] = tmp;
          }
        }
        indexBytes = ByteData.sublistView(migrated);
      } else {
        // TODO(winding): Support legacy winding migration for triangleStrip
        // topology (requires vertex-order reversal, not index-triple swap).
        // TODO(winding): Support non-indexed geometry winding migration.
        indexBytes = ByteData.sublistView(rawIndexBytes);
      }
    }

    // Set baked bounds before upload so the position scan is skipped; without
    // bounds, the upload scans unskinned positions (and leaves skinned
    // geometry unbounded, matching the importer).
    final bounds = res.bounds;
    if (bounds != null) {
      final aabb = Aabb3.minMax(bounds.min.clone(), bounds.max.clone());
      geometry.setLocalBounds(aabb, _circumscribedSphere(aabb));
    }

    if (legacy && soa) {
      (geometry as UnskinnedGeometry).uploadUnskinnedAttributeStreams(
        InterleavedLayoutAdapter.upgradeLegacyUnskinnedSoa(
          vertexBytes,
          vertexCount,
        ),
        vertexCount,
        indices: indexBytes,
        indexType: indexType,
      );
    } else if (soa && morphData != null) {
      // Morphed geometry keeps its base interleaved for CPU re-blending, so
      // a structure-of-arrays payload (the emitter writes morphed geometry
      // interleaved, but be tolerant) is interleaved once here.
      final streams = InterleavedLayoutAdapter.sliceUnskinnedStreams(
        vertexBytes,
        vertexCount,
      );
      geometry.uploadVertexData(
        ByteData.sublistView(
          InterleavedLayoutAdapter.packUnskinned(
            positions: Float32List.sublistView(streams.position),
            vertexCount: vertexCount,
            normals: Float32List.sublistView(streams.normal),
            texCoords: Float32List.sublistView(streams.texCoord),
            texCoords1: Float32List.sublistView(streams.texCoord1),
            colors: Float32List.sublistView(streams.color),
            tangents: Float32List.sublistView(streams.tangent),
          ),
        ),
        vertexCount,
        indexBytes,
        indexType: indexType,
      );
    } else if (soa) {
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
      final upgraded = legacy
          ? skinned
                ? InterleavedLayoutAdapter.upgradeLegacySkinnedInterleaved(
                    ByteData.sublistView(vertexBytes),
                    vertexCount,
                  )
                : InterleavedLayoutAdapter.upgradeLegacyUnskinnedInterleaved(
                    ByteData.sublistView(vertexBytes),
                    vertexCount,
                  )
          : vertexBytes;
      geometry.uploadVertexData(
        ByteData.sublistView(upgraded),
        vertexCount,
        indexBytes,
        indexType: indexType,
      );
    }
    geometry.primitiveType = _topology(res.topology);
    return geometry;
  }

  /// Reads a geometry's morph delta payload into engine [MorphTargetData]:
  /// the dense position slab, then the normal and tangent slabs when the
  /// spec declares them.
  MorphTargetData _buildMorphData(
    GeometryResource res,
    MorphTargetsSpec spec,
    int vertexCount,
  ) {
    final bytes = _payloadBytes(spec.deltas, 'morph delta');
    final floats = bytes.offsetInBytes % 4 == 0
        ? bytes.buffer.asFloat32List(
            bytes.offsetInBytes,
            bytes.lengthInBytes ~/ 4,
          )
        : Float32List.sublistView(Uint8List.fromList(bytes));
    final slab = spec.targetCount * vertexCount * 3;
    final sections =
        1 + (spec.hasNormalDeltas ? 1 : 0) + (spec.hasTangentDeltas ? 1 : 0);
    if (floats.length < slab * sections) {
      throw FsceneFormatException(
        'Geometry ${res.id} morph delta payload has ${floats.length} floats; '
        'expected ${slab * sections} for ${spec.targetCount} targets of '
        '$vertexCount vertices',
      );
    }
    var offset = slab;
    Float32List? section(bool present) {
      if (!present) return null;
      final result = Float32List.sublistView(floats, offset, offset + slab);
      offset += slab;
      return result;
    }

    return MorphTargetData(
      vertexCount: vertexCount,
      targetCount: spec.targetCount,
      positionDeltas: Float32List.sublistView(floats, 0, slab),
      normalDeltas: section(spec.hasNormalDeltas),
      tangentDeltas: section(spec.hasTangentDeltas),
      targetNames: spec.targetNames,
      defaultWeights: spec.defaultWeights,
    );
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
    TorusGeometrySpec(
      :final radius,
      :final tubeRadius,
      :final radialSegments,
      :final tubularSegments,
    ) =>
      TorusGeometry(
        radius: radius,
        tubeRadius: tubeRadius,
        radialSegments: radialSegments,
        tubularSegments: tubularSegments,
      ),
    CylinderGeometrySpec(
      :final bottomRadius,
      :final topRadius,
      :final height,
      :final radialSegments,
      :final heightSegments,
      :final bottomCap,
      :final topCap,
    ) =>
      CylinderGeometry(
        bottomRadius: bottomRadius,
        topRadius: topRadius,
        height: height,
        radialSegments: radialSegments,
        heightSegments: heightSegments,
        bottomCap: bottomCap,
        topCap: topCap,
      ),
    CapsuleGeometrySpec(
      :final radius,
      :final height,
      :final radialSegments,
      :final capRings,
    ) =>
      CapsuleGeometry(
        radius: radius,
        height: height,
        radialSegments: radialSegments,
        capRings: capRings,
      ),
    DiscGeometrySpec(:final radius, :final segments) => DiscGeometry(
      radius: radius,
      segments: segments,
    ),
    WedgeGeometrySpec(:final size) => WedgeGeometry(size),
    TerrainGeometrySpec(
      :final width,
      :final depth,
      :final columns,
      :final rows,
      :final amplitude,
      :final frequency,
      :final octaves,
      :final seed,
    ) =>
      TerrainGeometry.noise(
        width: width,
        depth: depth,
        columns: columns,
        rows: rows,
        amplitude: amplitude,
        frequency: frequency,
        octaves: octaves,
        seed: seed,
      ),
    IcosphereGeometrySpec(:final radius, :final subdivisions) =>
      IcosphereGeometry(radius: radius, subdivisions: subdivisions),
  };

  Material _buildMaterial(LocalId id) {
    final res = document.resource(id);
    if (res is! MaterialResource) {
      throw FsceneFormatException('Resource $id is not a material');
    }
    return _materialForType(res)
      ..name = res.name
      ..depthBias = readDouble(res.properties, 'depthBias', 0);
  }

  Material _materialForType(MaterialResource res) {
    switch (res.type) {
      case 'unlit':
        return _unlit(res.properties);
      case 'physicallyBased':
        return _pbr(res.properties);
      case 'physical':
        debugPrint(
          'fscene: physical material needs the async loader; using core PBR',
        );
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
    m.baseColorTextureTransform = _textureTransform(
      p,
      'baseColorTextureTransform',
    );
    m.baseColorTextureTexCoord = _textureTexCoord(
      p,
      'baseColorTextureTransform',
    );
    m.doubleSided = readBool(p, 'doubleSided', m.doubleSided);
    m.alphaMode = _alphaMode(readString(p, 'alphaMode', 'opaque'));
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
    m.emissiveStrength = readDouble(p, 'emissiveStrength', m.emissiveStrength);
    m.metallicFactor = readDouble(p, 'metallic', m.metallicFactor);
    m.roughnessFactor = readDouble(p, 'roughness', m.roughnessFactor);
    m.occlusionStrength = readDouble(
      p,
      'occlusionStrength',
      m.occlusionStrength,
    );
    final baseColorTexture = _textureRef(p, 'baseColorTexture');
    if (baseColorTexture != null) m.baseColorTexture = baseColorTexture;
    m.baseColorTextureTransform = _textureTransform(
      p,
      'baseColorTextureTransform',
    );
    m.baseColorTextureTexCoord = _textureTexCoord(
      p,
      'baseColorTextureTransform',
    );
    final metallicRoughnessTexture = _textureRef(p, 'metallicRoughnessTexture');
    if (metallicRoughnessTexture != null) {
      m.metallicRoughnessTexture = metallicRoughnessTexture;
    }
    m.metallicRoughnessTextureTransform = _textureTransform(
      p,
      'metallicRoughnessTextureTransform',
    );
    m.metallicRoughnessTextureTexCoord = _textureTexCoord(
      p,
      'metallicRoughnessTextureTransform',
    );
    final normalTexture = _textureRef(p, 'normalTexture');
    if (normalTexture != null) m.normalTexture = normalTexture;
    m.normalTextureTransform = _textureTransform(p, 'normalTextureTransform');
    m.normalTextureTexCoord = _textureTexCoord(p, 'normalTextureTransform');
    final occlusionTexture = _textureRef(p, 'occlusionTexture');
    if (occlusionTexture != null) m.occlusionTexture = occlusionTexture;
    m.occlusionTextureTransform = _textureTransform(
      p,
      'occlusionTextureTransform',
    );
    m.occlusionTextureTexCoord = _textureTexCoord(
      p,
      'occlusionTextureTransform',
    );
    final emissiveTexture = _textureRef(p, 'emissiveTexture');
    if (emissiveTexture != null) m.emissiveTexture = emissiveTexture;
    m.emissiveTextureTransform = _textureTransform(
      p,
      'emissiveTextureTransform',
    );
    m.emissiveTextureTexCoord = _textureTexCoord(p, 'emissiveTextureTransform');
    m.normalScale = readDouble(p, 'normalScale', m.normalScale);
    m.doubleSided = readBool(p, 'doubleSided', m.doubleSided);
    m.alphaMode = _alphaMode(readString(p, 'alphaMode', 'opaque'));
    m.alphaCutoff = readDouble(p, 'alphaCutoff', m.alphaCutoff);
    return m;
  }

  PhysicalMaterialDescriptor _physicalDescriptor(MaterialResource resource) {
    final p = resource.properties;
    return PhysicalMaterialDescriptor(
      name: resource.name,
      baseColorTexture: _physicalTexture(p, 'baseColorTexture'),
      baseColor: readColor(p, 'baseColor'),
      metallicRoughnessTexture: _physicalTexture(p, 'metallicRoughnessTexture'),
      metallic: readDouble(p, 'metallic', 1.0),
      roughness: readDouble(p, 'roughness', 1.0),
      normalTexture: _physicalTexture(p, 'normalTexture'),
      normalScale: readDouble(p, 'normalScale', 1.0),
      occlusionTexture: _physicalTexture(p, 'occlusionTexture'),
      occlusionStrength: readDouble(p, 'occlusionStrength', 1.0),
      emissiveTexture: _physicalTexture(p, 'emissiveTexture'),
      emissive: readColor(p, 'emissive'),
      emissiveStrength: readDouble(p, 'emissiveStrength', 1.0),
      specularTexture: _physicalTexture(p, 'specularTexture'),
      specular: readDouble(p, 'specular', 1.0),
      specularColorTexture: _physicalTexture(p, 'specularColorTexture'),
      specularColor: readColor(p, 'specularColor'),
      ior: readDouble(p, 'ior', 1.5),
      clearcoatTexture: _physicalTexture(p, 'clearcoatTexture'),
      clearcoat: readDouble(p, 'clearcoat', 0.0),
      clearcoatRoughnessTexture: _physicalTexture(
        p,
        'clearcoatRoughnessTexture',
      ),
      clearcoatRoughness: readDouble(p, 'clearcoatRoughness', 0.0),
      clearcoatNormalTexture: _physicalTexture(p, 'clearcoatNormalTexture'),
      clearcoatNormalScale: switch (p['clearcoatNormalScale']) {
        DoubleValue(:final value) => Vector2.all(value),
        _ => readVec2(p, 'clearcoatNormalScale', Vector2.all(1.0)),
      },
      sheenColorTexture: _physicalTexture(p, 'sheenColorTexture'),
      sheenColor: readColor(p, 'sheenColor'),
      sheenRoughnessTexture: _physicalTexture(p, 'sheenRoughnessTexture'),
      sheenRoughness: readDouble(p, 'sheenRoughness', 0.0),
      transmissionTexture: _physicalTexture(p, 'transmissionTexture'),
      transmission: readDouble(p, 'transmission', 0.0),
      diffuseTransmissionTexture: _physicalTexture(
        p,
        'diffuseTransmissionTexture',
      ),
      diffuseTransmission: readDouble(p, 'diffuseTransmission', 0.0),
      diffuseTransmissionColorTexture: _physicalTexture(
        p,
        'diffuseTransmissionColorTexture',
      ),
      diffuseTransmissionColor: readColor(p, 'diffuseTransmissionColor'),
      thicknessTexture: _physicalTexture(p, 'thicknessTexture'),
      thickness: readDouble(p, 'thickness', 0.0),
      attenuationDistance: readDouble(
        p,
        'attenuationDistance',
        double.infinity,
      ),
      attenuationColor: readColor(p, 'attenuationColor'),
      dispersion: readDouble(p, 'dispersion', 0.0),
      iridescenceTexture: _physicalTexture(p, 'iridescenceTexture'),
      iridescence: readDouble(p, 'iridescence', 0.0),
      iridescenceIor: readDouble(p, 'iridescenceIor', 1.3),
      iridescenceThicknessTexture: _physicalTexture(
        p,
        'iridescenceThicknessTexture',
      ),
      iridescenceThicknessMinimum: readDouble(
        p,
        'iridescenceThicknessMinimum',
        100.0,
      ),
      iridescenceThicknessMaximum: readDouble(
        p,
        'iridescenceThicknessMaximum',
        400.0,
      ),
      anisotropyTexture: _physicalTexture(p, 'anisotropyTexture'),
      anisotropy: readDouble(p, 'anisotropy', 0.0),
      anisotropyRotation: readDouble(p, 'anisotropyRotation', 0.0),
      alphaMode: _alphaMode(readString(p, 'alphaMode', 'opaque')),
      alphaCutoff: readDouble(p, 'alphaCutoff', 0.5),
      doubleSided: readBool(p, 'doubleSided', false),
    );
  }

  PhysicalTexture _physicalTexture(
    Map<String, PropertyValue> properties,
    String key,
  ) {
    final transformKey = '${key}Transform';
    final transformValue = properties[transformKey];
    final texCoord = transformValue is MapValue
        ? readInt(transformValue.values, 'texCoord', 0)
        : 0;
    return PhysicalTexture(
      source: _textureRef(properties, key),
      transform: _textureTransform(properties, transformKey),
      texCoord: texCoord,
    );
  }

  TextureTransform _textureTransform(
    Map<String, PropertyValue> properties,
    String key,
  ) {
    final value = properties[key];
    if (value is! MapValue) return TextureTransform();
    final values = value.values;
    return TextureTransform(
      offset: readVec2(values, 'offset', Vector2.zero()),
      scale: readVec2(values, 'scale', Vector2.all(1.0)),
      rotation: readDouble(values, 'rotation', 0.0),
    );
  }

  int _textureTexCoord(Map<String, PropertyValue> properties, String key) {
    final value = properties[key];
    return value is MapValue
        ? readInt(value.values, 'texCoord', 0).clamp(0, 1)
        : 0;
  }
}
