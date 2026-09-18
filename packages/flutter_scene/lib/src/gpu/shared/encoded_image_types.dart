/// How a mip level is averaged from the level above it, mirroring the
/// engine's CPU chain so a chain built by the backend matches one uploaded
/// level by level.
enum MipContent {
  /// sRGB-encoded color, averaged in linear light.
  color,

  /// Linear data (roughness, occlusion, masks), averaged as stored.
  data,

  /// A tangent-space normal map, averaged as vectors and renormalized.
  normal,
}

/// Scales [width] x [height] down so the longest side is at most [maxSize],
/// keeping the aspect ratio and never upscaling.
(int, int) fitWithin(int width, int height, int maxSize) {
  assert(maxSize >= 1);
  final longest = width > height ? width : height;
  if (longest <= maxSize) return (width, height);
  return (
    (width * maxSize ~/ longest).clamp(1, maxSize),
    (height * maxSize ~/ longest).clamp(1, maxSize),
  );
}
