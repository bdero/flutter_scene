import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/shaders.dart';

/// Directional volumetric god rays (crepuscular rays / light shafts).
///
/// A full-screen post-process that marches the view ray against the scene's
/// directional light shadow map, accumulating single-scattering so sunlight
/// streaming through gaps in geometry is visible as shafts. Off by default; set
/// [enabled]. It requires a shadow-casting [DirectionalLight] and a
/// [PerspectiveCamera] (it reads the cascaded shadow map and the camera depth);
/// it is skipped otherwise.
///
/// The march is per-pixel and samples the shadow map at every step, so it is a
/// desktop-leaning effect on mobile/web: keep [stepCount] low and [maxDistance]
/// bounded. See `Scene.godRays`.
/// {@category Lighting and environment}
class GodRaysSettings {
  /// Whether god rays are drawn. Off by default.
  bool enabled = false;

  /// Overall brightness of the in-scattered light.
  double intensity = 1.0;

  /// Scattering strength along the ray: how thick and bright the shafts read.
  double density = 0.5;

  /// Henyey-Greenstein phase asymmetry (`-1` to `1`). Positive concentrates the
  /// glow toward the sun (forward scattering); `0` is uniform.
  double anisotropy = 0.7;

  /// Ray-march steps per pixel. More steps reduce banding at a linear cost;
  /// clamped to `1..64`. Pair a low count with [jitter].
  int stepCount = 24;

  /// Maximum distance the ray marches, in world units. Bounds the cost and
  /// keeps far pixels from marching the whole depth range.
  double maxDistance = 200.0;

  /// Dither applied to the ray start (in steps) to trade banding for fine
  /// noise. `0` disables it.
  double jitter = 1.0;

  /// The shaft color. This is used directly (not the light's direct radiance),
  /// so shafts show even for a shadow-only sun whose direct intensity is zero;
  /// tint it to match the sun. White by default.
  Vector3 color = Vector3(1.0, 1.0, 1.0);
}

/// The engine-inserted [CustomRenderPass] that renders [GodRaysSettings]. It
/// declares the depth and shadow inputs it needs and, when they are available,
/// marches the god-rays shader over the HDR scene color. Not user-facing;
/// `Scene` adds it when `scene.godRays.enabled`.
class GodRaysPass extends CustomRenderPass {
  GodRaysPass(this.settings);

  final GodRaysSettings settings;

  gpu.Shader? _shaderCache;
  gpu.Shader get _shader =>
      _shaderCache ??= baseShaderLibrary['GodRaysFragment']!;

  @override
  String get name => 'god_rays';

  @override
  RenderStage get stage => RenderStage.afterScene;

  @override
  Set<RenderInput> get inputs => const {
    RenderInput.depth,
    RenderInput.shadowMap,
  };

  @override
  void execute(RenderPassContext context) {
    final depth = context.sceneDepthLinear;
    final shadowMap = context.shadowMap;
    final shadowInfo = context.shadowInfo;
    // No depth or no shadow-casting directional light this frame: leave the
    // scene color untouched (writing nothing keeps the chain intact).
    if (depth == null || shadowMap == null || shadowInfo == null) return;

    context.applyShader(
      _shader,
      textures: {'input_depth': depth, 'input_shadow': shadowMap},
      uniforms: {
        'PostCameraInfo': context.cameraInfo,
        'PostShadowInfo': shadowInfo,
        'GodRaysInfo': _packSettings(),
      },
      frameInfo: true,
    );
  }

  ByteData _packSettings() {
    final steps = settings.stepCount.clamp(1, 64).toDouble();
    final g = settings.anisotropy.clamp(-0.95, 0.95);
    final f = Float32List(12)
      ..[0] = settings.intensity
      ..[1] = settings.density
      ..[2] = g
      ..[3] = steps
      ..[4] = settings.maxDistance
      ..[5] = settings.jitter
      ..[8] = settings.color.x
      ..[9] = settings.color.y
      ..[10] = settings.color.z;
    return ByteData.sublistView(f);
  }
}
