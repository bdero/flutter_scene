import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/shaders.dart';

/// One expanding distortion ring, in screen space.
/// {@category Rendering}
class DistortionPulse {
  DistortionPulse({
    Vector2? center,
    this.radius = 0.0,
    this.thickness = 0.08,
    this.strength = 0.02,
    this.chromaticAberration = 0.5,
  }) : center = center ?? Vector2(0.5, 0.5);

  /// Where the ring is centered, in screen UV (origin top-left).
  Vector2 center;

  /// The ring's current radius, aspect-corrected so it stays circular. Grow
  /// it from 0 over the pulse's life.
  double radius;

  /// Radial width of the distorted band. Wider reads softer.
  double thickness;

  /// Peak screen-UV displacement at the ring. Fade it to 0 as the pulse ends.
  double strength;

  /// How far the red and blue taps separate across the ring, as a fraction of
  /// the displacement. `0` is none.
  double chromaticAberration;
}

/// Parametric radial screen distortion, driven per frame from game code.
///
/// Each [DistortionPulse] warps the display-referred image along a ring
/// expanding from a screen point, with an optional per-channel split so the
/// ring fringes. Off by default; add a pulse and set [enabled]. Reachable
/// through `Scene.screenDistortion`.
///
/// At most [maxPulses] pulses are applied per frame; extras are ignored.
/// {@category Rendering}
class ScreenDistortionSettings {
  /// Maximum simultaneous pulses. Fixed so the shader loop has a
  /// compile-time bound.
  static const int maxPulses = 4;

  /// Whether distortion runs. Off by default.
  bool enabled = false;

  /// The live pulses, applied in list order. Mutate freely per frame.
  final List<DistortionPulse> pulses = [];
}

/// The engine-inserted [CustomRenderPass] that renders
/// [ScreenDistortionSettings]. Not user-facing; `Scene` adds it when
/// `scene.screenDistortion.enabled` and at least one pulse is live.
@internal
class ScreenDistortionPass extends CustomRenderPass {
  ScreenDistortionPass(this.settings);

  final ScreenDistortionSettings settings;

  gpu.Shader? _shaderCache;
  gpu.Shader get _shader =>
      _shaderCache ??= baseShaderLibrary['ScreenDistortionFragment']!;

  @override
  String get name => 'screen_distortion';

  @override
  RenderStage get stage => RenderStage.afterToneMapping;

  @override
  void execute(RenderPassContext context) {
    final pulses = settings.pulses;
    if (pulses.isEmpty) return;

    final dimensions = context.dimensions;
    final aspect = dimensions.height <= 0
        ? 1.0
        : dimensions.width / dimensions.height;

    context.applyShader(
      _shader,
      uniforms: {'DistortionInfo': _packPulses(aspect)},
    );
  }

  ByteData _packPulses(double aspect) {
    final pulses = settings.pulses;
    final count = pulses.length < ScreenDistortionSettings.maxPulses
        ? pulses.length
        : ScreenDistortionSettings.maxPulses;
    // vec4 params + vec4 pulse_center[4] + vec4 pulse_shape[4].
    final f = Float32List(4 + 4 * 4 + 4 * 4)
      ..[0] = count.toDouble()
      ..[1] = aspect;
    for (var i = 0; i < count; i++) {
      final pulse = pulses[i];
      final centerBase = 4 + i * 4;
      f[centerBase] = pulse.center.x;
      f[centerBase + 1] = pulse.center.y;
      f[centerBase + 2] = pulse.radius;
      f[centerBase + 3] = pulse.thickness;
      final shapeBase = 4 + 4 * 4 + i * 4;
      f[shapeBase] = pulse.strength;
      f[shapeBase + 1] = pulse.chromaticAberration;
    }
    return ByteData.sublistView(f);
  }
}
