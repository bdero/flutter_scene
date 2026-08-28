//------------------------------------------------------------------------------
/// The matrix that carries an object-space normal into world space.
///
/// Positions and tangents transform by the model matrix M, but a normal has to
/// transform by (M^-1)^T to stay perpendicular to the surface it came from.
/// mat3(M) equals (M^-1)^T only for rotation, uniform scale (up to a positive
/// scalar, which the later normalize removes), and reflection, so it is correct
/// for most transforms and wrong for the rest: under non-uniform scale or shear
/// it tilts the normal off the surface, and normalizing does not recover the
/// direction. That error corrupts analytic lighting and IBL alike.
///

mat3 WorldNormalMatrix(mat3 linear) {
  // A collapsed transform (a zero scale on an axis, which is how a node gets
  // hidden by scaling it away) is singular, and inverse() fills every component
  // with infinities that normalize turns into NaN -- a black hole in the
  // lighting rather than the degenerate normal the caller already tolerates.
  // Fall back to the linear part there, which is what shipped before this.
  float det = determinant(linear);
  if (abs(det) < 1e-12) {
    return linear;
  }
  return transpose(inverse(linear));
}
