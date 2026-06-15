import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart';
import 'package:flutter_scene/src/render/object_filter.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/resolve_pass.dart';
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_scene/src/shader_uniform_bindings.dart';
import 'package:flutter_scene/src/shaders.dart';

/// A named anchor point in the built-in render pipeline where a
/// [CustomRenderPass] runs. Ordering within one stage follows the order the
/// passes were added.
///
/// The stages are coarse and stable, so a custom pass keeps working as the
/// internal pipeline evolves. The first two stages operate on the linear
/// HDR scene color (before tone mapping); the last two operate on the
/// display-referred image (after the resolve/tone-mapping pass).
/// {@category Rendering}
enum RenderStage {
  /// Right after the scene is drawn (opaque and transparent), on the linear
  /// HDR scene color, before bloom and any HDR custom effects.
  afterScene,

  /// On the linear HDR scene color just before tone mapping, after bloom
  /// and HDR custom effects.
  beforeToneMapping,

  /// On the display-referred image right after tone mapping, before
  /// anti-aliasing.
  afterToneMapping,

  /// At the very end, after anti-aliasing and display-referred custom
  /// effects (the overlay slot the built-in selection outline uses).
  afterAntiAliasing,
}

/// A user-supplied render pass inserted into the built-in pipeline at a
/// named [stage]. Add one with `Scene.addRenderPass`.
///
/// A pass composes two engine-driven primitives on the [RenderPassContext]:
/// [RenderPassContext.drawObjects] (render a filtered set of nodes flat into
/// a mask texture) and [RenderPassContext.applyShader] (run a full-screen
/// fragment shader that reads the current color and writes the next). The
/// built-in selection outline is exactly a [drawObjects] mask composited by
/// an [applyShader] outline shader, so anything it does, a custom pass can.
///
/// ```dart
/// class TintPass extends CustomRenderPass {
///   TintPass(this.shader);
///   final gpu.Shader shader;
///   @override
///   String get name => 'tint';
///   @override
///   RenderStage get stage => RenderStage.afterToneMapping;
///   @override
///   void execute(RenderPassContext context) {
///     context.applyShader(shader); // reads input_color, writes the chain
///   }
/// }
/// ```
/// {@category Rendering}
abstract class CustomRenderPass {
  /// A short human-readable name, used for debugging.
  String get name;

  /// Where in the pipeline this pass runs.
  RenderStage get stage;

  /// Whether this pass runs. A disabled pass is skipped entirely (it never
  /// consumes a buffer), so toggling it does not disturb the rest of the
  /// chain.
  bool enabled = true;

  /// Records this pass's work for one frame using [context].
  void execute(RenderPassContext context);
}

/// The frame context handed to [CustomRenderPass.execute].
///
/// A friendlier facade over the internal render graph. It exposes the
/// standard pipeline buffers as read-only [gpu.Texture] handles, an
/// object-filtered draw ([drawObjects]), and a full-screen shader step
/// ([applyShader]) that advances this stage's color chain. The engine owns
/// all GPU orchestration; a pass never creates command buffers or pipelines
/// itself. It is created by the engine; do not construct one.
/// {@category Rendering}
class RenderPassContext {
  RenderPassContext._(
    this._context,
    this.stage,
    this.camera,
    this.dimensions,
    this._destination,
    this._renderScene,
    this._viewLayerMask,
    this._passKey,
    this._time,
  );

  final RenderGraphContext _context;

  /// The stage this pass was registered for.
  final RenderStage stage;

  /// The camera the current view is rendered with.
  final Camera camera;

  /// The render-target size in physical pixels.
  final ui.Size dimensions;

  final gpu.Texture _destination;
  final RenderScene _renderScene;
  final int _viewLayerMask;
  final String _passKey;
  final double _time;
  bool _wrote = false;
  int _drawCounter = 0;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;

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

  static final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  /// The linear HDR scene color. Available at every stage (at the
  /// display-referred stages it is the pre-tone-mapped color), so a custom
  /// pass can reach back to the HDR image.
  gpu.Texture get sceneColorHdr =>
      _context.blackboard.require<gpu.Texture>(kSceneColorBlackboardKey);

  /// The current display-referred image (after tone mapping). Throws if read
  /// at the [RenderStage.afterScene] / [RenderStage.beforeToneMapping]
  /// stages (it does not exist yet); use [sceneColorHdr] there.
  gpu.Texture get displayColor =>
      _context.blackboard.require<gpu.Texture>(kDisplayColorBlackboardKey);

  /// The linear (view-space) depth buffer, or null when no depth prepass ran
  /// this frame (it only runs when ambient occlusion is enabled).
  gpu.Texture? get sceneDepthLinear =>
      _context.blackboard.get<gpu.Texture>(kLinearDepthBlackboardKey);

  // Whether this stage operates on the HDR scene color or the display image.
  Object get _chainKey =>
      stage == RenderStage.afterScene || stage == RenderStage.beforeToneMapping
      ? kSceneColorBlackboardKey
      : kDisplayColorBlackboardKey;

  /// The current color for this stage's chain (HDR at the HDR stages, the
  /// display image at the display stages). [applyShader] binds this as
  /// `input_color` automatically; this getter is for sampling it explicitly.
  gpu.Texture get currentColor =>
      _context.blackboard.require<gpu.Texture>(_chainKey);

