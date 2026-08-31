//------------------------------------------------------------------------------
/// The matrix that carries an object-space normal into world space.
///
/// Positions and tangents transform by the model matrix M, but a normal has to
/// transform by (M^-1)^T to stay perpendicular to the surface it came from.
/// mat3(M) equals (M^-1)^T only for rotation, uniform scale (up to a positive
/// scalar, which the later normalize removes), and reflection, so it is correct
/// for most transforms and wrong for the rest. Under non-uniform scale or shear
/// it tilts the normal off the surface, and normalizing does not recover the
/// direction, which corrupts analytic lighting and IBL alike.
///
/// Built from cofactors rather than transpose(inverse(M)). The two differ only
/// by a factor of the determinant, whose magnitude the later normalize removes
/// and whose sign this applies directly, so the result is the same normal for
/// less work and with no division to go singular. It also keeps the helper off
/// inverse(), which GLSL ES 1.00 does not have.

mat3 WorldNormalMatrix(mat3 linear) {
  // Columns of the transposed cofactor matrix, which is the adjugate
  // transposed and so the inverse-transpose scaled by the determinant.
  mat3 cofactor = mat3(cross(linear[1], linear[2]),
                       cross(linear[2], linear[0]),
                       cross(linear[0], linear[1]));

  // The determinant falls out of the cofactors already computed. Testing it
  // against zero rather than an epsilon keeps the helper scale-invariant: a
  // determinant scales as the cube of the model's scale, so any fixed
  // threshold would reject a legitimately small model (1e-12 rejects a
  // uniform scale of 1e-4) and silently hand back the wrong normal.
  float det = dot(linear[0], cofactor[0]);
  if (det == 0.0) {
    // A collapsed transform (a zero scale on an axis, which is how a node gets
    // hidden by scaling it away) has no inverse and no meaningful normal. Fall
    // back to the linear part, which is what shipped before this.
    return linear;
  }
  return cofactor * sign(det);
}
