/// Deterministic noise, matched between CPU and GPU.
///
/// [FastNoiseLite] evaluates OpenSimplex2/OpenSimplex2S noise (with fBm,
/// ridged, and ping-pong fractal layering) in pure Dart, producing identical
/// values on native and web. The engine ships a GLSL counterpart
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
