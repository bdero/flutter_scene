/// The profiler's arithmetic: what it calls late, and what it says a scene
/// weighs.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_scene_editor/src/panels/profiler_panel.dart';

FrameTiming _frame({required int buildUs, required int rasterUs}) =>
    FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: buildUs,
      rasterStart: buildUs,
      rasterFinish: buildUs + rasterUs,
      rasterFinishWallTime: buildUs + rasterUs,
    );

void main() {
  test('a frame is late when build and raster together miss the budget', () {
    final timings = FrameTimings()
      // 8 + 6 = 14ms, comfortable.
      ..add(_frame(buildUs: 8000, rasterUs: 6000))
      // 9 + 9 = 18ms, over 16.67.
      ..add(_frame(buildUs: 9000, rasterUs: 9000));

    expect(timings.totals, [14000, 18000]);
    expect(timings.lastTotal, 18000);
    expect(timings.worstTotal, 18000);
    expect(timings.meanTotal, 16000);
    expect(
      timings.lateFrames,
      1,
      reason: 'the frame that missed is counted, the one that did not is not',
    );
  });

  test('the window forgets frames older than itself', () {
    final timings = FrameTimings(window: 3);
    for (var i = 1; i <= 5; i++) {
      timings.add(_frame(buildUs: i * 1000, rasterUs: 0));
    }

    // A profiler that keeps every frame of a long session is a memory leak
    // with a graph on it.
    expect(timings.totals, [3000, 4000, 5000]);
  });

  test('an empty window reports nothing rather than dividing by zero', () {
    final timings = FrameTimings();

    expect(timings.isEmpty, isTrue);
    expect(timings.meanTotal, 0);
    expect(timings.worstTotal, 0);
    expect(timings.lateFrames, 0);
  });

  test('a scene with no realized root weighs nothing', () {
    final weight = SceneWeight.of(null);

    expect(weight.nodes, 0);
    expect(weight.triangles, 0);
    expect(weight.primitives, 0);
  });
}
