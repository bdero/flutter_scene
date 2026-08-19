// Screen-space lens flare: a chain of ghosts mirrored through the screen
// center plus a circular halo, both with radial chromatic dispersion,
// generated from a low bloom mip and added into the chain so the upsample
// stages blur and composite them with the rest of the glow.
//
// The ghost/halo construction follows John Chapman's "Pseudo Lens Flare"
// (https://john-chapman.github.io/2017/11/05/pseudo-lens-flare.html); the
// placement in the bloom pyramid follows Filament's bloom flare stage.

uniform LensFlareInfo {
  // x: intensity. y: ghost count. z: ghost spacing. w: chromatic
  // dispersion in UV units.
  vec4 params0;
  // x: halo radius (UV units). y: halo intensity relative to the ghosts.
  // z: target aspect (width / height). w: unused.
  vec4 params1;
}
flare_info;

// A low mip of the bloom pyramid (thresholded, blurred scene color).
uniform sampler2D source;
// The finished bloom (full-resolution mip), added back here so the flare
// composites into a cleared, write-once target instead of an additively
// blended reload (which some backends drop).
uniform sampler2D base;

in vec2 v_uv;
out vec4 frag_color;

#define MAX_GHOSTS 8

// Samples the source with the r and b channels pulled apart along [dir],
// the cheap fringe real lens elements give off-center flares.
vec3 SampleDistorted(vec2 uv, vec2 dir, float amount) {
  return vec3(
      textureLod(source, uv + dir * amount, 0.0).r,
      textureLod(source, uv, 0.0).g,
      textureLod(source, uv - dir * amount, 0.0).b);
}

void main() {
  // Ghost features mirror through the screen center.
  vec2 uv = vec2(1.0) - v_uv;
  vec2 to_center = vec2(0.5) - uv;
  vec2 dir =
      to_center * inversesqrt(max(dot(to_center, to_center), 1e-6));

  float intensity = flare_info.params0.x;
  int ghost_count = int(flare_info.params0.y);
  vec2 ghost_step = to_center * flare_info.params0.z;
  float dispersion = flare_info.params0.w;

  vec3 result = vec3(0.0);
  for (int i = 0; i < MAX_GHOSTS; i++) {
    if (i >= ghost_count) {
      break;
    }
    vec2 ghost_uv = fract(uv + ghost_step * float(i));
    // Brighter toward the screen center, so ghosts fade out at the edges
    // instead of popping at the border.
    float weight = 1.0 - distance(ghost_uv, vec2(0.5)) / 0.75;
    weight = pow(clamp(weight, 0.0, 1.0), 10.0);
    result += SampleDistorted(ghost_uv, dir, dispersion) * weight;
  }

  // The halo: every pixel samples a fixed distance toward the center, so
  // bright sources smear into a ring of that radius. The offset walks in
  // aspect-corrected space to keep the ring circular on non-square targets.
  float aspect = flare_info.params1.z;
  vec2 corrected = (uv - 0.5) * vec2(aspect, 1.0);
  vec2 halo_dir =
      -corrected * inversesqrt(max(dot(corrected, corrected), 1e-6));
  vec2 halo_uv =
      uv + halo_dir * flare_info.params1.x / vec2(aspect, 1.0);
  float halo_weight = 1.0 - distance(fract(halo_uv), vec2(0.5)) / 0.75;
  halo_weight = pow(clamp(halo_weight, 0.0, 1.0), 5.0);
  result += SampleDistorted(fract(halo_uv), dir, dispersion) *
            (halo_weight * flare_info.params1.y);

  frag_color = vec4(texture(base, v_uv).rgb + result * intensity, 1.0);
}
