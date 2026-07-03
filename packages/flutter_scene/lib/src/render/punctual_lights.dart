import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// The maximum number of additional analytic lights (point + spot + extra
/// directional) shaded per frame. Must match `MAX_PUNCTUAL_LIGHTS` in
/// `shaders/material_lighting.glsl`; the fragment loop is a constant-bounded
/// unroll over this count, so it is a compile-time constant in both places.
///
/// TODO(lighting): this is a hard *global* cap and the shaded set is shared by
/// every fragment. Per-object culling via the render BVH turns it into a
/// per-object budget with an unbounded scene total (see the near-term revision
/// in notes/rendering/punctual_lights_design.md), and a punctual on/off shader
/// permutation makes the no-light case cost nothing. TODO(#188474): when Flutter
/// GPU exposes storage buffers/compute, a higher-tier variant can read a storage
/// buffer with a real dynamic loop (no cap, no data-texture packing) and move
/// light-to-region assignment to a compute pass, with this remaining the
/// base-tier fallback.
const int kMaxPunctualLights = 16;

// Each light is one row of the data texture, four RGBA32F texels wide:
//   col 0: position.xyz, type   (0 directional, 1 point, 2 spot)
//   col 1: color.rgb * intensity, inverse range (0 = infinite)
//   col 2: direction.xyz, spot angular scale
//   col 3: spot angular offset, (unused)
// The shader reads these by computed UV, sidestepping the GLSL-ES-1.00 ban on
// dynamically indexing a uniform array (see punctual_lights_design.md).
const int _texelsPerLight = 4;
const int _floatsPerLight = _texelsPerLight * 4;

const double _typeDirectional = 0.0;
const double _typePoint = 1.0;
const double _typeSpot = 2.0;

/// The result of building a frame's punctual light buffer: the data texture and
/// the number of valid light rows in it.
class PunctualLighting {
  const PunctualLighting(this.texture, this.count);

  /// An empty result (no additional lights this frame).
  const PunctualLighting.empty() : texture = null, count = 0;

  /// The RGBA32F data texture, or null when [count] is zero.
  final gpu.Texture? texture;

  /// The number of valid light rows in [texture].
  final int count;
}

/// Builds the per-frame data texture that carries the scene's additional
/// analytic lights (point and spot lights, plus directional lights past the
/// first, which the shadowed `FragInfo` path owns) to every lit draw.
///
/// One instance lives on the `Scene` and is rebuilt once per frame. It keeps a
/// small ring of textures so a frame still in flight is never overwritten
/// (mirrors the skinning joints texture).
class PunctualLightBuffer {
  static const int _ringSize = 3;
  final List<gpu.Texture?> _ring = List<gpu.Texture?>.filled(_ringSize, null);
  int _cursor = 0;

  // Warns once (debug only) when the scene has more lights than fit.
  bool _warnedOverflow = false;

  /// Packs [directionals] (skipping the first, the shadowed directional the
  /// `FragInfo` path already shades), [points], and [spots] into a data
  /// texture. Returns [PunctualLighting.empty] when there are no additional
  /// lights, so a scene with only a single directional light allocates nothing
  /// and renders exactly as before.
  PunctualLighting build({
    required List<DirectionalLightComponent> directionals,
    required List<PointLightComponent> points,
    required List<SpotLightComponent> spots,
  }) {
    final (floats, count) = packLights(
      directionals: directionals,
      points: points,
      spots: spots,
    );
    if (count == 0) {
      return const PunctualLighting.empty();
    }

    assert(() {
      final total =
          (directionals.isEmpty ? 0 : directionals.length - 1) +
          points.length +
          spots.length;
      if (total > kMaxPunctualLights && !_warnedOverflow) {
        _warnedOverflow = true;
        debugPrint(
          'flutter_scene: $total additional lights exceed the '
          '$kMaxPunctualLights-light limit; the extras are not shaded.',
        );
      }
      return true;
    }());

    _cursor = (_cursor + 1) % _ringSize;
    final texture = _ring[_cursor] ??= gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      _texelsPerLight,
      kMaxPunctualLights,
      format: gpu.PixelFormat.r32g32b32a32Float,
    );
    texture.overwrite(floats.buffer.asByteData());
    return PunctualLighting(texture, count);
  }

  /// Packs the additional analytic lights into the RGBA32F float buffer the
  /// data texture is uploaded from, returning the buffer and the number of
  /// light rows written (capped at [kMaxPunctualLights]). Pure and
  /// GPU-independent so the texel layout, falloff, and cone math can be unit
  /// tested; [build] wraps it with the texture upload.
  static (Float32List, int) packLights({
    required List<DirectionalLightComponent> directionals,
    required List<PointLightComponent> points,
    required List<SpotLightComponent> spots,
  }) {
    final floats = Float32List(kMaxPunctualLights * _floatsPerLight);
    var count = 0;

    // Directional lights past the first: the first is shaded (with shadows) by
    // the FragInfo path, the rest fold in here as attenuation-free entries.
    for (
      var i = 1;
      i < directionals.length && count < kMaxPunctualLights;
      i++
    ) {
      final component = directionals[i];
      final light = component.light;
      final base = count * _floatsPerLight;
      floats[base + 3] = _typeDirectional;
      final dir = component.worldDirection;
      floats[base + 8] = dir.x;
      floats[base + 9] = dir.y;
      floats[base + 10] = dir.z;
      floats[base + 4] = light.color.x * light.intensity;
      floats[base + 5] = light.color.y * light.intensity;
      floats[base + 6] = light.color.z * light.intensity;
      count++;
    }

    for (final component in points) {
      if (count >= kMaxPunctualLights) break;
      final light = component.light;
      final base = count * _floatsPerLight;
      final position = component.worldPosition;
      floats[base + 0] = position.x;
      floats[base + 1] = position.y;
      floats[base + 2] = position.z;
      floats[base + 3] = _typePoint;
      floats[base + 4] = light.color.x * light.intensity;
      floats[base + 5] = light.color.y * light.intensity;
      floats[base + 6] = light.color.z * light.intensity;
      floats[base + 7] = light.range > 0.0 ? 1.0 / light.range : 0.0;
      count++;
    }

    for (final component in spots) {
      if (count >= kMaxPunctualLights) break;
      final light = component.light;
      final base = count * _floatsPerLight;
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
      count++;
    }

    return (floats, count);
  }
}
