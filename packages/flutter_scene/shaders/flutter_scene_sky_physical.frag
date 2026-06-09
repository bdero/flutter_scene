// Built-in physical sky: an analytic single-scattering daylight model (after
// Preetham et al., "A Practical Analytic Model for Daylight") with Rayleigh
// and Mie terms, a zenith-angle optical-mass approximation (no ray march), an
// HDR sun disk attenuated by the atmosphere, and a ground fade below the
// horizon. Driven by the engine's sky vertex shader (`v_ray` is the world
// view direction); outputs linear HDR radiance with premultiplied alpha.

#include <pbr.glsl>  // kPi

uniform PhysicalSkyInfo {
  // xyz = direction toward the sun (world), w = sun angular radius (radians).
  vec4 sun_direction;
  // rgb = Rayleigh tint, w = Rayleigh coefficient.
  vec4 rayleigh;
  // rgb = Mie tint, w = Mie coefficient.
  vec4 mie;
  // x = turbidity, y = Mie eccentricity (forward-scatter g), z = energy.
  vec4 params;
  vec4 ground_color;
}
sky_info;

in vec3 v_ray;

out vec4 frag_color;

const vec3 kUp = vec3(0.0, 1.0, 0.0);
// Effective optical thickness of the molecular and aerosol atmospheres at the
// zenith, in meters.
const float kRayleighZenithSize = 8400.0;
const float kMieZenithSize = 1250.0;

float HenyeyGreensteinPhase(float cos_theta, float g) {
  return (1.0 / (4.0 * kPi)) *
         ((1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

void main() {
  vec3 dir = normalize(v_ray);
  vec3 sun_dir = normalize(sky_info.sun_direction.xyz);

  // The sun's contribution fades as it approaches and crosses the horizon.
  // The base intensity is tuned so a midday sky sits near 1.0 linear
  // luminance under the default scene exposure.
  float sun_zenith_cos = clamp(dot(kUp, sun_dir), -1.0, 1.0);
  float sun_energy = max(0.0, 1.0 - exp(-((kPi * 0.5) - acos(sun_zenith_cos)))) *
                     60.0 * sky_info.params.z;
  float sun_fade = 1.0 - clamp(1.0 - exp(sun_dir.y), 0.0, 1.0);

  // Scattering coefficients. Rayleigh thins as the sun sets (reddening the
  // remaining light); Mie scales with turbidity.
  vec3 rayleigh_beta =
      max(sky_info.rayleigh.w - (1.0 - sun_fade), 0.0) *
      sky_info.rayleigh.rgb * 0.0001;
  vec3 mie_beta =
      sky_info.params.x * sky_info.mie.w * sky_info.mie.rgb * 0.000434;

  // Optical mass along the view ray (zenith-angle approximation; the
  // direction is clamped to the horizon so the pow base stays positive).
  float zenith = acos(max(0.0, dot(kUp, dir)));
  float optical_mass =
      1.0 / (cos(zenith) + 0.00094 * pow(1.6386 - zenith, -1.253));
  vec3 extinction = exp(-(rayleigh_beta * kRayleighZenithSize +
                          mie_beta * kMieZenithSize) *
                        optical_mass);

  // In-scattered light toward the viewer.
  float cos_theta = dot(dir, sun_dir);
  float rayleigh_phase =
      (3.0 / (16.0 * kPi)) * (1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));
  float mie_phase = HenyeyGreensteinPhase(cos_theta, sky_info.params.y);
  vec3 scatter = (rayleigh_beta * rayleigh_phase + mie_beta * mie_phase) /
                 (rayleigh_beta + mie_beta);

  vec3 inscatter = pow(sun_energy * scatter * (1.0 - extinction), vec3(1.5));
  // Re-saturate toward the extinction color at low sun angles (sunsets).
  inscatter *= mix(vec3(1.0),
                   pow(sun_energy * scatter * extinction, vec3(0.5)),
                   clamp(pow(1.0 - sun_zenith_cos, 5.0), 0.0, 1.0));

  // Fade to the ground color below the horizon.
  inscatter *= mix(sky_info.ground_color.rgb, vec3(1.0),
                   smoothstep(-0.1, 0.1, dir.y));

  // HDR sun disk, attenuated by the atmosphere it shines through.
  float disk_outer = cos(sky_info.sun_direction.w);
  float disk_inner = cos(sky_info.sun_direction.w * 0.5);
  float sun_disk = smoothstep(disk_outer, disk_inner, cos_theta);
  vec3 direct = sun_energy * extinction * sun_disk;

  frag_color = vec4(inscatter + direct, 1.0);
}
