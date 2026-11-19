// Parallax occlusion mapping, shared by the lit parallax entries, the
// silhouette coverage and depth shaders, and `.fmat` materials.
//
// The height field rides the alpha channel of the normal texture (1 at the
// surface, 0 at the deepest point), so it costs no sampler. The view ray is
// marched through it in tangent space and every material texture is then
// sampled where the ray lands.
//
// The functions are plain and cost nothing until called. The ParallaxInfo
// block exists only under FLUTTER_SCENE_PARALLAX_OCCLUSION, so shaders built
// without parallax keep their interface.
//
// Requires material_varyings.glsl and normals.glsl.

#ifndef FLUTTER_SCENE_PARALLAX_GLSL_
#define FLUTTER_SCENE_PARALLAX_GLSL_

// The most layers one march takes, so the loop has a constant bound.
const int kParallaxMaxSteps = 64;

// Secant refinement iterations after the linear search. Removes the terracing
// a single interpolation leaves between layers.
const int kParallaxRefinements = 3;

// Samples along the light ray for self-shadowing.
const int kParallaxShadowSamples = 8;

// The march state in the normal slot's UV space.
struct ParallaxRay {
  // The undisplaced UV the march starts from.
  highp vec2 uv;
  // UV travel per unit of depth (the full height range is depth 1).
  highp vec2 uv_per_depth;
  // The explicit mip level every tap reads, taken once from the undisplaced
  // UV so the loop needs no derivatives.
  highp float lod;
  // Fades the effect out where the march would cross under a texel or two,
  // 0 to 1. Multiplies the depth, so the offset stays continuous.
  highp float fade;
  // The field's depth in UV units after the fade.
  highp float depth_scale;
  // The tangent frame, unit length, for carrying other directions into
  // tangent space (the light for self-shadowing).
  highp vec3 tangent;
  highp vec3 bitangent;
  highp vec3 normal;
};

// A march result.
struct ParallaxHit {
  // Add to the undisplaced UV for every texture lookup of the surface.
  highp vec2 offset;
  // Hit depth, 0 at the surface and 1 at the deepest point of the field.
  highp float depth;
};

// Converts a world direction into the march's UV-and-height space: x and y
// per unit of UV, z along the normal. The frame's bitangent points against V
// (glTF normal maps are +Y up while V grows down), so V travel flips.
highp vec3 ParallaxTangentDirection(ParallaxRay ray, highp vec3 direction) {
  return vec3(dot(direction, ray.tangent), -dot(direction, ray.bitangent),
              dot(direction, ray.normal));
}

// Sets up a march from the undisplaced `uv` (the normal slot's transformed
// UV) for a viewer along `view_dir` (unit, from the surface toward the eye).
// `view_vector` is the unnormalized camera minus position vector the tangent
// frame differentiates. `scale` is the field's depth in UV units.
//
// Call it in uniform control flow: it takes screen-space derivatives.
ParallaxRay ParallaxBeginRay(sampler2D height_tex, vec3 normal,
                             highp vec3 view_vector, highp vec3 view_dir,
                             highp vec2 uv, float scale) {
  ParallaxRay ray;
  ray.uv = uv;
  mat3 frame = TangentFrame(normal, -view_vector, uv);
  // The derivative frame is only scale-invariant, so unitize before
  // projecting. The floors keep a degenerate frame finite.
  ray.tangent = frame[0] * inversesqrt(max(dot(frame[0], frame[0]), 1e-20));
  ray.bitangent = frame[1] * inversesqrt(max(dot(frame[1], frame[1]), 1e-20));
  ray.normal = normal;
  highp vec3 view_ts = ParallaxTangentDirection(ray, view_dir);
  // A grazing ray crosses far per unit of depth; floor the slope so the
  // march spans a bounded distance instead of smearing.
  highp vec2 travel = view_ts.xy / max(view_ts.z, 0.05) * scale;

  highp vec2 size = vec2(textureSize(height_tex, 0));
  highp vec2 dx = dFdx(uv) * size;
  highp vec2 dy = dFdy(uv) * size;
  ray.lod = max(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 1e-8)), 0.0);
  // Texels the full march crosses at that mip. Under one, the relief is
  // smaller than what the texture can show, so fade it out by three.
  highp float texels = length(travel * size) * exp2(-ray.lod);
  ray.fade = clamp((texels - 1.0) * 0.5, 0.0, 1.0);
  ray.uv_per_depth = travel * ray.fade;
  ray.depth_scale = scale * ray.fade;
  return ray;
}

