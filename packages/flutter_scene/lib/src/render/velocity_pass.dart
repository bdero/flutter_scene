import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart'
    show SkinnedGeometry, kUnskinnedPositionOnlyLayout;
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/constants.dart'
    show kSkinnedPerVertexSize;
import 'package:flutter_scene/src/render/depth_prepass.dart'
    show kPrepassDepthStencilBlackboardKey;
import 'package:flutter_scene/src/render/depth_raster.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/instance_packing.dart'
    show bindSingleInstanceData;
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_layers.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/viewport_camera.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/material/vertex_attributes.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';

/// Render-graph blackboard key for the screen-space velocity buffer.
const String kVelocityBlackboardKey = 'velocity';

final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

final VertexLayoutDescriptor _kSkinnedVelocityLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: kSkinnedPerVertexSize,
      attributes: [
        VertexAttributeDescriptor(
          name: 'position',
          format: gpu.VertexFormat.float32x3,
        ),
        VertexAttributeDescriptor(
          name: 'joints',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 72,
        ),
        VertexAttributeDescriptor(
          name: 'weights',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 88,
        ),
      ],
    ),
  ],
);

/// Renders screen-space motion vectors for dynamic and deforming geometry.
///
/// Static objects are not rendered into this buffer; their motion is
/// reconstructed analytically in the TAA resolve pass from camera motion and
/// linear depth.
class VelocityPass extends RenderGraphPass {
  VelocityPass({
    Camera? camera,
    required RenderScene renderScene,
    required ui.Size dimensions,
    required Matrix4 currentViewProjection,
    required Matrix4 previousViewProjection,
    required Vector2 currentJitterNdc,
    required Vector2 previousJitterNdc,
    int layerMask = kRenderLayerAll,
    List<Plane> cullingPlanes = const [],
    bool skinnedMotion = true,
  }) : _camera = camera,
       _renderScene = renderScene,
       _dimensions = dimensions,
       _currentViewProjection = currentViewProjection,
       _previousViewProjection = previousViewProjection,
       _currentJitterNdc = currentJitterNdc,
       _previousJitterNdc = previousJitterNdc,
       _layerMask = layerMask,
       _cullingPlanes = cullingPlanes,
       _skinnedMotion = skinnedMotion;

  // The view's camera, for its culling frustum and depth raster. Null draws
  // with the standard mapping and culls against [_currentViewProjection].
  final Camera? _camera;
  final RenderScene _renderScene;
  final ui.Size _dimensions;
  final Matrix4 _currentViewProjection;
  final Matrix4 _previousViewProjection;
  final Vector2 _currentJitterNdc;
  final Vector2 _previousJitterNdc;
  final int _layerMask;
  final List<Plane> _cullingPlanes;
  final bool _skinnedMotion;

  static final gpu.Shader _unskinnedVertexShader =
      baseShaderLibrary['VelocityUnskinnedVertex']!;
  static final gpu.Shader _skinnedVertexShader =
      baseShaderLibrary['VelocitySkinnedVertex']!;
  static final gpu.Shader _fragmentShader =
      baseShaderLibrary['VelocityFragment']!;

  @override
  String get name => 'VelocityPass';

