// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/pipeline_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpuPipelineState equality', () {
    test('two default states are equal and hash alike', () {
      const a = GpuPipelineState();
      const b = GpuPipelineState();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every field participates in equality', () {
      const base = GpuPipelineState();
      expect(base, isNot(base.copyWith(cullMode: gpu.CullMode.frontFace)));
      expect(
        base,
        isNot(base.copyWith(windingOrder: gpu.WindingOrder.clockwise)),
      );
      expect(base, isNot(base.copyWith(primitiveType: gpu.PrimitiveType.line)));
      expect(base, isNot(base.copyWith(depthWriteEnable: false)));
      expect(
        base,
        isNot(base.copyWith(depthCompareOperation: gpu.CompareFunction.always)),
      );
      expect(base, isNot(base.copyWith(blend: GpuBlendEquation.alphaBlend)));
    });

    // The reason this type exists: a WebGPU backend keys its pipeline cache by
    // exactly this tuple, so equal states must collapse to one entry.
    test('works as a map key', () {
      final cache = <GpuPipelineState, int>{};
      cache[const GpuPipelineState()] = 1;
      cache[const GpuPipelineState()] = 2;
      cache[const GpuPipelineState(cullMode: gpu.CullMode.none)] = 3;
      expect(cache.length, 2);
      expect(cache[const GpuPipelineState()], 2);
    });
  });

  group('GpuPipelineState.copyWith', () {
    test('replaces only the named field', () {
      const base = GpuPipelineState();
      final changed = base.copyWith(cullMode: gpu.CullMode.none);
      expect(changed.cullMode, gpu.CullMode.none);
      expect(changed.windingOrder, base.windingOrder);
      expect(changed.depthWriteEnable, base.depthWriteEnable);
    });

    test('clearBlend removes blending, which a null argument cannot', () {
      const blended = GpuPipelineState(blend: GpuBlendEquation.alphaBlend);
      expect(blended.copyWith().blend, isNotNull);
      expect(blended.copyWith(clearBlend: true).blend, isNull);
      expect(blended.copyWith(clearBlend: true).colorBlendEnable, isFalse);
    });
  });

  group('GpuPipelineState defaults', () {
    // Opaque geometry is the overwhelmingly common case, so a bare state
    // should be that rather than something arbitrary.
    test('describe opaque back-face-culled geometry', () {
      const state = GpuPipelineState();
      expect(state.cullMode, gpu.CullMode.backFace);
      expect(state.windingOrder, gpu.WindingOrder.counterClockwise);
      expect(state.primitiveType, gpu.PrimitiveType.triangle);
      expect(state.depthWriteEnable, isTrue);
      expect(state.depthCompareOperation, gpu.CompareFunction.lessEqual);
      expect(state.colorBlendEnable, isFalse);
    });
  });

  group('GpuBlendEquation', () {
    test('has value equality so it can key a cache', () {
      expect(const GpuBlendEquation(), const GpuBlendEquation());
      expect(
        const GpuBlendEquation().hashCode,
        const GpuBlendEquation().hashCode,
      );
    });

    test('distinguishes additive from alpha blending', () {
      expect(GpuBlendEquation.additive, isNot(GpuBlendEquation.alphaBlend));
    });

    test('every field participates in equality', () {
      const base = GpuBlendEquation();
      expect(
        base,
        isNot(
          const GpuBlendEquation(sourceColorBlendFactor: gpu.BlendFactor.zero),
        ),
      );
      expect(
        base,
        isNot(
          const GpuBlendEquation(
            alphaBlendOperation: gpu.BlendOperation.subtract,
          ),
        ),
      );
    });

    test('toGpu carries every field across', () {
      const eq = GpuBlendEquation(
        colorBlendOperation: gpu.BlendOperation.subtract,
        sourceColorBlendFactor: gpu.BlendFactor.zero,
        destinationColorBlendFactor: gpu.BlendFactor.one,
        alphaBlendOperation: gpu.BlendOperation.reverseSubtract,
        sourceAlphaBlendFactor: gpu.BlendFactor.destinationColor,
        destinationAlphaBlendFactor: gpu.BlendFactor.sourceColor,
      );
      final g = eq.toGpu();
      expect(g.colorBlendOperation, gpu.BlendOperation.subtract);
      expect(g.sourceColorBlendFactor, gpu.BlendFactor.zero);
      expect(g.destinationColorBlendFactor, gpu.BlendFactor.one);
      expect(g.alphaBlendOperation, gpu.BlendOperation.reverseSubtract);
      expect(g.sourceAlphaBlendFactor, gpu.BlendFactor.destinationColor);
      expect(g.destinationAlphaBlendFactor, gpu.BlendFactor.sourceColor);
    });

    test('toGpu returns a fresh instance each call', () {
      // gpu.ColorBlendEquation is mutable, so sharing one across draws would
      // let a later mutation reach back into an earlier state.
      const eq = GpuBlendEquation();
      expect(identical(eq.toGpu(), eq.toGpu()), isFalse);
    });
  });
}