// The layer count a march takes: one per texel crossed, at most `max_steps`.
int ParallaxLayerCount(sampler2D height_tex, ParallaxRay ray, int max_steps) {
  highp vec2 size = vec2(textureSize(height_tex, 0));
  highp float texels = length(ray.uv_per_depth * size) * exp2(-ray.lod);
  return clamp(int(ceil(texels)), 2, max_steps);
}

highp float ParallaxSurfaceDepth(sampler2D height_tex, ParallaxRay ray,
                                 highp float depth) {
  return 1.0 -
         textureLod(height_tex, ray.uv - ray.uv_per_depth * depth, ray.lod).a;
}

// Marches `ray` through the field in `steps` layers, then refines the
// crossing with a few secant steps.
ParallaxHit ParallaxMarch(sampler2D height_tex, ParallaxRay ray, int steps) {
  ParallaxHit hit;
  hit.offset = vec2(0.0);
  hit.depth = 0.0;
  if (ray.fade <= 0.0) return hit;
  highp float layer = 1.0 / float(steps);
  highp float depth = 0.0;
  highp float surface = ParallaxSurfaceDepth(height_tex, ray, 0.0);
  highp float previous_depth = 0.0;
  highp float previous_surface = surface;
  // Constant bound with a dynamic break, the loop shape every backend
  // accepts.
  for (int i = 0; i < kParallaxMaxSteps; i++) {
    if (i >= steps || depth >= surface) break;
    previous_depth = depth;
    previous_surface = surface;
    depth += layer;
    surface = ParallaxSurfaceDepth(height_tex, ray, depth);
  }
  // Above the field at the previous layer (positive) and on or below it at
  // this one. A hit on the first tap has nothing to refine.
  highp float d0 = previous_depth;
  highp float f0 = previous_surface - previous_depth;
  highp float d1 = depth;
  highp float f1 = surface - depth;
  if (d1 > 0.0) {
    for (int i = 0; i < kParallaxRefinements; i++) {
      highp float t = f0 / max(f0 - f1, 1e-6);
      highp float d = mix(d0, d1, clamp(t, 0.0, 1.0));
      highp float f = ParallaxSurfaceDepth(height_tex, ray, d) - d;
      if (f > 0.0) {
        d0 = d;
        f0 = f;
      } else {
        d1 = d;
        f1 = f;
      }
    }
    depth = mix(d0, d1, clamp(f0 / max(f0 - f1, 1e-6), 0.0, 1.0));
  }
  hit.depth = depth;
  hit.offset = -ray.uv_per_depth * depth;
  return hit;
}

#ifndef FLUTTER_SCENE_NO_VIEW_INFO
// A march for `.fmat` Surface() code, from the geometric normal and the
// engine view (GetViewDirection), so a cutout material's depth passes march
// the view of the camera they render from (the light's, for a directional
// shadow).
// TODO(parallax-fmat-punctual-shadow): spot and point shadow passes still
// march toward the scene camera, since GetViewDirection's perspective path
// reads v_viewvector, which those passes leave aimed at it.
ParallaxRay ParallaxBeginSurfaceRay(sampler2D height_tex, highp vec2 uv,
                                    float scale) {
  return ParallaxBeginRay(height_tex, GetWorldNormal(), v_viewvector,
                          GetViewDirection(), uv, scale);
}

