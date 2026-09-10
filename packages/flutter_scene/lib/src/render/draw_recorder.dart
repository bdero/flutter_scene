/// The per-draw recording hook the encoders report through during a capture
/// frame. Steady-state frames have no recorder attached, so every call site
/// is one null check.
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

/// Which encoder phase a draw belongs to.
/// {@category Debugging and profiling}
enum DrawPhase { opaque, translucent, shadow, depth, other }

/// Why a submitted render item did not draw.
/// {@category Debugging and profiling}
enum DrawSkipReason {
  /// Rejected by the view's render layer mask.
  layerMasked,

  /// Outside the frustum (or every instance was).
  frustumCulled,

  /// The level-of-detail selection culled it at this distance.
  lodCulled,

  /// The backend refused to build its pipeline.
  pipelineRejected,
}

/// Why an opaque draw did not merge with the record sorted after it.
/// {@category Debugging and profiling}
enum BatchBreakReason {
  /// It was the last record, or the next one merged.
  none,

  /// The geometry has no instanced vertex layout (skinned).
  unbatchableGeometry,

  /// This item binds a joints texture.
  skinned,

  /// This item binds morph weights.
  morphed,

  /// The material declares per-instance attributes.
  instanceAttributes,
  differentPipeline,
  differentGeometry,
  differentMaterial,
  differentLodFade,
  differentLights,
  differentLightChannels,

  /// The next item is skinned or morphed.
  nextSkinnedOrMorphed,
}

/// What the encoder knows about the draw calls it is about to issue.
/// {@category Debugging and profiling}
final class DrawContext {
  const DrawContext({
    required this.phase,
    this.item,
    this.geometry,
    this.material,
    this.vertexShader,
    this.fragmentShader,
    this.pipeline,
    this.batchedItems = 1,
    this.batchBreak = BatchBreakReason.none,
  });

  final DrawPhase phase;
  final RenderItem? item;
  final Geometry? geometry;
  final Material? material;
  final gpu.Shader? vertexShader;
  final gpu.Shader? fragmentShader;
  final gpu.RenderPipeline? pipeline;

  /// Render items folded into the draw (more than one for a merged batch).
  final int batchedItems;
  final BatchBreakReason batchBreak;
}

/// Receives draw-level events from the encoders during a capture frame.
/// {@category Debugging and profiling}
abstract interface class DrawRecorder {
  /// Sets the context the following draws are issued under, until the next
  /// [setContext] or [clearContext].
  void setContext(DrawContext context);

  /// Draws issued after this carry no context (fullscreen and utility
  /// passes).
  void clearContext();

  /// One draw call reached the backend.
  void onDraw(int vertexCount, int instanceCount, {required bool indexed});

  /// A submitted item did not draw.
  void onSkip(RenderItem item, DrawSkipReason reason);

  /// Uniform bytes were emplaced into the frame's transient buffer.
  void onUniformEmplaced(ByteData bytes);
}

/// The recorder for the pass being encoded, or null outside a capture.
DrawRecorder? activeDrawRecorder;
