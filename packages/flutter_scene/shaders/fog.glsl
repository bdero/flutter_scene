// Distance fog shared by every material shader. Applied per-fragment on the
// linear-HDR premultiplied-alpha color a material produces, before the
// tone-mapping resolve pass, so fog is scene-referred radiance that exposure and
// tone mapping act on along with the rest of the scene.
//
// The FogInfo block is self-contained (it does not depend on either material's
// FragInfo layout) so lit and unlit shaders share one declaration. It is packed
// and bound by EngineLightingUniforms.bindFog. Uses the world-space varyings
// v_position and v_viewvector (= cameraPosition - fragmentPosition).

uniform FogInfo {
  // x: mode (0 none, 1 linear, 2 exponential, 3 exponential-squared)
  // y: enabled (> 0.5)   z: maximum opacity   w: unused
  vec4 params0;
  // x: density   y: start distance   z: end distance   w: cutoff distance
  // (<= 0 disables the cutoff)
  vec4 params1;
  // x: height (reference altitude)   y: height falloff (0 = uniform)
  // z: sun in-scatter strength (0 = off)   w: sun in-scatter exponent
  vec4 params2;
  // rgb: flat fog color (linear)   w: unused
  vec4 color;
  // rgb: directional light color * intensity (linear)   w: has-sun (> 0.5)
  vec4 sun;
  // xyz: directional light travel direction (world space, toward the scene)
  vec4 sun_dir;
}
fog;

// Blends [premult_color] (linear HDR, premultiplied by its own alpha) toward the
// fog color by the distance-based fog factor. Returns the fogged premultiplied
// color; alpha (coverage) is left unchanged so a transparent fragment adds no
// fog (the geometry behind it is fogged by its own, farther fragment).
vec4 ApplyFog(vec4 premult_color) {
  if (fog.params0.y < 0.5) {
    return premult_color;
  }
  int mode = int(fog.params0.x + 0.5);
  if (mode == 0) {
    return premult_color;
  }

  float d = length(v_viewvector); // camera -> fragment distance
  float cutoff = fog.params1.w;
  if (cutoff > 0.0 && d > cutoff) {
    return premult_color; // e.g. exclude an already-hazed skybox / far layer
  }

  float density = fog.params1.x;
  float start = fog.params1.y;
  float end = fog.params1.z;
  float falloff = fog.params2.y;

  float fog_factor;
  if (mode == 1) {
    // Linear near/far.
    fog_factor = clamp((d - start) / max(end - start, 1e-4), 0.0, 1.0);
  } else if (mode == 2) {
    // Exponential, optionally height-modulated. With falloff <= 0 the height
    // integral collapses to a uniform-density path (plain exponential fog).
    float optical;
    if (falloff > 1e-5) {
      // Analytic integral of an exponential height-density profile along the
      // view ray (Beer-Lambert). density(y) = density * exp(-falloff*(y-height)).
      vec3 frag_pos = v_position;
      vec3 camera_pos = v_position + v_viewvector;
      float height = fog.params2.x;
      float density_at_camera = density * exp(-falloff * (camera_pos.y - height));
      float density_at_frag = density * exp(-falloff * (frag_pos.y - height));
      float fh = falloff * (frag_pos.y - camera_pos.y);
      // Average density over the ray's vertical span (the horizontal limit is
      // handled by falling back to the camera-altitude density).
      float per_meter = (abs(fh) > 0.00125)
                            ? (density_at_camera - density_at_frag) / fh
                            : density_at_camera;
      optical = per_meter * max(d - start, 0.0);
    } else {
      optical = density * max(d - start, 0.0);
    }
    fog_factor = 1.0 - exp(-optical);
  } else {
    // Exponential-squared.
    float x = density * max(d - start, 0.0);
    fog_factor = 1.0 - exp(-x * x);
  }
  fog_factor = min(fog_factor, fog.params0.z);
  if (fog_factor <= 0.0) {
    return premult_color;
  }

  vec3 fog_color = fog.color.rgb;
  // Cheap sun in-scatter: brighten the fog toward the directional light, so
  // looking into the sun through fog glows. No volumetrics.
  if (fog.sun.w > 0.5 && fog.params2.z > 0.0) {
    vec3 ray_dir = -normalize(v_viewvector); // camera -> fragment
    vec3 to_sun = -normalize(fog.sun_dir.xyz); // toward the light source
    float sun_amount = max(dot(ray_dir, to_sun), 0.0);
    float glow = pow(sun_amount, fog.params2.w);
    fog_color += fog.sun.rgb * glow * fog.params2.z;
  }

  // Premultiplied-alpha "over": fog color scaled by the fragment's own alpha,
  // coverage unchanged. For opaque (a = 1) this is the intuitive
  // mix(rgb, fog_color, f); for a transparent gap (a = 0) it adds nothing.
  float a = premult_color.a;
  vec3 rgb = mix(premult_color.rgb, fog_color * a, fog_factor);
  return vec4(rgb, a);
}
