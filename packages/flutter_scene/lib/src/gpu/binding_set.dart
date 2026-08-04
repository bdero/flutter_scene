/// A shader's resources bound as a group rather than one at a time.
///
/// Split along the line that matters to a backend which caches bind groups.
/// Textures and samplers are stable for as long as the material lives, so a
/// backend can realize them once. Uniforms are rewritten every draw from the
/// transient allocator, so they are supplied per draw and a caching backend
/// addresses them through a dynamic offset instead of rebuilding the group.
///
/// The Flutter GPU backend replays both halves as individual binds, which costs
/// exactly what binding each resource directly costs today. It becomes a single
/// call once flutter/flutter#190400 lands, behind an unchanged seam. Whether
/// that has happened is reported by
/// `GpuCapabilities.reusableBindingSets`.
///
/// This library imports the shim rather than being exported by it, so one
/// definition covers every backend.
library;

import 'gpu.dart' as gpu;
import 'shared/gpu_binding_layout.dart';

/// A texture and the sampler it is read through.
class GpuTextureBinding {
  const GpuTextureBinding(this.texture, [this.sampler]);

  final gpu.Texture texture;

  /// Null uses the backend's default sampler, matching `bindTexture`.
  final gpu.SamplerOptions? sampler;

  @override
  bool operator ==(Object other) =>
      other is GpuTextureBinding &&
      identical(other.texture, texture) &&
      other.sampler == sampler;

  @override
  int get hashCode => Object.hash(identityHashCode(texture), sampler);
}

/// The stable half of a shader's bindings, bound once and reused.
///
/// Built per material rather than per draw. Rebuild it when a material swaps a
/// texture; it is cheap, but rebuilding per draw defeats the point.
class GpuBindingSet {
  GpuBindingSet({
    required this.shader,
    required Map<String, GpuTextureBinding> textures,
  }) : textures = Map.unmodifiable(textures),
       layout = GpuBindingLayout([
         for (final name in textures.keys)
           (name: name, kind: GpuBindingKind.texture),
       ]);

  /// The shader whose reflection names these slots.
  final gpu.Shader shader;

  /// Textures by reflected uniform name.
  final Map<String, GpuTextureBinding> textures;

  /// The shape of this set, for a backend that caches by layout.
  final GpuBindingLayout layout;

  /// Binds the stable half onto [pass].
  ///
  /// A backend with real binding sets replaces this with one call; until then
  /// it is the same sequence of `bindTexture` calls the caller would have made.
  void bindTo(gpu.RenderPass pass) {
    for (final entry in textures.entries) {
      final binding = entry.value;
      final sampler = binding.sampler;
      if (sampler == null) {
        pass.bindTexture(shader.getUniformSlot(entry.key), binding.texture);
      } else {
        pass.bindTexture(
          shader.getUniformSlot(entry.key),
          binding.texture,
          sampler: sampler,
        );
      }
    }
  }

  /// Binds a per-draw uniform belonging to this set's shader.
  ///
  /// Separate from [bindTo] because the view comes from the transient
  /// allocator and differs every draw, which is exactly the resource a caching
  /// backend addresses with a dynamic offset.
  void bindUniform(gpu.RenderPass pass, String name, gpu.BufferView view) {
    pass.bindUniform(shader.getUniformSlot(name), view);
  }
}
