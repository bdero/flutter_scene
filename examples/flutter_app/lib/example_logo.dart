import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

class ExampleLogo extends StatefulWidget {
  const ExampleLogo({super.key});

  @override
  ExampleLogoState createState() => ExampleLogoState();
}

class ExampleLogoState extends State<ExampleLogo> {
  Scene scene = Scene();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The scene hot reloads in place: loadScene patches a re-exported GLB into
    // this node automatically, and the logo holds only the root, so no reload
    // callback is needed.
    final value = await loadScene('assets_src/flutter_logo_baked.glb');
    // The ground's texture is a loose image cooked by the buildTextures hook
    // (see hook/build.dart), loaded by its source path.
    final groundTexture = await loadTexture('assets/ground_grid.png');
    if (!mounted) {
      return;
    }

    // The directional key light and shadows are driven by the shared settings
    // panel via ExampleSettings.applyTo.

    // A simple ground plane to catch the logo's shadow.
    final ground = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(8.0, 0.1, 8.0)),
        PhysicallyBasedMaterial()
          ..baseColorTexture = groundTexture
          ..metallicFactor = 0.0
          ..roughnessFactor = 0.9,
      ),
    );
    ground.localTransform = vm.Matrix4.translation(vm.Vector3(0.0, -1.0, 0.0));
    scene.add(ground);

    value.name = 'FlutterLogo';
    scene.add(value);
    debugPrint('Model loaded: ${value.name}');

    debugPrint('Scene loaded.');
    setState(() {
      loaded = true;
    });
  }

  @override
  void dispose() {
    // Optional: the scene is dropped with this State. `Node.fromAsset` caches
    // the imported model template (shared across clones), so its GPU resources
    // persist for the session regardless.
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t) * 5, 2, cos(t) * 5),
          target: vm.Vector3(0, 0, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}
