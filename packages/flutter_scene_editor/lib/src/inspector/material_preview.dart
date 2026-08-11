/// A live thumbnail of a material: a sphere lit by the default studio
/// environment, rendering the node's actual realized material so it reflects
/// edits (and compiled `.fmat` shaders) as they happen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;
// ignore: implementation_imports
import 'package:scene/scene.dart' show LocalId;

import '../controller/editor_controller.dart';

class MaterialPreview extends StatefulWidget {
  const MaterialPreview({
    super.key,
    required this.controller,
    required this.nodeId,
  });

  final EditorController controller;
  final LocalId nodeId;

  @override
  State<MaterialPreview> createState() => _MaterialPreviewState();
}

class _MaterialPreviewState extends State<MaterialPreview> {
  // Framed slightly off-axis so curvature and highlights read on the sphere.
  final fs.PerspectiveCamera _camera = fs.PerspectiveCamera(
    position: vm.Vector3(0.55, 0.45, 1.9),
    target: vm.Vector3.zero(),
  );
  fs.Geometry? _sphere;

  fs.Geometry? _ensureSphere() {
    if (_sphere != null) return _sphere;
    try {
      // Touches the base shader bundle, so this only succeeds once the scene's
      // static resources have loaded (always true by the time an inspector for
      // a realized node is shown).
      _sphere = fs.SphereGeometry(radius: 0.62, segments: 48, rings: 24);
    } catch (_) {
      return null;
    }
    return _sphere;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final material = widget.controller.liveMeshMaterial(widget.nodeId);
    final sphere = _ensureSphere();
    if (material == null || sphere == null) {
      return Center(
        child: Icon(Icons.blur_on, size: 26, color: scheme.onSurfaceVariant),
      );
    }
    // The declarative view owns its own scene (disposed with the widget) and
    // repaints every frame, so in-place parameter edits show live. The default
    // environment is the studio IBL.
    return fs.SceneView.declarative(
      camera: _camera,
      children: [fs.SceneMesh(geometry: sphere, material: material)],
    );
  }
}
