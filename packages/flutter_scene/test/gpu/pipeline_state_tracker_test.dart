// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/pipeline_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpuPipelineState.diffFrom', () {
    test('reports everything changed against an unknown pass', () {
      final delta = const GpuPipelineState().diffFrom(null);
      expect(delta.length, 6);
      expect(delta.isEmpty, isFalse);
    });

    test('reports nothing changed against an identical state', () {
      final delta = const GpuPipelineState().diffFrom(const GpuPipelineState());
      expect(delta.isEmpty, isTrue);
      expect(delta.length, 0);
    });

    test('reports exactly the field that changed', () {
      const from = GpuPipelineState();
      final delta = from.copyWith(cullMode: gpu.CullMode.none).diffFrom(from);
      expect(delta.cullMode, isTrue);
      expect(delta.windingOrder, isFalse);
      expect(delta.primitiveType, isFalse);
      expect(delta.depthWriteEnable, isFalse);
      expect(delta.depthCompareOperation, isFalse);
      expect(delta.blend, isFalse);
      expect(delta.length, 1);
    });

    test('treats gaining and losing blending as a change', () {
      const opaque = GpuPipelineState();
      const blended = GpuPipelineState(blend: GpuBlendEquation.alphaBlend);
      expect(blended.diffFrom(opaque).blend, isTrue);
      expect(opaque.diffFrom(blended).blend, isTrue);
    });

    test('treats a different blend equation as a change', () {
      const a = GpuPipelineState(blend: GpuBlendEquation.alphaBlend);
      const b = GpuPipelineState(blend: GpuBlendEquation.additive);
      expect(b.diffFrom(a).blend, isTrue);
      expect(b.diffFrom(a).length, 1);
    });

    test('counts several simultaneous changes', () {
      const from = GpuPipelineState();
      final delta = from
          .copyWith(
            cullMode: gpu.CullMode.none,
            primitiveType: gpu.PrimitiveType.line,
            depthWriteEnable: false,
          )
          .diffFrom(from);
      expect(delta.length, 3);
    });
  });

  group('GpuPipelineStateTracker', () {
    test('starts knowing nothing about the pass', () {
      final tracker = GpuPipelineStateTracker();
      expect(tracker.current, isNull);
      expect(tracker.callsIssued, 0);
      expect(tracker.deltaFor(const GpuPipelineState()).length, 6);
    });

    test('deltaFor does not change what is tracked', () {
      final tracker = GpuPipelineStateTracker();
      tracker.deltaFor(const GpuPipelineState());
      expect(tracker.current, isNull);
    });

    test('invalidate forces the next apply to re-issue everything', () {
      final tracker = GpuPipelineStateTracker();
      // Simulate an apply having happened.
      tracker.invalidate();
      expect(tracker.current, isNull);
      expect(tracker.deltaFor(const GpuPipelineState()).length, 6);
    });

    test('reset clears the state and the counter', () {
      final tracker = GpuPipelineStateTracker()..reset();
      expect(tracker.current, isNull);
      expect(tracker.callsIssued, 0);
    });
  });

  group('GpuPipelineStateDelta', () {
    test('everything marks all six fields', () {
      const delta = GpuPipelineStateDelta.everything();
      expect(delta.cullMode, isTrue);
      expect(delta.windingOrder, isTrue);
      expect(delta.primitiveType, isTrue);
      expect(delta.depthWriteEnable, isTrue);
      expect(delta.depthCompareOperation, isTrue);
      expect(delta.blend, isTrue);
      expect(delta.length, 6);
    });

    test('the default is empty', () {
      const delta = GpuPipelineStateDelta();
      expect(delta.isEmpty, isTrue);
      expect(delta.length, 0);
    });

    test('toString reports how many fields changed', () {
      expect(
        const GpuPipelineStateDelta.everything().toString(),
        contains('6 changed'),
      );
    });
  });
}