  /// Draws a filtered set of the scene's geometry flat into a returned mask
  /// texture, each object filled with a color (coverage in alpha), with its
  /// own cleared depth so the objects self-occlude but are not occluded by
  /// the rest of the scene (an x-ray silhouette). The building block for
  /// masks, outlines, and highlights; sample the result in [applyShader].
  ///
  /// [filter] selects which nodes draw. [colorOf] gives a per-node color
  /// (linear RGBA); when null every object uses [color] (default opaque
  /// white). The mask is view-sized and valid for the rest of the frame.
  gpu.Texture drawObjects({
    NodeFilter filter = const NodeFilter.all(),
    Vector4? color,
    Vector4 Function(Object node)? colorOf,
    Vector4? clearColor,
  }) {
    final width = dimensions.width.toInt();
    final height = dimensions.height.toInt();
    final index = _drawCounter++;
    final mask = _context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: _destination.format,
        debugName: 'custom_mask_${_passKey}_$index',
      ),
    );
    final depth = _context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: width,
        height: height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        debugName: 'custom_mask_depth_${_passKey}_$index',
      ),
    );
    final fill = color ?? Vector4(1, 1, 1, 1);
    renderObjectMask(
      target: mask,
      depth: depth,
      clearColor: clearColor ?? Vector4.zero(),
      cameraTransform: camera.getViewTransform(dimensions),
      cameraPosition: camera.position,
      renderScene: _renderScene,
      transientsBuffer: _context.transientsBuffer,
      layerMask: _viewLayerMask,
      filter: filter,
      colorOf: colorOf == null
          ? (_) => fill
          : (item) {
              final node = item.sourceNode;
              return node == null ? fill : colorOf(node);
            },
    );
    return mask;
  }

  /// Runs [fragmentShader] as a full-screen pass that advances this stage's
  /// color chain: the engine binds the current color as `sampler2D
  /// input_color` (sampled at the `v_uv` varying), renders into the next
  /// buffer, and makes it the current color for downstream passes.
  ///
  /// Bind extra inputs with [textures] (each a `sampler2D` by name, sampled
  /// with [samplers] or a default linear-clamp sampler) and [uniforms] (each
  /// a std140 uniform block by name). Set [frameInfo] when the shader
  /// declares a `PostFrameInfo` block (resolution / texel_size / time), the
  /// same contract as a `PostEffect`.
  ///
  /// Call at most once per pass; for multiple chained effects use multiple
  /// [CustomRenderPass]es. At an HDR stage the shader must output linear HDR
  /// premultiplied by alpha (the material-shader contract).
  void applyShader(
    gpu.Shader fragmentShader, {
    Map<String, gpu.Texture> textures = const {},
    Map<String, gpu.SamplerOptions> samplers = const {},
    Map<String, ByteData> uniforms = const {},
    bool frameInfo = false,
  }) {
    final input = _context.blackboard.require<gpu.Texture>(_chainKey);

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: _destination)),
    );
    renderPass.bindPipeline(
      gpu.gpuContext.createRenderPipeline(_vertexShader, fragmentShader),
    );
    bindVertexBufferCompat(renderPass, _quadView, 6);

    renderPass.bindTexture(
      fragmentShader.getUniformSlot('input_color'),
      input,
      sampler: _linearClamp,
    );

    if (frameInfo) {
      final w = dimensions.width;
      final h = dimensions.height;
      final info = Float32List(8)
        ..[0] = w
        ..[1] = h
        ..[2] = w == 0 ? 0.0 : 1.0 / w
        ..[3] = h == 0 ? 0.0 : 1.0 / h
        ..[4] = _time;
      renderPass.bindUniform(
        fragmentShader.getUniformSlot('PostFrameInfo'),
        _context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
    }

    if (textures.isNotEmpty || uniforms.isNotEmpty) {
      final bindings = ShaderUniformBindings();
      for (final entry in uniforms.entries) {
        bindings.setUniformBlock(entry.key, entry.value);
      }
      for (final entry in textures.entries) {
        bindings.setTexture(
          entry.key,
          entry.value,
          sampler: samplers[entry.key] ?? _linearClamp,
        );
      }
      bindings.bind(renderPass, fragmentShader, _context.transientsBuffer);
    }

    drawCompat(renderPass, 6);
    commandBuffer.submit();

    _wrote = true;
  }
}

/// Wraps a user [CustomRenderPass] as a render-graph pass, building the
/// facade context and publishing the color chain when the pass wrote it.
class UserRenderGraphPass extends RenderGraphPass {
  UserRenderGraphPass({
    required CustomRenderPass pass,
    required Camera camera,
    required ui.Size dimensions,
    required gpu.Texture destination,
    required RenderScene renderScene,
    required int viewLayerMask,
    required int passIndex,
    required double time,
  }) : _pass = pass,
       _camera = camera,
       _dimensions = dimensions,
       _destination = destination,
       _renderScene = renderScene,
       _viewLayerMask = viewLayerMask,
       _passIndex = passIndex,
       _time = time;

  final CustomRenderPass _pass;
  final Camera _camera;
  final ui.Size _dimensions;
  final gpu.Texture _destination;
  final RenderScene _renderScene;
  final int _viewLayerMask;
  final int _passIndex;
  final double _time;

  @override
  String get name => _pass.name;

  @override
  void execute(RenderGraphContext context) {
    final passContext = RenderPassContext._(
      context,
      _pass.stage,
      _camera,
      _dimensions,
      _destination,
      _renderScene,
      _viewLayerMask,
      '${_pass.stage.name}_$_passIndex',
      _time,
    );
    _pass.execute(passContext);
    if (passContext._wrote) {
      context.blackboard.set(passContext._chainKey, _destination);
    }
  }
}
