import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Waits, without blocking Dart, until the raster thread has worked through
/// everything submitted so far.
///
/// On the OpenGL ES backend, Flutter GPU does not execute a command buffer
/// where it is submitted: `CommandBuffer.submit` posts the encode and the
/// reactor flush to the raster thread, and calls back on the UI thread once
/// that has run. An empty command buffer is therefore a cheap rendezvous: its
/// completion means the raster thread is past everything queued before it.
///
/// Two places need that:
///
///  * before the draws that compile pipelines. `flutter::gpu::RenderPass::Draw`
///    resolves its pipeline through `GetOrCreatePipeline`
///    (`flutter/lib/gpu/render_pass.cc`), which on GLES posts pipeline creation
///    to the raster thread and **blocks the calling thread** on the result —
///    its own comment warns it "could hang the UI thread long enough to miss a
///    frame". Awaiting the raster thread first turns that block into an await.
///
///  * between large batches of GPU passes, so a single submission does not
///    hand the driver more work than the display pipeline can absorb before
///    its next present.
///
/// The other backends complete inline, where this is a cheap no-op. The
/// timeout keeps a caller from hanging on a backend that never reports
/// completion.
Future<void> awaitRasterThread({
  Duration timeout = const Duration(seconds: 2),
}) {
  final completer = Completer<void>();
  void done() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  try {
    gpu.gpuContext.createCommandBuffer().submit(
      completionCallback: (_) => done(),
    );
  } catch (_) {
    // A backend that cannot submit an empty command buffer does not need the
    // rendezvous.
    done();
  }
  return completer.future.timeout(timeout, onTimeout: () {});
}

/// Waits for one whole frame to go through the pipeline, so a batch of GPU
/// passes submitted before it is paced by the display instead of piling up.
///
/// [awaitRasterThread] only says that the raster thread has *encoded* and
/// submitted the GL commands: on GLES `CommandBuffer.submit` posts the reactor
/// flush to the raster thread and calls back as soon as it has run, which is
/// long before the GPU has executed anything. There is no GPU-completion
/// signal exposed to Dart, so the thing to wait on is a frame: a frame cannot
/// be presented until the GPU has finished the work queued ahead of it, and
/// the engine will not let the UI thread run more than a frame ahead of the
/// raster thread. Awaiting the end of a frame therefore throttles a producer
/// to what the GPU is actually retiring.
///
/// Falls back to the raster rendezvous alone when there is no binding (a
/// headless test), and times out rather than hanging if no frame is served.
Future<void> awaitFrame({Duration timeout = const Duration(seconds: 2)}) async {
  final binding = SchedulerBinding.instance;
  binding.scheduleFrame();
  await binding.endOfFrame.timeout(timeout, onTimeout: () {});
  await awaitRasterThread(timeout: timeout);
}
