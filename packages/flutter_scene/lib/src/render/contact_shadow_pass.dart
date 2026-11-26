import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/contact_shadows.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/contact_shadow_wavefront.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/ssao_pass.dart' show fullscreenQuad;
import 'package:flutter_scene/src/render/uniform_slots.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';

/// Render-graph blackboard key under which [ContactShadowPass] publishes the
/// screen-space shadow mask: an rgba8 texture at the depth prepass's
/// resolution holding one light's contact visibility per channel (1 lit).
const String kScreenSpaceShadowsBlackboardKey = 'screen_space_shadows';

/// How many lights one mask carries, one per channel.
const int kContactShadowChannels = 4;

// Frames before the temporal noise offsets repeat, matching the ambient
// occlusion chain.
const int _kTemporalNoiseCycle = 16;

/// The kind of light a mask channel marches toward.
enum ContactShadowLightType {
  /// Parallel rays toward [ContactShadowLight.vector], a view-space
  /// direction.
  directional,

  /// Rays toward [ContactShadowLight.vector], a view-space position.
  point,

  /// A point light limited to the cone around [ContactShadowLight.axis].
  spot,
}

/// One light's contact-shadow march, in the camera's view space (+x right,
/// +y up, +z forward).
class ContactShadowLight {
  const ContactShadowLight({
    required this.type,
    required this.vector,
    required this.distance,
    this.inverseRange = 0.0,
    this.outerConeCos = -1.0,
    this.axis,
  });

  /// A directional light's direction toward the light.
  factory ContactShadowLight.directional(
    Vector3 towardLightView,
    double distance,
  ) => ContactShadowLight(
    type: ContactShadowLightType.directional,
    vector: towardLightView.normalized(),
    distance: distance,
  );

  final ContactShadowLightType type;

  /// The view-space direction toward a directional light, or a point or
  /// spot light's view-space position.
  final Vector3 vector;

  /// How far each ray marches, in world units.
  final double distance;

  /// One over the light's range, 0 for unbounded.
  final double inverseRange;

  /// A spot's cosine at its outer cone edge.
  final double outerConeCos;

  /// A spot's view-space travel direction.
  final Vector3? axis;
}

/// Rotates world-space direction [world] into the view space spanned by
/// [right], [up], and [forward].
Vector3 viewDirection(
  Vector3 world,
  Vector3 right,
  Vector3 up,
  Vector3 forward,
) => Vector3(world.dot(right), world.dot(up), world.dot(forward));

/// Marches the linear depth prepass toward up to four lights and publishes
/// the screen-space shadow mask under [kScreenSpaceShadowsBlackboardKey].
///
/// A single full-screen fragment pass at the depth prepass's resolution; see
/// `flutter_scene_contact_shadows.frag`.
class ContactShadowPass extends RenderGraphPass {
  ContactShadowPass({
    required ProjectionParams projection,
    required ContactShadowSettings settings,
    required int steps,
    required List<ContactShadowLight?> channels,
    int temporalNoiseFrame = 0,
    bool packDepth = false,
    bool halfResolution = false,
    ContactShadowWavefront? wavefront,
    int wavefrontMaxSamples = 60,
  }) : assert(channels.length <= kContactShadowChannels),
       _projection = projection,
       _settings = settings,
       _steps = steps,
       _channels = channels,
       _temporalNoiseFrame = temporalNoiseFrame,
       _packDepth = packDepth,
       _halfResolution = halfResolution,
       _wavefront = wavefront,
       _wavefrontMaxSamples = wavefrontMaxSamples;

  final ProjectionParams _projection;
  final ContactShadowSettings _settings;
  final int _steps;
  final List<ContactShadowLight?> _channels;
  final int _temporalNoiseFrame;
  final bool _packDepth;

  // Whether the mask is half the depth prepass's size (rounded down), each
  // texel marching from the depth texel at its center.
  final bool _halfResolution;

  // Marches channel r in compute when set and ready, capped at this many
  // samples per pixel.
  final ContactShadowWavefront? _wavefront;
  final int _wavefrontMaxSamples;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _fragmentShader =
      baseShaderLibrary['ContactShadowsFragment']!;

  // Linear depth is fp32 and must not be interpolated across edges.
  static final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  // Every renderable backend accepts rgba8, unlike the single-channel
  // formats.
  static const gpu.PixelFormat _maskFormat = gpu.PixelFormat.r8g8b8a8UNormInt;

