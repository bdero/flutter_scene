import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/rect_area_light_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/light_culling.dart';
import 'package:flutter_scene/src/render/point_shadow.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';

/// The per-object punctual light budget: how many lights the per-object
/// culling path lists for a single item (the fallback for non-perspective
/// views and light-channel-mask frames). The scene may hold any number of
/// lights; the fragment loop is dynamically bounded (every compiled dialect
/// is GLSL ES 3.00 or newer), so this is purely the CPU-side list cap that
/// bounds the per-object index buffer.
const int kMaxPunctualLights = 16;

/// The froxel path's per-froxel light budget, matching Filament's uint8
/// ceiling. Wide enough that truncation is effectively out of the design
/// (a froxel's list caps only past 255 overlapping lights, and the nearest
/// are kept); the fragment loop shades exactly the froxel's count.
const int kMaxFroxelLights = 255;

// A punctual light is one row of the parameters texture, eight RGBA32F texels
// wide:
//   col 0: position.xyz, type   (0 directional, 1 point, 2 spot)
//   col 1: color.rgb * intensity, inverse range (0 = infinite)
//   col 2: direction.xyz, spot angular scale
//   col 3: spot angular offset, shadow slot (-1 = none), falloff exponent,
//          unused
//   col 4-7: world -> spot-clip matrix for a shadow-casting spot. A
//          shadow-casting point light instead packs its face-depth mapping and
//          sampling parameters here (col 4: depth scale/offset, normal bias,
//          softness; col 5: depth bias, inverse face resolution), and its
//          col 3 shadow slot is its first atlas tile relative to the cascade
//          tiles. Unused otherwise.
// The shader reads these by computed UV, sidestepping the GLSL ES 1.00 ban on
// dynamically indexing a uniform array in a fragment shader. The shadow data
// rides here rather than in its own texture so no extra sampler is needed
// (the lit shader is at the backend's sampler limit).
const int _texelsPerLight = 8;
const int _floatsPerLight = _texelsPerLight * 4;

// The per-object light-index buffer is packed into a 2D texture at most this
// many texels wide (each texel one light index in .r), so a large scene's
// index buffer stays within the max texture width; the height grows instead.
const int _indexTexMaxWidth = 2048;

const double _typeDirectional = 0.0;
const double _typePoint = 1.0;
const double _typeSpot = 2.0;
const double _typeArea = 3.0;

/// The GPU-side punctual lighting for a frame: the parameters texture holding
/// every scene light, the per-object light-index texture, and their dimensions
/// (needed by the shader to normalize its fetch coordinates).
class PunctualLighting {
  const PunctualLighting({
    required this.paramsTexture,
    required this.indexTexture,
    required this.paramsCount,
    required this.indexWidth,
    required this.indexHeight,
    this.spotShadowCount = 0,
    this.pointShadowTileCount = 0,
    this.spotShadowDepthBias = 0.0,
    this.spotShadowNormalBias = 0.0,
    this.spotShadowSoftness = 0.0,
    this.internalBuffer,
  });

  /// An empty result (no punctual lights this frame).
  const PunctualLighting.empty()
    : paramsTexture = null,
      indexTexture = null,
      paramsCount = 0,
      indexWidth = 0,
      indexHeight = 0,
      spotShadowCount = 0,
      pointShadowTileCount = 0,
      spotShadowDepthBias = 0.0,
      spotShadowNormalBias = 0.0,
      spotShadowSoftness = 0.0,
      internalBuffer = null;

  /// The buffer that built this result, for per-view froxel builds
  /// ([PunctualLightBuffer.buildFroxels]); null when froxel clustering is
  /// unavailable this frame (no lights, non-uniform light channels, or the
  /// scene disabled it).
  final PunctualLightBuffer? internalBuffer;

  /// All scene lights, one per row (RGBA32F, `paramsCount` rows), or null when
  /// there are none.
  final gpu.Texture? paramsTexture;

  /// The flattened per-object light-index buffer (each item's
  /// `[lightListOffset, +lightListCount)` slice indexes into [paramsTexture]),
  /// or null when no item is reached by any light.
  final gpu.Texture? indexTexture;

