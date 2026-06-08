import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Demonstrates the prefab composer: one prefab document (a two-cube "robot")
/// instantiated several times in a row, each instance recoloring the body and
/// rotating the head through per-instance overrides. The host document is
/// composed (instances expanded, ids remapped, deltas applied) and then
/// realized.
class ExampleFscenePrefab extends StatefulWidget {
  const ExampleFscenePrefab({super.key});

  @override
  State<ExampleFscenePrefab> createState() => _ExampleFscenePrefabState();
}

class _ExampleFscenePrefabState extends State<ExampleFscenePrefab> {
  final Scene scene = Scene();

  @override
  void initState() {
    super.initState();
    final prefab = _robotPrefab();
    final host = _hostScene(prefab);
    final composed = composeScene(host, resolve: (_) => prefab);
    scene.add(realizeScene(composed));
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6 * 0.3;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t) * 12, 6, cos(t) * 12),
          target: vm.Vector3(0, 1, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}

// A single-root prefab: 'body' (a cube) with a smaller 'head' cube on top.
// Both share one grey material.
SceneDocument _robotPrefab() {
  final doc = SceneDocument();
  final material = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.7, 0.7, 0.7, 1.0),
        'roughness': const DoubleValue(0.5),
      },
    ),
  );
  final bodyGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: CuboidGeometrySpec(extents: vm.Vector3(1, 1.4, 1)),
    ),
  );
  final headGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: CuboidGeometrySpec(extents: vm.Vector3(0.7, 0.7, 0.7)),
    ),
  );
  final body = doc.createNode(
    name: 'body',
    root: true,
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(bodyGeometry.id),
          'material': ResourceRefValue(material.id),
        },
      ),
    ],
  );
  final head = doc.createNode(
    name: 'head',
    transform: TrsTransform(translation: vm.Vector3(0, 1.1, 0)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(headGeometry.id),
          'material': ResourceRefValue(material.id),
        },
      ),
    ],
  );
  body.children.add(head.id);
  return doc;
}

SceneDocument _hostScene(SceneDocument prefab) {
  // The host authors overrides against the prefab's own node ids.
  final bodyId = prefab.rootNodes.single.id;
  final headId = prefab.rootNodes.single.children.single;

  final doc = SceneDocument();
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
          'intensity': const DoubleValue(4.0),
          'castsShadow': const BoolValue(true),
        },
      ),
    ],
  );

  final groundGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: PlaneGeometrySpec(width: 16, depth: 8),
    ),
  );
  final groundMaterial = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {'baseColor': const ColorValue(0.3, 0.35, 0.4, 1.0)},
    ),
  );
  doc.createNode(
    name: 'ground',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(0, -0.7, 0)),
    components: [
      ComponentSpec(
        'mesh',
        properties: {
          'geometry': ResourceRefValue(groundGeometry.id),
          'material': ResourceRefValue(groundMaterial.id),
        },
      ),
    ],
  );

  const colors = [
    ColorValue(0.9, 0.3, 0.3, 1.0),
    ColorValue(0.9, 0.7, 0.2, 1.0),
    ColorValue(0.3, 0.8, 0.4, 1.0),
    ColorValue(0.3, 0.5, 0.9, 1.0),
    ColorValue(0.7, 0.4, 0.9, 1.0),
  ];
  for (var i = 0; i < colors.length; i++) {
    // A per-instance body material in this color.
    final bodyMaterial = doc.addResource(
      MaterialResource(
        doc.newId(),
        type: 'physicallyBased',
        properties: {
          'baseColor': colors[i],
          'roughness': const DoubleValue(0.4),
        },
      ),
    );
    doc
        .createNode(
          name: 'robot$i',
          root: true,
          transform: TrsTransform(
            translation: vm.Vector3((i - 2) * 2.6, 0.7, 0),
          ),
        )
        .instance = PrefabInstanceSpec(
      source: const AssetRef('robot.fscene'),
      overrides: [
        // Recolor the body, and tilt each head differently.
        PropertyOverride(
          target: bodyId,
          path: 'components.mesh.material',
          value: ResourceRefValue(bodyMaterial.id),
        ),
        PropertyOverride(
          target: headId,
          path: 'transform.trs.r',
          value: QuaternionValue(
            vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), (i - 2) * 0.4),
          ),
        ),
      ],
    );
  }
  return doc;
}
