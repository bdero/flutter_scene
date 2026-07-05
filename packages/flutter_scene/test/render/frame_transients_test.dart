import 'dart:typed_data';

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

ByteData _bytes(int length, [int fill = 0xAB]) {
  final data = ByteData(length);
  for (var i = 0; i < length; i++) {
    data.setUint8(i, fill);
  }
  return data;
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

    test('before-submit listeners run with the id being recorded', () {
      final tracker = GpuSubmissionTracker();
      final seen = <int>[];
      tracker.addBeforeSubmitListener(seen.add);
      final a = tracker.record();
      final b = tracker.record();
      expect(seen, [a, b]);
    });
  });

  group('TransientArena.planEmplacement', () {
    test('aligns within the block', () {
      final plan = TransientArena.planEmplacement(
        cursor: 100,
        alignment: 256,
        length: 100,
        blockLength: 1024,
      );
      expect(plan.rollOver, isFalse);
      expect(plan.offset, 256);
    });

    test('rolls over when the write end crosses the block', () {
      // The exact numbers from the flutter_gpu HostBuffer bug observed in
      // the wild: aligned offset 1023744 fits, 1023744 + 656 does not.
      final plan = TransientArena.planEmplacement(
        cursor: 1023744,
        alignment: 256,
        length: 656,
        blockLength: 1024000,
      );
      expect(plan.rollOver, isTrue);
      expect(plan.offset, 0);
    });

    test('a write ending exactly at the block boundary fits', () {
      final plan = TransientArena.planEmplacement(
        cursor: 512,
        alignment: 256,
        length: 512,
        blockLength: 1024,
      );
      expect(plan.rollOver, isFalse);
      expect(plan.offset, 512);
    });
  });

  if (!_gpuAvailable()) {
    test(
      'transient arena suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  group('TransientArena', () {
    test('emplacements are aligned and stay inside the block', () {
      final tracker = GpuSubmissionTracker();
      final arena = TransientArena(tracker, alignment: 256);

      final first = arena.emplace(_bytes(100));
      final second = arena.emplace(_bytes(100));
      expect(first.offsetInBytes, 0);
      expect(first.lengthInBytes, 100);
      expect(second.offsetInBytes, 256);
      expect(second.lengthInBytes, 100);
      expect(identical(first.buffer, second.buffer), isTrue);
    });

    test('rolls to a new block when the write itself would not fit', () {
      // Regression for the flutter_gpu HostBuffer boundary bug: an aligned
      // offset that fits while the write's end does not (observed in the
      // wild as offset 1023744 + length 656 against a 1024000-byte block).
      final tracker = GpuSubmissionTracker();
      final arena = TransientArena(
        tracker,
        alignment: 256,
        blockLengthInBytes: 1024000,
      );

      final first = arena.emplace(_bytes(1023744));
      expect(first.offsetInBytes, 0);
      final second = arena.emplace(_bytes(656));
      expect(second.offsetInBytes, 0); // new block
      expect(second.lengthInBytes, 656);
      expect(identical(first.buffer, second.buffer), isFalse);
    });

    test('oversize requests get a dedicated block', () {
      final tracker = GpuSubmissionTracker();
      final arena = TransientArena(
        tracker,
        alignment: 256,
        blockLengthInBytes: 1024,
      );

      final big = arena.emplace(_bytes(4096));
      expect(big.offsetInBytes, 0);
      expect(big.lengthInBytes, 4096);

      // The oversize block does not become the bump target.
      final small = arena.emplace(_bytes(64));
      expect(identical(small.buffer, big.buffer), isFalse);
    });

    test('reuses blocks only after their submissions complete', () {
      final tracker = GpuSubmissionTracker();
      final arena = TransientArena(
        tracker,
        alignment: 256,
        blockLengthInBytes: 1024,
      );

      final first = arena.emplace(_bytes(100));
      tracker.record(); // seals + stamps the block
      arena.beginFrame();

      // Still in flight: the next frame must use a different device buffer.
      final second = arena.emplace(_bytes(100));
      expect(identical(second.buffer, first.buffer), isFalse);
      tracker.record();
      arena.beginFrame();

      // Everything completed: the first block is reusable now.
      tracker.complete(1);
      tracker.complete(2);
      final third = arena.emplace(_bytes(100));
      expect(identical(third.buffer, first.buffer), isTrue);
    });

    test('a submission seals the open block mid-frame', () {
      final tracker = GpuSubmissionTracker();
      final arena = TransientArena(
        tracker,
        alignment: 256,
        blockLengthInBytes: 1024,
      );

      final before = arena.emplace(_bytes(100));
      tracker.record(); // a pass submits; open blocks seal
      final after = arena.emplace(_bytes(100));
      // Sealed blocks are never written again, so the post-submit
      // emplacement lands in a fresh block.
      expect(identical(after.buffer, before.buffer), isFalse);
    });

    test('grows under pending load and shrinks back after completion', () {
      final tracker = GpuSubmissionTracker();
      final arena = TransientArena(
        tracker,
        alignment: 256,
        blockLengthInBytes: 1024,
      );

      final ids = <int>[];
      for (var frame = 0; frame < 4; frame++) {
        arena.emplace(_bytes(512));
        ids.add(tracker.record());
        arena.beginFrame();
      }
      expect(arena.blockCount, 4);

      for (final id in ids) {
        tracker.complete(id);
      }
      // Two idle frames: the pool trims to last frame's usage plus a spare.
      arena.beginFrame();
      arena.beginFrame();
      expect(arena.blockCount, lessThanOrEqualTo(2));
    });

    test('single flush per block: staged bytes upload on seal', () {
      final tracker = GpuSubmissionTracker();
      final arena = TransientArena(
        tracker,
        alignment: 256,
        blockLengthInBytes: 1024,
      );

      // Interleave two emplacements, then seal via a recorded submission.
      // The device buffer contents cannot be read back here (no readback in
      // the shim-agnostic API), so this exercises the code path for
      // crashes/asserts and leaves visual verification to the smoke scenes.
      arena.emplace(_bytes(100, 0x11));
      arena.emplace(_bytes(100, 0x22));
      tracker.record();
      arena.beginFrame();
    });
  });
}
