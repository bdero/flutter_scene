import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/mipmap.dart';

/// Uploads [levels] (base first) into [texture] in one submission.
///
/// Each `gpu.Texture.overwrite` is its own staging buffer, blit pass, and
/// submission, so a per-level loop pays that once per level. Contiguous
/// `copyBufferToTexture` calls on one command buffer share a single blit pass.
void uploadLevelsInto(gpu.Texture texture, List<MipLevel> levels) {
  if (levels.length == 1) {
    texture.overwrite(ByteData.sublistView(levels[0].pixels));
    return;
  }
  var total = 0;
  for (final level in levels) {
    total += level.pixels.lengthInBytes;
  }
  final staging = gpu.gpuContext.createDeviceBuffer(
    gpu.StorageMode.hostVisible,
    total,
  );
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  var offset = 0;
  for (var i = 0; i < levels.length; i++) {
    final bytes = ByteData.sublistView(levels[i].pixels);
    staging.overwrite(bytes, destinationOffsetInBytes: offset);
    commandBuffer.copyBufferToTexture(
      gpu.BufferView(
        staging,
        offsetInBytes: offset,
        lengthInBytes: bytes.lengthInBytes,
      ),
      gpu.TextureRegion(texture, mipLevel: i),
    );
    offset += bytes.lengthInBytes;
  }
  staging.flush();
  commandBuffer.submit();
}
