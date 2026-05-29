import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Renders a spinning cuboid through the full flutter_scene pipeline
/// (geometry, material, render graph, tonemap) on top of the WebGL2 shim.
/// The end-to-end Phase 5 integration test.
class SceneTab extends StatefulWidget {
  const SceneTab({super.key});

  @override
  State<SceneTab> createState() => _SceneTabState();
}

class _SceneTabState extends State<SceneTab>
    with SingleTickerProviderStateMixin {
  final Scene _scene = Scene();
  late final Ticker _ticker;
  double _elapsed = 0;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Geometry/material constructors touch baseShaderLibrary, so they must
    // run only after the shader bundle has finished loading (on web the
    // synchronous fallback throws).
    Scene.initializeStaticResources()
        .then((_) {
          if (!mounted) return;
          final material = PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.85, 0.30, 0.20, 1.0)
            ..metallicFactor = 0.1
            ..roughnessFactor = 0.45
            ..vertexColorWeight = 0.0;
          final mesh = Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material);
          _scene.add(Node(mesh: mesh));
          setState(() => _ready = true);
        })
        .catchError((Object e, StackTrace st) {
          if (mounted) setState(() => _error = '$e\n$st');
        });

    _ticker = createTicker((d) {
      setState(() => _elapsed = d.inMicroseconds / 1e6);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return CustomPaint(
      painter: _ScenePainter(_scene, _elapsed),
      child: const SizedBox.expand(),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.elapsed);
  final Scene scene;
  final double elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = PerspectiveCamera(
      position: vm.Vector3(sin(elapsed) * 5, 2, cos(elapsed) * 5),
      target: vm.Vector3(0, 0, 0),
    );
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) => true;
}
