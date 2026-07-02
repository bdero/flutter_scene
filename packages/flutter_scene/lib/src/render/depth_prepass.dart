import 'dart:typed_data';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart'
    show bindUnskinnedFrameInfo;
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';

/// Render-graph blackboard key under which [DepthPrepass] publishes the
/// camera linear-depth texture: planar view-space depth (world units) in
/// the red channel, with the far value where no geometry was drawn.
const String kLinearDepthBlackboardKey = 'linear_depth';

/// Renders the opaque scene's depth from the camera into a linear-depth
/// color target and publishes it on the render-graph blackboard.
///
/// Screen-space effects (ambient occlusion today, and depth-aware effects
/// later) read this to reconstruct view-space positions. The prepass also
/// primes early-Z for the following color pass.
///
/// Planar view-space depth is written into the red channel of a
/// floating-point color target (rather than relying on a shader-readable
/// depth-stencil texture), mirroring how the shadow pass stores depth in a
/// color attachment. That keeps the texture sampleable identically on
/// every backend.
class DepthPrepass extends RenderGraphPass {
  DepthPrepass({
    required Camera camera,
    required RenderScene renderScene,
    required ui.Size dimensions,
    required Vector3 cameraForward,
    required double farDepth,
    int layerMask = kRenderLayerAll,
    bool writeNormals = false,
    Vector3? cameraRight,
    Vector3? cameraUp,
  }) : _camera = camera,
       _renderScene = renderScene,
       _dimensions = dimensions,
       _cameraForward = cameraForward,
       _farDepth = farDepth,
       _layerMask = layerMask,
       _writeNormals = writeNormals,
       _cameraRight = cameraRight ?? Vector3.zero(),
       _cameraUp = cameraUp ?? Vector3.zero();

  final Camera _camera;
  final RenderScene _renderScene;
  final ui.Size _dimensions;
  final Vector3 _cameraForward;
  final double _farDepth;
  final int _layerMask;

  // When set, the prepass also writes the interpolated view-space normal
  // into the linear-depth target's green/blue/alpha channels (the depth uses
  // only red), for screen-space reflections. This forces the full vertex
  // shader (the depth-only position path carries no normal), so it is left
  // off when only ambient occlusion needs the prepass.
  final bool _writeNormals;
  final Vector3 _cameraRight;
  final Vector3 _cameraUp;

  @override
  String get name => 'DepthPrepass';

  @override
  void execute(RenderGraphContext context) {
    final width = _dimensions.width.toInt();
    final height = _dimensions.height.toInt();

    // fp32 (not fp16): the occlusion pass reconstructs view-space positions
    // and normals from this depth, and fp16's ~11-bit mantissa quantizes it
    // into visibly banded steps (the same reason the shadow map is fp32).
    // Only the red channel is used.
    // TODO(flutter_scene): use a single-channel r32Float once Flutter GPU
    // exposes it, to drop the three unused channels' bandwidth.
    final linearDepth = context.texturePool.acquire(
      TransientTextureDescriptor.color(
        width: width,
        height: height,
        format: gpu.PixelFormat.r32g32b32a32Float,
        debugName: 'linear_depth',
      ),
    );
    final depth = context.texturePool.acquire(
      TransientTextureDescriptor.depth(
        width: width,
        height: height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        debugName: 'depth_prepass_depth',
      ),
    );
    final target = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: linearDepth,
        // Background texels (no geometry) read as the far plane, i.e. fully
        // unoccluded for any consumer.
        clearValue: Vector4(_farDepth, 0.0, 0.0, 1.0),
      ),
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: depth,
        depthClearValue: 1.0,
      ),
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(target);
    final encoder = _DepthPrepassEncoder(
      renderPass,
      context.transientsBuffer,
      _camera.getViewTransform(_dimensions),
      _camera.position,
      _cameraForward,
      _layerMask,
      writeNormals: _writeNormals,
      cameraRight: _cameraRight,
      cameraUp: _cameraUp,
    );
    _renderScene.cull(encoder.frustum, encoder.submit);
    commandBuffer.submit();

    context.blackboard.set(kLinearDepthBlackboardKey, linearDepth);
  }
}

