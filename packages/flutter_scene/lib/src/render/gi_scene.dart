import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/material/unlit_material.dart';
import 'package:flutter_scene/src/render/gi_bvh.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:vector_math/vector_math.dart';

/// Floats per instance record: the world-to-object rows, then the bottom
/// level's first node and triangle, the material, and the mirror sign.
const int kGiInstanceStride = 16;

/// Floats per material record: albedo with 1 in w when double-sided,
/// emission, then the albedo and emission tiles (-1 for none).
const int kGiMaterialStride = 12;

/// Floats per light record, the lit shader's first four parameter texels.
const int kGiLightStride = 16;

/// Whether the traced feed builds bottom levels on another isolate. Tests
/// that need the scene on the first frame turn it off.
@visibleForTesting
bool giBuildOnIsolate = true;

/// The scene as the traced feed sees it: packed bottom levels, rebuilt when
/// the set of meshes changes, and per-frame instances, materials, and lights.
///
/// Each distinct mesh gets one bottom level in object space, built on another
/// isolate, shared by every instance of it. Skinned meshes get a copy each,
/// which [GiSkinnedRegion] rebuilds from their compute-skinned vertices and
/// refits every frame.
class GiScene {
  final Map<Geometry, _BlasEntry> _blases = Map.identity();

  /// Packed bottom levels, reuploaded when [_layoutKey] changes.
  gpu.DeviceBuffer? blasNodes;
  gpu.DeviceBuffer? blasTriangles;
  gpu.DeviceBuffer? corners;
  gpu.DeviceBuffer? refitOrder;
  List<Object> _layoutKey = const [];
  final Map<_BlasEntry, (int, int)> _staticOffsets = Map.identity();
  final Map<RenderItem, GiSkinnedRegion> _skinnedRegions = Map.identity();

  /// Material texture tiles, keyed by texture.
  final GiMaterialAtlas atlas = GiMaterialAtlas();

  /// The most recent build, for tests.
  @visibleForTesting
  static Duration debugLastBuild = Duration.zero;

  /// What the most recent frame traced, for tests.
  @visibleForTesting
  static ({int bounded, int skinned, int materials, int textures})?
  debugLastFrame;

  /// Gathers this frame's instances, building bottom levels for meshes seen
  /// for the first time and repacking when the set of ready ones changed.
  GiSceneFrame prepare(RenderScene scene, {double emissiveBoost = 1.0}) {
    atlas.reset();
    final statics = <(RenderItem, _BlasEntry)>[];
    final skinned = <(RenderItem, _BlasEntry)>[];
    for (final item in scene.items) {
      final geometry = item.geometry;
      if (!item.visible ||
          !item.primitiveVisible ||
          !geometry.isReadable ||
          geometry.primitiveType != gpu.PrimitiveType.triangle ||
          item.material.drawsNothing) {
        continue;
      }
      // TODO(gi-trace-dynamic): morph targets are left out. Rebuild their
      // triangles from a compute-morphed stream as skinned meshes do.
      if (item.morphWeights != null) continue;
      final isSkinned = item.jointsTexture != null;
      // A skinned mesh is traced only from its compute-skinned vertices.
      // TODO(gi-trace-dynamic): skin on the CPU where compute skinning is off.
      if (isSkinned &&
          (item.preSkinnedVertices == null ||
              !identical(item.preSkinnedSource, geometry))) {
        continue;
      }
      final entry = _entryFor(geometry);
      if (entry == null) continue;
      (isSkinned ? skinned : statics).add((item, entry));
    }
    _repack(statics, skinned);

    final materials = _GiMaterialTable(atlas, emissiveBoost);
    final bounded = <_Instance>[];
    for (final (item, entry) in statics) {
      final (nodeBase, triangleBase) = _staticOffsets[entry]!;
      final material = materials.indexOf(item.material);
      final transforms = item.instanceTransforms;
      if (transforms == null) {
        bounded.add(
          _Instance.of(
            item.worldTransform,
            entry.blas!,
            nodeBase,
            triangleBase,
            material,
          ),
        );
      } else {
        for (final local in transforms) {
          bounded.add(
            _Instance.of(
              item.worldTransform.multiplied(local),
              entry.blas!,
              nodeBase,
              triangleBase,
              material,
            ),
          );
        }
      }
    }

    // TODO(gi-trace-build): the top level is rebuilt on the UI thread every
    // frame. Refit it instead while the instance set is unchanged.
    final boxes = Float32List(bounded.length * 6);
    for (var i = 0; i < bounded.length; i++) {
      boxes.setAll(i * 6, bounded[i].bounds);
    }
    final tlas = GiBvhNodes.build(boxes, maxLeaf: 2);
    final skinnedRegions = [
      for (final (item, _) in skinned) _skinnedRegions[item]!,
    ];
    final instanceCount = bounded.length + skinned.length;
    final instances = Float32List(
      math.max(1, instanceCount) * kGiInstanceStride,
    );
    for (var i = 0; i < bounded.length; i++) {
      bounded[tlas.order[i]].write(instances, i * kGiInstanceStride);
    }
    for (var i = 0; i < skinned.length; i++) {
      final (item, _) = skinned[i];
      final region = skinnedRegions[i];
      // Skinned vertices are already in world space.
      _Instance(
        Matrix4.identity(),
        const [],
        region.nodeBase,
        region.triangleBase,
        materials.indexOf(item.material),
        1.0,
      ).write(instances, (bounded.length + i) * kGiInstanceStride);
    }

    debugLastFrame = (
      bounded: bounded.length,
      skinned: skinned.length,
      materials: materials.count,
      textures: atlas.textureCount,
    );
    return GiSceneFrame(
      tlasNodes: tlas.nodeCount == 0
          ? Float32List(kGiBvhNodeStride)
          : tlas.nodes,
      tlasNodeCount: tlas.nodeCount,
      instances: instances,
      boundedCount: bounded.length,
      instanceCount: instanceCount,
      materials: materials.finish(),
      skinned: [
        for (var i = 0; i < skinned.length; i++)
          (skinned[i].$1.preSkinnedVertices!, skinnedRegions[i]),
      ],
    );
  }

