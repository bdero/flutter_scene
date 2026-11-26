/// A live thumbnail of a material: a sphere lit by the default studio
/// environment, rendering the node's actual realized material so it reflects
/// edits (and compiled `.fmat` shaders) as they happen.
library;

import 'package:material_ui/material_ui.dart';
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

  /// Compiles the pipelines a lit material's preview draws, once per run, so
  /// the first preview does not stall the inspector.
  static Future<void> warmUp() => _warmUp ??= _warmUpPreview();
  static Future<void>? _warmUp;

  static Future<void> _warmUpPreview() async {
    await fs.Scene.initializeStaticResources();
    // A plain scene configures the lit variant as the preview's own does.
    final scene = fs.Scene();
    try {
      await scene.warmUp(
        [fs.RenderView(camera: _previewCamera())],
        sliceBudget: const Duration(milliseconds: 50),
        extraNodes: [
          fs.Node(
            mesh: fs.Mesh(_previewSphere(), fs.PhysicallyBasedMaterial()),
          ),
        ],
      );
    } finally {
      scene.dispose();
    }
  }

  // Framed slightly off-axis so curvature and highlights read on the sphere.
  static fs.PerspectiveCamera _previewCamera() => fs.PerspectiveCamera(
    position: vm.Vector3(0.55, 0.45, 1.9),
    target: vm.Vector3.zero(),
  );

  static fs.Geometry _previewSphere() =>
      fs.SphereGeometry(radius: 0.62, segments: 48, rings: 24);

  @override
  State<MaterialPreview> createState() => _MaterialPreviewState();
}

class _MaterialPreviewState extends State<MaterialPreview> {
  final fs.PerspectiveCamera _camera = MaterialPreview._previewCamera();
  fs.Geometry? _sphere;

  fs.Geometry? _ensureSphere() {
    if (_sphere != null) return _sphere;
    try {
      // Touches the base shader bundle, so this only succeeds once the scene's
      // static resources have loaded (always true by the time an inspector for
      // a realized node is shown).
      _sphere = MaterialPreview._previewSphere();
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
