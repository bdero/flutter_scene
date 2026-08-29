// Enhanced subpixel morphological antialiasing (SMAA 1x), ported from the
// reference implementation at https://github.com/iryoku/smaa (SMAA.hlsl) to
// the engine's GLSL ES 3.00 dialect. The three passes are
// flutter_scene_smaa_edges.frag, flutter_scene_smaa_weights.frag, and
// flutter_scene_smaa_blend.frag; each defines its entry inputs and includes
// this file for the shared machinery. The port computes the reference's
// vertex-stage offsets per fragment, rewrites the unbounded searches as
// constant-bounded loops, and keeps the math otherwise identical, at the
// SMAA_PRESET_HIGH quality tier.
//
// The area and search textures are the reference data shipped as
// assets/smaa_area.bin and assets/smaa_search.bin (see smaa_textures.dart).
//
// Reference implementation license (Jimenez et al.):
//
// Copyright (C) 2013 Jorge Jimenez (jorge@iryoku.com)
// Copyright (C) 2013 Jose I. Echevarria (joseignacioechevarria@gmail.com)
// Copyright (C) 2013 Belen Masia (bmasia@unizar.es)
// Copyright (C) 2013 Fernando Navarro (fernandn@microsoft.com)
// Copyright (C) 2013 Diego Gutierrez (diegog@unizar.es)
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software. As clarification,
// there is no requirement that the copyright notice and permission be
// included in binary distributions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

// SMAA_RT_METRICS: (1/width, 1/height, width, height) of the display target.
#define SMAA_RT_METRICS smaa_info.rt_metrics

// Runtime quality parameters (Scene.smaa), defaulting to the
// SMAA_PRESET_HIGH tier. Loops bounded by the search steps are dynamically
// bounded, legal in every compiled dialect (GLSL ES 3.00+).
#define SMAA_THRESHOLD smaa_info.params.x
#define SMAA_MAX_SEARCH_STEPS int(smaa_info.params.y)
#define SMAA_MAX_SEARCH_STEPS_DIAG int(smaa_info.params.z)
#define SMAA_CORNER_ROUNDING smaa_info.params.w
#define SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR 2.0

#define SMAA_AREATEX_MAX_DISTANCE 16.0
#define SMAA_AREATEX_MAX_DISTANCE_DIAG 20.0
#define SMAA_AREATEX_PIXEL_SIZE (1.0 / vec2(160.0, 560.0))
#define SMAA_AREATEX_SUBTEX_SIZE (1.0 / 7.0)
#define SMAA_SEARCHTEX_SIZE vec2(66.0, 33.0)
#define SMAA_SEARCHTEX_PACKED_SIZE vec2(64.0, 16.0)
#define SMAA_CORNER_ROUNDING_NORM (SMAA_CORNER_ROUNDING / 100.0)

// Conditional moves, kept from the reference to match its branch shape.
void SmaaMovc2(bvec2 cond, inout vec2 variable, vec2 value) {
  if (cond.x) variable.x = value.x;
  if (cond.y) variable.y = value.y;
}

void SmaaMovc4(bvec4 cond, inout vec4 variable, vec4 value) {
  SmaaMovc2(cond.xy, variable.xy, value.xy);
  SmaaMovc2(cond.zw, variable.zw, value.zw);
}

// Decodes two binary edge values from one bilinear-filtered fetch taken at
// a 0.25 texel offset (see @SearchDiag2Optimization in the reference).
vec2 SmaaDecodeDiagBilinearAccess2(vec2 e) {
  e.r = e.r * abs(5.0 * e.r - 5.0 * 0.75);
  return round(e);
}

vec4 SmaaDecodeDiagBilinearAccess4(vec4 e) {
  e.rb = e.rb * abs(5.0 * e.rb - 5.0 * 0.75);
  return round(e);
}

