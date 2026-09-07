// Built-in weather sky: the analytic daylight model of the physical sky with a
// procedural cloud layer over it, plus the storm controls a driver component
// animates (overcast darkening and a lightning flash).
//
// The clouds are a flat layer projected onto the view ray rather than a march
// through a volume. A sky is drawn once per frame over every pixel, so a march
// costs more than the rest of the frame's shading put together; a projected
// layer with a shaped FBM gets the silhouette, the wind, and the parallax
// toward the horizon for a handful of noise taps.
//
// Driven by the engine's sky vertex shader (`v_ray` is the world view
// direction); outputs linear HDR radiance with premultiplied alpha.

#include <noise.glsl>
#include <pbr.glsl>  // kPi

uniform WeatherSkyInfo {
  // xyz = direction toward the sun (world), w = sun angular radius (radians).
  vec4 sun_direction;
  // rgb = Rayleigh tint, w = Rayleigh coefficient.
  vec4 rayleigh;
  // rgb = Mie tint, w = Mie coefficient.
  vec4 mie;
  // x = turbidity, y = Mie eccentricity (forward-scatter g), z = energy.
  vec4 params;
  vec4 ground_color;
  // x = coverage (0 clear, 1 overcast), y = density (opacity at full cover),
  // z = layer altitude in the dome projection, w = detail (extra octaves).
  vec4 cloud_params;
  // xy = wind offset in layer space, z = seed, w = softness of the cloud edge.
  vec4 cloud_motion;
  // rgb = the colour lit cloud tops take, a = how far the shadowed underside
  // darkens toward it (0 keeps the lit colour everywhere).
  vec4 cloud_color;
  // x = storm darkening (0 none, 1 fully overcast gloom), y = lightning flash
  // (0 none, 1 full), zw unused.
  vec4 storm;
}
sky_info;

in vec3 v_ray;

out vec4 frag_color;

const vec3 kUp = vec3(0.0, 1.0, 0.0);
const float kRayleighZenithSize = 8400.0;
const float kMieZenithSize = 1250.0;

