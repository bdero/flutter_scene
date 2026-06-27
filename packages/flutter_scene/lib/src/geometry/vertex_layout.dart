import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// A described vertex attribute: the shader input it feeds (by [name]), its
/// element [format], and its byte [offsetInBytes] within the owning buffer's
/// per-element stride.
///
/// This is the engine-side, value-equal description of a single attribute.
/// It lowers to a [gpu.VertexAttribute] (the flutter_gpu pipeline type) but,
/// unlike that type, compares by value so two structurally identical layouts
/// can be interned to one identity (see [vertexLayoutId]).
@immutable
class VertexAttributeDescriptor {
  const VertexAttributeDescriptor({
    required this.name,
    required this.format,
    this.offsetInBytes = 0,
  });

  /// Name of the shader-side input this attribute feeds (e.g. `position`).
  /// flutter_gpu binds vertex attributes by name, so this must match the
  /// vertex shader's `in` declaration.
  final String name;

  /// Format of each element of this attribute.
  final gpu.VertexFormat format;

  /// Byte offset of this attribute from the start of each element of the
  /// owning [VertexBufferDescriptor].
  final int offsetInBytes;

  gpu.VertexAttribute _toGpu() => gpu.VertexAttribute(
    name: name,
    format: format,
    offsetInBytes: offsetInBytes,
  );

  @override
  bool operator ==(Object other) =>
      other is VertexAttributeDescriptor &&
      other.name == name &&
      other.format == format &&
      other.offsetInBytes == offsetInBytes;

  @override
  int get hashCode => Object.hash(name, format, offsetInBytes);
}

/// One vertex buffer slot: its per-element [strideInBytes], how it advances
/// while drawing ([stepMode]), and the [attributes] read from it. The
/// buffer's position in [VertexLayoutDescriptor.buffers] is its binding slot.
///
/// Lowers to a [gpu.VertexBuffer]; compares by value.
@immutable
class VertexBufferDescriptor {
  const VertexBufferDescriptor({
    required this.strideInBytes,
    required this.attributes,
    this.stepMode = gpu.VertexStepMode.vertex,
  });

  /// Byte distance from the start of one element to the start of the next.
  final int strideInBytes;

  /// Attributes read from this slot by the vertex shader.
  final List<VertexAttributeDescriptor> attributes;

  /// Whether this slot advances per vertex or per instance.
  final gpu.VertexStepMode stepMode;

  gpu.VertexBuffer _toGpu() => gpu.VertexBuffer(
    strideInBytes: strideInBytes,
    stepMode: stepMode,
    attributes: [for (final attribute in attributes) attribute._toGpu()],
  );

  @override
  bool operator ==(Object other) =>
      other is VertexBufferDescriptor &&
      other.strideInBytes == strideInBytes &&
      other.stepMode == stepMode &&
      listEquals(other.attributes, attributes);

  @override
  int get hashCode =>
      Object.hash(strideInBytes, stepMode, Object.hashAll(attributes));
}

/// A complete, described vertex input layout: the buffer slots a pipeline
/// reads from and the attributes each one feeds.
///
/// This is the engine-side description that replaces the two magic
/// per-vertex byte counts with an explicit attribute set. It lowers to a
/// [gpu.VertexLayout] via [toGpuLayout] (the flutter_gpu pipeline type, kept
/// as the dumb lowering target), but adds value equality so identical
/// layouts share one pipeline-cache identity. The canonical instance is
/// `kUnskinnedInstancedLayout`.
@immutable
class VertexLayoutDescriptor {
  const VertexLayoutDescriptor({required this.buffers});

  /// Vertex buffer slots; list position is the binding slot.
  final List<VertexBufferDescriptor> buffers;

  /// Lowers this description to the flutter_gpu pipeline layout, validating
  /// it first.
  ///
  /// Called at pipeline-creation time (once per interned layout). Throws an
  /// [ArgumentError] when an attribute would read past its slot's stride or
  /// when an attribute name is reused, so a malformed layout fails loudly
  /// here instead of producing silently wrong rendering.
  gpu.VertexLayout toGpuLayout() {
    _validate();
    return gpu.VertexLayout(
      buffers: [for (final buffer in buffers) buffer._toGpu()],
    );
  }

  void _validate() {
    final seenNames = <String>{};
    for (final buffer in buffers) {
      for (final attribute in buffer.attributes) {
        if (!seenNames.add(attribute.name)) {
          throw ArgumentError(
            'Vertex attribute "${attribute.name}" is declared more than once '
            'in the layout; attribute names must be unique because '
            'flutter_gpu binds them by name.',
          );
        }
        final end = attribute.offsetInBytes + attribute.format.bytesPerElement;
        if (end > buffer.strideInBytes) {
          throw ArgumentError(
            'Vertex attribute "${attribute.name}" ends at byte $end, past its '
            'buffer stride of ${buffer.strideInBytes}.',
          );
        }
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VertexLayoutDescriptor && listEquals(other.buffers, buffers);

  @override
  int get hashCode => Object.hashAll(buffers);
}

// Interned identities for layout descriptors. A pipeline depends on its
// vertex layout as well as its shaders, so a cache keyed on the shader pair
// alone serves the wrong pipeline once one shader has more than one layout.
// Interning collapses every structurally identical layout to one small
// integer the pipeline-cache key can carry. (Mirrors interned vertex-layout
// ids used by other engines.) The map is never pruned: layouts are a small,
// process-stable set, so ids stay stable for the process lifetime.
final Map<VertexLayoutDescriptor, int> _layoutIds = {};

/// A stable, process-wide integer identity for [layout], shared by every
/// structurally equal layout.
///
/// The default reflection-derived layout (a `null` layout, used by skinned
/// geometry) is id `0`; described layouts are numbered from `1`. Pipeline
/// caches include this in their key so two layouts on one vertex shader do
/// not collide.
@internal
int vertexLayoutId(VertexLayoutDescriptor? layout) =>
    layout == null ? 0 : (_layoutIds[layout] ??= _layoutIds.length + 1);
