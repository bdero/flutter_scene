// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // GLES keeps sampler state on the texture, so a placeholder bound to several
  // slots of one draw takes the last sampler applied. Point sampling reads its
  // one texel exactly, so every binding agrees.
  test('a placeholder slot binds point-sampled', () {
    expect(placeholderSampler.minFilter, gpu.MinMagFilter.nearest);
    expect(placeholderSampler.magFilter, gpu.MinMagFilter.nearest);
    expect(placeholderSampler.mipFilter, gpu.MipFilter.nearest);
    expect(placeholderSampler.maxAnisotropy, 1);

    final linear = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
    );
    expect(samplerOrPlaceholder(null, linear), same(placeholderSampler));
  });
}
