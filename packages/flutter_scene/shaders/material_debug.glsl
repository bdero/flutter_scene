// Surface debug views. A material's main() fills MaterialInputs through
// Surface(), then asks DebugViewMode() whether a view is active and, when it
// is, writes DebugSurfaceOutput() instead of (or split with) the lit result.
//
// The output is display-referred: the resolve pass copies these pixels
// through untouched (no exposure, tone mapping, or display encoding), so a
// scalar of 0.5 reads back as 0.5 and a color channel is sRGB-encoded here.
// Colors encode, directions map through 0.5 * v + 0.5, scalars go out raw
// after the range remap and gain. Channel ids match SurfaceDebugChannel on
// the Dart side; keep the two lists in step.
//
// Requires material_varyings.glsl and material_inputs.glsl. Uniform control
// flow everywhere: the split test is per pixel, so a caller that wants the
// lit result on one side evaluates both and selects (DebugViewSplit); the
// lit path never runs under the non-uniform split branch.

#ifndef MATERIAL_DEBUG_GLSL_
#define MATERIAL_DEBUG_GLSL_

uniform DebugViewInfo {
  // x: channel id (0 is off). y: split x in pixels, negative for no split;
  // pixels at or right of it show the view. z: gain. w: out-of-range policy
  // for scalar channels, 0 clamp, 1 black out, 2 cycle.
  vec4 view;
  // x, y: scalar remap range (min, max). z: object seed, w: material seed,
  // for the identity channels.
  vec4 params;
}
debug_view_info;

// Geometry.
#define DEBUG_CHANNEL_WORLD_NORMAL 1.0
#define DEBUG_CHANNEL_SHADING_NORMAL 2.0
#define DEBUG_CHANNEL_TANGENT 3.0
#define DEBUG_CHANNEL_BITANGENT 4.0
#define DEBUG_CHANNEL_TANGENT_HANDEDNESS 5.0
#define DEBUG_CHANNEL_UV0 6.0
#define DEBUG_CHANNEL_UV1 7.0
#define DEBUG_CHANNEL_VERTEX_COLOR 8.0
#define DEBUG_CHANNEL_VIEW_DIRECTION 9.0
#define DEBUG_CHANNEL_WORLD_POSITION 10.0
#define DEBUG_CHANNEL_FACE_ORIENTATION 11.0
#define DEBUG_CHANNEL_UV0_CHECKER 12.0
#define DEBUG_CHANNEL_UV1_CHECKER 13.0
// Surface.
#define DEBUG_CHANNEL_BASE_COLOR 20.0
#define DEBUG_CHANNEL_ALPHA 21.0
#define DEBUG_CHANNEL_METALLIC 22.0
#define DEBUG_CHANNEL_ROUGHNESS 23.0
#define DEBUG_CHANNEL_SPECULAR 24.0
#define DEBUG_CHANNEL_OCCLUSION 25.0
#define DEBUG_CHANNEL_EMISSIVE 26.0
// Physical.
#define DEBUG_CHANNEL_CLEARCOAT 40.0
#define DEBUG_CHANNEL_CLEARCOAT_ROUGHNESS 41.0
#define DEBUG_CHANNEL_CLEARCOAT_NORMAL 42.0
#define DEBUG_CHANNEL_SHEEN_COLOR 43.0
#define DEBUG_CHANNEL_SHEEN_ROUGHNESS 44.0
#define DEBUG_CHANNEL_TRANSMISSION 45.0
#define DEBUG_CHANNEL_TRANSMISSION_COLOR 46.0
#define DEBUG_CHANNEL_DIFFUSE_TRANSMISSION 47.0
#define DEBUG_CHANNEL_ANISOTROPY 48.0
#define DEBUG_CHANNEL_ANISOTROPY_DIRECTION 49.0
#define DEBUG_CHANNEL_IRIDESCENCE 50.0
#define DEBUG_CHANNEL_IRIDESCENCE_THICKNESS 51.0
#define DEBUG_CHANNEL_IOR 52.0
#define DEBUG_CHANNEL_SPECULAR_COLOR 53.0
// Identity.
#define DEBUG_CHANNEL_OBJECT_COLOR 60.0
#define DEBUG_CHANNEL_MATERIAL_COLOR 61.0
// Validation.
#define DEBUG_CHANNEL_VALIDATION 70.0
#define DEBUG_CHANNEL_NON_FINITE 71.0
#define DEBUG_CHANNEL_BASE_COLOR_RANGE 72.0
#define DEBUG_CHANNEL_METALLIC_BINARY 73.0
#define DEBUG_CHANNEL_NORMAL_LENGTH 74.0
#define DEBUG_CHANNEL_MISSING_TANGENT 75.0
#define DEBUG_CHANNEL_UV_RANGE 76.0
// Custom.
#define DEBUG_CHANNEL_CUSTOM 80.0

