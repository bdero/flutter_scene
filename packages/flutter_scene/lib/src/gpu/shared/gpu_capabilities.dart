/// What a GPU backend can do, as opposed to how it does it.
///
/// Backends differ in two unrelated ways. Some differences are *conformance*
/// differences, where a backend reaches the same result by another route; those
/// stay hidden inside the backend and never appear here. The rest are
/// *capability* differences, where a backend genuinely cannot do something, and
/// those belong here.
///
/// Capabilities are meant to be read where a feature picks its implementation,
/// not inside a per-frame path. A capability check in a draw loop is at the
/// wrong altitude.
library;

/// How completely a backend is integrated with the Flutter host it draws into.
///
/// A label derived from the individual capabilities below, for logging and for
/// documenting a backend at a glance. Branch on the specific capability rather
/// than on the tier.
enum GpuHostTier {
  /// Textures cross into and out of Flutter without a copy. Rendered output
  /// can be drawn as a `ui.Image`, and Flutter-rendered content can be sampled
  /// as a texture.
  full,

  /// Rendered output can reach the screen, but Flutter-rendered content cannot
  /// be sampled without a readback.
  presentOnly,

  /// No Flutter integration at all. Output is only reachable by reading it
  /// back.
  headless,
}

/// The capability set of the active GPU backend.
class GpuCapabilities {
  const GpuCapabilities({
    required this.textureToImage,
    required this.imageToTexture,
    required this.presentAsImage,
    required this.compute,
    this.indirectDraw = false,
    this.reusableBindingSets = false,
  });

  /// A rendered texture can be handed to Flutter as a `ui.Image` without a
  /// readback, which is what compositing a scene onto a canvas needs.
  final bool textureToImage;

  /// A Flutter-rendered `ui.Image` can be wrapped as a texture without a
  /// readback, which is what sampling widget content inside a scene needs.
  ///
  /// False on backends that cannot share textures with the framework, where
  /// callers read the image back and upload it instead.
  final bool imageToTexture;

  /// Offscreen output can be presented as a `ui.Image` through the backend's
  /// own present path rather than through [textureToImage].
  final bool presentAsImage;

  /// Compute pipelines and dispatches are available.
  final bool compute;

  /// Draw parameters can come from a GPU buffer, so culling and LOD selection
  /// can run on the GPU without a round trip.
  ///
  /// False on Flutter GPU until flutter/flutter#190402 lands, and false on
  /// WebGL2 permanently.
  final bool indirectDraw;

  /// A group of resources can be bound in one call rather than per resource.
  ///
  /// False on Flutter GPU until flutter/flutter#190400 lands, where the seam's
  /// binding sets are replayed as individual binds at the same cost as the
  /// per-resource path they replace.
  final bool reusableBindingSets;

  /// The tier these capabilities add up to.
  GpuHostTier get hostTier {
    if (!textureToImage && !presentAsImage) return GpuHostTier.headless;
    if (imageToTexture) return GpuHostTier.full;
    return GpuHostTier.presentOnly;
  }

  @override
  String toString() =>
      'GpuCapabilities(${hostTier.name}, textureToImage: $textureToImage, '
      'imageToTexture: $imageToTexture, presentAsImage: $presentAsImage, '
      'compute: $compute, indirectDraw: $indirectDraw, '
      'reusableBindingSets: $reusableBindingSets)';
}