  /// Number of light rows in [paramsTexture].
  final int paramsCount;

  /// Dimensions of [indexTexture], for the shader's fetch-coordinate math.
  final int indexWidth;
  final int indexHeight;

  /// Number of shadow-casting spots this frame (their tiles follow the
  /// directional cascades in the shared shadow atlas, and their matrices ride
  /// in the params texture). Zero disables spot shadow sampling.
  final int spotShadowCount;

  /// Number of atlas tiles claimed by shadow-casting point lights (two per
  /// caster, following the spot tiles). Zero disables point shadow sampling.
  final int pointShadowTileCount;

  /// Shared spot-shadow sampling parameters (from the first caster).
  final double spotShadowDepthBias;
  final double spotShadowNormalBias;
  final double spotShadowSoftness;
}

// A ring of exactly-sized host-visible RGBA32F textures, so a frame in flight is
// never overwritten. Reallocates when the requested size changes (mirrors the
// skinning joints texture); steady light counts reuse the ring.
class _TextureRing {
  _TextureRing({int size = 3}) : _ring = List<gpu.Texture?>.filled(size, null);

  /// How many frames a handed-out texture must survive before its slot may be
  /// written again, matching the depth the per-frame rings already use.
  static const int _framesInFlight = 3;

  List<gpu.Texture?> _ring;
  int _cursor = 0;
  int _width = 0;
  int _height = 0;
  int _acquiredThisFrame = 0;

  /// Marks a frame boundary, growing the ring when the frame just finished
  /// acquired more textures than it can cover.
  void beginFrame() {
    final needed = _acquiredThisFrame * _framesInFlight;
    if (needed > _ring.length) {
      _ring = List<gpu.Texture?>.filled(needed, null);
      _cursor = 0;
    }
    _acquiredThisFrame = 0;
  }

  gpu.Texture acquire(int width, int height) {
    if (width != _width || height != _height) {
      _ring.fillRange(0, _ring.length, null);
      _width = width;
      _height = height;
    }
    _acquiredThisFrame++;
    _cursor = (_cursor + 1) % _ring.length;
    return _ring[_cursor] ??= gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      format: gpu.PixelFormat.r32g32b32a32Float,
    );
  }
}

/// Per-view froxel clustering: the view frustum subdivided into a
/// screen-tile x depth-slice grid, each cell (froxel) carrying the list of
/// punctual lights that reach it. The fragment shader looks its froxel up by
/// view position and shades only that list, so no draw carries any per-object
/// light state and the per-loop light budget applies per froxel instead of
/// per object (a level-spanning mesh is no longer special).
///
/// [texture] packs the whole structure into one RGBA32F data texture bound on
/// the same sampler as the per-object index buffer: texels
/// `[0, nx * ny * nz)` are the froxel table (records offset in `.r`, light
/// count in `.g`, offsets absolute into the same texture), and the records
/// (light row in `.r`) follow. Depth slices are exponential;
/// `slice = floor(log2(viewDepth) * zScale + zBias)`, clamped.
class FroxelLighting {
  const FroxelLighting({
    required this.texture,
    required this.width,
    required this.height,
    required this.nx,
    required this.ny,
    required this.nz,
    required this.zScale,
    required this.zBias,
  });

  final gpu.Texture texture;
  final int width;
  final int height;
  final int nx;
  final int ny;
  final int nz;
  final double zScale;
  final double zBias;
}

/// The packed light parameters plus the culling inputs derived from them.
class _PackedLights {
  _PackedLights(this.params, this.count, this.cullables);

  final Float32List params;
  final int count;
  final List<CullableLight> cullables;
}

/// Builds the per-frame punctual lighting: the parameters texture holding every
/// point, spot, and extra-directional light in the scene, and the per-object
/// light-index texture produced by culling those lights against the items.
///
/// One instance lives on the `Scene` and is rebuilt once per frame (the
/// light-object assignment is view-independent).
class PunctualLightBuffer {
  final _TextureRing _paramsRing = _TextureRing();
  final _TextureRing _indexRing = _TextureRing();

  bool _warnedOverflow = false;