// One-call march for `.fmat` authors: the UV offset to add to `uv` for every
// texture lookup of the surface. `scale` is the field's depth in UV units and
// `max_steps` caps the layers (the count otherwise follows the texels
// crossed). Call it in uniform control flow.
highp vec2 ParallaxOcclusionOffset(sampler2D height_tex, highp vec2 uv,
                                   float scale, int max_steps) {
  ParallaxRay ray = ParallaxBeginSurfaceRay(height_tex, uv, scale);
  return ParallaxMarch(height_tex, ray,
                       ParallaxLayerCount(height_tex, ray, max_steps))
      .offset;
}
#endif  // FLUTTER_SCENE_NO_VIEW_INFO

// Soft self-shadowing inside the relief: marches from the hit toward the
// light along `light_dir` (unit, world space, from the surface toward the
// light) and returns visibility, 1 lit to 0 shadowed. The blocker nearest the
// hit counts most, which softens the shadow with distance.
float ParallaxSelfShadow(sampler2D height_tex, ParallaxRay ray,
                         ParallaxHit hit, highp vec3 light_dir) {
  highp vec3 light_ts = ParallaxTangentDirection(ray, light_dir);
  highp float height = 1.0 - hit.depth;
  if (light_ts.z <= 0.0 || height >= 0.999 || ray.fade <= 0.0) return 1.0;
  // UV travel per unit of height toward the light.
  highp vec2 uv_per_height =
      light_ts.xy / max(light_ts.z, 0.05) * ray.depth_scale;
  highp vec2 hit_uv = ray.uv + hit.offset;
  highp float blocked = 0.0;
  for (int i = 1; i <= kParallaxShadowSamples; i++) {
    highp float t = float(i) / float(kParallaxShadowSamples);
    highp float ray_height = mix(height, 1.0, t);
    highp vec2 uv =
        hit_uv + uv_per_height * (ray_height - height);
    highp float field = textureLod(height_tex, uv, ray.lod).a;
    blocked = max(blocked, (field - ray_height) * (1.0 - t));
  }
  return 1.0 - clamp(blocked * 6.0, 0.0, 1.0);
}

// The depth along the ray where it leaves the silhouette box [lo, hi] in the
// normal slot's UV space. Large when the ray never leaves it.
highp float ParallaxExitDepth(ParallaxRay ray, highp vec2 lo, highp vec2 hi) {
  // uv(depth) = ray.uv - uv_per_depth * depth.
  highp vec2 velocity = -ray.uv_per_depth;
  highp float exit_depth = 1e9;
  if (velocity.x > 1e-12) {
    exit_depth = min(exit_depth, (hi.x - ray.uv.x) / velocity.x);
  } else if (velocity.x < -1e-12) {
    exit_depth = min(exit_depth, (lo.x - ray.uv.x) / velocity.x);
  }
  if (velocity.y > 1e-12) {
    exit_depth = min(exit_depth, (hi.y - ray.uv.y) / velocity.y);
  } else if (velocity.y < -1e-12) {
    exit_depth = min(exit_depth, (lo.y - ray.uv.y) / velocity.y);
  }
  return max(exit_depth, 0.0);
}

// Silhouette bounds in the normal slot's UV space for `uv`: the box itself
// (mode 1), or the grid tile `uv` sits in (mode 2, `box.zw` the tile size).
void ParallaxSilhouetteBox(highp vec4 box, float mode, highp vec2 uv,
                           out highp vec2 lo, out highp vec2 hi) {
  if (mode > 1.5) {
    highp vec2 tile = max(box.zw, vec2(1e-6));
    lo = floor(uv / tile) * tile;
    hi = lo + tile;
  } else {
    lo = box.xy;
    hi = box.zw;
  }
}

// Whether the ray hit the field before leaving the silhouette box. A fragment
// for which this is false shows whatever is behind the surface.
bool ParallaxInsideSilhouette(ParallaxRay ray, ParallaxHit hit,
                              highp vec4 box, float mode) {
  if (mode < 0.5) return true;
  highp vec2 lo;
  highp vec2 hi;
  ParallaxSilhouetteBox(box, mode, ray.uv, lo, hi);
  return hit.depth <= ParallaxExitDepth(ray, lo, hi);
}

