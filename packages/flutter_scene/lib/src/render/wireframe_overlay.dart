import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/debug_view.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';

/// Draws every visible mesh's triangle edges as lines into [pass], on top of
/// the scene it just finished, depth-tested against the scene's own depth.
///
/// Each item draws with its own vertex path (the engine vertex shader or the
/// material's vertex block, skinning, morphing, instancing) and the flat
/// `MaskFragment`, with the geometry's cached edge index buffer swapped in
/// for its triangle indices. A geometry that keeps no CPU indices has no
/// edges and is skipped, reported once.
void encodeWireframeOverlay({
  required gpu.RenderPass pass,
  required TransientWriter transients,
  required RenderScene renderScene,
  required Frustum frustum,
  required Matrix4 cameraTransform,
  required Vector3 cameraPosition,
  required int layerMask,
  required List<Plane> cullingPlanes,
  required bool includeOffscreen,
  required DebugViewFrame frame,
}) {
  if (!frame.overlays.contains(DebugOverlay.wireframe)) return;
  final encoder = _WireframeEncoder(
    pass,
    transients,
    cameraTransform,
    cameraPosition,
    layerMask,
    frame,
  );
  if (includeOffscreen) {
    for (final item in renderScene.items) {
      encoder.submit(item);
    }
  } else {
    renderScene.cull(frustum, encoder.submit, additionalPlanes: cullingPlanes);
  }
}

// Whether the missing-edges message was printed this process. One line is
// enough; the overlay is a debugging aid, not a rendering path.
bool _reportedMissingEdges = false;

/// World-space distance the lines are pulled toward the camera, scaled by
/// distance in the vertex shader, so they sit on top of the fill they trace
/// instead of z-fighting with it.
const double _wireframeDepthBias = 0.004;

class _WireframeEncoder {
  _WireframeEncoder(
    this._pass,
    this._transients,
    this._cameraTransform,
    this._cameraPosition,
    this._layerMask,
    this._frame,
  ) {
    _pass.setDepthWriteEnable(false);
    _pass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    _pass.setCullMode(gpu.CullMode.none);
    _pass.setWindingOrder(gpu.WindingOrder.clockwise);
    _pass.setColorBlendEnable(true);
    _pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ),
    );
    final color = _frame.wireframeColor;
    _color = Float32List(4)
      ..[0] = color.x * color.w
      ..[1] = color.y * color.w
      ..[2] = color.z * color.w
      ..[3] = color.w;
  }

  final gpu.RenderPass _pass;
  final TransientWriter _transients;
  final Matrix4 _cameraTransform;
  final Vector3 _cameraPosition;
  final int _layerMask;
  final DebugViewFrame _frame;
  late final Float32List _color;

  static final gpu.Shader _fragment = baseShaderLibrary['MaskFragment']!;

  gpu.RenderPipeline? _boundPipeline;

  void submit(RenderItem item) {
    if (!item.drawsColor) return;
    if ((item.layers & _layerMask) == 0) return;
    // A node excluded from the scene view is excluded from its overlays too.
    if (identical(item.debugView, DebugView.none)) return;
    final geometry = item.geometry;
    final edges = geometry.debugEdges;
    if (edges == null) {
      if (!_reportedMissingEdges &&
          geometry.primitiveType == gpu.PrimitiveType.triangle) {
        _reportedMissingEdges = true;
        debugPrint(
          'flutter_scene: the wireframe overlay skipped a ${geometry.runtimeType} '
          'that keeps no CPU index data. Geometry built through the importers, '
          'MeshGeometry, or uploadVertexData retains it; caller-managed buffers '
          'do not.',
        );
      }
      return;
    }
    final material = item.material;
    _pass.clearBindings();
    item.applyJointsTexture(geometry);
    item.applyMorphWeights(geometry);
    // Position-only where the geometry offers it; otherwise the full vertex
    // path, exactly as the selection mask draws.
    final depthVertex = geometry.depthOnlyVertex;
    final materialVertex = material.materialVertexShader(
      depthVertex != null ? 'depth' : geometry.materialVertexVariant,
    );
    final activeVertex =
        materialVertex ?? depthVertex?.shader ?? geometry.vertexShader;
    final pipeline = resolvePipeline(
      activeVertex,
      _fragment,
      vertexLayout: depthVertex?.layout ?? geometry.instancedVertexLayout,
    );
    if (!identical(_boundPipeline, pipeline)) {
      _pass.bindPipeline(pipeline);
      _boundPipeline = pipeline;
    }
    _pass.setPrimitiveType(gpu.PrimitiveType.line);
    _pass.bindUniform(
      _fragment.getUniformSlot('MaskInfo'),
      _transients.emplace(ByteData.sublistView(_color)),
    );

    void bindDraw(Matrix4 worldTransform) {
      if (depthVertex != null) {
        geometry.bindPositionStream(_pass);
        bindUnskinnedFrameInfo(
          _pass,
          _transients,
          activeVertex,
          _cameraTransform,
          _cameraPosition,
          depthBias: _wireframeDepthBias,
        );
      } else {
        geometry.bind(
          _pass,
          _transients,
          worldTransform,
          _cameraTransform,
          _cameraPosition,
          shaderOverride: materialVertex,
          depthBias: _wireframeDepthBias,
        );
      }
      if (materialVertex != null) {
        material.bindVertexStage(_pass, materialVertex, _transients);
      }
      // The edge list replaces the triangle indices the bind above set.
      bindIndexBufferCompat(_pass, edges.view, edges.type, edges.count);
    }

    final instances = item.instanceTransforms;
    if (instances != null) {
      if (geometry.instancedVertexLayout == null) {
        for (final instanceTransform in instances) {
          bindDraw(item.worldTransform * instanceTransform);
          drawIndexedCompat(_pass, edges.count);
        }
        return;
      }
      bindDraw(item.worldTransform);
      final packed = packInstanceTransforms(
        item.worldTransform,
        instances,
        nodeWindingFlipped: item.windingFlipped,
        scratch: transientInstancePackingScratch,
      );
      if (packed.ccwCount > 0) {
        bindInstanceTransforms(_pass, packed.ccw);
        drawIndexedCompat(_pass, edges.count, instanceCount: packed.ccwCount);
      }
      if (packed.cwCount > 0) {
        bindInstanceTransforms(_pass, packed.cw);
        drawIndexedCompat(_pass, edges.count, instanceCount: packed.cwCount);
      }
      return;
    }

    bindDraw(item.worldTransform);
    if (geometry.instancedVertexLayout != null &&
        geometry.bindsModelTransformInstance) {
      bindSingleInstanceTransform(_pass, item.worldTransform);
    }
    drawIndexedCompat(_pass, edges.count);
  }
}
