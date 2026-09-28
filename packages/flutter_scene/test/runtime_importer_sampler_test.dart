// How a glTF sampler's wrap and filter modes map onto the sampler options of
// a runtime-imported texture. The upload needs a GPU, so only the mapping is
// tested here.

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/runtime_importer/texture_builder.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = const TextureSampling().toSamplerOptions();

  test('the default glTF sampler changes nothing', () {
    expect(identical(gltfSamplerOptions(GltfSampler(), base), base), isTrue);
  });

  test('wrap modes map per axis', () {
    final options = gltfSamplerOptions(
      GltfSampler(wrapS: 33071, wrapT: 33648),
      base,
    );
    expect(options.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(options.heightAddressMode, gpu.SamplerAddressMode.mirror);
    // Filters are untouched, so trilinear anisotropic sampling survives.
    expect(options.minFilter, base.minFilter);
    expect(options.mipFilter, base.mipFilter);
    expect(options.maxAnisotropy, base.maxAnisotropy);
  });

  test('NEAREST filters drop anisotropy', () {
    final options = gltfSamplerOptions(
      GltfSampler(magFilter: 9728, minFilter: 9984),
      base,
    );
    expect(options.magFilter, gpu.MinMagFilter.nearest);
    expect(options.minFilter, gpu.MinMagFilter.nearest);
    expect(options.mipFilter, gpu.MipFilter.nearest);
    expect(options.maxAnisotropy, 1);
  });

  test('LINEAR_MIPMAP_LINEAR with CLAMP_TO_EDGE keeps anisotropy', () {
    final options = gltfSamplerOptions(
      GltfSampler(magFilter: 9729, minFilter: 9987, wrapS: 33071, wrapT: 33071),
      base,
    );
    expect(options.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(options.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(options.maxAnisotropy, base.maxAnisotropy);
  });
}