/// Records each opaque object's planar view-space depth into the prepass
/// render pass, from the camera's point of view.
///
/// Mirrors `ShadowEncoder`: it reuses the engine's standard vertex shaders
/// (so unskinned and skinned geometry are both covered) paired with the
/// `LinearDepthFragment` shader, and supplies the camera view-projection in
/// place of the light-space matrix. Translucent objects do not write depth.
class _DepthPrepassEncoder {
  _DepthPrepassEncoder(
    this._renderPass,
    this._transientsBuffer,
    this._cameraTransform,
    this._cameraPosition,
    Vector3 cameraForward,
    this._layerMask, {
    required bool writeNormals,
    required Vector3 cameraRight,
    required Vector3 cameraUp,
  }) : _writeNormals = writeNormals {
    frustum = Frustum.matrix(_cameraTransform);
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    // Match the standard materials' winding / culling so the same faces
    // that are visible contribute depth.
    _renderPass.setCullMode(gpu.CullMode.backFace);
    _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
    // The camera axes are constant across the pass. Pack them once and
    // rebind per draw (clearBindings drops the binding between draws). The
    // normal-writing path also needs the right/up axes to rotate the world
    // normal into view space; the depth-only path uses just forward.
    if (writeNormals) {
      _depthInfo = Float32List(12)
        ..[0] = cameraForward.x
        ..[1] = cameraForward.y
        ..[2] = cameraForward.z
        ..[4] = cameraRight.x
        ..[5] = cameraRight.y
        ..[6] = cameraRight.z
        ..[8] = cameraUp.x
        ..[9] = cameraUp.y
        ..[10] = cameraUp.z;
    } else {
      _depthInfo = Float32List(4)
        ..[0] = cameraForward.x
        ..[1] = cameraForward.y
        ..[2] = cameraForward.z;
    }
  }

  final gpu.RenderPass _renderPass;
  final gpu.HostBuffer _transientsBuffer;
  final Matrix4 _cameraTransform;
  final Vector3 _cameraPosition;
  final int _layerMask;
  final bool _writeNormals;
  late final Float32List _depthInfo;

  static final gpu.Shader _depthShader =
      baseShaderLibrary['LinearDepthFragment']!;
  static final gpu.Shader _depthNormalShader =
      baseShaderLibrary['LinearDepthNormalFragment']!;

  // The fragment shader and its uniform-block name for this pass.
  gpu.Shader get _fragmentShader =>
      _writeNormals ? _depthNormalShader : _depthShader;
  String get _infoBlockName => _writeNormals ? 'DepthNormalInfo' : 'DepthInfo';

  /// Frustum of the camera view-projection, used for per-item culling.
  late final Frustum frustum;

  /// Reusable AABB for the per-item cull check.
  final Aabb3 cullScratchAabb = Aabb3();

  /// The pipeline currently bound on the render pass, or null before the
  /// first draw. `clearBindings` leaves the pipeline in place, so
  /// consecutive objects that share one only bind it once.
  gpu.RenderPipeline? _boundPipeline;

