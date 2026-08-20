// The runtime view of a material's `instance_attributes` declaration: the
// schema the instance-rate vertex buffer is laid out from, resolved from the
// `.fmat` sidecar. Values are supplied per instance through
// `InstancedMesh.setInstanceAttribute`.

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// One declared per-instance attribute, resolved to its place in the packed
/// instance record.
@internal
class InstanceAttributeSlot {
  const InstanceAttributeSlot({
    required this.name,
    required this.type,
    required this.floatOffset,
  });

  final String name;
  final FmatType type;

  /// Float index within the instance record, past the fixed transform and
  /// color block.
  final int floatOffset;

  /// Floats a caller supplies (a `vec3` pad is not one of them).
  int get components => type.componentCount;

  /// Floats this attribute occupies, including a `vec3`'s tail pad.
  int get packedFloats => type == FmatType.vec3 ? 4 : type.componentCount;

  /// The instance-rate vertex input the generated shader declares.
  String get inputName => 'instance_$name';
}

/// The per-instance attributes a material declares, in declaration order.
///
/// Instances of this class are identity-stable for a material's lifetime (a
/// hot reload that changes the declaration builds a new one), so consumers
/// cache derived data keyed on identity.
@internal
class InstanceAttributeSchema {
  InstanceAttributeSchema(this.attributes)
    : floatCount = attributes.isEmpty
          ? 0
          : attributes.last.floatOffset + attributes.last.packedFloats,
      _byName = {for (final a in attributes) a.name: a};

  /// Builds a schema from a `.fmat` sidecar entry, or null when the material
  /// declares no instance attributes.
  static InstanceAttributeSchema? fromMetadata(Map<String, Object?> metadata) {
    final raw = metadata['instance_attributes'];
    if (raw is! List || raw.isEmpty) return null;
    final slots = <InstanceAttributeSlot>[];
    for (final entry in raw) {
      final a = (entry as Map).cast<String, Object?>();
      final name = a['name'] as String;
      final type = FmatType.fromToken(a['type'] as String);
      if (type == null) {
        throw StateError(
          'Unknown instance attribute type "${a['type']}" for "$name".',
        );
      }
      final offset = a['offset'] as int?;
      if (offset == null || offset < kInstanceRecordBaseBytes) {
        throw StateError(
          'Instance attribute "$name" has no valid record offset (stale '
          'sidecar).',
        );
      }
      slots.add(
        InstanceAttributeSlot(
          name: name,
          type: type,
          floatOffset: (offset - kInstanceRecordBaseBytes) ~/ 4,
        ),
      );
    }
    return InstanceAttributeSchema(slots);
  }

  final List<InstanceAttributeSlot> attributes;

  /// Floats appended to each instance record, past the fixed 20-float
  /// transform and color block.
  final int floatCount;

  final Map<String, InstanceAttributeSlot> _byName;

  InstanceAttributeSlot? slot(String name) => _byName[name];

  /// Bytes one packed instance record occupies with this schema applied.
  int get recordBytes => kInstanceRecordBaseBytes + floatCount * 4;

  /// Widens [base], the engine's fixed instance-rate buffer, with one
  /// instance-rate input per declared attribute.
  ///
  /// Throws when [base] is not the engine's record, since the attribute
  /// offsets are resolved against that layout and a different one would feed
  /// the shader the wrong bytes.
  VertexBufferDescriptor widen(VertexBufferDescriptor base) {
    if (base.strideInBytes != kInstanceRecordBaseBytes) {
      throw StateError(
        'A material declaring instance_attributes needs the engine instance '
        'record ($kInstanceRecordBaseBytes bytes), but this geometry '
        'describes a ${base.strideInBytes}-byte instance-rate buffer. Drop '
        'the custom instance layout or the instance_attributes declaration.',
      );
    }
    return VertexBufferDescriptor(
      strideInBytes: recordBytes,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        ...base.attributes,
        for (final a in attributes)
          VertexAttributeDescriptor(
            name: a.inputName,
            format: _formatFor(a.components),
            offsetInBytes: kInstanceRecordBaseBytes + a.floatOffset * 4,
          ),
      ],
    );
  }
}

/// Fails a draw whose packed instance data is not the width [schema] expects.
///
/// The instance buffer and the pipeline's vertex layout are chosen separately,
/// so a disagreement would feed the shader whatever the neighboring bytes hold
/// rather than failing.
@internal
void checkInstanceRecordWidth(
  InstanceAttributeSchema? schema,
  int attributeFloats,
) {
  final expected = schema?.floatCount ?? 0;
  if (attributeFloats == expected) return;
  throw StateError(
    'This material expects $expected instance attribute float(s) per '
    'instance, but the instance data carries $attributeFloats. The mesh and '
    'the material disagree about the instance-rate layout.',
  );
}

gpu.VertexFormat _formatFor(int components) => switch (components) {
  1 => gpu.VertexFormat.float32,
  2 => gpu.VertexFormat.float32x2,
  3 => gpu.VertexFormat.float32x3,
  _ => gpu.VertexFormat.float32x4,
};
