import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';

final gpu.Shader _vertexShader = baseShaderLibrary['FullscreenVertex']!;
final gpu.Shader _fragmentShader = baseShaderLibrary['CopyFragment']!;

final gpu.DeviceBuffer _quadBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
  ByteData.sublistView(
    Float32List.fromList(<double>[
      -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
      -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
    ]),
  ),
);
final gpu.BufferView _quadView = gpu.BufferView(
  _quadBuffer,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

final gpu.SamplerOptions _linearClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// Copies all of [source] into the [region] of [destination] (pixels, origin
/// top-left), leaving the rest of [destination] as it was.
///
/// A viewport plus scissor confine the full-screen quad, so the other views
/// sharing [destination] keep their pixels. Sizes that differ resample
/// linearly.
void copyTextureToRegion(
  gpu.Texture source,
  gpu.Texture destination,
  ui.Rect region,
) {
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: destination,
        loadAction: gpu.LoadAction.load,
        storeAction: gpu.StoreAction.store,
      ),
    ),
  );
  final x = region.left.round();
  final y = region.top.round();
  final width = region.width.round();
  final height = region.height.round();
  renderPass.setViewport(
    gpu.Viewport(x: x, y: y, width: width, height: height),
  );
  renderPass.setScissor(gpu.Scissor(x: x, y: y, width: width, height: height));
  renderPass.bindPipeline(resolvePipeline(_vertexShader, _fragmentShader));
  renderPass.setColorBlendEnable(false);
  bindVertexBufferCompat(renderPass, _quadView, 6);
  renderPass.bindTexture(
    _fragmentShader.cachedUniformSlot('source_texture'),
    source,
    sampler: _linearClamp,
  );
  drawCompat(renderPass, 6);
  rendererSubmissions.submit(commandBuffer);
}