// Diagonal pattern searches. The reference's condition-driven while loops
// are constant-bounded for-loops with an interior break (a uniform-bounded
// loop is rejected by conforming GLES compilers, and this shape also keeps
// the Direct3D translation crash-free).
vec2 SmaaSearchDiag1(sampler2D edges_tex, vec2 texcoord, vec2 dir,
                     out vec2 e) {
  vec4 coord = vec4(texcoord, -1.0, 1.0);
  vec3 t = vec3(SMAA_RT_METRICS.xy, 1.0);
  e = vec2(0.0);
  for (int i = 0; i < SMAA_MAX_SEARCH_STEPS_DIAG; i++) {
    if (!(coord.z < float(SMAA_MAX_SEARCH_STEPS_DIAG - 1) &&
          coord.w > 0.9)) {
      break;
    }
    coord.xyz = t * vec3(dir, 1.0) + coord.xyz;
    e = textureLod(edges_tex, coord.xy, 0.0).rg;
    coord.w = dot(e, vec2(0.5, 0.5));
  }
  return coord.zw;
}

vec2 SmaaSearchDiag2(sampler2D edges_tex, vec2 texcoord, vec2 dir,
                     out vec2 e) {
  vec4 coord = vec4(texcoord, -1.0, 1.0);
  coord.x += 0.25 * SMAA_RT_METRICS.x;
  vec3 t = vec3(SMAA_RT_METRICS.xy, 1.0);
  e = vec2(0.0);
  for (int i = 0; i < SMAA_MAX_SEARCH_STEPS_DIAG; i++) {
    if (!(coord.z < float(SMAA_MAX_SEARCH_STEPS_DIAG - 1) &&
          coord.w > 0.9)) {
      break;
    }
    coord.xyz = t * vec3(dir, 1.0) + coord.xyz;
    e = textureLod(edges_tex, coord.xy, 0.0).rg;
    e = SmaaDecodeDiagBilinearAccess2(e);
    coord.w = dot(e, vec2(0.5, 0.5));
  }
  return coord.zw;
}

// Area for a diagonal distance and crossing edges [e].
vec2 SmaaAreaDiag(sampler2D area_tex, vec2 dist, vec2 e, float offset) {
  vec2 texcoord =
      vec2(SMAA_AREATEX_MAX_DISTANCE_DIAG) * e + dist;
  texcoord = SMAA_AREATEX_PIXEL_SIZE * texcoord +
             0.5 * SMAA_AREATEX_PIXEL_SIZE;
  // Diagonal areas live in the second half of the texture.
  texcoord.x += 0.5;
  texcoord.y += SMAA_AREATEX_SUBTEX_SIZE * offset;
  return textureLod(area_tex, texcoord, 0.0).rg;
}

// Searches for diagonal patterns around the pixel and returns their weights.
vec2 SmaaCalculateDiagWeights(sampler2D edges_tex, sampler2D area_tex,
                              vec2 texcoord, vec2 e) {
  vec2 weights = vec2(0.0);

  vec4 d;
  vec2 end;
  if (e.r > 0.0) {
    d.xz = SmaaSearchDiag1(edges_tex, texcoord, vec2(-1.0, 1.0), end);
    d.x += float(end.y > 0.9);
  } else {
    d.xz = vec2(0.0);
  }
  d.yw = SmaaSearchDiag1(edges_tex, texcoord, vec2(1.0, -1.0), end);

  if (d.x + d.y > 2.0) {
    vec4 coords = vec4(-d.x + 0.25, d.x, d.y, -d.y - 0.25) *
                      SMAA_RT_METRICS.xyxy +
                  texcoord.xyxy;
    vec4 c;
    c.xy = textureLodOffset(edges_tex, coords.xy, 0.0, ivec2(-1, 0)).rg;
    c.zw = textureLodOffset(edges_tex, coords.zw, 0.0, ivec2(1, 0)).rg;
    c.yxwz = SmaaDecodeDiagBilinearAccess4(c.xyzw);
    vec2 cc = vec2(2.0) * c.xz + c.yw;
    SmaaMovc2(bvec2(step(0.9, d.zw)), cc, vec2(0.0));
    weights += SmaaAreaDiag(area_tex, d.xy, cc, 0.0);
  }

  d.xz = SmaaSearchDiag2(edges_tex, texcoord, vec2(-1.0, -1.0), end);
  if (textureLodOffset(edges_tex, texcoord, 0.0, ivec2(1, 0)).r > 0.0) {
    d.yw = SmaaSearchDiag2(edges_tex, texcoord, vec2(1.0, 1.0), end);
    d.y += float(end.y > 0.9);
  } else {
    d.yw = vec2(0.0);
  }

  if (d.x + d.y > 2.0) {
    vec4 coords = vec4(-d.x, -d.x, d.y, d.y) * SMAA_RT_METRICS.xyxy +
                  texcoord.xyxy;
    vec4 c;
    c.x = textureLodOffset(edges_tex, coords.xy, 0.0, ivec2(-1, 0)).g;
    c.y = textureLodOffset(edges_tex, coords.xy, 0.0, ivec2(0, -1)).r;
    c.zw = textureLodOffset(edges_tex, coords.zw, 0.0, ivec2(1, 0)).gr;
    vec2 cc = vec2(2.0) * c.xz + c.yw;
    SmaaMovc2(bvec2(step(0.9, d.zw)), cc, vec2(0.0));
    weights += SmaaAreaDiag(area_tex, d.xy, cc, 0.0).gr;
  }

  return weights;
}

