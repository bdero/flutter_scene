// Covers per-draw capture records: the recorder hook the encoders report
// through, uniform attribution to the following draw, and (GPU-gated) the
// records a real scene produces, named through shader reflection.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/draw_recorder.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_graph_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

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

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  test('draws record the encoder context and pending uniforms', () {
    final graph = RenderGraph()
      ..addPass(
        _FakePass('shadow', () {
          final recorder = activeDrawRecorder!;
          recorder.onUniformEmplaced(ByteData(64));
          recorder.onUniformEmplaced(ByteData(16));
          recorder.setContext(
            const DrawContext(phase: DrawPhase.shadow, batchedItems: 3),
          );
          recorder.onDraw(36, 2, indexed: true);
          recorder.clearContext();
          recorder.onDraw(6, 1, indexed: false);
        }),
      )
      ..addPass(
        _FakePass('empty', () => expect(activeDrawRecorder, isNotNull)),
      );

    final capturer = RenderGraphCapturer(
      request: const RenderGraphCaptureRequest(captureImages: false),
    );
    graph.execute(
      transientsBuffer: _ThrowingWriter(),
      texturePool: TransientTexturePool(),
      observer: capturer,
    );
    expect(activeDrawRecorder, isNull);
    final result = capturer.finish(pixelWidth: 8, pixelHeight: 8);

    final shadow = result.passes[0];
    expect(shadow.draws, hasLength(2));
    final first = shadow.draws[0];
    expect(first.order, 0);
    expect(first.passIndex, 0);
    expect(first.phase, DrawPhase.shadow);
    expect(first.vertexCount, 36);
    expect(first.instanceCount, 2);
    expect(first.indexed, isTrue);
    expect(first.batchedItems, 3);
    expect(first.triangles, 24);
    expect(first.uniformBlocks.map((b) => b.byteLength), [64, 16]);
    expect(first.nodePath, isNull);
    final second = shadow.draws[1];
    expect(second.order, 1);
    expect(second.phase, DrawPhase.other);
    expect(second.uniformBlocks, isEmpty);
    expect(result.passes[1].draws, isEmpty);
    expect(result.draws.length, 2);

    final json = first.toJson();
    expect(json['phase'], 'shadow');
    expect((json['uniformBlocks'] as List).first['bytes'], 64);
    expect((json['uniformBlocks'] as List).first['candidates'], isEmpty);
    expect(jsonEncode(json), isNotEmpty);
  });

  test('a steady-state execute attaches no recorder', () {
    final graph = RenderGraph()
      ..addPass(_FakePass('p', () => expect(activeDrawRecorder, isNull)));
    graph.execute(
      transientsBuffer: _ThrowingWriter(),
      texturePool: TransientTexturePool(),
    );
  });

  testWidgets('captures a rendered scene\'s draws', (tester) async {
    if (!_gpuAvailable()) return;
    await Scene.initializeStaticResources();
    Scene.debugAllowRenderGraphCapture = true;
    final scene = Scene();
    scene.add(
      Node(
        name: 'box',
        mesh: Mesh(CuboidGeometry(Vector3.all(1)), UnlitMaterial()),
      ),
    );
    final future = scene.captureRenderGraph(
      request: const RenderGraphCaptureRequest(captureImages: false),
    );
    final recorder = ui.PictureRecorder();
    scene.render(
      PerspectiveCamera(position: Vector3(0, 0, 5)),
      ui.Canvas(recorder),
      viewport: const ui.Rect.fromLTWH(0, 0, 64, 64),
      pixelRatio: 1.0,
    );
    recorder.endRecording();
    final result = await future;

    final scenePass = result.passes.singleWhere((p) => p.name == 'ScenePass');
    final draws = scenePass.draws
        .where((d) => d.nodePath?.endsWith('box') ?? false)
        .toList();
    expect(draws, isNotEmpty);
    final draw = draws.first;
    expect(draw.phase, DrawPhase.opaque);
    expect(draw.materialType, 'UnlitMaterial');
    expect(draw.geometryType, 'CuboidGeometry');
    expect(draw.vertexCount, 36);
    expect(draw.indexed, isTrue);
    expect(draw.instanceCount, 1);
    expect(draw.pipelineId, isNotNull);
    expect(draw.batchBreak, BatchBreakReason.none);
    expect(draw.uniformBlocks, isNotEmpty);

    await ShaderReflection.loadBundleInfo(baseShaderLibrary);
    expect(draw.vertexShaderName, 'UnskinnedVertex');
    expect(draw.fragmentShaderName, 'UnlitFragment');
    final named = [
      for (final block in draw.uniformBlocks) block.nameFor(draw),
    ].whereType<String>().toList();
    expect(named, contains('FrameInfo'));
    final decoded = draw.uniformBlocks
        .firstWhere((b) => b.nameFor(draw) == 'FrameInfo')
        .decode(draw)!;
    expect(decoded.map((v) => v.name), contains('mvp'));
    expect(jsonEncode(draw.toJson()), contains('UnlitFragment'));

    // The frame's stats saw the same draws.
    final frame = scene.renderStats.latest!;
    expect(frame.counters.draws, greaterThanOrEqualTo(result.draws.length));
    expect(frame.views.single.passes.map((p) => p.name), contains('ScenePass'));
  });
}
