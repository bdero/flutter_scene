import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/mipmap.dart';

/// Uploads [levels] (base first) into [texture], one level at a time.
///
/// The web backend uploads straight into the texture object per level; there is
/// no staging buffer or command buffer to share between them.
void uploadLevelsInto(gpu.Texture texture, List<MipLevel> levels) {
  for (var i = 0; i < levels.length; i++) {
    texture.overwrite(ByteData.sublistView(levels[i].pixels), mipLevel: i);
  }
}
