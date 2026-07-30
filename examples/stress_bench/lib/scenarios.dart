import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// Shared per-run resources, constructed once after
/// [Scene.initializeStaticResources] completes.
class BenchResources {
  BenchResources()
    : geometry = CuboidGeometry(Vector3(1, 1, 1)),
      opaque = UnlitMaterial()..baseColorFactor = Vector4(0.8, 0.3, 0.2, 1.0),
      translucent = UnlitMaterial()
        ..baseColorFactor = Vector4(0.2, 0.5, 0.9, 0.5)
        ..alphaMode = AlphaMode.blend;

  final Geometry geometry;
  final Material opaque;
  final Material translucent;
}

/// One stress workload. The runner mounts [mount] into the scene, calls
/// [perFrame] before each measured frame, and removes [mount] afterward.
abstract class Scenario {
  Scenario(this.resources);

  final BenchResources resources;

  String get name;
  int get itemCount;

  final Node mount = Node(name: 'bench');

  /// Frames the whole field with roughly half of it inside the frustum,
  /// so frustum culling does real work.
  final Camera camera = PerspectiveCamera(
    position: Vector3(0, 60, -220),
    target: Vector3(0, 0, 60),
    fovFar: 400,
  );

  void build();

  void perFrame(int frame) {}
}

/// Populates [parent] with a 3-level tree ending in [leafCount] mesh
/// leaves laid out on an XZ grid, and returns the leaves.
List<Node> buildField(
  Node parent,
  BenchResources resources, {
  required int leafCount,
  Material? material,
  double spread = 320,
}) {
  final leaves = <Node>[];
  final mat = material ?? resources.opaque;
  final side = math.sqrt(leafCount).ceil();
  final spacing = spread / side;
  const groupSize = 256;
  Node? group;
  for (var i = 0; i < leafCount; i++) {
    if (i % groupSize == 0) {
      group = Node(name: 'group${i ~/ groupSize}');
      parent.add(group);
    }
    final x = (i % side - side / 2) * spacing;
    final z = (i ~/ side - side / 2) * spacing;
    final y = math.sin(i * 0.37) * 8;
    final leaf = Node(
      name: 'leaf$i',
      localTransform: Matrix4.translation(Vector3(x, y, z)),
      mesh: Mesh(resources.geometry, mat),
    );
    group!.add(leaf);
    leaves.add(leaf);
  }
  return leaves;
}

/// Rotates [node] in place around Y without allocating.
void spinNode(Node node, double angle) {
  final t = node.localTransform;
  final tx = t.storage[12], ty = t.storage[13], tz = t.storage[14];
  t.setIdentity();
  t.rotateY(angle);
  t.setTranslationRaw(tx, ty, tz);
  node.markTransformDirty();
}

/// Fully static field. Isolates the per-item pre-pass refresh floor (walk,
/// transform copy, bounds recompute) with zero movers.
class StaticField extends Scenario {
  StaticField(super.resources, {this.leafCount = 10240});

  final int leafCount;

  @override
  String get name => 'static_${leafCount ~/ 1024}k';

  @override
  int get itemCount => leafCount;

  @override
  void build() => buildField(mount, resources, leafCount: leafCount);
}

/// A fraction of the field rotates each frame. Stresses dirty propagation,
/// world transform recompute, bounds refresh, and BVH refit.
class MoversField extends Scenario {
  MoversField(
    super.resources, {
    this.leafCount = 10240,
    this.moverFraction = 0.1,
  });

  final int leafCount;
  final double moverFraction;
  late final List<Node> _movers;

  @override
  String get name =>
      'movers_${(moverFraction * 100).round()}pct_${leafCount ~/ 1024}k';

  @override
  int get itemCount => leafCount;

  @override
  void build() {
    final leaves = buildField(mount, resources, leafCount: leafCount);
    final step = (1 / moverFraction).round();
    _movers = [for (var i = 0; i < leaves.length; i += step) leaves[i]];
  }

  @override
  void perFrame(int frame) {
    final angle = frame * 0.02;
    for (final mover in _movers) {
      spinNode(mover, angle);
    }
  }
}

