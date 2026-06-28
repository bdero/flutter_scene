import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/render/lod.dart';

/// A [MeshComponent] that draws one of several level-of-detail variants of an
/// object, chosen each frame from how large the object appears on screen.
///
/// Supply [LodLevel]s highest detail first, with strictly descending
/// [LodLevel.screenSize] thresholds (a fraction of the viewport height). The
/// engine picks the highest-detail level whose threshold the object's
/// projected size still meets, and draws nothing once the size falls below
/// the smallest threshold (the cull floor; set the last level's threshold to
/// `0` to never cull). Selection is per view, so the same object can pick
/// different levels in a split-screen frame.
///
/// [lodBias] scales the projected size before selection (above `1` keeps
/// detail at a greater distance), and [hysteresis] is a dead-band around each
/// threshold so an object hovering on a boundary does not flip-flop.
///
/// Because selection is screen-size based it is field-of-view aware and
/// resolution independent. The highest-detail level's bounds are used for
/// frustum culling, so culling stays conservative.
///
/// Current limitations:
/// - The shadow and depth-prepass passes always draw the highest-detail
///   level and ignore the LOD cull, so a tiny object culled in the color
///   pass can still cast a shadow or write depth (a per-pass LOD bias is
///   future work).
/// - Selection memory (for the [hysteresis] dead-band) is shared across
///   views, so a multi-view frame can see one view's last choice bias
///   another's.
/// - Hardware-instanced draws are not supported here; a [LodComponent]
///   draws a single mesh, so it picks one level for the whole node.
/// - A non-perspective camera disables the metric and draws the
///   highest-detail level.
///
/// ```dart
/// node.addComponent(LodComponent([
///   LodLevel(geometry: high, material: mat, screenSize: 0.4),
///   LodLevel(geometry: mid, material: mat, screenSize: 0.15),
///   LodLevel(geometry: low, material: mat, screenSize: 0.04),
/// ]));
/// ```
/// {@category Scene graph}
class LodComponent extends MeshComponent {
  /// Creates an LOD component over [levels] (highest detail first).
  LodComponent(
    List<LodLevel> levels, {
    double lodBias = 1.0,
    double hysteresis = 0.1,
  }) : _selection = LodSelection(
         levels,
         lodBias: lodBias,
         hysteresis: hysteresis,
       ),
       super(Mesh(levels.first.geometry, levels.first.material));

  final LodSelection _selection;

  @override
  void onMount() {
    super.onMount();
    // Tag the item the base class just registered so the encoder selects a
    // level per view instead of drawing the highest-detail fallback.
    for (final item in renderItems) {
      item.lod = _selection;
    }
  }
}
