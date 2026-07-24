/// How a per-contact friction or restitution value is derived from the
/// two participating materials.
/// {@category Physics}
enum CombineRule { average, min, max, multiply }

/// Surface properties (friction, restitution, density) of a collider.
///
/// Materials are immutable, identity-shared value objects: assign one
/// instance to many colliders and the backend will cook it once.
/// {@category Physics}
class PhysicsMaterial {
  /// Coulomb friction coefficient. Typical range is `[0, 1]`; higher
  /// values produce more resistance to sliding.
  final double friction;

  /// Bounciness, in `[0, 1]`. `0` is fully inelastic; `1` preserves
  /// kinetic energy on bounce.
  final double restitution;

  /// Mass per unit volume. Used by the backend to derive mass and
  /// inertia from the collider's [Shape] when the owning rigid body has
  /// no explicit mass set.
  final double density;

  /// Rule for combining this material's [friction] with the other
  /// participating material's [friction] at a contact.
  final CombineRule frictionCombine;

  /// Rule for combining this material's [restitution] with the other
  /// participating material's [restitution] at a contact.
  final CombineRule restitutionCombine;

  const PhysicsMaterial({
    this.friction = 0.5,
    this.restitution = 0.0,
    this.density = 1.0,
    this.frictionCombine = CombineRule.average,
    this.restitutionCombine = CombineRule.average,
  });

  /// Reasonable defaults: friction `0.5`, restitution `0.0`, density
  /// `1.0`, both combine rules [CombineRule.average].
  static const PhysicsMaterial defaultMaterial = PhysicsMaterial();
}
