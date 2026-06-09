import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Demonstrates lazy-subtree streaming: a row of `LoadPolicy.lazy` tree
/// placeholders that realize empty, then load and unload their prefab content
/// on demand via [loadSubtree] / [unloadSubtree]. The "tree" prefab is loaded
/// from an in-memory document.
class ExampleFsceneStream extends StatefulWidget {
  const ExampleFsceneStream({super.key});

  @override
  State<ExampleFsceneStream> createState() => _ExampleFsceneStreamState();
}

class _ExampleFsceneStreamState extends State<ExampleFsceneStream> {
  final Scene scene = Scene();
  final SceneDocument _prefab = _treePrefab();
  final List<Node> _placeholders = [];
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final root = realizeScene(_hostScene());
    _collectPlaceholders(root);
    scene.add(root);
  }

  void _collectPlaceholders(Node node) {
    if (isLazySubtree(node)) _placeholders.add(node);
    for (final child in node.children) {
      _collectPlaceholders(child);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_loaded) {
      for (final placeholder in _placeholders) {
        unloadSubtree(placeholder);
      }
    } else {
      for (final placeholder in _placeholders) {
        await loadSubtree(placeholder, load: (_) async => _prefab);
      }
    }
    if (!mounted) return;
    setState(() {
      _loaded = !_loaded;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) {
              final t = elapsed.inMicroseconds / 1e6 * 0.25;
              return PerspectiveCamera(
                position: vm.Vector3(sin(t) * 11, 5, cos(t) * 11),
                target: vm.Vector3(0, 0.5, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              onPressed: _busy ? null : _toggle,
              child: Text(_loaded ? 'Unload subtrees' : 'Load subtrees'),
            ),
          ),
        ),
      ],
    );
  }
}

ComponentSpec _mesh(LocalId geometry, LocalId material) => ComponentSpec(
  'mesh',
  properties: {
    'geometry': ResourceRefValue(geometry),
    'material': ResourceRefValue(material),
  },
);

// A single-root "tree" prefab: a trunk with foliage on top.
SceneDocument _treePrefab() {
  final doc = SceneDocument();
  final trunkMaterial = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.4, 0.26, 0.13, 1.0),
        'roughness': const DoubleValue(0.8),
      },
    ),
  );
  final foliageMaterial = doc.addResource(
    MaterialResource(
      doc.newId(),
      type: 'physicallyBased',
      properties: {
        'baseColor': const ColorValue(0.22, 0.6, 0.27, 1.0),
        'roughness': const DoubleValue(0.7),
      },
    ),
  );
  final trunkGeometry = doc.addResource(
    GeometryResource(
      doc.newId(),
      procedural: CuboidGeometrySpec(extents: vm.Vector3(0.3, 1.2, 0.3)),
    ),
  );
  final foliageGeometry = doc.addResource(
    GeometryResource(doc.newId(), procedural: SphereGeometrySpec(radius: 0.75)),
  );
  final trunk = doc.createNode(
    name: 'trunk',
    root: true,
    components: [_mesh(trunkGeometry.id, trunkMaterial.id)],
  );
  final foliage = doc.createNode(
    name: 'foliage',
    transform: TrsTransform(translation: vm.Vector3(0, 1.2, 0)),
    components: [_mesh(foliageGeometry.id, foliageMaterial.id)],
  );
  trunk.children.add(foliage.id);
  return doc;
}

SceneDocument _hostScene() {
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
      properties: {'baseColor': const ColorValue(0.32, 0.38, 0.3, 1.0)},
    ),
  );
  doc.createNode(
    name: 'ground',
    root: true,
    transform: TrsTransform(translation: vm.Vector3(0, -0.6, 0)),
    components: [_mesh(groundGeometry.id, groundMaterial.id)],
  );

  // A row of lazy tree placeholders.
  for (var i = 0; i < 5; i++) {
    doc
        .createNode(
          name: 'slot$i',
          root: true,
          transform: TrsTransform(translation: vm.Vector3((i - 2) * 2.2, 0, 0)),
        )
        .instance = PrefabInstanceSpec(
      source: const AssetRef('tree'),
      load: LoadPolicy.lazy,
    );
  }
  return doc;
}
