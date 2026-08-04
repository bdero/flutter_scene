/// The shape of a shader's resource bindings, independent of the resources
/// themselves.
///
/// A material's textures are stable for as long as the material lives, but its
/// uniforms are rewritten every draw from the transient allocator, so a
/// "binding set" is not one uniform thing. WebGPU models exactly this split as
/// a bind group whose textures are fixed and whose uniform buffer is addressed
/// through a dynamic offset, and a bind group can only be built once its layout
/// is known. This is that layout.
///
/// Pure data, so it can be compared, cached, and tested without a GPU.
library;

/// What kind of resource occupies a binding slot.
enum GpuBindingKind {
  /// A uniform buffer. Its contents are rewritten per draw, so a backend that
  /// caches bind groups addresses it through a dynamic offset rather than
  /// rebuilding the group.
  uniformBuffer,

  /// A texture and its sampler. Stable for as long as the material is.
  texture,
}

/// One entry in a [GpuBindingLayout].
typedef GpuBindingSlot = ({String name, GpuBindingKind kind});

/// The ordered set of slots a shader expects.
///
/// Two shaders with the same layout can share a realized bind group layout, so
/// this has value equality and is usable as a cache key.
class GpuBindingLayout {
  GpuBindingLayout(Iterable<GpuBindingSlot> slots)
    : slots = List.unmodifiable(_sorted(slots));

  /// Slots in a canonical order, so two layouts that differ only in the order
  /// they were declared compare equal.
  final List<GpuBindingSlot> slots;

  static List<GpuBindingSlot> _sorted(Iterable<GpuBindingSlot> slots) {
    final seen = <String>{};
    for (final s in slots) {
      if (!seen.add(s.name)) {
        throw ArgumentError.value(s.name, 'slots', 'duplicate binding name');
      }
    }
    return [...slots]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// The uniform buffer slots, which a backend addresses per draw.
  Iterable<String> get uniformNames => slots
      .where((s) => s.kind == GpuBindingKind.uniformBuffer)
      .map((s) => s.name);

  /// The texture slots, which a backend can bind once and reuse.
  Iterable<String> get textureNames =>
      slots.where((s) => s.kind == GpuBindingKind.texture).map((s) => s.name);

  /// The kind of [name], or null when this layout has no such slot.
  GpuBindingKind? kindOf(String name) {
    for (final s in slots) {
      if (s.name == name) return s.kind;
    }
    return null;
  }

  /// Whether [name] is one of this layout's slots.
  bool contains(String name) => kindOf(name) != null;

  @override
  bool operator ==(Object other) {
    if (other is! GpuBindingLayout) return false;
    if (other.slots.length != slots.length) return false;
    for (var i = 0; i < slots.length; i++) {
      if (other.slots[i] != slots[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll([for (final s in slots) Object.hash(s.name, s.kind)]);

  @override
  String toString() =>
      'GpuBindingLayout(${slots.map((s) => '${s.name}:${s.kind.name}').join(', ')})';
}
