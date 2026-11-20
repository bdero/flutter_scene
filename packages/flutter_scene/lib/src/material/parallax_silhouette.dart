import 'package:flutter/foundation.dart' show internal;
import 'package:vector_math/vector_math.dart';

/// Where a parallax-mapped surface's relief ends, so its outline follows the
/// relief instead of the flat geometry.
///
/// A fragment whose marched view ray leaves the bounds before it hits the
/// height field is cut away, so the surface behind shows through, and the
/// depth prepass and shadow maps cut it the same way. The bounds are in the
/// UV space of the material's normal texture, after its texture transform.
///
/// Exact where a UV boundary is the visible edge: quads, decals, box faces,
/// and atlas tiles. On curved meshes the cut follows the UV layout, not the
/// silhouette.
/// TODO(parallax-curved-silhouette): curved silhouettes need per-vertex
/// curvature or extruded shell geometry.
/// {@category Materials}
class ParallaxSilhouette {
  /// Cuts outside the UV box from [min] to [max].
  ParallaxSilhouette.bounds(Vector2 min, Vector2 max)
    : _mode = 1,
      _a = min.clone(),
      _b = max.clone();

  /// Cuts at the edges of the grid tile each fragment's UV sits in, with
  /// tiles of [size] UV units from the origin. For texture atlases, where
  /// every face samples one tile.
  ParallaxSilhouette.tiles(Vector2 size)
    : _mode = 2,
      _a = Vector2.zero(),
      _b = size.clone();

  /// Cuts outside the unit UV square, for a quad or box face mapped once.
  static final ParallaxSilhouette unit = ParallaxSilhouette.bounds(
    Vector2.zero(),
    Vector2.all(1),
  );

  final int _mode;
  final Vector2 _a;
  final Vector2 _b;

  /// Whether this cuts at grid tiles rather than one box.
  bool get isTiled => _mode == 2;

  /// The box's low corner, or the origin for tiles.
  Vector2 get min => _a.clone();

  /// The box's high corner, or the tile size for tiles.
  Vector2 get max => _b.clone();

  /// The shader's silhouette mode, 1 a box and 2 tiles.
  @internal
  int get shaderMode => _mode;

  @override
  bool operator ==(Object other) =>
      other is ParallaxSilhouette &&
      other._mode == _mode &&
      other._a == _a &&
      other._b == _b;

  @override
  int get hashCode => Object.hash(_mode, _a.x, _a.y, _b.x, _b.y);

  @override
  String toString() => isTiled
      ? 'ParallaxSilhouette.tiles($_b)'
      : 'ParallaxSilhouette.bounds($_a, $_b)';
}
