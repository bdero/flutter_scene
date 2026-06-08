import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Builds a scene as an `.fscene` document in code, writes it to `.fscene`
/// text, reads it back, and realizes it into a live node graph. This
/// exercises the full round-trip: document model -> JSON -> live scene, with
/// procedural geometry, parameter materials, and a directional light.
class ExampleFscene extends StatefulWidget {
  const ExampleFscene({super.key});

  @override
  State<ExampleFscene> createState() => _ExampleFsceneState();
}

class _ExampleFsceneState extends State<ExampleFscene> {
  final Scene scene = Scene();

  @override
  void initState() {
    super.initState();
    final text = writeFscene(_buildDocument());
    scene.add(loadFsceneString(text));
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t) * 6, 3, cos(t) * 6),
          target: vm.Vector3(0, 0, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}

SceneDocument _buildDocument() {
  final doc = SceneDocument();

  // A sun, pitched down toward the scene.
  doc.createNode(
    name: 'sun',
    root: true,
    transform: TrsTransform(
      rotation: vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), -1.0),
    ),
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(3.0),
          'castsShadow': const BoolValue(true),
        },
      ),
    ],
  );

  final red = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.9, 0.2, 0.2, 1.0),
        'roughness': const DoubleValue(0.4),
      },
    ),
  );
  final blue = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.2, 0.4, 0.9, 1.0),
        'metallic': const DoubleValue(0.8),
        'roughness': const DoubleValue(0.3),
      },
    ),
  );

  final planeGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: PlaneGeometrySpec(width: 10, depth: 10),
    ),
  );
  doc.createNode(
    name: 'ground',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(0, -1, 0)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(planeGeometry.id),
          'material': ResourceRefValue(blue.id),
        },
      ),
    ],
  );

  final cubeGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: CuboidGeometrySpec(extents: vm.Vector3(1, 1, 1)),
    ),
  );
  for (var i = 0; i < 5; i++) {
    final angle = i / 5 * 2 * pi;
    doc.createNode(
      name: 'cube$i',
      root: true,
      transform: TrsTransform(
        translation: vm.Vector3(cos(angle) * 2.5, 0, sin(angle) * 2.5),
      ),
      components: [
        ComponentSpec(
          'mesh',
          properties: {
            'geometry': ResourceRefValue(cubeGeometry.id),
            'material': ResourceRefValue(i.isEven ? red.id : blue.id),
          },
        ),
      ],
    );
  }

  return doc;
}