// Maps a UV offset measured in a slot's transformed space back to the raw
// channel, undoing the transform's rotation and scale (a translation does not
// move an offset).
highp vec2 UntransformMaterialUvOffset(highp vec2 offset, highp vec4 transform,
                                       vec2 rotation) {
  highp vec2 unrotated =
      vec2(rotation.x * offset.x - rotation.y * offset.y,
           rotation.y * offset.x + rotation.x * offset.y);
  highp vec2 scale = transform.zw;
  scale.x = scale.x != 0.0 ? scale.x : 1.0;
  scale.y = scale.y != 0.0 ? scale.y : 1.0;
  return unrotated / scale;
}

// Maps a raw-channel UV offset into a slot's transformed space, its scale and
// then rotation, the linear part of ApplyMaterialUvTransform.
highp vec2 TransformMaterialUvOffset(highp vec2 offset, highp vec4 transform,
                                     vec2 rotation) {
  highp vec2 scaled = offset * transform.zw;
  return vec2(rotation.x * scaled.x + rotation.y * scaled.y,
              -rotation.y * scaled.x + rotation.x * scaled.y);
}

#ifdef FLUTTER_SCENE_PARALLAX_OCCLUSION
// The parallax controls, bound by the engine for the parallax entries only.
uniform ParallaxInfo {
  // x: field depth in the normal slot's UV units. y: most layers per march.
  // z: self-shadow strength, 0 off. w: silhouette mode, 0 none, 1 a UV box,
  // 2 grid tiles.
  highp vec4 params;
  // The silhouette box, xy its low and zw its high corner, or zw the tile
  // size under the tile mode. In the normal slot's UV space.
  highp vec4 silhouette;
}
parallax_info;

// Marches the engine parallax controls from `uv`.
ParallaxRay ParallaxBeginEngineRay(sampler2D height_tex, vec3 normal,
                                   highp vec3 view_vector,
                                   highp vec3 view_dir, highp vec2 uv) {
  return ParallaxBeginRay(height_tex, normal, view_vector, view_dir, uv,
                          parallax_info.params.x);
}

ParallaxHit ParallaxEngineMarch(sampler2D height_tex, ParallaxRay ray) {
  return ParallaxMarch(
      height_tex, ray,
      ParallaxLayerCount(height_tex, ray,
                         int(parallax_info.params.y + 0.5)));
}

bool ParallaxEngineInsideSilhouette(ParallaxRay ray, ParallaxHit hit) {
  return ParallaxInsideSilhouette(ray, hit, parallax_info.silhouette,
                                  parallax_info.params.w);
}
#endif  // FLUTTER_SCENE_PARALLAX_OCCLUSION

// PerturbNormal for a displaced lookup: samples the normal map at `uv +
// offset` with the undisplaced UV's gradients, and builds the tangent frame
// from the undisplaced UV, so neither the mip level nor the frame jumps where
// the march crosses between relief layers.
vec3 ParallaxPerturbNormal(sampler2D normal_tex, vec3 normal,
                           highp vec3 view_vector, highp vec2 uv,
                           highp vec2 offset, vec2 scale) {
  vec3 map = textureGrad(normal_tex, uv + offset, dFdx(uv), dFdy(uv)).xyz;
  map = map * 255. / 127. - 128. / 127.;
  map.xy *= scale;
  mat3 TBN = TangentFrame(normal, -view_vector, uv);
  return normalize(TBN * map).xyz;
}

// Samples a material slot displaced by the raw-channel `offset`, carried into
// the slot's own transform when it has one, with the undisplaced UV's
// gradients.
vec4 ParallaxSlotTexture(sampler2D tex, highp vec2 uv, bool transformed,
                         highp vec2 offset, highp vec4 transform,
                         highp vec4 rotation) {
  highp vec2 slot_offset =
      transformed ? TransformMaterialUvOffset(offset, transform, rotation.xy)
                  : offset;
  return textureGrad(tex, uv + slot_offset, dFdx(uv), dFdy(uv));
}

#endif  // FLUTTER_SCENE_PARALLAX_GLSL_
