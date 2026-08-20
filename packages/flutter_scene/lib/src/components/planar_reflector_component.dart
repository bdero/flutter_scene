import 'package:flutter/foundation.dart' show internal;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render/planar_reflection.dart';
import 'package:flutter_scene/src/render/render_layers.dart';

/// A [Component] that renders a per-frame planar reflection of the scene for
/// the mirror surface at its node.
///
/// Each frame the surface is visible, the engine renders one offscreen
/// capture of the scene from the view camera reflected across the surface's
/// plane, with the capture's near plane clamped to that plane so geometry
/// behind the mirror never appears. The plane passes through the node's
/// origin with [localNormal] (the local `+Y` by default) as its facing
/// direction, both taken through the node's world transform.
///
/// The capture reaches materials in this node's subtree that declare the
/// `planar_reflection` engine input in their `.fmat` (see `MATERIALS.md`),
/// which sample it projectively through `GetPlanarReflection()`. Give each
/// reflector group its own material instance; a material shared across
/// groups receives one group's capture arbitrarily.
///
/// A capture is a second scene submission. Its GPU fragment cost scales with
/// [resolutionScale], but the CPU and draw-call cost scale with scene
/// complexity like any other view of the scene; bound it with [layerMask].
/// The capture reuses the frame's shadow atlas and runs without screen-space
/// post-processing (no occlusion, reflections, bloom, depth of field, or god
/// rays), and reflectors seen inside a capture draw without their own
/// reflection (their base material look), so captures never recurse. Worst
/// case is one extra scene render per reflection group per frame.
///
/// Captures follow the frame's primary view (the first screen view). Views
/// rendered to a `RenderTexture` composite the previous frame's capture, and
/// additional views reuse the primary view's capture.
/// {@category Rendering}
// TODO(planar-blur): blur the capture with a small mip chain keyed by the
// surface roughness, plus a maxRoughness cutoff that skips the capture
// entirely; today the capture is the sharp mirror term.
// TODO(planar-depth-fade): fade the reflection by the reflected hit's
// distance from the plane so tall reflections soften like SSR's range fade.
// TODO(planar-multiview): capture per consuming view; today secondary views
// reuse the primary view's capture, which is approximate for their cameras.
class PlanarReflectorComponent extends Component {
  /// Creates a planar reflector for the mirror surface at the owning node.
  PlanarReflectorComponent({
    this.resolutionScale = 0.5,
    this.layerMask = kRenderLayerAll,
    this.reflectionGroupId = -1,
    this.clipBias = 1e-3,
    Vector3? localNormal,
  }) : localNormal = localNormal ?? Vector3(0, 1, 0),
       assert(
         resolutionScale > 0.0 && resolutionScale.isFinite,
         'resolutionScale must be a positive, finite number.',
       );

  /// The capture's resolution relative to the view it follows, clamped to
  /// `0.1..1.0` at capture time. Defaults to `0.5` (half resolution, a
  /// quarter of the fragment work), matching the screen-space reflection
  /// knob. Setting [enabled] false pauses capturing entirely and the
  /// surface falls back to its base look.
  double resolutionScale;

  /// A bitmask selecting which node layers render into the capture, the
  /// same selection a `RenderView.layerMask` makes. Defaults to every
  /// layer. Use it to keep expensive or irrelevant content out of the
  /// mirror.
  int layerMask;

  /// Reflectors sharing a non-negative group id share one capture per
  /// frame; give co-planar surfaces (tiles of one floor) the same id so
  /// they cost one scene render together. The default `-1` gives this
  /// reflector its own capture. Surfaces in one group must be co-planar;
  /// the group's plane comes from one member.
  int reflectionGroupId;

  /// World-space offset of the capture's clip plane in front of the mirror
  /// plane, keeping the surface itself (and coplanar acne) out of the
  /// capture. The default suits meter-scale scenes.
  double clipBias;

  /// The mirror plane's facing direction in the node's local space.
  /// Defaults to `+Y` (a floor mirror when the node is unrotated).
  Vector3 localNormal;

  /// The mirror plane in world space, derived from the node's transform:
  /// through the node's origin, facing [localNormal] under the node's
  /// rotation and scale.
  Plane worldPlane() {
    final transform = node.globalTransform;
    final point = transform.getTranslation();
    // Normals transform by the inverse transpose so non-uniform scale keeps
    // the plane's facing correct; a singular transform falls back to the
    // raw rotation.
    final rotation = transform.getRotation();
    final inverted = Matrix3.copy(rotation);
    final normalMatrix = inverted.invert() != 0.0
        ? (inverted..transpose())
        : rotation;
    final normal = (normalMatrix * localNormal) as Vector3;
    if (normal.length2 < 1e-24) {
      return Plane.normalconstant(Vector3(0, 1, 0), -point.y);
    }
    normal.normalize();
    return Plane.normalconstant(normal, -normal.dot(point));
  }

  /// This frame's capture, or null while none is active. Set by the
  /// renderer.
  @internal
  PlanarReflectionFrame? get internalFrame => _frame;
  PlanarReflectionFrame? _frame;

  /// Routes [frame] (or its absence) to the mirror surface's materials, the
  /// ones in this node's subtree that sample a planar reflection. Called by
  /// the renderer each frame before the view's scene pass encodes.
  @internal
  void internalDistributeFrame(PlanarReflectionFrame? frame) {
    if (_frame == null && frame == null) return;
    _frame = frame;
    if (!isAttached) return;
    void visit(Node target) {
      for (final component in target.getComponents<MeshComponent>()) {
        for (final primitive in component.mesh.primitives) {
          final material = primitive.material;
          if (material.usesPlanarReflection) {
            material.planarReflectionFrame = frame;
          }
        }
      }
      for (final child in target.children) {
        visit(child);
      }
    }

    visit(node);
  }

  @override
  void onMount() {
    node.internalRenderScene?.addPlanarReflectorComponent(this);
  }

  @override
  void onUnmount() {
    internalDistributeFrame(null);
    if (isAttached) {
      node.internalRenderScene?.removePlanarReflectorComponent(this);
    }
  }
}
