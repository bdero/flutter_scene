// The runtime view of a material's custom vertex `attributes` declaration:
// the per-vertex inputs its generated vertex shader reads, resolved from the
// `.fmat` sidecar. Geometry supplies them with `Geometry.setCustomAttribute`.

import 'package:flutter/foundation.dart';

/// One declared custom vertex attribute.
@internal
typedef VertexAttributeDeclaration = ({String name, int components});

/// The custom vertex attributes a draw's vertex shader reads, in declaration
/// order.
///
/// Geometry resolves its streams against this: a declared attribute it lacks
/// reads zero, and a stream nobody declared is left out of the layout.
/// Instances are identity-stable for a material's lifetime (a hot reload that
/// changes the declaration builds a new one), so consumers cache on identity.
@internal
class VertexAttributeSchema {
  const VertexAttributeSchema(this.attributes);

  /// Reads no custom attributes: every engine vertex shader, and a material's
  /// position-only depth variant.
  static const VertexAttributeSchema none = VertexAttributeSchema([]);

  final List<VertexAttributeDeclaration> attributes;

  /// Builds a schema from a `.fmat` sidecar, or null when the sidecar predates
  /// the `attributes` entry (it then binds every stream the geometry has).
  static VertexAttributeSchema? fromMetadata(Map<String, Object?> metadata) {
    final raw = metadata['attributes'];
    if (raw is! List) return null;
    if (raw.isEmpty) return none;
    return VertexAttributeSchema([
      for (final entry in raw)
        (
          name: (entry as Map)['name'] as String,
          components: entry['components'] as int,
        ),
    ]);
  }
}
