import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';

// Fullscreen NDC quad (6 vec2s).
final gpu.DeviceBuffer _quad = gpu.gpuContext.createDeviceBufferWithCopy(
  ByteData.sublistView(
    Float32List.fromList(<double>[
      -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
      -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
    ]),
  ),
);
final gpu.BufferView _quadView = gpu.BufferView(
  _quad,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// Copies the [primary] and [secondary] environments' 9-texel diffuse-SH
/// coefficient textures into the rows of [target] (9x2, row 0 primary), so
/// the lit shader reads both cross-fade environments through the single
/// `sh_coefficients` sampler.
void encodeShComposite(
  gpu.Texture target,
  gpu.Texture primary,
  gpu.Texture secondary,
) {
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final pass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
  );
  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['ShCompositeFragment']!;
  pass.bindPipeline(resolvePipeline(vertexShader, fragmentShader));
  pass.setColorBlendEnable(false);
  pass.setCullMode(gpu.CullMode.none);
  pass.setPrimitiveType(gpu.PrimitiveType.triangle);
  bindVertexBufferCompat(pass, _quadView, 6);
  pass.bindTexture(
    fragmentShader.getUniformSlot('sh_primary'),
    primary,
    sampler: _nearestClamp,
  );
  pass.bindTexture(
    fragmentShader.getUniformSlot('sh_secondary'),
    secondary,
    sampler: _nearestClamp,
  );
  drawCompat(pass, 6);
  rendererSubmissions.submit(commandBuffer);
}
