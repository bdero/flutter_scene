// Covers the steady-state render stats: the frame/view/pass scopes, counter
// attribution through the shared accumulator, and the bounded history. No
// GPU work; passes bump the accumulator the way the draw funnel does.

import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_stats.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingWriter implements TransientWriter {
  @override
  gpu.BufferView emplace(ByteData bytes) =>
      throw UnimplementedError('not used by these passes');
}

class _FakePass extends RenderGraphPass {
  _FakePass(this.name, this.body);

  @override
  final String name;
  final void Function() body;

  @override
  void execute(RenderGraphContext context) => body();
}

/// Draws once at every pass end, the way a capture's thumbnail copy does.
class _CopyingObserver implements RenderGraphObserver {
  @override
  void onPassBegin(RenderGraphPass pass, int indexInGraph) {}
  @override
  void onPassEnd(RenderGraphPass pass, int elapsedMicros) => _draw();
  @override
  void onBlackboardRead(Object key, Object? value) {}
  @override
  void onBlackboardWrite(Object key, Object? value) {}
  @override
  void onTextureAcquired(
    TransientTextureDescriptor descriptor,
    gpu.Texture texture,
  ) {}
}

void _draw({int vertices = 3, int instances = 1}) {
  activeRenderCounters.draws++;
  activeRenderCounters.instances += instances;
  activeRenderCounters.vertices += vertices * instances;
}

void main() {
  test('pass counters are deltas of the shared accumulator', () {
    final stats = RenderStats();
    stats.beginFrame();
    final view = stats.beginView(
      viewIndex: 0,
      width: 320,
      height: 200,
      offscreen: false,
    )!;
    final graph = RenderGraph()
      ..addPass(
        _FakePass('shadow', () {
          _draw(vertices: 30);
          _draw(vertices: 30);
        }),
      )
      ..addPass(_FakePass('empty', () {}))
      ..addPass(
        _FakePass('scene', () {
          _draw(vertices: 12, instances: 5);
          activeRenderCounters.pipelineBinds += 2;
          activeRenderCounters.culled += 4;
        }),
      );
    graph.execute(
      transientsBuffer: _ThrowingWriter(),
      texturePool: TransientTexturePool(),
      stats: view,
    );
    // Work outside any view still lands in the frame totals.
    _draw(vertices: 6);
    stats.endFrame(pipelineCacheSize: 7);

    final frame = stats.latest!;
    expect(frame.frameIndex, 0);
    expect(frame.pipelineCacheSize, 7);
    expect(frame.views, hasLength(1));
    expect(view.passes.map((p) => p.name), ['shadow', 'empty', 'scene']);
    expect(view.passes[0].counters.draws, 2);
    expect(view.passes[0].counters.vertices, 60);
    expect(view.passes[1].counters.draws, 0);
    expect(view.passes[2].counters.draws, 1);
    expect(view.passes[2].counters.instances, 5);
    expect(view.passes[2].counters.vertices, 60);
    expect(view.passes[2].counters.pipelineBinds, 2);
    expect(view.passes[2].counters.culled, 4);
    for (final pass in view.passes) {
      expect(pass.cpuMicros, greaterThanOrEqualTo(0));
      expect(pass.gpuMicros, isNull);
    }
    expect(frame.counters.draws, 4);
    expect(frame.counters.vertices, 126);
    expect(frame.counters.instances, 8);
    expect(frame.cpuMicros, greaterThanOrEqualTo(0));
    expect(stats.activeFrame, isNull);
    expect(stats.frameCount, 1);
  });

  test('observer work at the pass boundary is not charged to the pass', () {
    final stats = RenderStats();
    stats.beginFrame();
    final view = stats.beginView(
      viewIndex: 0,
      width: 1,
      height: 1,
      offscreen: false,
    )!;
    final graph = RenderGraph()..addPass(_FakePass('scene', () => _draw()));
    graph.execute(
      transientsBuffer: _ThrowingWriter(),
      texturePool: TransientTexturePool(),
      observer: _CopyingObserver(),
      stats: view,
    );
    stats.endFrame(pipelineCacheSize: 0);
    expect(view.passes.single.counters.draws, 1);
    expect(stats.latest!.counters.draws, 2);
  });

  test('history is bounded and latest is a distinct record per frame', () {
    final stats = RenderStats(historyLength: 2);
    final frames = <RenderFrameStats>[];
    for (var i = 0; i < 4; i++) {
      stats.beginFrame();
      _draw();
      stats.endFrame(pipelineCacheSize: 0);
      frames.add(stats.latest!);
    }
    expect(frames.map((f) => f.frameIndex), [0, 1, 2, 3]);
    expect(stats.history.map((f) => f.frameIndex), [2, 3]);
    expect(frames[0].counters.draws, 1);
    expect(stats.frameCount, 4);

    stats.historyLength = 0;
    stats.beginFrame();
    stats.endFrame(pipelineCacheSize: 0);
    expect(stats.history, isEmpty);
    expect(stats.latest!.frameIndex, 4);
  });

  test('a view outside a frame records nothing', () {
    final stats = RenderStats();
    expect(
      stats.beginView(viewIndex: 0, width: 1, height: 1, offscreen: false),
      isNull,
    );
    stats.endFrame(pipelineCacheSize: 0);
    expect(stats.latest, isNull);
  });

  test('stats serialize', () {
    final stats = RenderStats();
    stats.beginFrame();
    final view = stats.beginView(
      viewIndex: 0,
      width: 8,
      height: 8,
      offscreen: false,
    )!;
    view.passes.add(RenderPassStats(name: 'p', indexInGraph: 0));
    stats.endFrame(pipelineCacheSize: 1);
    final json = stats.latest!.toJson();
    expect(json['views'], isList);
    final passes = (json['views'] as List).first['passes'] as List;
    expect(passes.first['name'], 'p');
    expect((json['counters'] as Map)['draws'], 0);
  });
}
