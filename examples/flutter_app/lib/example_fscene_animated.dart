import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart'
    show importGlbToFscenebBytes;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Imports a skinned, animated `.glb` at runtime through the glTF -> `.fsceneb`
/// importer, then realizes it (binding the skin and parsing the animations)
/// and plays a looping clip. Exercises the whole skinned/animated path through
/// the `.fscene` pipeline.
class ExampleFsceneAnimated extends StatefulWidget {
  const ExampleFsceneAnimated({super.key});

  @override
  State<ExampleFsceneAnimated> createState() => _ExampleFsceneAnimatedState();
}

class _ExampleFsceneAnimatedState extends State<ExampleFsceneAnimated> {
  final Scene scene = Scene();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final glb = await rootBundle.load('assets_src/dash.glb');
    final bytes = glb.buffer.asUint8List(glb.offsetInBytes, glb.lengthInBytes);
    // The glTF import (image decode + geometry packing) is heavy CPU work, so
    // run it on a background isolate to keep the UI responsive while loading.
    final container = await compute(importGlbToFscenebBytes, bytes);
    if (!mounted) return;
    final dash = (await loadFscenebBytesAsync(container))..name = 'Dash';
    if (!mounted) return;

    // Play a clearly-moving clip, looping (falls back to the first animation).
    final animation =
        dash.findAnimationByName('Walk') ??
        (dash.parsedAnimations.isNotEmpty ? dash.parsedAnimations.first : null);
    if (animation != null) {
      dash.createAnimationClip(animation)
        ..loop = true
        ..play();
    }

    scene.add(dash);
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
        final rotation = elapsed.inMicroseconds / 1e6 * 0.5;
        const distance = 6.0;
        return PerspectiveCamera(
          position: vm.Vector3(
            sin(rotation) * distance,
            2,
            cos(rotation) * distance,
          ),
          target: vm.Vector3(0, 1.5, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}
