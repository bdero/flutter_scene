import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/light.dart';

/// One cascade's cached static-caster shadow tile: the persistent texture the
/// static geometry was rendered into, the light-space matrix it was rendered
/// with, and the coverage it was fit to.
class ShadowCascadeCacheEntry {
  /// The persistent tile texture, allocated lazily by the shadow pass on the
  /// entry's first refresh (kept out of [DirectionalShadowCache.plan] so the
  /// planning logic stays GPU-free).
  gpu.Texture? tile;

  /// World -> light-clip matrix the tile's content was rendered with. Every
  /// consumer (dynamic casters, the lit shader, custom passes) samples through
  /// this matrix, not the frame's ideal one, so the cached content stays
  /// correct while it is reused.
  final Matrix4 matrix = Matrix4.zero();

  /// The ideal bounding-sphere the slack box was built around.
  final Vector3 center = Vector3.zero();
  double radius = 0.0;

  /// Side length of the slack-enlarged orthographic box in world units.
  double boxSize = 0.0;

  /// The static-content signature the tile was rendered with; a mismatch
  /// marks the tile stale (refreshed amortized).
  int renderedSignature = 0;

  /// Whether the tile has ever been rendered with the current parameters.
  bool hasContent = false;
}

/// A static tile the shadow pass must (re)render this frame.
class ShadowTileRefresh {
  ShadowTileRefresh(this.cascadeIndex, this.entry);

  final int cascadeIndex;
  final ShadowCascadeCacheEntry entry;
}

/// One frame's cached-shadow decisions: the cascades every consumer samples
/// with (cached matrices, this frame's split distances) and the tiles to
/// re-render.
class ShadowCachePlan {
  ShadowCachePlan(this.cascades, this.refreshes, this.entries);

  /// Effective cascades. Matrices and box sizes describe the cached tiles;
  /// split distances are the frame's ideal ones (they only select which
  /// cascade a fragment samples).
  final List<ShadowCascade> cascades;

  /// Tiles to render static casters into this frame, in cascade order.
  final List<ShadowTileRefresh> refreshes;

  /// All cache entries, indexed by cascade.
  final List<ShadowCascadeCacheEntry> entries;
}

/// Cross-frame cache for the directional light's cascaded shadow tiles.
///
/// Static casters ([RenderItem.shadowStatic]) render into persistent per
/// cascade tiles that are reused while they still cover the view; the shadow
/// pass composites them into each frame's atlas and draws only the dynamic
/// casters on top. Tiles are fit with [slackFactor] extra radius so the
/// camera can move and turn inside the slack before a cascade must
/// re-render, and content-stale tiles (a static caster appeared or vanished)
/// refresh at most [maxAmortizedRefreshes] per frame, nearest cascade first,
/// so streaming worlds never pay for every cascade at once.
class DirectionalShadowCache {
  /// How much larger than the ideal bounding sphere each tile is rendered.
  /// Costs ~13% effective resolution; buys re-render-free camera movement
  /// within the slack.
  static const double slackFactor = 1.15;

  /// Upper bound on stale-but-usable tile refreshes per frame.
  static const int maxAmortizedRefreshes = 1;

  final List<ShadowCascadeCacheEntry> _entries = [];
  final Vector3 _lightDir = Vector3.zero();
  int _resolution = 0;
  ShadowCasterFaces _casterFaces = ShadowCasterFaces.front;

  /// Decides which tiles to re-render for this frame's [idealCascades] and
  /// returns the effective cascades to sample with.
  ///
  /// [staticSignature] fingerprints the static caster set; any change marks
  /// every tile stale. A change to the light basis or shadow parameters
  /// rebuilds the cache outright.
  ShadowCachePlan plan({
    required DirectionalLight light,
    required Vector3 lightDirection,
    required List<ShadowCascade> idealCascades,
    required int staticSignature,
  }) {
    final resolution = light.shadowMapResolution;
    final dir = lightDirection.normalized();
    final paramsChanged =
        resolution != _resolution ||
        light.shadowCasterFaces != _casterFaces ||
        _entries.length != idealCascades.length ||
        (dir - _lightDir).length2 > 1e-10;
    if (paramsChanged) {
      _entries.clear();
      for (var i = 0; i < idealCascades.length; i++) {
        _entries.add(ShadowCascadeCacheEntry());
      }
      _resolution = resolution;
      _casterFaces = light.shadowCasterFaces;
      _lightDir.setFrom(dir);
    }

    final refreshes = <ShadowTileRefresh>[];
    final effective = <ShadowCascade>[];
    var amortized = 0;
    for (var i = 0; i < idealCascades.length; i++) {
      final ideal = idealCascades[i];
      final entry = _entries[i];
      final center = ideal.center ?? Vector3.zero();
      // A tile is reusable while the ideal sphere still fits inside its
      // slack box; the radius only changes with camera/shadow parameters.
      final fits =
          entry.hasContent &&
          (ideal.radius - entry.radius).abs() <= entry.radius * 1e-3 &&
          (center - entry.center).length <= entry.radius * (slackFactor - 1.0);
      var refresh = false;
      if (!fits) {
        // Unusable (first render, coverage drift, or parameter change):
        // must render this frame or the cascade has no shadows.
        refresh = true;
      } else if (entry.renderedSignature != staticSignature &&
          amortized < maxAmortizedRefreshes) {
        // Usable but stale content: refresh a bounded number per frame,
        // nearest cascade first (this loop runs near-to-far).
        refresh = true;
        amortized++;
      }
      if (refresh) {
        entry.center.setFrom(center);
        entry.radius = ideal.radius;
        entry.boxSize = ideal.radius * slackFactor * 2.0;
        entry.matrix.setFrom(
          light.cascadeLightSpaceMatrix(
            dir,
            center,
            ideal.radius * slackFactor,
          ),
        );
        entry.renderedSignature = staticSignature;
        entry.hasContent = true;
        refreshes.add(ShadowTileRefresh(i, entry));
      }
      effective.add(
        ShadowCascade(
          lightSpaceMatrix: entry.matrix,
          splitDistance: ideal.splitDistance,
          boxSize: entry.boxSize,
          center: entry.center,
          radius: entry.radius,
        ),
      );
    }
    return ShadowCachePlan(effective, refreshes, _entries);
  }
}