  /// Packs the scene's punctual lights other than [primary] as the lit
  /// shader does, keeping each light's first four texels.
  static (Float32List, int) packLights(RenderScene scene) {
    final (params, count) = PunctualLightBuffer.packLights(
      directionals: scene.directionalLights,
      primaryDirectional: scene.primaryDirectionalLight,
      points: scene.pointLights,
      spots: scene.spotLights,
    );
    final lights = Float32List(math.max(1, count) * kGiLightStride);
    for (var i = 0; i < count; i++) {
      lights.setRange(
        i * kGiLightStride,
        (i + 1) * kGiLightStride,
        params,
        i * (params.length ~/ count),
      );
    }
    return (lights, count);
  }

  _BlasEntry? _entryFor(Geometry geometry) {
    final version = geometry.localBoundsVersion;
    var entry = _blases[geometry];
    if (entry == null || entry.version != version) {
      entry = _BlasEntry(version);
      _blases[geometry] = entry;
      _build(geometry, entry);
    }
    return entry.blas == null ? null : entry;
  }

  void _build(Geometry geometry, _BlasEntry entry) {
    final mesh = geometry.extractMeshData();
    final indices = mesh.indices;
    final input = GiBlasInput(
      positions: mesh.positions,
      uvs: mesh.texCoords,
      indices: indices == null
          ? null
          : (indices is Int32List ? indices : Int32List.fromList(indices)),
    );
    if (!giBuildOnIsolate) {
      final watch = Stopwatch()..start();
      entry.blas = buildGiBlas(input);
      debugLastBuild = watch.elapsed;
      return;
    }
    final watch = Stopwatch()..start();
    compute(buildGiBlas, input, debugLabel: 'gi bottom level').then(
      (blas) {
        debugLastBuild = watch.elapsed;
        if (identical(_blases[geometry], entry)) entry.blas = blas;
      },
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'flutter_scene',
            context: ErrorDescription('while building a traced GI mesh'),
          ),
        );
      },
    );
  }

  // Packs every ready static bottom level, then a copy per skinned item,
  // when the set of either changed since the last frame.
  void _repack(
    List<(RenderItem, _BlasEntry)> statics,
    List<(RenderItem, _BlasEntry)> skinned,
  ) {
    final uniqueStatics = <_BlasEntry>{
      for (final (_, entry) in statics) entry,
    }.toList();
    final key = <Object>[
      ...uniqueStatics,
      _separator,
      for (final (item, entry) in skinned) ...[item, entry],
    ];
    if (listEquals(key, _layoutKey) && blasNodes != null) return;
    _layoutKey = key;
    // Unreferenced meshes are dropped, so a removed mesh frees its tree.
    final live = <Geometry>{
      for (final (item, _) in statics) item.geometry,
      for (final (item, _) in skinned) item.geometry,
    };
    _blases.removeWhere(
      (geometry, entry) => !live.contains(geometry) && entry.blas != null,
    );

    var nodeCount = 0;
    var triangleCount = 0;
    var cornerCount = 0;
    var orderCount = 0;
    for (final entry in uniqueStatics) {
      nodeCount += entry.blas!.nodeCount;
      triangleCount += entry.blas!.triangleCount;
    }
    for (final (_, entry) in skinned) {
      nodeCount += entry.blas!.nodeCount;
      triangleCount += entry.blas!.triangleCount;
      cornerCount += entry.blas!.corners.length;
      orderCount += entry.blas!.refitOrder.length;
    }
    final nodes = Float32List(math.max(1, nodeCount) * kGiBvhNodeStride);
    final triangles = Float32List(
      math.max(1, triangleCount) * kGiTriangleStride,
    );
    final cornerData = Int32List(math.max(1, cornerCount));
    final orderData = Int32List(math.max(1, orderCount));

    var nodeBase = 0;
    var triangleBase = 0;
    _staticOffsets.clear();
    void place(GiBlas blas) {
      nodes.setAll(nodeBase * kGiBvhNodeStride, blas.nodes);
      triangles.setAll(triangleBase * kGiTriangleStride, blas.triangles);
    }

    for (final entry in uniqueStatics) {
      final blas = entry.blas!;
      place(blas);
      _staticOffsets[entry] = (nodeBase, triangleBase);
      nodeBase += blas.nodeCount;
      triangleBase += blas.triangleCount;
    }
    _skinnedRegions.clear();
    var cornerBase = 0;
    var orderBase = 0;
    for (final (item, entry) in skinned) {
      final blas = entry.blas!;
      place(blas);
      cornerData.setAll(cornerBase, blas.corners);
      orderData.setAll(orderBase, blas.refitOrder);
      _skinnedRegions[item] = GiSkinnedRegion(
        nodeBase: nodeBase,
        triangleBase: triangleBase,
        triangleCount: blas.triangleCount,
        cornerBase: cornerBase,
        orderBase: orderBase,
        levelStarts: blas.levelStarts,
      );
      nodeBase += blas.nodeCount;
      triangleBase += blas.triangleCount;
      cornerBase += blas.corners.length;
      orderBase += blas.refitOrder.length;
    }

    gpu.DeviceBuffer upload(TypedData data) =>
        gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(data));
    blasNodes = upload(nodes);
    blasTriangles = upload(triangles);
    corners = upload(cornerData);
    refitOrder = upload(orderData);
  }

  static final Object _separator = Object();
}