  /// How many items (per-object mode) or froxels (clustered mode) dropped
  /// lights this frame because more than [kMaxPunctualLights] punctual lights
  /// reached them. Zero when everything fit its budget. Editors surface this;
  /// games can poll it to catch lighting authoring problems.
  int get overflowedItemCount => _overflowedItemCount;
  int _overflowedItemCount = 0;

  /// Packs the scene's [directionals] (skipping [primaryDirectional], which
  /// the shadow-capable `FragInfo` path already shades), [points], and [spots]
  /// into the parameters buffer, culls them against [items] using [bvh], and
  /// uploads both the parameters and per-object index textures. Returns
  /// [PunctualLighting.empty] when there are no punctual lights, so a scene with
  /// only a single directional light allocates nothing and renders as before.
  PunctualLighting build({
    required List<DirectionalLightComponent> directionals,
    required DirectionalLightComponent? primaryDirectional,
    required List<PointLightComponent> points,
    required List<SpotLightComponent> spots,
    List<RectAreaLightComponent> areas = const [],
    required List<RenderItem> items,
    required Bvh bvh,
    SpotShadowFrame? spotShadows,
    PointShadowFrame? pointShadows,
    // The shared atlas gives every tile one size, so a point light's faces
    // render at half that rather than at its own shadowMapResolution. The
    // shader clamps its kernel with this, so it has to be the size the faces
    // actually got.
    int pointFaceResolution = 512,
    bool enableFroxels = true,
  }) {
    // One build per frame, so this is where the rings roll over.
    _froxelRing.beginFrame();
    final packed = _packLights(
      directionals,
      points,
      spots,
      areas,
      primaryDirectional: primaryDirectional,
    );
    final count = packed.count;
    if (count == 0) {
      _overflowedItemCount = 0;
      _cullables = const [];
      return const PunctualLighting.empty();
    }

    // Froxel clustering assigns lights per screen cell, so it cannot honor
    // per-item light channel masks; a frame using non-default channels falls
    // back to the per-object lists. TODO(froxel-channels): pack the light's
    // mask into its params row and test it in the shader once integer ops are
    // dependable across the GLSL ES transpile.
    _cullables = packed.cullables;
    _froxelsEligible =
        enableFroxels &&
        packed.cullables.every((light) => light.channelMask == 0xFF) &&
        items.every((item) => item.lightChannelMask == 0xFF);

    // Stamp each shadow-casting spot's slot (texel 3.y) and world -> spot-clip
    // matrix (texels 4-7) into its parameters row, so the shader can sample the
    // right shared-atlas tile without a separate matrices texture.
    final spotTileCount = spotShadows?.matrices.length ?? 0;
    if (spotShadows != null) {
      final spotRowStart =
          directionals.where((d) => !identical(d, primaryDirectional)).length +
          points.length;
      for (var si = 0; si < spots.length; si++) {
        final slot = spotShadows.slotOf(spots[si]);
        if (slot < 0) continue;
        final base = (spotRowStart + si) * _floatsPerLight;
        packed.params[base + 13] = slot.toDouble();
        packed.params.setRange(
          base + 16,
          base + 32,
          spotShadows.matrices[slot].storage,
        );
      }
    }

    // Stamp each shadow-casting point light's first atlas tile (texel 3.y,
    // relative to the cascade tiles, after the spot tiles) and its face-depth
    // mapping plus sampling parameters (texels 4-5, free for point rows). The
    // shader reconstructs each cube face's projection analytically from the
    // light position, so no per-face matrices are needed: window depth is
    // scale - offset / faceDepth, the standard perspective mapping.
    final pointTileCount =
        (pointShadows?.casters.length ?? 0) * kPointShadowTilesPerLight;
    if (pointShadows != null) {
      final pointRowStart = directionals
          .where((d) => !identical(d, primaryDirectional))
          .length;
      for (var pi = 0; pi < points.length; pi++) {
        final slot = pointShadows.slotOf(points[pi]);
        if (slot < 0) continue;
        final light = points[pi].light;
        final near = light.shadowNear;
        final far = math.max(light.shadowFar, near * (1.0 + 1e-4));
        final base = (pointRowStart + pi) * _floatsPerLight;
        packed.params[base + 13] =
            (spotTileCount + slot * kPointShadowTilesPerLight).toDouble();
        packed.params[base + 16] = far / (far - near);
        packed.params[base + 17] = far * near / (far - near);
        packed.params[base + 18] = light.shadowNormalBias;
        packed.params[base + 19] = light.shadowSoftness;
        packed.params[base + 20] = light.shadowDepthBias;
        packed.params[base + 21] = 1.0 / pointFaceResolution;
      }
    }

    // Bump the froxel epoch only when the packed light data actually changed
    // (compared after the spot-shadow stamping above), so a static view with
    // static lights reuses last frame's froxel texture.
    final lastParams = _lastParams;
    if (lastParams == null ||
        lastParams.length != packed.params.length ||
        !_floatsEqual(lastParams, packed.params)) {
      _buildEpoch++;
      _lastParams = Float32List.fromList(packed.params);
    }

    final cull = assignLightsToItems(
      items: items,
      bvh: bvh,
      lights: packed.cullables,
      maxPerItem: kMaxPunctualLights,
    );
    // With froxels eligible the per-object lists only serve non-perspective
    // views, so their overflow does not represent what the frame shades; the
    // per-view froxel builds add their own overflow instead.
    _overflowedItemCount = _froxelsEligible ? 0 : cull.overflowedItemCount;

    assert(() {
      if (cull.overflowed && !_warnedOverflow) {
        _warnedOverflow = true;
        debugPrint(
          'flutter_scene: an object is reached by more than $kMaxPunctualLights '
          'punctual lights; the excess is not shaded.',
        );
      }
      return true;
    }());

    final paramsTexture = _paramsRing.acquire(_texelsPerLight, count);
    paramsTexture.overwrite(packed.params.buffer.asByteData());

    final indexLength = cull.indices.length;
    if (indexLength == 0) {
      // Every item was culled out (lights exist but reach nothing this frame).
      return PunctualLighting(
        paramsTexture: paramsTexture,
        indexTexture: null,
        paramsCount: count,
        indexWidth: 0,
        indexHeight: 0,
        spotShadowCount: spotTileCount,
        pointShadowTileCount: pointTileCount,
        spotShadowDepthBias: spotShadows?.depthBias ?? 0.0,
        spotShadowNormalBias: spotShadows?.normalBias ?? 0.0,
        spotShadowSoftness: spotShadows?.softness ?? 0.0,
        internalBuffer: _froxelsEligible ? this : null,
      );
    }

    final indexWidth = math.min(indexLength, _indexTexMaxWidth);
    final indexHeight = (indexLength + indexWidth - 1) ~/ indexWidth;
    // RGBA32F; the light index rides in .r, the rest is unread padding.
    final indexData = Float32List(indexWidth * indexHeight * 4);
    for (var i = 0; i < indexLength; i++) {
      indexData[i * 4] = cull.indices[i].toDouble();
    }
    final indexTexture = _indexRing.acquire(indexWidth, indexHeight);
    indexTexture.overwrite(indexData.buffer.asByteData());

    return PunctualLighting(
      paramsTexture: paramsTexture,
      indexTexture: indexTexture,
      paramsCount: count,
      indexWidth: indexWidth,
      indexHeight: indexHeight,
      spotShadowCount: spotTileCount,
      pointShadowTileCount: pointTileCount,
      spotShadowDepthBias: spotShadows?.depthBias ?? 0.0,
      spotShadowNormalBias: spotShadows?.normalBias ?? 0.0,
      spotShadowSoftness: spotShadows?.softness ?? 0.0,
      internalBuffer: _froxelsEligible ? this : null,
    );
  }

