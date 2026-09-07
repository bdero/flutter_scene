/// The tool state the rail and the viewport share.
///
/// The transform mode used to live inside the viewport, drawn as a bar
/// floating over the scene. It moved out for one reason: with several scene
/// views open, "which tool am I holding" is a property of the editor, not of a
/// view, and a tool that has to be re-picked per view is a tool that is wrong
/// half the time. The rail owns the question; the viewport reads the answer.
///
/// The capability flags travel the other way. Whether the selection can be
/// sculpted is something only the viewport knows -- it has the scene, the
/// selection and the terrain under the cursor -- so it publishes that, and the
/// rail uses it to disable a brush with a reason instead of arming one that
/// would do nothing.
library;

import 'package:flutter/foundation.dart';

import 'transform_gizmo.dart';

/// Which point rotation and scale act about with several nodes selected.
enum PivotMode {
  /// Each selected node rotates and scales about its own origin; positions
  /// never change under rotate/scale.
  individualOrigins,

  /// The whole selection rotates and scales about the median of the selected
  /// nodes' origins, where the gizmo also draws.
  medianPoint,
}

/// Which brush, if any, currently owns the primary mouse button.
///
/// One at a time: the terrain brush and the scatter brush both want the
/// primary button, so arming one disarms the other, and either disarms the
/// transform handles.
enum ViewportBrush { none, terrain, scatter }

/// What the gizmo does, where it does it, and what is armed.
class ViewportToolState extends ChangeNotifier {
  ViewportToolState({
    GizmoMode mode = GizmoMode.translate,
    TransformSpace space = TransformSpace.global,
    PivotMode pivot = PivotMode.medianPoint,
  }) : _mode = mode,
       _space = space,
       _pivot = pivot;

  GizmoMode _mode;
  TransformSpace _space;
  PivotMode _pivot;
  bool _snap = false;
  ViewportBrush _brush = ViewportBrush.none;
  bool _canSculpt = false;
  bool _canScatter = false;
  int _frameSignal = 0;

  GizmoMode get mode => _mode;
  set mode(GizmoMode value) {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
  }

  TransformSpace get space => _space;
  set space(TransformSpace value) {
    if (_space == value) return;
    _space = value;
    notifyListeners();
  }

  PivotMode get pivot => _pivot;
  set pivot(PivotMode value) {
    if (_pivot == value) return;
    _pivot = value;
    notifyListeners();
  }

  /// Whether a drag lands on the step rather than wherever it stopped.
  bool get snap => _snap;
  set snap(bool value) {
    if (_snap == value) return;
    _snap = value;
    notifyListeners();
  }

  /// The steps a snapped drag lands on: world units, degrees, and a scale
  /// factor. Deliberately plain numbers rather than settings for now -- a
  /// quarter unit and fifteen degrees are what people reach for.
  double translateStep = 0.25;
  double rotateStepDegrees = 15;
  double scaleStep = 0.1;

  ViewportBrush get brush => _brush;
  set brush(ViewportBrush value) {
    if (_brush == value) return;
    _brush = value;
    notifyListeners();
  }

  /// Whether the selection is terrain a brush could reach. Published by the
  /// viewport, read by the rail.
  bool get canSculpt => _canSculpt;

  /// Whether the selection carries a scatter layer to paint into.
  bool get canScatter => _canScatter;

  /// Called by the viewport each time what the brushes could reach changes.
  ///
  /// Also disarms a brush that has lost its target, so the primary button
  /// goes back to the handles rather than staying held by a brush with
  /// nothing under it.
  void publishBrushTargets({required bool sculpt, required bool scatter}) {
    if (_canSculpt == sculpt && _canScatter == scatter) return;
    _canSculpt = sculpt;
    _canScatter = scatter;
    if (!sculpt && _brush == ViewportBrush.terrain) {
      _brush = ViewportBrush.none;
    }
    if (!scatter && _brush == ViewportBrush.scatter) {
      _brush = ViewportBrush.none;
    }
    notifyListeners();
  }

  /// Bumped when something asks the viewport to frame the selection. The
  /// viewport watches the number rather than taking a callback, so any number
  /// of views can each answer for themselves.
  int get frameSignal => _frameSignal;
  void requestFrame() {
    _frameSignal++;
    notifyListeners();
  }

  /// Flips between the two frames, which is what the rail's toggle and the
  /// keyboard shortcut both do.
  void toggleSpace() => space = space == TransformSpace.global
      ? TransformSpace.local
      : TransformSpace.global;

  void togglePivot() => pivot = pivot == PivotMode.medianPoint
      ? PivotMode.individualOrigins
      : PivotMode.medianPoint;
}