/// One skinned item's copy of its bottom level in the packed buffers.
class GiSkinnedRegion {
  GiSkinnedRegion({
    required this.nodeBase,
    required this.triangleBase,
    required this.triangleCount,
    required this.cornerBase,
    required this.orderBase,
    required this.levelStarts,
  });

  final int nodeBase;
  final int triangleBase;
  final int triangleCount;
  final int cornerBase;
  final int orderBase;

  /// Where each depth group starts in the refit order, deepest first.
  final Int32List levelStarts;
}

/// One frame of the traced scene, ready to upload.
class GiSceneFrame {
  GiSceneFrame({
    required this.tlasNodes,
    required this.tlasNodeCount,
    required this.instances,
    required this.boundedCount,
    required this.instanceCount,
    required this.materials,
    required this.skinned,
  });

  final Float32List tlasNodes;
  final int tlasNodeCount;

  /// Bounded instances in top-level leaf order, then skinned ones.
  final Float32List instances;
  final int boundedCount;
  final int instanceCount;
  final Float32List materials;

  /// Each skinned instance's skinned vertices and packed region.
  final List<(gpu.BufferView, GiSkinnedRegion)> skinned;
}

class _BlasEntry {
  _BlasEntry(this.version);
  final int version;
  GiBlas? blas;
}

class _Instance {
  _Instance(
    this.worldToObject,
    this.bounds,
    this.nodeBase,
    this.triangleBase,
    this.material,
    this.mirror,
  );

  factory _Instance.of(
    Matrix4 world,
    GiBlas blas,
    int nodeBase,
    int triangleBase,
    int material,
  ) {
    // The root node's box, carried to world space by its eight corners.
    final n = blas.nodes;
    final low = Vector3(n[0], n[1], n[2]);
    final high = Vector3(n[4], n[5], n[6]);
    final box = Aabb3.minMax(low, high)..transform(world);
    return _Instance(
      Matrix4.inverted(world),
      [...box.min.storage, ...box.max.storage],
      nodeBase,
      triangleBase,
      material,
      world.determinant() < 0 ? -1.0 : 1.0,
    );
  }

  final Matrix4 worldToObject;
  final List<double> bounds;
  final int nodeBase;
  final int triangleBase;
  final int material;
  final double mirror;