  @override
  void execute(RenderGraphContext context) {
    final width = _dimensions.width.toInt();
    final height = _dimensions.height.toInt();
    if (width <= 0 || height <= 0) return;

    final depthTexture = context.blackboard.get<gpu.Texture>(
      kPrepassDepthStencilBlackboardKey,
    );
    final velocityTexture = context.texturePool.acquire(
      TransientTextureDescriptor(
        width: width,
        height: height,
        format: gpu.PixelFormat.r16g16b16a16Float,
        debugName: 'velocity_pass_output',
        attachmentKey: depthTexture != null ? 'prepass_depth' : 'no_depth',
      ),
    );
    context.blackboard.set(kVelocityBlackboardKey, velocityTexture);

    final target = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: velocityTexture, clearValue: Vector4.zero()),
      depthStencilAttachment: depthTexture != null
          ? gpu.DepthStencilAttachment(
              texture: depthTexture,
              depthLoadAction: gpu.LoadAction.load,
              depthStoreAction: gpu.StoreAction.dontCare,
            )
          : null,
    );

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(target);

    renderPass.setDepthWriteEnable(false);
    renderPass.setColorBlendEnable(false);
    if (depthTexture != null) {
      // TODO(depth-invariance): Metal compiles these shaders with fast math and
      // no invariance, so this pass and the prepass may round one position
      // differently and drop its motion vectors. Declare `invariant
      // gl_Position` in both once Impeller preserves invariance at runtime.
      renderPass.setDepthCompareOperation(gpu.CompareFunction.equal);
    } else {
      renderPass.setDepthCompareOperation(gpu.CompareFunction.always);
    }
    renderPass.setCullMode(gpu.CullMode.backFace);

    final camera = _camera;
    final raster = camera == null
        ? DepthRaster.standard
        : depthRasterOf(camera);
    final frameInfoData = Float32List(40);
    frameInfoData.setRange(0, 16, _currentViewProjection.storage);
    frameInfoData.setRange(16, 32, _previousViewProjection.storage);
    frameInfoData[32] = _currentJitterNdc.x;
    frameInfoData[33] = _currentJitterNdc.y;
    frameInfoData[34] = _previousJitterNdc.x;
    frameInfoData[35] = _previousJitterNdc.y;
    if (camera != null) {
      frameInfoData[36] = camera.position.x;
      frameInfoData[37] = camera.position.y;
      frameInfoData[38] = camera.position.z;
    }
    final frameInfoView = context.transientsBuffer.emplace(
      ByteData.sublistView(frameInfoData),
    );

    final skinnedModelInfo = Float32List(40);
    final unskinnedModelInfo = Float32List(40);

    final frustum = camera == null
        ? cullingFrustum(_currentViewProjection)
        : cullingFrustumOf(camera, _dimensions);

    void submitItem(RenderItem item) {
      if (!item.drawsColor) return;
      if ((item.layers & _layerMask) == 0) return;
      if (!item.isMoving) return;

      final isSkinned =
          item.geometry is SkinnedGeometry &&
          item.jointsTexture != null &&
          _skinnedMotion;

      final vertexShader = isSkinned
          ? _skinnedVertexShader
          : _unskinnedVertexShader;
      final vertexLayout = isSkinned
          ? _kSkinnedVelocityLayout
          : (item.geometry.depthOnlyVertex?.layout ??
                kUnskinnedPositionOnlyLayout);
      final pipeline = resolvePipeline(
        vertexShader,
        _fragmentShader,
        vertexLayout: vertexLayout,
      );

      renderPass.clearBindings();
      renderPass.bindPipeline(pipeline);
      renderPass.setPrimitiveType(item.geometry.primitiveType);
      // Match the prepass offset, or the equal test drops layered surfaces.
      setCurrentDrawDepthOffset(
        raster,
        item.material.depthLayer,
        item.material.tieBreakRank,
      );
      renderPass.bindUniform(
        vertexShader.cachedUniformSlot('VelocityFrameInfo'),
        frameInfoView,
      );
      renderPass.bindUniform(
        _fragmentShader.cachedUniformSlot('VelocityFrameInfo'),
        frameInfoView,
      );

      if (isSkinned) {
        skinnedModelInfo.setRange(0, 16, item.worldTransform.storage);
        skinnedModelInfo.setRange(16, 32, item.previousWorldTransform.storage);
        skinnedModelInfo[32] = item.jointsTextureWidth.toDouble();
        skinnedModelInfo[33] = item.jointsTextureWidth.toDouble();
        skinnedModelInfo[34] = 1.0;
        skinnedModelInfo[35] = item.material.depthBias;
        skinnedModelInfo.setRange(36, 40, currentDrawDepthOffset);
        renderPass.bindUniform(
          vertexShader.cachedUniformSlot('VelocitySkinnedModelInfo'),
          context.transientsBuffer.emplace(
            ByteData.sublistView(skinnedModelInfo),
          ),
        );
        renderPass.bindTexture(
          vertexShader.cachedUniformSlot('current_joints_texture'),
          item.jointsTexture!,
          sampler: _nearestClamp,
        );
        renderPass.bindTexture(
          vertexShader.cachedUniformSlot('previous_joints_texture'),
          item.previousJointsTexture ?? item.jointsTexture!,
          sampler: _nearestClamp,
        );
        // The velocity shaders read no custom attributes.
        item.geometry
          ..useVertexAttributes(VertexAttributeSchema.none)
          ..bindGeometryBuffers(renderPass);
      } else {
        unskinnedModelInfo.setRange(0, 16, item.worldTransform.storage);
        unskinnedModelInfo.setRange(
          16,
          32,
          item.previousWorldTransform.storage,
        );
        unskinnedModelInfo.setRange(32, 36, currentDrawDepthOffset);
        unskinnedModelInfo[36] = item.material.depthBias;
        renderPass.bindUniform(
          vertexShader.cachedUniformSlot('VelocityModelInfo'),
          context.transientsBuffer.emplace(
            ByteData.sublistView(unskinnedModelInfo),
          ),
        );
        item.geometry.bindPositionStream(renderPass);
        bindSingleInstanceData(renderPass, item.worldTransform, slot: 1);
      }

      item.geometry.draw(renderPass);
    }

    _renderScene.cull(frustum, submitItem, additionalPlanes: _cullingPlanes);

    rendererSubmissions.submit(commandBuffer);
  }
}
