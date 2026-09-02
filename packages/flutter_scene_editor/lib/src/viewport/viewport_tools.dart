/// The tool state the rail and the viewport share.
///
/// The transform mode used to live inside the viewport, drawn as a bar
/// floating over the scene. It moved out for one reason: with several scene
/// views open, "which tool am I holding" is a property of the editor, not of a
/// view, and a tool that has to be re-picked per view is a tool that is wrong
/// half the time. The rail owns the question; the viewport reads the answer.
library;

import 'package:flutter/foundation.dart';

import 'transform_gizmo.dart';

/// Which handle the gizmo shows, and what frame it works in.
class ViewportToolState extends ChangeNotifier {
  ViewportToolState({
    GizmoMode mode = GizmoMode.translate,
    TransformSpace space = TransformSpace.global,
  }) : _mode = mode,
       _space = space;

  GizmoMode _mode;
  TransformSpace _space;

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

  /// Flips between the two frames, which is what the rail's toggle and the
  /// keyboard shortcut both do.
  void toggleSpace() => space = space == TransformSpace.global
      ? TransformSpace.local
      : TransformSpace.global;
}
