import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Loads a `.fsceneb` scene by source path through [loadScene]. The build hook
/// (`buildScenes`) imported `assets_src/fcar.glb` into a `.fsceneb` DataAsset;
/// this resolves and realizes it by source path.
class ExampleFsceneImport extends StatefulWidget {
  const ExampleFsceneImport({super.key});

  @override
  State<ExampleFsceneImport> createState() => _ExampleFsceneImportState();
}

class _ExampleFsceneImportState extends State<ExampleFsceneImport> {
  final Scene scene = Scene();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final car = (await loadScene('assets_src/fcar.glb'))..name = 'Car';
    final environment = await EnvironmentMap.fromEquirectImageAsset(
      assetPath: 'assets/little_paris_eiffel_tower.png',
    );
    if (!mounted) return;
    scene.add(car);
    scene.environment = environment;
    scene.exposure = 2.5;
    setState(() => loaded = true);
  }

  @override
  void dispose() {
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
        final rotation = elapsed.inMicroseconds / 1e6 * 0.2;
        return PerspectiveCamera(
          position: vm.Vector3(sin(rotation) * 5, 2, cos(rotation) * 5) * 2,
          target: vm.Vector3(0, 0, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}
