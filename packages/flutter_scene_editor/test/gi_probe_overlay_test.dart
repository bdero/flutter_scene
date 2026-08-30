// Covers the probe-overlay culling: distance bounds the draw, the limit is a
// backstop that keeps the nearest probes, and a degenerate grid draws nothing.

import 'package:flutter_scene/scene.dart' show IrradianceProbeGrid;
import 'package:flutter_scene_editor/src/viewport/component_gizmos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

IrradianceProbeGrid _grid({Vector3? counts, Vector3? spacing}) =>
    IrradianceProbeGrid(
      origin: Vector3.zero(),
      spacing: spacing ?? Vector3.all(1),
      counts: counts ?? Vector3.all(5),
    );

void main() {
  test('probes past the draw distance are dropped', () {
    final grid = _grid();
    final all = probesWithinDistance(grid, Vector3.zero(), 100, limit: 10000);
    expect(all, hasLength(grid.probeCount));

    // A 2-unit radius around the origin corner keeps only the probes whose
    // lattice offset is within that sphere.
    final near = probesWithinDistance(grid, Vector3.zero(), 2, limit: 10000);
    expect(near.length, lessThan(all.length));
    for (final probe in near) {
      expect(probe.length, lessThanOrEqualTo(2.0 + 1e-6));
    }
  });

  test('the limit keeps the nearest probes', () {
    final grid = _grid(counts: Vector3.all(8));
    final eye = Vector3.zero();
    final limited = probesWithinDistance(grid, eye, 1000, limit: 5);
    expect(limited, hasLength(5));
    // Nearest-first: every kept probe is at least as close as every dropped
    // one, so a truncated draw shows what the viewer is looking at.
    final kept = limited.map((p) => p.distanceTo(eye)).toList();
    final all = probesWithinDistance(
      grid,
      eye,
      1000,
      limit: 100000,
    ).map((p) => p.distanceTo(eye)).toList()..sort();
    expect(kept..sort(), all.take(5).toList());
  });

  test('a degenerate grid or zero distance draws nothing', () {
    expect(
      probesWithinDistance(_grid(), Vector3.zero(), 0, limit: 100),
      isEmpty,
    );
    expect(
      probesWithinDistance(
        _grid(counts: Vector3.zero()),
        Vector3.zero(),
        50,
        limit: 100,
      ),
      isEmpty,
    );
  });
}
