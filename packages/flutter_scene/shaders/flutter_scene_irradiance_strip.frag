// Writes the head of the irradiance-field atlas: the environment's diffuse
// spherical-harmonic strip in rows 0 and 1, and the reserved per-probe state
// rows below it.
//
// Folding the strip into the atlas is what lets the field cost no additional
// sampler. Rows 0 and 1 stay byte-identical to the standalone coefficient
// texture the lit shader reads when the field is off, so the receiver's
// fallback path is unchanged.

uniform StripInfo {
  // x: the first atlas row past this head region. The draw covers the whole
  // atlas and discards below it. y: 1 when the traced feed owns the state
  // rows, which it copies in itself.
  vec4 extent;
}
info;

uniform highp sampler2D sh_strip;

out vec4 frag_color;

void main() {
  ivec2 coord = ivec2(floor(gl_FragCoord.xy));
  if (coord.y >= int(info.extent.x)) {
    discard;
  }
  if (coord.y < 2 && coord.x < 9) {
    // A scene with no environment cross-fade binds a single-row strip, where
    // both rows read the primary environment.
    int rows = textureSize(sh_strip, 0).y;
    frag_color = texelFetch(sh_strip, ivec2(coord.x, min(coord.y, rows - 1)),
                            0);
  } else {
    // Per-probe state, a relocation offset in rgb and inactivity in alpha.
    // Zero leaves every probe where the lattice puts it, active.
    // TODO(gi-probe-state): carry a bake's per-probe state too.
    if (info.extent.y > 0.5) {
      discard;
    }
    frag_color = vec4(0.0);
  }
}