// 0 when no view is active, 1 for a whole-viewport view, 2 for a split.
float DebugViewMode() {
  if (debug_view_info.view.x < 0.5) {
    return 0.0;
  }
  return debug_view_info.view.y < 0.0 ? 1.0 : 2.0;
}

// The split select: the view right of the split line, the lit result left.
vec4 DebugViewSplit(vec4 debug, vec4 lit) {
  return gl_FragCoord.x >= debug_view_info.view.y ? debug : lit;
}

vec3 DebugLinearToSRGB(vec3 c) {
  c = max(c, vec3(0.0));
  return mix(c * 12.92,
             1.055 * pow(max(c, vec3(0.0031308)), vec3(1.0 / 2.4)) - 0.055,
             step(0.0031308, c));
}

// Scalar channel encoding: remap through the range, apply the out-of-range
// policy, then the gain.
vec3 DebugScalar(float v) {
  float lo = debug_view_info.params.x;
  float hi = debug_view_info.params.y;
  float t = (v - lo) / max(hi - lo, 1e-6);
  float policy = debug_view_info.view.w;
  if (policy > 1.5) {
    t = fract(t);
  } else if (policy > 0.5) {
    t = t < 0.0 || t > 1.0 ? 0.0 : t;
  } else {
    t = clamp(t, 0.0, 1.0);
  }
  return vec3(t * debug_view_info.view.z);
}

// Direction encoding, unit vector to [0, 1].
vec3 DebugDirection(vec3 d) {
  float len = length(d);
  d = len > 1e-6 ? d / len : vec3(0.0);
  return (d * 0.5 + 0.5) * debug_view_info.view.z;
}

// Linear color encoding, display-encoded so the pixel matches the value an
// author typed.
vec3 DebugColor(vec3 c) {
  return DebugLinearToSRGB(c * debug_view_info.view.z);
}

// Screen-space 8 px checkerboard, the "this channel does not exist on this
// material" pattern. Distinct from black, which is a real value.
vec3 DebugUnavailable() {
  vec2 cell = floor(gl_FragCoord.xy / 8.0);
  float parity = mod(cell.x + cell.y, 2.0);
  return vec3(mix(0.22, 0.32, parity));
}

// Diagonal magenta stripes, the "this material does not participate" pattern
// drawn by the fallback shader for every material channel.
vec3 DebugNotParticipating() {
  float band = mod(floor((gl_FragCoord.x + gl_FragCoord.y) / 6.0), 2.0);
  return mix(vec3(0.2, 0.0, 0.2), vec3(1.0, 0.0, 1.0), band);
}

