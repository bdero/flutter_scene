// Covers the render graph observer: pass boundaries with CPU times,
// blackboard read/write attribution, and the capturer's metadata-only
// recording (no GPU work is involved without image capture).

import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_graph_capture.dart';
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
  final void Function(RenderGraphContext context) body;

  @override
  void execute(RenderGraphContext context) => body(context);
}

void main() {
  test('observer sees pass boundaries and attributed blackboard traffic', () {
    final graph = RenderGraph()
      ..addPass(
        _FakePass('producer', (context) {
          context.blackboard.set('shadow_uniform', ByteData(64));
          context.blackboard.set('meta', 'value');
        }),
      )
      ..addPass(
        _FakePass('consumer', (context) {
          context.blackboard.get<ByteData>('shadow_uniform');
          context.blackboard.get<ByteData>('absent');
          context.blackboard.require<String>('meta');
        }),
      );

    final capturer = RenderGraphCapturer(
      request: const RenderGraphCaptureRequest(captureImages: false),
    );
    graph.execute(
      transientsBuffer: _ThrowingWriter(),
      texturePool: TransientTexturePool(),
      observer: capturer,
    );
    final result = capturer.finish(pixelWidth: 640, pixelHeight: 480);

    expect(result.passes.map((p) => p.name), ['producer', 'consumer']);
    expect(result.passes[0].writes, ['shadow_uniform', 'meta']);
    expect(result.passes[0].reads, isEmpty);
    // Absent keys read as null and are not recorded as edges.
    expect(result.passes[1].reads, ['shadow_uniform', 'meta']);
    expect(result.passes[1].writes, isEmpty);
    for (final pass in result.passes) {
      expect(pass.cpuMicros, greaterThanOrEqualTo(0));
    }

    // The ByteData write is recorded as a non-texture resource.
    final data = result.resources.singleWhere((r) => r.key == 'shadow_uniform');
    expect(data.isTexture, isFalse);
    expect(data.byteLength, 64);
    expect(data.passIndex, 0);
    expect(result.pixelWidth, 640);
  });

  test('resourceAt resolves the latest write before a pass', () {
    final graph = RenderGraph()
      ..addPass(
        _FakePass('a', (context) {
          context.blackboard.set('k', ByteData(1));
        }),
      )
      ..addPass(
        _FakePass('b', (context) {
          context.blackboard.set('k', ByteData(2));
        }),
      );
    final capturer = RenderGraphCapturer(
      request: const RenderGraphCaptureRequest(captureImages: false),
    );
    graph.execute(
      transientsBuffer: _ThrowingWriter(),
      texturePool: TransientTexturePool(),
      observer: capturer,
    );
    final result = capturer.finish(pixelWidth: 1, pixelHeight: 1);
    expect(result.resourceAt('k', 0)!.byteLength, 1);
    expect(result.resourceAt('k', 1)!.byteLength, 2);
    expect(result.resourceAt('missing', 1), isNull);
  });

  test('steady-state execute has no observer plumbing', () {
    var ran = false;
    final graph = RenderGraph()..addPass(_FakePass('only', (_) => ran = true));
    graph.execute(
      transientsBuffer: _ThrowingWriter(),
      texturePool: TransientTexturePool(),
    );
    expect(ran, isTrue);
  });
}
