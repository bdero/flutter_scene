part of '_gpu.dart';

/// Format of a single vertex attribute element. Mirrors flutter_gpu.
enum VertexFormat {
  /// One 32-bit float (4 bytes).
  float32(bytesPerElement: 4, componentCount: 1),

  /// Two 32-bit floats (8 bytes).
  float32x2(bytesPerElement: 8, componentCount: 2),

  /// Three 32-bit floats (12 bytes).
  float32x3(bytesPerElement: 12, componentCount: 3),

  /// Four 32-bit floats (16 bytes).
  float32x4(bytesPerElement: 16, componentCount: 4),

  /// One 32-bit unsigned integer (4 bytes).
  uint32(bytesPerElement: 4, componentCount: 1),

  /// Two 32-bit unsigned integers (8 bytes).
  uint32x2(bytesPerElement: 8, componentCount: 2),

  /// Three 32-bit unsigned integers (12 bytes).
  uint32x3(bytesPerElement: 12, componentCount: 3),

  /// Four 32-bit unsigned integers (16 bytes).
  uint32x4(bytesPerElement: 16, componentCount: 4),

  /// One 32-bit signed integer (4 bytes).
  sint32(bytesPerElement: 4, componentCount: 1),

  /// Two 32-bit signed integers (8 bytes).
  sint32x2(bytesPerElement: 8, componentCount: 2),

  /// Three 32-bit signed integers (12 bytes).
  sint32x3(bytesPerElement: 12, componentCount: 3),

  /// Four 32-bit signed integers (16 bytes).
  sint32x4(bytesPerElement: 16, componentCount: 4);

  const VertexFormat({
    required this.bytesPerElement,
    required this.componentCount,
  });

  /// Total size in bytes of a single attribute element of this format.
  final int bytesPerElement;

  /// Number of scalar components in a single attribute element.
  final int componentCount;
}

/// How a [VertexBuffer] advances through its elements while drawing.
/// Mirrors flutter_gpu.
enum VertexStepMode {
  /// Advance to the next buffer element for each vertex.
  vertex,

  /// Advance to the next buffer element for each instance.
  instance,
}

/// A single vertex attribute: the shader input it feeds (by name), its byte
/// offset within the owning buffer's element, and its format. Mirrors
/// flutter_gpu.
class VertexAttribute {
  const VertexAttribute({
    required this.name,
    required this.format,
    this.offsetInBytes = 0,
  });

  /// Name of the shader-side input this attribute feeds (e.g. `position`).
  final String name;

  /// Format of each attribute element.
  final VertexFormat format;

  /// Byte offset of this attribute from the start of each element.
  final int offsetInBytes;
}

/// One vertex buffer slot: per-element stride, step mode, and the
/// attributes read from it. The buffer's position in [VertexLayout.buffers]
/// is its binding slot. Mirrors flutter_gpu.
class VertexBuffer {
  const VertexBuffer({
    required this.strideInBytes,
    required this.attributes,
    this.stepMode = VertexStepMode.vertex,
  });

  /// Byte distance from the start of one element to the start of the next.
  final int strideInBytes;

  /// Attributes read from this vertex buffer by the vertex shader.
  final List<VertexAttribute> attributes;

  /// How this vertex buffer advances while drawing.
  final VertexStepMode stepMode;
}

/// A complete vertex input layout: vertex buffer slots and the attributes
/// that read from each one. Overrides the WebGL2 backend's default
/// reflection-derived single-buffer layout. Mirrors flutter_gpu.
class VertexLayout {
  const VertexLayout({required this.buffers});

  /// Vertex buffer slots; list position is the binding slot.
  final List<VertexBuffer> buffers;
}