float HenyeyGreensteinPhase(float cos_theta, float g) {
  return (1.0 / (4.0 * kPi)) *
         ((1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

// Where the view ray meets the cloud layer, in layer space.
//
// The layer sits at a fixed height, so the intersection is `altitude / dir.y`
// along the ray: near the zenith that is a short reach and the texture is
// coarse, and toward the horizon it stretches to the edge of the world, which
// is exactly the compression that makes a flat layer read as a sky rather than
// as a ceiling.
vec2 CloudLayerUv(vec3 dir, float altitude, vec2 wind) {
  float ny = max(dir.y, 0.02);
  return dir.xz * (altitude / ny) + wind;
}

// The cloud field: a shaped FBM in `[0, 1]`, where 0 is clear sky.
//
// Coverage remaps the noise rather than scaling it, so raising it grows the
// existing clouds outward instead of fading a uniform haze up from nothing,
// which is what a coverage dial is expected to do.
float CloudField(vec2 uv, float coverage, float detail, float softness,
                 int seed) {
  int octaves = 3 + int(clamp(detail, 0.0, 1.0) * 3.0);
  float base = NoiseFbm2(uv * 0.35, seed, octaves, 2.0, 0.5) * 0.5 + 0.5;
  // A second, slower field warps the first, which breaks up the regularity
  // FBM alone leaves and gives the billows their curl.
  float warp = NoiseFbm2(uv * 0.12 + vec2(37.1, 11.7), seed + 91, 2, 2.0, 0.5);
  base = mix(base, base + warp * 0.25, 0.6);

  // Coverage is the threshold the field has to clear; softness is how wide
  // the transition across it is.
  float threshold = 1.0 - clamp(coverage, 0.0, 1.0);
  float edge = max(softness, 0.01);
  return smoothstep(threshold - edge, threshold + edge, base);
}

void main() {
  vec3 dir = normalize(v_ray);
  vec3 sun_dir = normalize(sky_info.sun_direction.xyz);

  float sun_zenith_cos = clamp(dot(kUp, sun_dir), -1.0, 1.0);
  float sun_energy = max(0.0, 1.0 - exp(-((kPi * 0.5) - acos(sun_zenith_cos)))) *
                     60.0 * sky_info.params.z;
  float sun_fade = 1.0 - clamp(1.0 - exp(sun_dir.y), 0.0, 1.0);

  vec3 rayleigh_beta =
      max(sky_info.rayleigh.w - (1.0 - sun_fade), 0.0) *
      sky_info.rayleigh.rgb * 0.0001;
  vec3 mie_beta =
      sky_info.params.x * sky_info.mie.w * sky_info.mie.rgb * 0.000434;

  float zenith = acos(max(0.0, dot(kUp, dir)));
  float optical_mass =
      1.0 / (cos(zenith) + 0.00094 * pow(1.6386 - zenith, -1.253));
  vec3 extinction = exp(-(rayleigh_beta * kRayleighZenithSize +
                          mie_beta * kMieZenithSize) *
                        optical_mass);

  float cos_theta = dot(dir, sun_dir);
  float rayleigh_phase =
      (3.0 / (16.0 * kPi)) * (1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));
  float mie_phase = HenyeyGreensteinPhase(cos_theta, sky_info.params.y);
  vec3 scatter = (rayleigh_beta * rayleigh_phase + mie_beta * mie_phase) /
                 (rayleigh_beta + mie_beta);

  vec3 inscatter = pow(sun_energy * scatter * (1.0 - extinction), vec3(1.5));
  inscatter *= mix(vec3(1.0),
                   pow(sun_energy * scatter * extinction, vec3(0.5)),
                   clamp(pow(1.0 - sun_zenith_cos, 5.0), 0.0, 1.0));
  inscatter *= mix(sky_info.ground_color.rgb, vec3(1.0),
                   smoothstep(-0.1, 0.1, dir.y));

  float disk_outer = cos(sky_info.sun_direction.w);
  float disk_inner = cos(sky_info.sun_direction.w * 0.5);
  float sun_disk = smoothstep(disk_outer, disk_inner, cos_theta);
  vec3 direct = sun_energy * extinction * sun_disk;

  vec3 sky = inscatter + direct;

  // A storm drains the sky toward its own extinction colour rather than
  // toward grey, so an overcast noon stays blue-grey and an overcast sunset
  // stays warm.
  float storm = clamp(sky_info.storm.x, 0.0, 1.0);
  sky = mix(sky, sky * vec3(0.28, 0.30, 0.34), storm);

  // --- clouds ------------------------------------------------------------
  float coverage = clamp(sky_info.cloud_params.x, 0.0, 1.0);
  if (coverage > 0.001) {
    vec2 uv = CloudLayerUv(dir, max(sky_info.cloud_params.z, 0.01),
                           sky_info.cloud_motion.xy);
    float field = CloudField(uv, coverage, sky_info.cloud_params.w,
                             sky_info.cloud_motion.w,
                             int(sky_info.cloud_motion.z));

    // Fade the layer out at the horizon: the projection stretches without
    // bound there, and a hard band where it ends is the giveaway that the
    // clouds are a plane.
    float horizon = smoothstep(0.0, 0.16, dir.y);
    float alpha = clamp(field * sky_info.cloud_params.y, 0.0, 1.0) * horizon;

    if (alpha > 0.001) {
      // Lighting the layer: the field's own gradient stands in for depth, so
      // the thin edges facing the sun stay bright and the thick middles go
      // dark, which is the shading that makes a cloud look like a volume.
      float thickness = clamp(field, 0.0, 1.0);
      float toward_sun = clamp(cos_theta * 0.5 + 0.5, 0.0, 1.0);
      float lit = mix(1.0 - thickness * sky_info.cloud_color.a,
                      1.0,
                      toward_sun * (1.0 - storm * 0.6));

      // Clouds are lit by the sun's colour, not by their own; at sunset they
      // have to go orange with everything else.
      vec3 sun_tint = normalize(max(extinction, vec3(0.001)));
      vec3 cloud = sky_info.cloud_color.rgb * lit *
                   mix(vec3(1.0), sun_tint, 0.65) *
                   max(sun_energy * 0.02, 0.05);
      cloud = mix(cloud, cloud * vec3(0.35, 0.36, 0.40), storm);

      // The flash lights the clouds from inside, brightest where they are
      // thickest, which is the opposite of how the sun lights them.
      float flash = max(sky_info.storm.y, 0.0);
      cloud += vec3(0.85, 0.88, 1.0) * flash * thickness * 3.0;

      sky = mix(sky, cloud, alpha);
      // The sun disk is occluded by whatever is in front of it.
      sky -= direct * alpha * (1.0 - flash);
    }
  }

  // A flash also lifts the whole sky a little, since the bolt lights the
  // atmosphere as well as the cloud it came from.
  sky += vec3(0.35, 0.38, 0.5) * max(sky_info.storm.y, 0.0) * 0.4;

  frag_color = vec4(max(sky, vec3(0.0)), 1.0);
}