// A stable, well-spread color for an integer seed (golden-ratio hue walk),
// with no trig so every backend agrees.
vec3 DebugSeedColor(float seed) {
  float h = fract(seed * 0.618033988749895);
  float s = 0.55 + 0.35 * fract(seed * 0.381966011250105);
  float v = 0.85;
  vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
  vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
  return v * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

// The lettered-grid stand-in: a colored checker whose cell tint walks with
// the integer part, so a mirrored or tiled mapping reads at a glance.
vec3 DebugUvChecker(vec2 uv) {
  vec2 cell = floor(uv * 8.0);
  float parity = mod(cell.x + cell.y, 2.0);
  vec3 tint = DebugSeedColor(cell.x + cell.y * 8.0);
  vec3 grid = mix(vec3(0.15), vec3(0.9), parity);
  vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
  float in_range = inside.x * inside.y;
  return mix(vec3(0.6, 0.0, 0.0), mix(grid, tint, 0.35), in_range);
}

// Flags on the RenderDoc scheme: red for NaN, green for infinity, blue for a
// negative color, and the given base tone otherwise.
vec3 DebugNonFinite(MaterialInputs material, vec3 base) {
  vec3 probe = material.base_color.rgb + material.normal + material.emissive +
               vec3(material.metallic + material.roughness +
                    material.occlusion);
  bool nan = any(isnan(probe));
  bool inf = any(isinf(probe));
  bool negative = min(min(material.base_color.r, material.base_color.g),
                      material.base_color.b) < 0.0 ||
                  min(min(material.emissive.r, material.emissive.g),
                      material.emissive.b) < 0.0;
  if (nan) {
    return vec3(1.0, 0.0, 0.0);
  }
  if (inf) {
    return vec3(0.0, 1.0, 0.0);
  }
  if (negative) {
    return vec3(0.0, 0.25, 1.0);
  }
  return base;
}

// Dielectric albedo outside the plausible sRGB 30..240 band (linear 0.013 to
// 0.87 luminance): blue for too dark, red for too bright. Metals pass.
vec3 DebugBaseColorRange(MaterialInputs material, vec3 base) {
  float luma = dot(material.base_color.rgb, vec3(0.2126, 0.7152, 0.0722));
  if (material.metallic > 0.5) {
    return base;
  }
  if (luma < 0.013) {
    return vec3(0.1, 0.3, 1.0);
  }
  if (luma > 0.87) {
    return vec3(1.0, 0.2, 0.1);
  }
  return base;
}

// A metallic value that is neither dielectric nor conductor.
vec3 DebugMetallicBinary(MaterialInputs material, vec3 base) {
  return material.metallic > 0.05 && material.metallic < 0.95
      ? vec3(1.0, 0.85, 0.0)
      : base;
}

// An interpolated normal far from unit length (a zero source normal, or vertex
// normals that nearly cancel across the triangle).
vec3 DebugNormalLength(vec3 base) {
  float len = length(v_normal);
  return len < 0.3 || len > 1.7 ? vec3(1.0, 0.5, 0.0) : base;
}

// A perturbed shading normal on a vertex with no tangent: the normal map is
// running on the derivative fallback frame.
vec3 DebugMissingTangent(MaterialInputs material, vec3 base) {
  bool no_tangent = dot(v_tangent.xyz, v_tangent.xyz) < 1e-8;
  bool perturbed =
      dot(normalize(material.normal), normalize(GetWorldNormal())) < 0.999;
  return no_tangent && perturbed ? vec3(1.0, 0.0, 0.6) : base;
}

// A primary UV outside the unit square.
vec3 DebugUvRange(vec3 base) {
  vec2 uv = GetUV0();
  bool outside = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
  return outside ? vec3(0.9, 0.9, 0.0) : base;
}

vec3 DebugPhysical(MaterialInputs material, float channel) {
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  if (channel == DEBUG_CHANNEL_CLEARCOAT) {
    return DebugScalar(material.clearcoat);
  } else if (channel == DEBUG_CHANNEL_CLEARCOAT_ROUGHNESS) {
    return DebugScalar(material.clearcoat_roughness);
  } else if (channel == DEBUG_CHANNEL_CLEARCOAT_NORMAL) {
    return DebugDirection(material.clearcoat_normal);
  } else if (channel == DEBUG_CHANNEL_SHEEN_COLOR) {
    return DebugColor(material.sheen_color);
  } else if (channel == DEBUG_CHANNEL_SHEEN_ROUGHNESS) {
    return DebugScalar(material.sheen_roughness);
  } else if (channel == DEBUG_CHANNEL_TRANSMISSION) {
    return DebugScalar(material.transmission);
  } else if (channel == DEBUG_CHANNEL_TRANSMISSION_COLOR) {
    return DebugColor(material.transmission_color);
  } else if (channel == DEBUG_CHANNEL_DIFFUSE_TRANSMISSION) {
    return DebugScalar(material.diffuse_transmission);
  } else if (channel == DEBUG_CHANNEL_ANISOTROPY) {
    return DebugScalar(material.anisotropy);
  } else if (channel == DEBUG_CHANNEL_ANISOTROPY_DIRECTION) {
    return DebugDirection(vec3(material.anisotropy_direction, 0.0));
  } else if (channel == DEBUG_CHANNEL_IRIDESCENCE) {
    return DebugScalar(material.iridescence);
  } else if (channel == DEBUG_CHANNEL_IRIDESCENCE_THICKNESS) {
    return DebugScalar(material.iridescence_thickness);
  } else if (channel == DEBUG_CHANNEL_IOR) {
    return DebugScalar(material.ior);
  } else if (channel == DEBUG_CHANNEL_SPECULAR_COLOR) {
    return DebugColor(material.specular_color * material.specular_weight);
  }
#endif
  return DebugUnavailable();
}

// The display-referred color for the active channel. Alpha is always 1: a
// view replaces the surface, it never blends with what is behind it.
vec4 DebugSurfaceOutput(MaterialInputs material) {
  float channel = debug_view_info.view.x;
  vec3 out_color;
  if (channel < 20.0) {
    // Geometry channels come from the varyings, so the fallback shader can
    // serve them too.
    if (channel == DEBUG_CHANNEL_WORLD_NORMAL) {
      out_color = DebugDirection(GetWorldNormal());
    } else if (channel == DEBUG_CHANNEL_SHADING_NORMAL) {
      out_color = DebugDirection(material.normal);
    } else if (channel == DEBUG_CHANNEL_TANGENT) {
      out_color = DebugDirection(v_tangent.xyz);
    } else if (channel == DEBUG_CHANNEL_BITANGENT) {
      out_color = DebugDirection(cross(normalize(v_normal), v_tangent.xyz) *
                                 (v_tangent.w < 0.0 ? -1.0 : 1.0));
    } else if (channel == DEBUG_CHANNEL_TANGENT_HANDEDNESS) {
      out_color = vec3(v_tangent.w < 0.0 ? 0.0 : 1.0);
    } else if (channel == DEBUG_CHANNEL_UV0) {
      out_color = vec3(clamp(GetUV0(), 0.0, 1.0), 0.0) * debug_view_info.view.z;
    } else if (channel == DEBUG_CHANNEL_UV1) {
      out_color = vec3(clamp(GetUV1(), 0.0, 1.0), 0.0) * debug_view_info.view.z;
    } else if (channel == DEBUG_CHANNEL_VERTEX_COLOR) {
      out_color = DebugColor(v_color.rgb);
    } else if (channel == DEBUG_CHANNEL_VIEW_DIRECTION) {
      out_color = DebugDirection(GetViewDirection());
    } else if (channel == DEBUG_CHANNEL_WORLD_POSITION) {
      vec3 p = v_position;
      out_color = vec3(DebugScalar(p.x).x, DebugScalar(p.y).x,
                       DebugScalar(p.z).x);
    } else if (channel == DEBUG_CHANNEL_FACE_ORIENTATION) {
      out_color = gl_FrontFacing ? vec3(0.45, 0.6, 1.0) : vec3(1.0, 0.15, 0.1);
    } else if (channel == DEBUG_CHANNEL_UV0_CHECKER) {
      out_color = DebugUvChecker(GetUV0());
    } else if (channel == DEBUG_CHANNEL_UV1_CHECKER) {
      out_color = DebugUvChecker(GetUV1());
    } else {
      out_color = DebugUnavailable();
    }
    return vec4(out_color, 1.0);
  }
#ifdef FLUTTER_SCENE_DEBUG_FALLBACK
  // A raw shader that did not opt in: the identity channels still hold,
  // everything that needs the surface description does not.
  if (channel == DEBUG_CHANNEL_OBJECT_COLOR) {
    return vec4(DebugSeedColor(debug_view_info.params.z), 1.0);
  } else if (channel == DEBUG_CHANNEL_MATERIAL_COLOR) {
    return vec4(DebugSeedColor(debug_view_info.params.w), 1.0);
  }
  return vec4(DebugNotParticipating(), 1.0);
#else
  if (channel < 40.0) {
    if (channel == DEBUG_CHANNEL_BASE_COLOR) {
      out_color = DebugColor(material.base_color.rgb);
    } else if (channel == DEBUG_CHANNEL_ALPHA) {
      out_color = DebugScalar(material.base_color.a);
    } else if (channel == DEBUG_CHANNEL_METALLIC) {
      out_color = DebugScalar(material.metallic);
    } else if (channel == DEBUG_CHANNEL_ROUGHNESS) {
      out_color = DebugScalar(material.roughness);
    } else if (channel == DEBUG_CHANNEL_SPECULAR) {
      out_color = DebugScalar(material.specular);
    } else if (channel == DEBUG_CHANNEL_OCCLUSION) {
      out_color = DebugScalar(material.occlusion);
    } else if (channel == DEBUG_CHANNEL_EMISSIVE) {
      out_color = DebugColor(material.emissive);
    } else {
      out_color = DebugUnavailable();
    }
  } else if (channel < 60.0) {
    out_color = DebugPhysical(material, channel);
  } else if (channel < 70.0) {
    if (channel == DEBUG_CHANNEL_OBJECT_COLOR) {
      out_color = DebugSeedColor(debug_view_info.params.z);
    } else if (channel == DEBUG_CHANNEL_MATERIAL_COLOR) {
      out_color = DebugSeedColor(debug_view_info.params.w);
    } else {
      out_color = DebugUnavailable();
    }
  } else if (channel < 80.0) {
    // Validation channels paint the flag over a flat gray so the geometry
    // stays readable. The combined view stacks them, worst flag first.
    vec3 base = vec3(0.35);
    if (channel == DEBUG_CHANNEL_VALIDATION) {
      out_color = DebugUvRange(base);
      out_color = DebugMissingTangent(material, out_color);
      out_color = DebugNormalLength(out_color);
      out_color = DebugMetallicBinary(material, out_color);
      out_color = DebugBaseColorRange(material, out_color);
      out_color = DebugNonFinite(material, out_color);
    } else if (channel == DEBUG_CHANNEL_NON_FINITE) {
      out_color = DebugNonFinite(material, base);
    } else if (channel == DEBUG_CHANNEL_BASE_COLOR_RANGE) {
      out_color = DebugBaseColorRange(material, base);
    } else if (channel == DEBUG_CHANNEL_METALLIC_BINARY) {
      out_color = DebugMetallicBinary(material, base);
    } else if (channel == DEBUG_CHANNEL_NORMAL_LENGTH) {
      out_color = DebugNormalLength(base);
    } else if (channel == DEBUG_CHANNEL_MISSING_TANGENT) {
      out_color = DebugMissingTangent(material, base);
    } else if (channel == DEBUG_CHANNEL_UV_RANGE) {
      out_color = DebugUvRange(base);
    } else {
      out_color = DebugUnavailable();
    }
  } else if (channel == DEBUG_CHANNEL_CUSTOM) {
    out_color = material.debug * debug_view_info.view.z;
  } else {
    out_color = DebugUnavailable();
  }
  return vec4(out_color, 1.0);
#endif
}

#endif // MATERIAL_DEBUG_GLSL_
