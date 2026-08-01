/// Which shader a material binds a uniform block or texture against.
///
/// A block declared in both stages is two bindings, not one, so setting it
/// for the fragment stage alone leaves the vertex stage's copy unset.
/// {@category Materials}
enum ShaderStage {
  /// The vertex shader, when the material supplies one.
  vertex,

  /// The fragment shader.
  fragment,
}

/// The mesh kind a vertex shader runs on.
///
/// A geometry selects the variant it needs, and the engine's standard shader
/// runs for any variant a material does not supply.
/// {@category Materials}
enum MeshVariant {
  /// A static mesh, whose vertices arrive as-is.
  unskinned('unskinned'),

  /// A skinned mesh, whose vertices are posed by joints before the material's
  /// shader sees them.
  skinned('skinned'),

  /// The position-only pass that draws shadow maps and the depth prepass.
  /// Supply this when the vertex stage moves geometry, so its shadow moves
  /// with it.
  depth('depth');

  const MeshVariant(this.name);

  /// The wire name the geometry and the `.fmat` sidecar use.
  final String name;

  /// The variant [name] selects, or [unskinned] for an unknown name.
  static MeshVariant fromName(String name) => switch (name) {
    'skinned' => MeshVariant.skinned,
    'depth' => MeshVariant.depth,
    _ => MeshVariant.unskinned,
  };
}
