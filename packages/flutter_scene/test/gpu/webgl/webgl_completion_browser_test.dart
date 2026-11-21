// Command completion gates transient buffer reuse.
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/web/_gpu.dart' show useWebGpuBackend;
import 'package:flutter_scene/src/gpu/web/webgl/_webgl.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

const _completionTimeout = Duration(seconds: 5);

gpu.CommandBuffer _clear(gpu.Texture target) {
  final commands = gpu.gpuContext.createCommandBuffer();
  commands.createRenderPass(
    gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
  );
  return commands;
}

Uint8List _readBuffer(
  web.WebGL2RenderingContext gl,
  web.WebGLBuffer buffer,
  int length,
) {
  final result = JSUint8Array.withLength(length);
  gl.bindBuffer(web.WebGL2RenderingContext.ARRAY_BUFFER, buffer);
  gl.getBufferSubData(web.WebGL2RenderingContext.ARRAY_BUFFER, 0, result);
  return result.toDart;
}

void main() {
  if (useWebGpuBackend) {
    test('needs the WebGL2 shim', () {
      markTestSkipped('The shim is WebGPU in this build.');
    });
    return;
  }

  late web.WebGL2RenderingContext gl;
  late gpu.Texture target;

  setUpAll(() async {
    await gpu.initializeGpuBackend();
    gl = (gpu.gpuContext as WebGlContext).gl;
  });

  setUp(() {
    target = gpu.gpuContext.createTexture(gpu.StorageMode.devicePrivate, 4, 4);
    addTearDown(() => gpu.gpuHost.releaseTexture(target));
  });

  test('submission completes successfully after yielding', () async {
    final completion = Completer<gpu.CompletionStatus>();
    var calls = 0;
    _clear(target).submit(
      completionCallback: expectAsync1((gpu.CompletionStatus status) {
        calls++;
        completion.complete(status);
      }),
    );

    expect(calls, 0);
    await Future<void>.value();
    expect(calls, 0);
    expect(
      await completion.future.timeout(_completionTimeout),
      gpu.CompletionStatus.successful,
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
  });

  test('queued and reentrant submissions complete once in order', () async {
    final completion = Completer<void>();
    final order = <int>[];
    final statuses = <gpu.CompletionStatus>[];
    final context = gl as JSObject;
    final fenceSync = context['fenceSync']! as JSFunction;
    final flush = context['flush']! as JSFunction;
    var fences = 0;
    var flushes = 0;
    addTearDown(() {
      context['fenceSync'] = fenceSync;
      context['flush'] = flush;
    });
    context['fenceSync'] = ((JSAny? condition, JSAny? flags) {
      fences++;
      return fenceSync.callAsFunction(context, condition, flags);
    }).toJS;
    context['flush'] = (() {
      flushes++;
      flush.callAsFunction(context);
    }).toJS;

    void submit(int index) {
      _clear(target).submit(
        completionCallback: expectAsync1((gpu.CompletionStatus status) {
          order.add(index);
          statuses.add(status);
          if (index == 0) submit(3);
          if (order.length == 4) completion.complete();
        }),
      );
    }

    for (var i = 0; i < 3; i++) {
      submit(i);
    }
    expect(order, isEmpty);
    expect(fences, 0);
    expect(flushes, 0);
    await Future<void>.value();
    expect(order, isEmpty);
    expect(fences, 1);
    expect(flushes, 1);
    await completion.future.timeout(_completionTimeout);
    await Future<void>.delayed(Duration.zero);
    expect(order, [0, 1, 2, 3]);
    expect(statuses, everyElement(gpu.CompletionStatus.successful));
    expect(fences, 2);
    expect(flushes, 2);
    expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
  });

  test('a transient buffer is reused only after completion', () async {
    final tracker = GpuSubmissionTracker();
    final pool = ImmediatePoolTransients(tracker, vertexData: true);
    final buffers = <gpu.DeviceBuffer>{};
    addTearDown(() => buffers.forEach(gpu.gpuHost.releaseBuffer));
    final firstData = Float32List.fromList([
      for (var i = 0; i < 100; i++) i * .25,
    ]);
    final firstBytes = Uint8List.fromList(firstData.buffer.asUint8List());
    final secondData = Float32List.fromList([
      for (var i = 0; i < 100; i++) -i * .5,
    ]);
    final secondBytes = Uint8List.fromList(secondData.buffer.asUint8List());
    final first = pool.emplaceTyped(firstData);
    buffers.add(first.buffer);
    final firstHandle =
        gl.getParameter(web.WebGL2RenderingContext.ARRAY_BUFFER_BINDING)
            as web.WebGLBuffer;
    firstData.fillRange(0, firstData.length, 99);

    final completion = Completer<void>();
    void onComplete() {
      completion.complete();
    }

    tracker.addCompletionListener(onComplete);
    addTearDown(() => tracker.removeCompletionListener(onComplete));
    tracker.submit(_clear(target));
    expect(tracker.latestSubmission, 1);
    expect(tracker.completedThrough, 0);
    expect(completion.isCompleted, isFalse);

    pool.beginFrame();
    final second = pool.emplaceTyped(secondData);
    buffers.add(second.buffer);
    final secondHandle =
        gl.getParameter(web.WebGL2RenderingContext.ARRAY_BUFFER_BINDING)
            as web.WebGLBuffer;
    secondData.fillRange(0, secondData.length, -99);
    expect(identical(second.buffer, first.buffer), isFalse);
    expect(pool.bufferCount, 2);
    expect(tracker.completedThrough, 0);

    // Readback occurs after the pending-submission assertions.
    expect(_readBuffer(gl, firstHandle, firstBytes.length), firstBytes);
    expect(_readBuffer(gl, secondHandle, secondBytes.length), secondBytes);
    await completion.future.timeout(_completionTimeout);
    expect(tracker.completedThrough, 1);
    expect(_readBuffer(gl, firstHandle, firstBytes.length), firstBytes);

    final replacement = Float32List.fromList([
      for (var i = 0; i < 100; i++) i + .75,
    ]);
    final replacementBytes = Uint8List.fromList(
      replacement.buffer.asUint8List(),
    );
    final reused = pool.emplaceTyped(replacement);
    replacement.fillRange(0, replacement.length, 0);
    expect(identical(reused.buffer, first.buffer), isTrue);
    expect(pool.bufferCount, 2);
    expect(
      _readBuffer(gl, firstHandle, replacementBytes.length),
      replacementBytes,
    );
    expect(_readBuffer(gl, secondHandle, secondBytes.length), secondBytes);
    expect(gl.getError(), web.WebGL2RenderingContext.NO_ERROR);
  });
}
