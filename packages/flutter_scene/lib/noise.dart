/// Deterministic noise, matched between CPU and GPU.
///
/// [FastNoiseLite] evaluates OpenSimplex2/OpenSimplex2S, Perlin, Value, and
/// Cellular noise (with fBm, ridged, and ping-pong fractal layering, plus
/// domain warp) in pure Dart. The engine ships a GLSL counterpart
/// (`#include <noise.glsl>` inside a `.fmat` block) implementing the same
/// algorithms with the same tables and seeds, so a field sampled on the CPU
/// and evaluated in a shader agree.
///
/// The agreement contract has two tiers. [noiseHash2] and [noiseHash3] (and
/// the GLSL `NoiseHash2`/`NoiseHash3`) are pure 32-bit integer math and match
/// bit for bit on every backend, use them for decisions that must never
/// disagree (world generation, placement). The float noise functions match
/// within a small tolerance (float32 rounding differs per GPU), which is
/// imperceptible visually; avoid re-deriving a hard threshold from float
/// noise on both sides, make the decision once and share it.
///
/// Web caveat: the GLSL noise is correct on every backend, including the web
/// (WebGL2). The Dart [FastNoiseLite], however, relies on 32-bit integer
/// arithmetic that overflows on the web, where Dart `int` is a JavaScript
/// double (exact only to 53 bits), so the hash loses its low bits and 3D
/// noise can overflow. Prefer the GLSL side, or a [bakeNoiseTexture] built at
/// build time or in a native isolate, when targeting the web. A web-safe
/// integer multiply for the Dart side is a planned follow-up.
library;

export 'src/noise/curl.dart' show noiseCurl3;
export 'src/noise/fast_noise_lite.dart'
    show
        CellularDistanceFunction,
        CellularReturnType,
        DomainWarpFractalType,
        DomainWarpType,
        FastNoiseLite,
        FractalType,
        NoiseType,
        noiseHash2,
        noiseHash3;
export 'src/noise/noise_pixels.dart' show bakeNoisePixels;
export 'src/noise/noise_texture.dart' show bakeNoiseTexture;
