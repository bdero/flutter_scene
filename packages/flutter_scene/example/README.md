# Flutter Scene example

A minimal scene: load a glTF model and draw it with a `PerspectiveCamera`
inside a `CustomPainter`.

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
      final model = await Node.fromAsset('assets/model.glb');
      scene.add(model);
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Center(child: CircularProgressIndicator());
    return CustomPaint(painter: _ScenePainter(scene), child: const SizedBox.expand());
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene);
  final Scene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = PerspectiveCamera(
      position: vm.Vector3(0, 2, 5),
      target: vm.Vector3(0, 0, 0),
    );
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true;
}
```

For a full, runnable app exercising materials, skinning/animation, custom
shaders, and more, see
[`examples/flutter_app`](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app).
