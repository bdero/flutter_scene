import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart'
    show importGlbToFscenebBytes;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Imports a real `.glb` at runtime through the glTF -> `.fsceneb` importer,
/// then realizes and renders it. The geometry is packed exactly as the
/// `.model` path packs it, but it travels through the `.fscene` pipeline:
/// glTF -> SceneDocument -> binary container -> live node graph.
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
    final glb = await rootBundle.load('assets_src/fcar.glb');
    final container = importGlbToFscenebBytes(
      glb.buffer.asUint8List(glb.offsetInBytes, glb.lengthInBytes),
    );
    final car = loadFscenebBytes(container)..name = 'Car';
    final environment = await EnvironmentMap.fromAssets(
      radianceImagePath: 'assets/little_paris_eiffel_tower.png',
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
