# Flutter Scene example

A minimal scene: load a glTF model and display it with a `PerspectiveCamera`
through `SceneView`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ModelView extends StatefulWidget {
  const ModelView({super.key});
  @override
  State<ModelView> createState() => _ModelViewState();
}

class _ModelViewState extends State<ModelView> {
  final Scene scene = Scene();
  bool ready = false;

  @override
  void initState() {
    super.initState();
    // Static resources (shader bundle, BRDF LUT) load asynchronously.
    Scene.initializeStaticResources().then((_) async {
      final model = await Node.fromGlbAsset('assets/model.glb');
      scene.add(model);
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Center(child: CircularProgressIndicator());
    // SceneView renders the scene and drives its per-frame loop; no
    // hand-written CustomPainter is needed.
    return SceneView(
      scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 2, 5),
        target: vm.Vector3(0, 0, 0),
      ),
    );
  }
}
```

For an animated camera, pass `cameraBuilder: (elapsed) => ...` instead of a
fixed `camera`.

To preprocess models offline and hot reload them (and `.fmat` materials) in
place, load by source path with `loadModel` / `loadFmatMaterial` and a
DataAssets build hook. For a full runnable app exercising materials,
skinning/animation, custom shaders, and hot reload, see
[`examples/flutter_app`](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app).
```