// How much length to add in the last step of the searches, from the packed
// search texture (see @PSEUDO_GATHER4 in the reference).
float SmaaSearchLength(sampler2D search_tex, vec2 e, float offset) {
  vec2 scale = SMAA_SEARCHTEX_SIZE * vec2(0.5, -1.0);
  vec2 bias = SMAA_SEARCHTEX_SIZE * vec2(offset, 1.0);
  scale += vec2(-1.0, 1.0);
  bias += vec2(0.5, -0.5);
  scale *= 1.0 / SMAA_SEARCHTEX_PACKED_SIZE;
  bias *= 1.0 / SMAA_SEARCHTEX_PACKED_SIZE;
  return textureLod(search_tex, scale * e + bias, 0.0).r;
}

// Horizontal/vertical searches. Each marches two texels per bilinear fetch
// from a texcoord the caller pre-offset by (-0.25, -0.125) or its mirror,
// again as constant-bounded loops.
float SmaaSearchXLeft(sampler2D edges_tex, sampler2D search_tex,
                      vec2 texcoord, float end) {
  vec2 e = vec2(0.0, 1.0);
  for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
    if (!(texcoord.x > end && e.g > 0.8281 && e.r == 0.0)) {
      break;
    }
    e = textureLod(edges_tex, texcoord, 0.0).rg;
    texcoord = -vec2(2.0, 0.0) * SMAA_RT_METRICS.xy + texcoord;
  }
  float offset =
      -(255.0 / 127.0) * SmaaSearchLength(search_tex, e, 0.0) + 3.25;
  return SMAA_RT_METRICS.x * offset + texcoord.x;
}

float SmaaSearchXRight(sampler2D edges_tex, sampler2D search_tex,
                       vec2 texcoord, float end) {
  vec2 e = vec2(0.0, 1.0);
  for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
    if (!(texcoord.x < end && e.g > 0.8281 && e.r == 0.0)) {
      break;
    }
    e = textureLod(edges_tex, texcoord, 0.0).rg;
    texcoord = vec2(2.0, 0.0) * SMAA_RT_METRICS.xy + texcoord;
  }
  float offset =
      -(255.0 / 127.0) * SmaaSearchLength(search_tex, e, 0.5) + 3.25;
  return -SMAA_RT_METRICS.x * offset + texcoord.x;
}