/// Translucent field. Every visible item becomes a depth-sorted record, so
/// this stresses per-frame record allocation and the back-to-front sort.
class TranslucentField extends Scenario {
  TranslucentField(super.resources, {this.leafCount = 4096});

  final int leafCount;

  @override
  String get name => 'translucent_${leafCount ~/ 1024}k';

  @override
  int get itemCount => leafCount;

  @override
  void build() => buildField(
    mount,
    resources,
    leafCount: leafCount,
    material: resources.translucent,
  );
}

/// Static field plus point lights. Stresses the per-frame light scatter
/// (BVH queries per light) and per-item light list assembly.
class LitField extends Scenario {
  LitField(super.resources, {this.leafCount = 10240, this.lightCount = 256});

  final int leafCount;
  final int lightCount;

  @override
  String get name => 'lights_${lightCount}_${leafCount ~/ 1024}k';

  @override
  int get itemCount => leafCount;

  @override
  void build() {
    buildField(mount, resources, leafCount: leafCount);
    final side = math.sqrt(lightCount).ceil();
    const spread = 320.0;
    final spacing = spread / side;
    for (var i = 0; i < lightCount; i++) {
      final x = (i % side - side / 2) * spacing;
      final z = (i ~/ side - side / 2) * spacing;
      final light = Node(
        name: 'light$i',
        localTransform: Matrix4.translation(Vector3(x, 12, z)),
      );
      light.addComponent(
        PointLightComponent(PointLight(intensity: 5, range: 25)),
      );
      mount.add(light);
    }
  }
}

/// One item with a large instance set. Stresses the per-frame instance
/// transform packing and the instanced encode path.
class InstancedField extends Scenario {
  InstancedField(super.resources, {this.instanceCount = 50000});

  final int instanceCount;

  @override
  String get name => 'instanced_${instanceCount ~/ 1000}k';

  @override
  int get itemCount => 1;

  @override
  void build() {
    final instanced = InstancedMesh(
      geometry: resources.geometry,
      material: resources.opaque,
    );
    final side = math.pow(instanceCount, 1 / 3).ceil();
    const spread = 200.0;
    final spacing = spread / side;
    final transform = Matrix4.identity();
    for (var i = 0; i < instanceCount; i++) {
      final x = (i % side - side / 2) * spacing;
      final y = ((i ~/ side) % side - side / 2) * spacing * 0.25;
      final z = (i ~/ (side * side) - side / 2) * spacing;
      transform.setTranslationRaw(x, y, z);
      instanced.addInstance(transform);
    }
    final node = Node(name: 'instanced');
    node.addComponent(InstancedMeshComponent(instanced));
    mount.add(node);
  }
}

/// Adds and removes a batch of nodes every frame on top of a static base.
/// Stresses mount/unmount, render item registration, and BVH rebuild.
class ChurnField extends Scenario {
  ChurnField(
    super.resources, {
    this.baseCount = 10240,
    this.churnPerFrame = 512,
  });

  final int baseCount;
  final int churnPerFrame;
  final Node _churnParent = Node(name: 'churn');
  final List<Node> _live = [];
  var _serial = 0;

  @override
  String get name => 'churn_${churnPerFrame}_${baseCount ~/ 1024}k';

  @override
  int get itemCount => baseCount + churnPerFrame;

  @override
  void build() {
    buildField(mount, resources, leafCount: baseCount);
    mount.add(_churnParent);
  }

  @override
  void perFrame(int frame) {
    while (_live.length > churnPerFrame) {
      _churnParent.remove(_live.removeAt(0));
    }
    final rng = math.Random(frame);
    for (var i = 0; i < churnPerFrame; i++) {
      final leaf = Node(
        name: 'churn${_serial++}',
        localTransform: Matrix4.translation(
          Vector3(
            rng.nextDouble() * 320 - 160,
            rng.nextDouble() * 16 - 8,
            rng.nextDouble() * 320 - 160,
          ),
        ),
        mesh: Mesh(resources.geometry, resources.opaque),
      );
      _churnParent.add(leaf);
      _live.add(leaf);
    }
  }
}
