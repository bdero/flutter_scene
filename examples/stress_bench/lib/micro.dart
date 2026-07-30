import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:vector_math/vector_math.dart';

/// Non-renderable stand-ins so [RenderItem]s can be built in pure Dart,
/// same pattern as the engine's bvh_test.
class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

List<RenderItem> _makeItems(int count) {
  final rng = math.Random(7);
  final geometry = _StubGeometry();
  final material = _StubMaterial();
  return List.generate(count, (i) {
    final center = Vector3(
      rng.nextDouble() * 200 - 100,
      rng.nextDouble() * 40 - 20,
      rng.nextDouble() * 200 - 100,
    );
    return RenderItem(geometry: geometry, material: material)
      ..worldBounds = Aabb3.minMax(
        center - Vector3.all(0.5),
        center + Vector3.all(0.5),
      );
  });
}

/// Times [body] over [reps] repetitions after [warmup] discarded ones and
/// returns milliseconds per repetition.
double _time(int reps, void Function() body, {int warmup = 3}) {
  for (var i = 0; i < warmup; i++) {
    body();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < reps; i++) {
    body();
  }
  sw.stop();
  return sw.elapsedMicroseconds / reps / 1000.0;
}

/// Runs the direct hot-loop benchmarks and returns name to ms/op.
Map<String, double> runMicroBenchmarks() {
  final results = <String, double>{};
  const n = 10240;
  final items = _makeItems(n);

  results['bvh_build_10k'] = _time(20, () => Bvh.build(items));

  final bvh = Bvh.build(items);
  final drift = Vector3(0.01, 0.0, 0.01);
  results['bvh_refit_10k'] = _time(200, () {
    for (final item in items) {
      item.worldBounds!
        ..min.add(drift)
        ..max.add(drift);
    }
    bvh.refit();
  });

  // A frustum covering roughly half of the item field.
  final frustum = Frustum.matrix(
    makeOrthographicMatrix(-100, 10, -100, 100, -30, 30),
  );
  var visited = 0;
  results['bvh_query_10k'] = _time(500, () {
    visited = 0;
    bvh.query(frustum, (_) => visited++);
  });
  results['bvh_query_10k_visited'] = visited.toDouble();

  const instanceCount = 50000;
  final rng = math.Random(11);
  final instances = List.generate(
    instanceCount,
    (_) => Matrix4.translation(
      Vector3(rng.nextDouble() * 100, rng.nextDouble() * 100, 0),
    ),
  );
  final nodeTransform = Matrix4.identity();
  results['pack_instances_50k'] = _time(
    30,
    () => packInstanceTransforms(nodeTransform, instances),
  );

  // A deep parent chain. Dirtying the root and reading the leaf walks the
  // dirty flag down and the recompute up the full depth.
  const depth = 1000;
  final chainRoot = Node(name: 'chain0');
  var current = chainRoot;
  for (var i = 1; i < depth; i++) {
    final next = Node(
      name: 'chain$i',
      localTransform: Matrix4.translation(Vector3(0.01, 0.01, 0)),
    );
    current.add(next);
    current = next;
  }
  final leaf = current;
  var spin = 0.0;
  results['transform_chain_1k'] = _time(2000, () {
    spin += 0.001;
    chainRoot.localTransform.setRotationZ(spin);
    chainRoot.markTransformDirty();
    leaf.globalTransform;
  });

  return results;
}
