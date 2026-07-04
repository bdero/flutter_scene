import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GpuSubmissionTracker', () {
    test('watermark handles out of order completion', () {
      final tracker = GpuSubmissionTracker();
      expect(tracker.completedThrough, 0);

      final a = tracker.record();
      final b = tracker.record();
      final c = tracker.record();
      expect(tracker.latestSubmission, c);

      tracker.complete(b);
      expect(tracker.completedThrough, 0);
      tracker.complete(a);
      expect(tracker.completedThrough, b);
      tracker.complete(c);
      expect(tracker.completedThrough, c);
    });
  });

  if (!_gpuAvailable()) {
    test(
      'transients pool suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  group('TransientsPool', () {
    test('reuses a buffer once its submissions complete', () {
      final tracker = GpuSubmissionTracker();
      final pool = TransientsPool(tracker);

      final first = pool.beginFrame();
      final id = tracker.record();
      tracker.complete(id);

      // The prior frame's work completed, so the same buffer is reused.
      final second = pool.beginFrame();
      expect(identical(second, first), isTrue);
      expect(pool.length, 1);
    });

    test('grows while submissions are pending and shrinks after', () {
      final tracker = GpuSubmissionTracker();
      final pool = TransientsPool(tracker);

      // Three frames whose GPU work never completes: every frame needs a
      // distinct buffer.
      final buffers = <Object>{};
      final pendingIds = <int>[];
      for (var i = 0; i < 3; i++) {
        buffers.add(pool.beginFrame());
        pendingIds.add(tracker.record());
      }
      expect(buffers.length, 3);
      expect(pool.length, 3);

      // Once everything completes, the pool reuses buffers and trims down
      // to the active buffer plus one idle spare.
      for (final id in pendingIds) {
        tracker.complete(id);
      }
      pool.beginFrame();
      pool.beginFrame();
      expect(pool.length, lessThanOrEqualTo(2));
    });

    test('never hands out the buffer stamped by pending work', () {
      final tracker = GpuSubmissionTracker();
      final pool = TransientsPool(tracker);

      final first = pool.beginFrame();
      tracker.record();

      // The pending submission may still read `first`, so the next frame
      // must get a different buffer.
      final second = pool.beginFrame();
      expect(identical(second, first), isFalse);
    });
  });
}