  /// Records [item]'s depth, unless it is hidden, translucent (no depth
  /// contribution), or culled by the camera frustum.
  void submit(RenderItem item) {
    if (!item.visible) return;
    if ((item.layers & _layerMask) == 0) return;
    if (!item.material.isOpaque()) return;
    if (item.frustumCulled) {
      final bounds = item.cullBounds;
      if (bounds != null) {
        cullScratchAabb
          ..copyFrom(bounds)
          ..transform(item.worldTransform);
        if (!frustum.intersectsWithAabb3(cullScratchAabb)) return;
      }
    }
    _renderPass.clearBindings();
    final geometry = item.geometry;
    // Unskinned geometry draws depth through a position-only shader and layout
    // (fetching only position); skinned geometry has no such variant, so it
    // falls back to its full vertex shader and bind. The normal-writing path
    // always uses the full vertex shader, since the position-only path
    // carries no normal.
    // TODO(vertex-materials): pair a `vertex { }` material's variant here (and
    // bind its MaterialParams) so the prepass depth matches the displaced color
    // pass; otherwise a depth prepass (enabled by SSAO/SSR) mismatches a
    // vertex-displacing material. This pass binds the real camera transform and
    // position, so a camera-relative displacement is correct once wired.
    final depthVertex = _writeNormals ? null : geometry.depthOnlyVertex;
    final pipeline = resolvePipeline(
      depthVertex?.shader ?? geometry.vertexShader,
      _fragmentShader,
      vertexLayout: depthVertex?.layout ?? geometry.instancedVertexLayout,
    );
    if (!identical(_boundPipeline, pipeline)) {
      _renderPass.bindPipeline(pipeline);
      _boundPipeline = pipeline;
    }
    _renderPass.setPrimitiveType(geometry.primitiveType);
    _renderPass.bindUniform(
      _fragmentShader.getUniformSlot(_infoBlockName),
      _transientsBuffer.emplace(ByteData.sublistView(_depthInfo)),
    );

    // Binds the vertex/index buffers and the per-frame uniform for one draw.
    // The position-only path resolves FrameInfo against the depth shader; the
    // skinned fallback uses the geometry's own bind (which ignores the model
    // transform passed here, since skinned uses joint matrices).
    void bindDraw(Matrix4 worldTransform) {
      if (depthVertex != null) {
        geometry.bindPositionStream(_renderPass);
        bindUnskinnedFrameInfo(
          _renderPass,
          _transientsBuffer,
          depthVertex.shader,
          _cameraTransform,
          _cameraPosition,
        );
      } else {
        geometry.bind(
          _renderPass,
          _transientsBuffer,
          worldTransform,
          _cameraTransform,
          _cameraPosition,
        );
      }
    }

    // The instance-rate model transform sits in the slot after the bound
    // vertex streams. The depth-only path binds just the position stream
    // (slot 0), so its instance is slot 1; the normal-writing path binds the
    // full stream set, so the instance follows them (slot
    // [vertexStreamCount]), matching the color encoder.
    final instanceSlot = depthVertex != null ? 1 : geometry.vertexStreamCount;

    final instances = item.instanceTransforms;
    if (instances != null) {
      if (geometry.instancedVertexLayout == null) {
        // Skinned geometry has no instance-attribute path; loop.
        for (final instanceTransform in instances) {
          bindDraw(item.worldTransform * instanceTransform);
          final flip =
              item.windingFlipped != (instanceTransform.determinant() < 0);
          _renderPass.setWindingOrder(
            flip
                ? gpu.WindingOrder.clockwise
                : gpu.WindingOrder.counterClockwise,
          );
          geometry.draw(_renderPass);
        }
        return;
      }
      bindDraw(item.worldTransform);
      final packed = packInstanceTransforms(
        item.worldTransform,
        instances,
        nodeWindingFlipped: item.windingFlipped,
      );
      if (packed.ccwCount > 0) {
        bindInstanceTransforms(_renderPass, packed.ccw, slot: instanceSlot);
        _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
        geometry.draw(_renderPass, instanceCount: packed.ccwCount);
      }
      if (packed.cwCount > 0) {
        bindInstanceTransforms(_renderPass, packed.cw, slot: instanceSlot);
        _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
        geometry.draw(_renderPass, instanceCount: packed.cwCount);
      }
      return;
    }

    bindDraw(item.worldTransform);
    // Skip the model-transform instance buffer for geometry that supplies its
    // own per-instance buffer (see the color encoder), or it clobbers the
    // stream slot.
    if (geometry.instancedVertexLayout != null &&
        geometry.bindsModelTransformInstance) {
      bindSingleInstanceTransform(
        _renderPass,
        item.worldTransform,
        slot: instanceSlot,
      );
    }
    _renderPass.setWindingOrder(
      item.windingFlipped
          ? gpu.WindingOrder.clockwise
          : gpu.WindingOrder.counterClockwise,
    );
    geometry.draw(_renderPass);
  }
}