  @override
  String get name => 'ContactShadowPass';

  /// Packs the `ContactShadowInfo` block for a [width] x [height] mask.
  /// Must match its layout in `flutter_scene_contact_shadows.frag`.
  static Float32List packInfo({
    required int width,
    required int height,
    required ProjectionParams projection,
    required ContactShadowSettings settings,
    required int steps,
    required List<ContactShadowLight?> channels,
    int temporalNoiseFrame = 0,
    bool packDepth = false,
    bool sunFromWavefront = false,
  }) {
    final info = Float32List(24 + 3 * 4 * kContactShadowChannels)
      ..[0] = width.toDouble()
      ..[1] = height.toDouble()
      ..[2] = 1.0 / width
      ..[3] = 1.0 / height
      ..[4] = projection.scaleX
      ..[5] = projection.scaleY
      ..[6] = projection.near
      ..[7] = projection.far
      ..[8] = projection.offsetX
      ..[9] = projection.offsetY
      ..[10] = projection.orthographicFlag
      ..[11] = (temporalNoiseFrame % _kTemporalNoiseCycle).toDouble()
      // depth_uv: identity.
      ..[12] = 1.0
      ..[13] = 1.0
      ..[16] = settings.thickness
      ..[17] = settings.maxDistance
      ..[18] = settings.fadeRange
      ..[19] = settings.opacity.clamp(0.0, 1.0)
      ..[20] = steps.toDouble()
      ..[21] = packDepth ? 1.0 : 0.0
      ..[22] = sunFromWavefront ? 1.0 : 0.0;
    const vectors = 24;
    const params = vectors + 4 * kContactShadowChannels;
    const axes = params + 4 * kContactShadowChannels;
    for (var i = 0; i < channels.length; i++) {
      final light = channels[i];
      if (light == null) continue;
      info
        ..[vectors + i * 4] = light.vector.x
        ..[vectors + i * 4 + 1] = light.vector.y
        ..[vectors + i * 4 + 2] = light.vector.z
        ..[vectors + i * 4 + 3] = light.type.index + 1.0
        ..[params + i * 4] = light.distance
        ..[params + i * 4 + 1] = light.inverseRange
        ..[params + i * 4 + 2] = light.outerConeCos;
      final axis = light.axis;
      if (axis != null) {
        info
          ..[axes + i * 4] = axis.x
          ..[axes + i * 4 + 1] = axis.y
          ..[axes + i * 4 + 2] = axis.z;
      }
    }
    return info;
  }

  @override
  void execute(RenderGraphContext context) {
    final linearDepth = context.blackboard.require<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );
    final width = _halfResolution
        ? math.max(1, linearDepth.width ~/ 2)
        : linearDepth.width;
    final height = _halfResolution
        ? math.max(1, linearDepth.height ~/ 2)
        : linearDepth.height;
    // The primary directional light marches in compute where it can.
    final sun = _channels.isEmpty ? null : _channels.first;
    final sunShadows = sun?.type == ContactShadowLightType.directional
        ? _wavefront?.encode(
            context,
            linearDepth: linearDepth,
            towardLight: sun!.vector,
            distance: sun.distance,
            projection: _projection,
            settings: _settings,
            maxSampleCount: _wavefrontMaxSamples,
          )
        : null;
    final mask = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: _maskFormat,
        debugName: 'screen_space_shadows',
      ),
    );
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: mask)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _fragmentShader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, fullscreenQuad(), 6);
    final info = packInfo(
      width: width,
      height: height,
      projection: _projection,
      settings: _settings,
      steps: _steps,
      channels: _channels,
      temporalNoiseFrame: _temporalNoiseFrame,
      packDepth: _packDepth,
      sunFromWavefront: sunShadows != null,
    );
    renderPass.bindUniform(
      _fragmentShader.cachedUniformSlot('ContactShadowInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    renderPass.bindTexture(
      _fragmentShader.cachedUniformSlot('linear_depth'),
      linearDepth,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _fragmentShader.cachedUniformSlot('sun_shadows'),
      sunShadows ?? Material.getWhitePlaceholderTexture(),
      sampler: _nearestClamp,
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
    context.blackboard.set(kScreenSpaceShadowsBlackboardKey, mask);
  }
}
