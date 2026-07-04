import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/light_culling.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';

/// The maximum number of punctual lights that can shade a single item. The
/// scene may hold any number of lights; per-object culling gives each item only
/// the lights that reach it, and the fragment loops that slice. Must match
/// `MAX_PUNCTUAL_LIGHTS` in `shaders/material_lighting.glsl` (the fragment loop
/// bound is a compile-time constant under GLSL ES 1.00), so this is a per-object
/// budget, not a global cap.
///
/// TODO(lighting): for the massive-scale tier, froxel clustering replaces the
/// per-object lists (no per-draw light state, CPU cost independent of draw
/// count); constrained mobile keeps this direct loop. TODO(#188474): with
/// Flutter GPU storage buffers/compute, a higher-tier variant can read a storage
/// buffer with a real dynamic loop and assign lights in a compute pass, with the
/// data-texture path here as the base-tier fallback.
const int kMaxPunctualLights = 16;

// A punctual light is one row of the parameters texture, eight RGBA32F texels
// wide:
//   col 0: position.xyz, type   (0 directional, 1 point, 2 spot)
//   col 1: color.rgb * intensity, inverse range (0 = infinite)
//   col 2: direction.xyz, spot angular scale
//   col 3: spot angular offset, shadow slot (-1 = none), unused, unused
//   col 4-7: world -> spot-clip matrix for a shadow-casting spot (else unused)
// The shader reads these by computed UV, sidestepping the GLSL-ES-1.00 ban on
// dynamically indexing a uniform array (see punctual_lights_design.md). The
// spot shadow matrix rides here rather than in its own texture so no extra
// sampler is needed (the lit shader is at the backend sampler limit).
const int _texelsPerLight = 8;
const int _floatsPerLight = _texelsPerLight * 4;

// The per-object light-index buffer is packed into a 2D texture at most this
// many texels wide (each texel one light index in .r), so a large scene's
// index buffer stays within the max texture width; the height grows instead.
const int _indexTexMaxWidth = 2048;

const double _typeDirectional = 0.0;
const double _typePoint = 1.0;
const double _typeSpot = 2.0;

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
    this.spotShadowDepthBias = 0.0,
    this.spotShadowNormalBias = 0.0,
    this.spotShadowSoftness = 0.0,
  });

  /// An empty result (no punctual lights this frame).
  const PunctualLighting.empty()
    : paramsTexture = null,
      indexTexture = null,
      paramsCount = 0,
      indexWidth = 0,
      indexHeight = 0,
      spotShadowCount = 0,
      spotShadowDepthBias = 0.0,
      spotShadowNormalBias = 0.0,
      spotShadowSoftness = 0.0;

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

  /// Shared spot-shadow sampling parameters (from the first caster).
  final double spotShadowDepthBias;
  final double spotShadowNormalBias;
  final double spotShadowSoftness;
}

// A ring of exactly-sized host-visible RGBA32F textures, so a frame in flight is
// never overwritten. Reallocates when the requested size changes (mirrors the
// skinning joints texture); steady light counts reuse the ring.
class _TextureRing {
  static const int _size = 3;
  final List<gpu.Texture?> _ring = List<gpu.Texture?>.filled(_size, null);
  int _cursor = 0;
  int _width = 0;
  int _height = 0;

  gpu.Texture acquire(int width, int height) {
    if (width != _width || height != _height) {
      _ring.fillRange(0, _size, null);
      _width = width;
      _height = height;
    }
    _cursor = (_cursor + 1) % _size;
    return _ring[_cursor] ??= gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      format: gpu.PixelFormat.r32g32b32a32Float,
    );
  }
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

  /// Packs the scene's [directionals] (skipping the first, the shadowed
  /// directional the `FragInfo` path already shades), [points], and [spots]
  /// into the parameters buffer, culls them against [items] using [bvh], and
  /// uploads both the parameters and per-object index textures. Returns
  /// [PunctualLighting.empty] when there are no punctual lights, so a scene with
  /// only a single directional light allocates nothing and renders as before.
  PunctualLighting build({
    required List<DirectionalLightComponent> directionals,
    required List<PointLightComponent> points,
    required List<SpotLightComponent> spots,
    required List<RenderItem> items,
    required Bvh bvh,
    SpotShadowFrame? spotShadows,
  }) {
    final packed = _packLights(directionals, points, spots);
    final count = packed.count;
    if (count == 0) {
      return const PunctualLighting.empty();
    }

    // Stamp each shadow-casting spot's slot (texel 3.y) and world -> spot-clip
    // matrix (texels 4-7) into its parameters row, so the shader can sample the
    // right shared-atlas tile without a separate matrices texture.
    if (spotShadows != null) {
      final spotRowStart = math.max(0, directionals.length - 1) + points.length;
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

    final cull = assignLightsToItems(
      items: items,
      bvh: bvh,
      lights: packed.cullables,
      maxPerItem: kMaxPunctualLights,
    );

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

    final spotCount = spotShadows?.matrices.length ?? 0;

    final indexLength = cull.indices.length;
    if (indexLength == 0) {
      // Every item was culled out (lights exist but reach nothing this frame).
      return PunctualLighting(
        paramsTexture: paramsTexture,
        indexTexture: null,
        paramsCount: count,
        indexWidth: 0,
        indexHeight: 0,
        spotShadowCount: spotCount,
        spotShadowDepthBias: spotShadows?.depthBias ?? 0.0,
        spotShadowNormalBias: spotShadows?.normalBias ?? 0.0,
        spotShadowSoftness: spotShadows?.softness ?? 0.0,
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
      spotShadowCount: spotCount,
      spotShadowDepthBias: spotShadows?.depthBias ?? 0.0,
      spotShadowNormalBias: spotShadows?.normalBias ?? 0.0,
      spotShadowSoftness: spotShadows?.softness ?? 0.0,
    );
  }

  /// Packs the additional analytic lights into the parameters buffer, returning
  /// it and the light count. Pure and GPU-independent so the texel layout,
  /// falloff, and cone math can be unit tested; [build] wraps it with culling
  /// and the texture uploads.
  @visibleForTesting
  static (Float32List, int) packLights({
    required List<DirectionalLightComponent> directionals,
    required List<PointLightComponent> points,
    required List<SpotLightComponent> spots,
  }) {
    final packed = _packLights(directionals, points, spots);
    return (packed.params, packed.count);
  }

  static _PackedLights _packLights(
    List<DirectionalLightComponent> directionals,
    List<PointLightComponent> points,
    List<SpotLightComponent> spots,
  ) {
    final count =
        math.max(0, directionals.length - 1) + points.length + spots.length;
    final floats = Float32List(count * _floatsPerLight);
    final cullables = <CullableLight>[];
    var row = 0;

    // Directional lights past the first: the first is shaded (with shadows) by
    // the FragInfo path, the rest fold in here as attenuation-free entries with
    // infinite influence (they reach every item).
    for (var i = 1; i < directionals.length; i++) {
      final component = directionals[i];
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
      cullables.add(CullableLight(row, null));
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
      cullables.add(
        CullableLight(row, lightInfluenceBounds(position, light.range)),
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
      cullables.add(
        CullableLight(row, lightInfluenceBounds(position, light.range)),
      );
      row++;
    }

    return _PackedLights(floats, count, cullables);
  }
}
