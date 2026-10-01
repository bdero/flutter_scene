import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/mipmap.dart';

/// Uploads [levels] (base first) into [texture], one GPU submission for the
/// whole chain.
///
/// `gpu.Texture.overwrite` is a complete upload on its own: it allocates a
/// staging buffer, records a blit pass into a command buffer of its own, and
/// submits it. On the backends that queue GPU work from the calling thread
/// (Vulkan, Metal) that is a command pool, a descriptor pool, a fence and a
/// queue submission *per mip level*, all on the thread that draws. Copying
/// every level out of one staging buffer through one command buffer pays that
/// once: Flutter GPU batches contiguous `copyBufferToTexture` calls into a
/// single blit pass.
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
