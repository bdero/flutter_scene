import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Waits, without blocking Dart, until the raster thread has worked through
/// everything submitted so far.
///
/// On the OpenGL ES backend, Flutter GPU does not execute a command buffer
/// where it is submitted: `CommandBuffer.submit` posts the encode and the
/// reactor flush to the raster thread, and calls back on the UI thread once
/// that has run. An empty command buffer is therefore a cheap rendezvous, its
/// completion meaning the raster thread is past everything queued before it.
///
/// Two places need that:
///
///  * before the draws that compile pipelines.
///    `flutter::gpu::RenderPass::GetOrCreatePipeline`
///    (`flutter/lib/gpu/render_pass.cc`) posts pipeline creation to the raster
///    thread on GLES and **blocks the calling thread** on the result, warning
///    in its own comment that it "could hang the UI thread long enough to miss
///    a frame". Awaiting the raster thread first turns that block into an
///    await, so the round trip lands on an idle thread.
///
///  * between large batches of GPU passes, so one submission does not hand the
///    driver more work than the display pipeline can absorb before its next
///    present.
///
/// Elsewhere this is close to free. The web shim runs the callback
/// synchronously, and the backends that submit from the calling thread
/// complete it as the buffer retires. Either way a caller resumes on a later
/// microtask, never on a blocked thread.
///
/// Completes immediately rather than throwing when there is no GPU context
/// yet, and gives up after [timeout] rather than hanging on a backend that
/// never reports completion.
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
    // No context, or a backend that cannot submit an empty command buffer.
    // Neither needs the rendezvous.
    done();
  }
  return completer.future.timeout(timeout, onTimeout: () {});
}

/// Paces a producer against presented frames.
///
/// One pacer per producer (one radiance fill), because the degradation below
/// is a statement about this fill's lifetime, not about the process.
class FramePacer {
  /// Set when a frame failed to arrive inside the timeout. Nothing is going to
  /// pace this fill, and making every later step wait out its own timeout
  /// would turn a paced fill into one long stall, so the rest of it runs on
  /// the raster rendezvous alone. Scoped to this pacer, so a later fill starts
  /// out willing to wait again.
  bool _framesStalled = false;

  /// Waits for one whole frame to go through the pipeline, so a batch of GPU
  /// passes submitted before it is paced by the display instead of piling up.
  ///
  /// [awaitRasterThread] only says that the raster thread has *encoded* and
  /// submitted the GL commands. On GLES `CommandBuffer.submit` posts the
  /// reactor flush and calls back as soon as it has run, long before the GPU
  /// has executed anything. There is no GPU-completion signal exposed to Dart,
  /// so the thing to wait on is a frame: a frame cannot be presented until the
  /// GPU has finished the work queued ahead of it, and the engine will not let
  /// the UI thread run more than a frame ahead of the raster thread.
  ///
  /// Skips the wait while the embedder has frames disabled (backgrounded, or
  /// the screen off), where waiting would only burn the timeout. That check is
  /// re-read every step, so a fill that spans a resume goes back to pacing on
  /// its own.
  Future<void> awaitFrame({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final binding = SchedulerBinding.instance;
    if (_framesStalled || !binding.framesEnabled) {
      return awaitRasterThread(timeout: timeout);
    }
    var timedOut = false;
    binding.scheduleFrame();
    await binding.endOfFrame.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
      },
    );
    if (timedOut) {
      _framesStalled = true;
    }
    await awaitRasterThread(timeout: timeout);
  }
}
