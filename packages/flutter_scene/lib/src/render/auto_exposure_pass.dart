import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';

import 'package:flutter_scene/src/auto_exposure.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;

/// Render-graph blackboard key for the 1x1 adapted exposure-factor texture
/// [AutoExposurePass] produces. The resolve pass samples it and multiplies
/// the factor with the scene's base exposure.
const String kAutoExposureFactorBlackboardKey = 'auto_exposure_factor';

// Side length of the metering seed grid. Fixed so the metering cost is
// resolution-independent and the halving chain to 1x1 stays exact.
const int _kMeterSize = 64;

// RGBA16F everywhere; single-channel float formats are not renderable on
// every backend (bloom's format choice is the precedent).
const gpu.PixelFormat _format = gpu.PixelFormat.r16g16b16a16Float;

/// Cross-frame state for auto exposure: the persistent ping-pong pair of
/// 1x1 adapted-factor textures and the adaptation clock. Owned by the
/// scene, created when auto exposure is first enabled and dropped when it
/// is disabled (re-enabling starts fresh and snaps, like the first frame).
class AutoExposureState {
  gpu.Texture? _a;
  gpu.Texture? _b;
  int _current = 0;

  /// Whether the adaptation state holds a value from a previous frame.
  /// False on the first metered frame, which snaps to the target instead
  /// of easing from uninitialized memory.
  bool seeded = false;

  final Stopwatch _clock = Stopwatch()..start();

  /// The 1x1 holding the previous frame's adapted factor.
  gpu.Texture get previous => _texture(_current);

  /// The 1x1 the adaptation pass writes this frame.
  gpu.Texture get next => _texture(1 - _current);

  /// Swaps [previous] and [next] after a metered frame.
  void flip() => _current = 1 - _current;

  /// Seconds since the last metered frame, clamped so a hitch or a pause
  /// does not step the adaptation by a huge dt. Zero on the first call.
  double takeDeltaSeconds() {
    final dt = _clock.elapsedMicroseconds / 1e6;
    _clock.reset();
    return dt.clamp(0.0, 0.25);
  }

  gpu.Texture _texture(int index) {
    final existing = index == 0 ? _a : _b;
    if (existing != null) return existing;
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      1,
      1,
      format: _format,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    if (index == 0) {
      _a = texture;
    } else {
      _b = texture;
    }
    return texture;
  }
}

/// Meters the HDR scene color and eases the adapted exposure factor toward
/// it, publishing the 1x1 factor texture under
/// [kAutoExposureFactorBlackboardKey] for [ResolvePass] to sample.
///
/// Three stages, all plain render passes (no compute, no readback, so it
/// runs on the WebGL2 backend): a seed draw samples the scene into a
/// [_kMeterSize]-square grid of center-weighted log-luminance samples, a
/// halving chain of copy draws averages the grid down to 1x1 (the
/// geometric-mean "log-average" meter), and a 1x1 adaptation draw blends
/// the persistent state toward the metered target.
class AutoExposurePass extends RenderGraphPass {
  AutoExposurePass({
    required AutoExposureSettings settings,
    required AutoExposureState state,
  }) : _settings = settings,
       _state = state;

  final AutoExposureSettings _settings;
  final AutoExposureState _state;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _seedShader =
      baseShaderLibrary['AutoExposureSeedFragment']!;
  static final gpu.Shader _downsampleShader =
      baseShaderLibrary['CopyFragment']!;
  static final gpu.Shader _adaptShader =
      baseShaderLibrary['AutoExposureAdaptFragment']!;

  // Two triangles of NDC positions covering the screen (6 vec2s).
  static final gpu.DeviceBuffer _quadBuffer = gpu.gpuContext
      .createDeviceBufferWithCopy(
        ByteData.sublistView(
          Float32List.fromList(<double>[
            -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
            -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
          ]),
        ),
      );
  static final gpu.BufferView _quadView = gpu.BufferView(
    _quadBuffer,
    offsetInBytes: 0,
    lengthInBytes: 6 * 2 * 4,
  );

  @override
  String get name => 'AutoExposurePass';

  @override
  void execute(RenderGraphContext context) {
    final scene = context.blackboard.require<gpu.Texture>(
      kSceneColorBlackboardKey,
    );

    // Seed the metering grid from the scene color.
    var metered = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: _kMeterSize,
        height: _kMeterSize,
        format: _format,
        debugName: 'auto_exposure_seed',
      ),
    );
    _draw(
      shader: _seedShader,
      sourceSlot: 'scene_color',
      source: scene,
      target: metered,
    );

    // Average down to 1x1. Each level halves exactly, so one bilinear tap
    // at the texel center is a precise 2x2 box average.
    for (var size = _kMeterSize ~/ 2; size >= 1; size ~/= 2) {
      final level = context.texturePool.acquire(
        TransientTextureDescriptor.color(
          width: size,
          height: size,
          format: _format,
          debugName: 'auto_exposure_$size',
        ),
      );
      _draw(
        shader: _downsampleShader,
        sourceSlot: 'source_texture',
        source: metered,
        target: level,
      );
      metered = level;
    }

    // Ease the persistent adaptation state toward the metered target. The
    // first metered frame (and a requested reset) snaps instead, so the
    // image never visibly ramps in from a stale or uninitialized factor.
    // TODO(auto-exposure): the adaptation state is per scene, so multiple
    // simultaneous views meter into one shared factor (the later view wins,
    // with a near-zero dt); per-view state needs a keyed state map.
    final dt = _state.takeDeltaSeconds();
    final snap = !_state.seeded || _settings.takeResetRequest();
    final info = Float32List(8)
      ..[0] = _settings.strength
      ..[1] = _exp2(_settings.compensation)
      ..[2] = _exp2(_settings.minEv)
      ..[3] = _exp2(_settings.maxEv)
      ..[4] = autoExposureBlend(deltaSeconds: dt, speed: _settings.speedUp)
      ..[5] = autoExposureBlend(deltaSeconds: dt, speed: _settings.speedDown)
      ..[6] = snap ? 1.0 : 0.0;
    _draw(
      shader: _adaptShader,
      sourceSlot: 'metered',
      source: metered,
      target: _state.next,
      bind: (renderPass) {
        renderPass.bindUniform(
          _adaptShader.getUniformSlot('AutoExposureAdaptInfo'),
          context.transientsBuffer.emplace(ByteData.sublistView(info)),
        );
        renderPass.bindTexture(
          _adaptShader.getUniformSlot('previous_adapted'),
          _state.previous,
          sampler: _nearestClamp,
        );
      },
      sampler: _nearestClamp,
    );

    context.blackboard.set(kAutoExposureFactorBlackboardKey, _state.next);
    _state.flip();
    _state.seeded = true;
  }

  void _draw({
    required gpu.Shader shader,
    required String sourceSlot,
    required gpu.Texture source,
    required gpu.Texture target,
    void Function(gpu.RenderPass renderPass)? bind,
    gpu.SamplerOptions? sampler,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, shader));
    renderPass.setColorBlendEnable(false);
    bindVertexBufferCompat(renderPass, _quadView, 6);
    renderPass.bindTexture(
      shader.getUniformSlot(sourceSlot),
      source,
      sampler: sampler ?? _linearClamp,
    );
    bind?.call(renderPass);
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }

  static double _exp2(double ev) => math.pow(2.0, ev).toDouble();

  static final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  static final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
}