float SmaaSearchYUp(sampler2D edges_tex, sampler2D search_tex, vec2 texcoord,
                    float end) {
  vec2 e = vec2(1.0, 0.0);
  for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
    if (!(texcoord.y > end && e.r > 0.8281 && e.g == 0.0)) {
      break;
    }
    e = textureLod(edges_tex, texcoord, 0.0).rg;
    texcoord = -vec2(0.0, 2.0) * SMAA_RT_METRICS.xy + texcoord;
  }
  float offset =
      -(255.0 / 127.0) * SmaaSearchLength(search_tex, e.gr, 0.0) + 3.25;
  return SMAA_RT_METRICS.y * offset + texcoord.y;
}

float SmaaSearchYDown(sampler2D edges_tex, sampler2D search_tex,
                      vec2 texcoord, float end) {
  vec2 e = vec2(1.0, 0.0);
  for (int i = 0; i < SMAA_MAX_SEARCH_STEPS; i++) {
    if (!(texcoord.y < end && e.r > 0.8281 && e.g == 0.0)) {
      break;
    }
    e = textureLod(edges_tex, texcoord, 0.0).rg;
    texcoord = vec2(0.0, 2.0) * SMAA_RT_METRICS.xy + texcoord;
  }
  float offset =
      -(255.0 / 127.0) * SmaaSearchLength(search_tex, e.gr, 0.5) + 3.25;
  return -SMAA_RT_METRICS.y * offset + texcoord.y;
}

// Area at each side of the edge for distances [dist] and crossing edges
// [e1], [e2]. The area texture is compressed quadratically (hence the
// caller's sqrt) and rounded to dodge bilinear precision error.
vec2 SmaaArea(sampler2D area_tex, vec2 dist, float e1, float e2) {
  vec2 texcoord =
      vec2(SMAA_AREATEX_MAX_DISTANCE) * round(4.0 * vec2(e1, e2)) + dist;
  texcoord = SMAA_AREATEX_PIXEL_SIZE * texcoord +
             0.5 * SMAA_AREATEX_PIXEL_SIZE;
  return textureLod(area_tex, texcoord, 0.0).rg;
}

// Corner rounding: pull blending back where a real (intended) corner meets
// the edge.
void SmaaDetectHorizontalCornerPattern(sampler2D edges_tex,
                                       inout vec2 weights, vec4 texcoord,
                                       vec2 d) {
  vec2 left_right = step(d.xy, d.yx);
  vec2 rounding = (1.0 - SMAA_CORNER_ROUNDING_NORM) * left_right;
  rounding /= left_right.x + left_right.y;

  vec2 factor = vec2(1.0);
  factor.x -= rounding.x *
              textureLodOffset(edges_tex, texcoord.xy, 0.0, ivec2(0, 1)).r;
  factor.x -= rounding.y *
              textureLodOffset(edges_tex, texcoord.zw, 0.0, ivec2(1, 1)).r;
  factor.y -= rounding.x *
              textureLodOffset(edges_tex, texcoord.xy, 0.0, ivec2(0, -2)).r;
  factor.y -= rounding.y *
              textureLodOffset(edges_tex, texcoord.zw, 0.0, ivec2(1, -2)).r;
  weights *= clamp(factor, 0.0, 1.0);
}

void SmaaDetectVerticalCornerPattern(sampler2D edges_tex, inout vec2 weights,
                                     vec4 texcoord, vec2 d) {
  vec2 left_right = step(d.xy, d.yx);
  vec2 rounding = (1.0 - SMAA_CORNER_ROUNDING_NORM) * left_right;
  rounding /= left_right.x + left_right.y;

  vec2 factor = vec2(1.0);
  factor.x -= rounding.x *
              textureLodOffset(edges_tex, texcoord.xy, 0.0, ivec2(1, 0)).g;
  factor.x -= rounding.y *
              textureLodOffset(edges_tex, texcoord.zw, 0.0, ivec2(1, 1)).g;
  factor.y -= rounding.x *
              textureLodOffset(edges_tex, texcoord.xy, 0.0, ivec2(-2, 0)).g;
  factor.y -= rounding.y *
              textureLodOffset(edges_tex, texcoord.zw, 0.0, ivec2(-2, 1)).g;
  weights *= clamp(factor, 0.0, 1.0);
}