  // Froxel grid shape and depth window. 16 x 9 tiles x 16 exponential depth
  // slices = 2304 froxels; the far bound caps how far punctual lights are
  // clustered (fragments and lights beyond it clamp into the last slice, so
  // distant geometry over-shades conservatively rather than losing lights).
  static const int froxelCountX = 16;
  static const int froxelCountY = 9;
  static const int froxelCountZ = 16;
  static const double _froxelNear = 0.25;
  static const double _froxelFar = 100.0;
  static const int _froxelTexWidth = 1024;

  // Several views build froxels in one frame (screen views, probe faces), and
  // how many is a property of the scene, so this ring sizes itself to the
  // busiest frame instead of guessing a depth.
  final _TextureRing _froxelRing = _TextureRing(size: 8);

  List<CullableLight> _cullables = const [];
  bool _froxelsEligible = false;

  // The lights-changed epoch (bumped per build) plus the camera the cached
  // froxels were built for; a static view reuses last frame's froxel texture
  // instead of refroxelizing (the Dart-side cost is per camera move, not per
  // frame).
  int _buildEpoch = 0;
  int _froxelCacheEpoch = -1;
  Float32List? _lastParams;

  static bool _floatsEqual(Float32List a, Float32List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  final Vector3 _cachePosition = Vector3.zero();
  final Vector3 _cacheForward = Vector3.zero();
  final Vector3 _cacheRight = Vector3.zero();
  double _cacheTanX = 0;
  double _cacheTanY = 0;
  int _cacheOverflow = 0;
  FroxelLighting? _cachedFroxels;

  /// Builds this view's froxel clustering from the camera basis the lit
  /// shaders already receive ([tanHalfFovX]/[tanHalfFovY] are the projection's
  /// half-fov tangents). Returns null for a non-perspective view (the
  /// per-object lists shade those). Call after [build] each frame.
  FroxelLighting? buildFroxels({
    required Vector3 cameraPosition,
    required Vector3 forward,
    required Vector3 right,
    required Vector3 up,
    required double tanHalfFovX,
    required double tanHalfFovY,
  }) {
    if (!_froxelsEligible ||
        _cullables.isEmpty ||
        tanHalfFovX <= 0 ||
        tanHalfFovY <= 0) {
      return null;
    }
    final cached = _cachedFroxels;
    if (cached != null &&
        _froxelCacheEpoch == _buildEpoch &&
        _cachePosition == cameraPosition &&
        _cacheForward == forward &&
        _cacheRight == right &&
        _cacheTanX == tanHalfFovX &&
        _cacheTanY == tanHalfFovY) {
      _overflowedItemCount += _cacheOverflow;
      return cached;
    }
    final result = computeFroxelData(
      lights: _cullables,
      cameraPosition: cameraPosition,
      forward: forward,
      right: right,
      up: up,
      tanHalfFovX: tanHalfFovX,
      tanHalfFovY: tanHalfFovY,
      maxPerFroxel: kMaxFroxelLights,
    );
    _overflowedItemCount += result.overflowedFroxels;
    final texture = _froxelRing.acquire(_froxelTexWidth, result.height);
    texture.overwrite(result.data.buffer.asByteData());
    final froxels = FroxelLighting(
      texture: texture,
      width: _froxelTexWidth,
      height: result.height,
      nx: froxelCountX,
      ny: froxelCountY,
      nz: froxelCountZ,
      zScale: result.zScale,
      zBias: result.zBias,
    );
    _froxelCacheEpoch = _buildEpoch;
    _cachePosition.setFrom(cameraPosition);
    _cacheForward.setFrom(forward);
    _cacheRight.setFrom(right);
    _cacheTanX = tanHalfFovX;
    _cacheTanY = tanHalfFovY;
    _cacheOverflow = result.overflowedFroxels;
    _cachedFroxels = froxels;
    return froxels;
  }

  /// The GPU-independent froxelization: assigns [lights] to froxels for a
  /// view at [cameraPosition] looking along [forward] (with [right]/[up]
  /// completing the basis) and packs the froxel table plus deduplicated
  /// records into an RGBA32F texel array [_froxelTexWidth] wide. Pure so the
  /// slice math and conservative assignment can be unit tested.
  ///
  /// A light is assigned to every froxel its influence sphere can touch,
  /// tested conservatively (view-space AABB of the sphere, widened at the
  /// sphere's near face), so froxels may over-include but never miss a light.
  /// An unranged light lands in every froxel. A froxel's list caps at
  /// [maxPerFroxel], keeping the lights nearest the froxel (directionals
  /// first); capped froxels are counted in `overflowedFroxels`.
  @visibleForTesting
  static ({
    Float32List data,
    int height,
    double zScale,
    double zBias,
    int overflowedFroxels,
  })
  computeFroxelData({
    required List<CullableLight> lights,
    required Vector3 cameraPosition,
    required Vector3 forward,
    required Vector3 right,
    required Vector3 up,
    required double tanHalfFovX,
    required double tanHalfFovY,
    required int maxPerFroxel,
  }) {
    const nx = froxelCountX, ny = froxelCountY, nz = froxelCountZ;
    const froxelCount = nx * ny * nz;
    final zScale = nz / (math.log(_froxelFar / _froxelNear) / math.ln2);
    final zBias = -(math.log(_froxelNear) / math.ln2) * zScale;
    int sliceOf(double depth) {
      final clamped = depth.clamp(_froxelNear, _froxelFar);
      final slice = (math.log(clamped) / math.ln2) * zScale + zBias;
      return slice.floor().clamp(0, nz - 1);
    }

    final lists = List<List<int>>.generate(froxelCount, (_) => <int>[]);
    final lightsByRow = <int, CullableLight>{
      for (final light in lights) light.index: light,
    };
    var overflowed = 0;

    final rel = Vector3.zero();
    for (final light in lights) {
      final bounds = light.bounds;
      final position = light.worldPosition;
      if (bounds == null || position == null) {
        // Unbounded influence (a directional light, or a light with no
        // range) reaches every froxel.
        for (var i = 0; i < froxelCount; i++) {
          lists[i].add(light.index);
        }
        continue;
      }
      final radius = (bounds.max.x - bounds.min.x) * 0.5;
      rel
        ..setFrom(position)
        ..sub(cameraPosition);
      final vz = rel.dot(forward);
      if (vz + radius <= 0) continue; // Fully behind the camera.
      final z0 = sliceOf(vz - radius);
      final z1 = sliceOf(vz + radius);

      // The tile rect projects the sphere's view-space AABB corner-extreme
      // over depth-extreme: a positive lateral extreme appears widest at the
      // AABB's near face, a negative one at its far face. (Projecting a
      // center-plus-extent instead undercovers by vx*r/(vz*(vz-r)), which
      // blows up near the camera and, for off-center lights, stays wider
      // than the light's shrinking on-screen influence at distance, so the
      // light visibly cuts off or vanishes.) A sphere reaching the near
      // window degenerates to huge extents and clamps to full coverage.
      final zNearFace = math.max(vz - radius, _froxelNear);
      final zFarFace = vz + radius;
      double ndcMax(double v) =>
          v + radius >= 0 ? (v + radius) / zNearFace : (v + radius) / zFarFace;
      double ndcMin(double v) =>
          v - radius <= 0 ? (v - radius) / zNearFace : (v - radius) / zFarFace;
      final vx = rel.dot(right);
      final vy = rel.dot(up);
      int tileX(double ndc) =>
          (((ndc * 0.5) + 0.5) * nx).floor().clamp(0, nx - 1);
      // Tile rows count downward from the top of the view (matching the
      // shader's 0.5 - ndcY * 0.5 mapping).
      int tileY(double ndc) =>
          ((0.5 - ndc * 0.5) * ny).floor().clamp(0, ny - 1);
      final x0 = tileX(ndcMin(vx) / tanHalfFovX);
      final x1 = tileX(ndcMax(vx) / tanHalfFovX);
      final y0 = tileY(ndcMax(vy) / tanHalfFovY);
      final y1 = tileY(ndcMin(vy) / tanHalfFovY);
      for (var z = z0; z <= z1; z++) {
        for (var y = y0; y <= y1; y++) {
          final rowBase = (z * ny + y) * nx;
          for (var x = x0; x <= x1; x++) {
            lists[rowBase + x].add(light.index);
          }
        }
      }
    }

    // Pack the table and records; identical lists share one record run. An
    // overfull froxel keeps its nearest lights (measured to the froxel's
    // center, directionals first since distance never attenuates them), so
    // the dropped excess is always the least visible.
    final records = <int>[];
    final shared = <String, (int, int)>{};
    final table = List<(int, int)>.filled(froxelCount, (0, 0));
    final center = Vector3.zero();
    for (var i = 0; i < froxelCount; i++) {
      final list = lists[i];
      if (list.isEmpty) continue;
      if (list.length > maxPerFroxel) {
        overflowed++;
        final fz = i ~/ (ny * nx);
        final fy = (i ~/ nx) % ny;
        final fx = i % nx;
        final depth = math.pow(2.0, (fz + 0.5 - zBias) / zScale).toDouble();
        final ndcX = ((fx + 0.5) / nx) * 2.0 - 1.0;
        final ndcY = -(((fy + 0.5) / ny) * 2.0 - 1.0);
        center
          ..setFrom(forward)
          ..scale(depth)
          ..addScaled(right, ndcX * depth * tanHalfFovX)
          ..addScaled(up, ndcY * depth * tanHalfFovY)
          ..add(cameraPosition);
        double distanceSq(int row) {
          final position = lightsByRow[row]?.worldPosition;
          if (position == null) return -1.0; // Directionals sort first.
          return position.distanceToSquared(center);
        }

        list.sort((a, b) => distanceSq(a).compareTo(distanceSq(b)));
      }
      final count = math.min(list.length, maxPerFroxel);
      final key = list.take(count).join(',');
      table[i] = shared.putIfAbsent(key, () {
        final offset = froxelCount + records.length;
        records.addAll(list.take(count));
        return (offset, count);
      });
    }

    final total = froxelCount + records.length;
    final height = (total + _froxelTexWidth - 1) ~/ _froxelTexWidth;
    final data = Float32List(_froxelTexWidth * height * 4);
    for (var i = 0; i < froxelCount; i++) {
      data[i * 4] = table[i].$1.toDouble();
      data[i * 4 + 1] = table[i].$2.toDouble();
    }
    for (var i = 0; i < records.length; i++) {
      data[(froxelCount + i) * 4] = records[i].toDouble();
    }
    return (
      data: data,
      height: height,
      zScale: zScale,
      zBias: zBias,
      overflowedFroxels: overflowed,
    );
  }

  /// Packs the additional analytic lights into the parameters buffer, returning
  /// it and the light count. Pure and GPU-independent so the texel layout,
  /// falloff, and cone math can be unit tested; [build] wraps it with culling
  /// and the texture uploads.
  @visibleForTesting
  static (Float32List, int) packLights({
    required List<DirectionalLightComponent> directionals,
    DirectionalLightComponent? primaryDirectional,
    required List<PointLightComponent> points,
    required List<SpotLightComponent> spots,
    List<RectAreaLightComponent> areas = const [],
  }) {
    final packed = _packLights(
      directionals,
      points,
      spots,
      areas,
      primaryDirectional:
          primaryDirectional ??
          (directionals.isEmpty ? null : directionals.first),
    );
    return (packed.params, packed.count);
  }

  static _PackedLights _packLights(
    List<DirectionalLightComponent> directionals,
    List<PointLightComponent> points,
    List<SpotLightComponent> spots,
    List<RectAreaLightComponent> areas, {
    DirectionalLightComponent? primaryDirectional,
  }) {
    final additionalDirectionalCount = directionals
        .where((d) => !identical(d, primaryDirectional))
        .length;
    final count =
        additionalDirectionalCount +
        points.length +
        spots.length +
        areas.length;
    final floats = Float32List(count * _floatsPerLight);
    final cullables = <CullableLight>[];
    var row = 0;

    // The primary directional is shaded (with shadows) by the FragInfo path.
    // Every other directional folds in here as an attenuation-free entry with
    // infinite influence.
    for (final component in directionals) {
      if (identical(component, primaryDirectional)) continue;
      final light = component.light;
      final base = row * _floatsPerLight;
      floats[base + 3] = _typeDirectional;
      final dir = component.worldDirection;
      floats[base + 8] = dir.x;
      floats[base + 9] = dir.y;
      floats[base + 10] = dir.z;
      floats[base + 4] = light.color.x * light.intensity;
      floats[base + 5] = light.color.y * light.intensity;
      floats[base + 6] = light.color.z * light.intensity;
      cullables.add(CullableLight(row, null, channelMask: light.channelMask));
      row++;
    }

    for (final component in points) {
      final light = component.light;
      final base = row * _floatsPerLight;
      final position = component.worldPosition;
      floats[base + 0] = position.x;
      floats[base + 1] = position.y;
      floats[base + 2] = position.z;
      floats[base + 3] = _typePoint;
      floats[base + 4] = light.color.x * light.intensity;
      floats[base + 5] = light.color.y * light.intensity;
      floats[base + 6] = light.color.z * light.intensity;
      floats[base + 7] = light.range > 0.0 ? 1.0 / light.range : 0.0;
      // Shadow slot (texel 3.y); -1 = no shadow. build() stamps the slot and
      // face-depth parameters for shadow-casting point lights.
      floats[base + 13] = -1.0;
      floats[base + 14] = math.max(light.falloffExponent, 0.1);
      cullables.add(
        CullableLight(
          row,
          lightInfluenceBounds(position, light.range),
          worldPosition: position,
          channelMask: light.channelMask,
        ),
      );
      row++;
    }

    for (final component in spots) {
      final light = component.light;
      final base = row * _floatsPerLight;
      final position = component.worldPosition;
      final direction = component.worldDirection;
      floats[base + 0] = position.x;
      floats[base + 1] = position.y;
      floats[base + 2] = position.z;
      floats[base + 3] = _typeSpot;
      floats[base + 4] = light.color.x * light.intensity;
      floats[base + 5] = light.color.y * light.intensity;
      floats[base + 6] = light.color.z * light.intensity;
      floats[base + 7] = light.range > 0.0 ? 1.0 / light.range : 0.0;
      floats[base + 8] = direction.x;
      floats[base + 9] = direction.y;
      floats[base + 10] = direction.z;
      // Precompute the cone scale/offset so the shader is a scale-add-clamp.
      final cosInner = math.cos(light.innerConeAngle);
      final cosOuter = math.cos(light.outerConeAngle);
      final scale = 1.0 / math.max(cosInner - cosOuter, 1e-4);
      floats[base + 11] = scale;
      floats[base + 12] = -cosOuter * scale;
      // Shadow slot (texel 3.y); -1 = no shadow. build() stamps the slot and
      // matrix for shadow-casting spots.
      floats[base + 13] = -1.0;
      floats[base + 14] = math.max(light.falloffExponent, 0.1);
      cullables.add(
        CullableLight(
          row,
          lightInfluenceBounds(position, light.range),
          worldPosition: position,
          channelMask: light.channelMask,
        ),
      );
      row++;
    }

    for (final component in areas) {
      final light = component.light;
      final base = row * _floatsPerLight;
      final position = component.worldPosition;
      floats[base + 0] = position.x;
      floats[base + 1] = position.y;
      floats[base + 2] = position.z;
      floats[base + 3] = _typeArea;
      floats[base + 4] = light.color.x * light.intensity;
      floats[base + 5] = light.color.y * light.intensity;
      floats[base + 6] = light.color.z * light.intensity;
      floats[base + 7] = light.range > 0.0 ? 1.0 / light.range : 0.0;
      final right = component.worldRight;
      final up = component.worldUp;
      floats[base + 8] = right.x;
      floats[base + 9] = right.y;
      floats[base + 10] = right.z;
      floats[base + 11] = light.width;
      floats[base + 12] = up.x;
      floats[base + 13] = up.y;
      floats[base + 14] = up.z;
      floats[base + 15] = light.height;
      // With no explicit range the influence is unbounded (the form factor
      // fades with distance but never reaches zero), so cull only ranged
      // panels, padded by the panel's own extent.
      final reach = light.range > 0.0
          ? light.range + 0.5 * math.max(light.width, light.height)
          : 0.0;
      cullables.add(
        CullableLight(
          row,
          reach > 0.0 ? lightInfluenceBounds(position, reach) : null,
          worldPosition: position,
          channelMask: light.channelMask,
        ),
      );
      row++;
    }

    return _PackedLights(floats, count, cullables);
  }
}