  void write(Float32List out, int offset) {
    final m = worldToObject.storage;
    for (var row = 0; row < 3; row++) {
      out
        ..[offset + row * 4] = m[row]
        ..[offset + row * 4 + 1] = m[4 + row]
        ..[offset + row * 4 + 2] = m[8 + row]
        ..[offset + row * 4 + 3] = m[12 + row];
    }
    out
      ..[offset + 12] = nodeBase.toDouble()
      ..[offset + 13] = triangleBase.toDouble()
      ..[offset + 14] = material.toDouble()
      ..[offset + 15] = mirror;
  }
}

// This frame's materials, deduplicated by instance.
class _GiMaterialTable {
  _GiMaterialTable(this.atlas, this.emissiveBoost);

  final GiMaterialAtlas atlas;
  final double emissiveBoost;
  final Map<Material, int> _indices = Map.identity();
  final List<double> _data = [];

  int indexOf(Material material) => _indices.putIfAbsent(material, () {
    _data.addAll(_entry(material));
    return _indices.length;
  });

  int get count => _indices.length;

  Float32List finish() => _data.isEmpty
      ? Float32List(kGiMaterialStride)
      : Float32List.fromList(_data);

  List<double> _entry(Material material) {
    final sides = material.doubleSided ? 1.0 : 0.0;
    switch (material) {
      case PhysicallyBasedMaterial m:
        final diffuse = 1.0 - m.metallicFactor.clamp(0.0, 1.0);
        final base = m.baseColorFactor;
        final emissive = m.emissiveFactor;
        final (ax, ay) = atlas.tileFor(m.baseColorTexture?.sampledTexture);
        final (ex, ey) = atlas.tileFor(m.emissiveTexture?.sampledTexture);
        return [
          base.x * diffuse, base.y * diffuse, base.z * diffuse, sides, //
          emissive.x * m.emissiveStrength * emissiveBoost,
          emissive.y * m.emissiveStrength * emissiveBoost,
          emissive.z * m.emissiveStrength * emissiveBoost,
          0,
          ax, ay, ex, ey,
        ];
      case UnlitMaterial m:
        // An unlit surface shows its color whatever lights it, so to the
        // field it is an emitter.
        final base = m.baseColorFactor;
        final (ex, ey) = atlas.tileFor(m.baseColorTexture?.sampledTexture);
        return [
          0, 0, 0, sides, //
          base.x * emissiveBoost, base.y * emissiveBoost,
          base.z * emissiveBoost, 0,
          -1, -1, ex, ey,
        ];
      default:
        // TODO(gi-trace-albedo): read other material kinds instead of a
        // gray default.
        return [0.5, 0.5, 0.5, sides, 0, 0, 0, 0, -1, -1, -1, -1];
    }
  }
}

/// The traced feed's material texture atlas: each base color or emissive
/// texture filtered into a small tile, which the trace samples at a hit's
/// interpolated texture coordinate.
class GiMaterialAtlas {
  /// Tile edge in texels.
  static const int tileEdge = 32;

  /// Tiles per atlas row.
  static const int tilesPerRow = 16;

  /// The most tiles the atlas holds. Textures past it read as white.
  static const int maxTiles = 1024;

  final Map<gpu.Texture, int> _tiles = Map.identity();
  final List<gpu.Texture> _order = [];
  List<gpu.Texture> _rendered = const [];
  gpu.Texture? texture;

  /// The tile [source] lands in, as its first texel, or (-1, -1) for none.
  (double, double) tileFor(gpu.Texture? source) {
    if (source == null) return (-1, -1);
    final tile = _tiles.putIfAbsent(source, () {
      _order.add(source);
      return _order.length - 1;
    });
    if (tile >= maxTiles) return (-1, -1);
    return (
      ((tile % tilesPerRow) * tileEdge).toDouble(),
      ((tile ~/ tilesPerRow) * tileEdge).toDouble(),
    );
  }

  /// The textures whose tiles changed since the last render, or null when
  /// none did. Clears textures no material used this frame.
  List<gpu.Texture>? takeChanged() {
    final current = _order.take(maxTiles).toList();
    if (listEquals(current, _rendered) && texture != null) return null;
    _rendered = current;
    return current;
  }

  /// Forgets tile assignments, so the next frame's materials claim tiles
  /// from the start and textures no longer used fall out.
  void reset() {
    _tiles.clear();
    _order.clear();
  }

  int get textureCount => math.min(_order.length, maxTiles);

  int get width => tilesPerRow * tileEdge;
  int heightFor(int tiles) =>
      math.max(1, (tiles + tilesPerRow - 1) ~/ tilesPerRow) * tileEdge;
}
