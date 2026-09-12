# Fragment precision

Fragment sources that shade materials (`flutter_scene_standard.frag`,
`flutter_scene_unlit.frag`, and every `.fmat` the emitter assembles) open
with `precision mediump float; precision highp int;`, so a float without a
qualifier is half precision on GPUs that honor it (Mali, Adreno, and the
web). The shader bundle compiler keeps the qualifiers as `RelaxedPrecision`
for the OpenGL ES and Vulkan backends; Metal ignores them and stays fp32.
Vertex sources stay at highp.

`highp` is written explicitly wherever half precision (a 10-bit mantissa, a
range of 65504) is not enough:

- World and view positions, the view vector, and anything derived from them
  before normalization: distances, fog, froxel indices, probe lattices.
- Texture coordinates, screen coordinates, shadow map and atlas coordinates,
  and the uniform members that produce them (matrices, sizes, inverse sizes).
- Depth, depth comparisons, and biases.
- Light and probe indices, which exceed the 2048 integers fp16 represents.
- The HDR accumulators (`direct`, `ambient`, `out_color`, radiance from a
  light or an environment), since the frame is not pre-exposed.
- Derivative-based tangent frames, whose intermediates underflow fp16.
- Members of a uniform block the vertex stage also declares (an emitted
  material's `MaterialParams`), since WebGL2 refuses to link a program whose
  shared block members differ in precision between stages.

Unit vectors, dot products, roughness, albedo, fresnel, occlusion, and the
BRDF terms stay at the default. Terms that can exceed the fp16 range for
legal inputs clamp to `kMediumpFloatMax` (the GGX lobe of a mirror-smooth
surface) or run in highp (the sheen lambda's exponentials, the thin-film
phase).

A material body in a `.fmat` inherits the mediump default like any engine
source; declare `highp` on positions or coordinates it computes itself, or
open the body with `precision highp float;` after its includes to run all of
it in float32. Custom `ShaderMaterial` sources set their own precision.

An include whose contract is float32 (`noise.glsl`, whose outputs mirror the
Dart port within tolerances below fp16 resolution) opens with
`precision highp float;` and closes by restoring the default named by
`FLUTTER_SCENE_DEFAULT_FLOAT_PRECISION`, which every mediump source defines
before its precision statement. A source that leaves it undefined (a vertex
stage, a custom fragment) stays highp after the include.
