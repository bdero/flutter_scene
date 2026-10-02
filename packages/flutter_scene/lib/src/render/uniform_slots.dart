import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

final Expando<Map<String, gpu.UniformSlot>> _slotsByShader = Expando(
  'uniform slots',
);
gpu.Shader? _lastShader;
Map<String, gpu.UniformSlot>? _lastSlots;

/// Shares one [gpu.UniformSlot] per shader and name.
///
/// [gpu.Shader.getUniformSlot] allocates a fresh slot per call, and binds run
/// per draw. A slot is an immutable (shader, name) pair, so sharing it is
/// safe.
extension CachedUniformSlots on gpu.Shader {
  /// [getUniformSlot], cached per shader and name.
  gpu.UniformSlot cachedUniformSlot(String name) {
    // Draws are sorted by pipeline, so consecutive lookups usually hit the
    // same shader and skip the expando.
    var slots = identical(this, _lastShader) ? _lastSlots : null;
    if (slots == null) {
      slots = _slotsByShader[this] ??= <String, gpu.UniformSlot>{};
      _lastShader = this;
      _lastSlots = slots;
    }
    return slots[name] ??= getUniformSlot(name);
  }
}
