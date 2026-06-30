import 'package:vector_math/vector_math.dart';

import 'gpu/gpu.dart' as gpu;
import 'material/physically_based_material.dart';

/// A uniform grid texture atlas: one or more equally sized PBR maps packed as
/// `columns` x `rows` square tiles, with an optional gutter of [padding] texels
/// around each tile so mip sampling does not bleed across tile edges.
///
/// The atlas does the UV bookkeeping for tiled content (voxel block faces,
/// sprite sheets, terrain tiles). Resolve a tile's atlas-space UV box with
/// [tileBounds], or map a within-tile coordinate with [tileUv]; a mesh writes
/// those UVs into its texture coordinates so a single material and draw call
/// covers every tile.
///
/// Maps follow the glTF metallic-roughness convention ([baseColor],
/// [metallicRoughness] with metallic in B and roughness in G, [normal],
/// [occlusion]); [toMaterial] wires them into a [PhysicallyBasedMaterial].
///
/// This is a CPU-side atlas (one packed texture). Once Flutter GPU gains 2D
/// array textures, a tile becomes an array layer and this padding/inset dance
/// is no longer needed; see the texture-array work tracked upstream.
/// {@category Assets and loading}
class TextureAtlas {
  /// Creates an atlas of [columns] x [rows] tiles, each [tileSize] texels
  /// square, separated by [padding] texels of gutter. The PBR maps are
  /// optional so the UV math can be used (and unit tested) on its own.
  TextureAtlas({
    required this.columns,
    required this.rows,
    required this.tileSize,
    this.padding = 0,
    this.baseColor,
    this.metallicRoughness,
    this.normal,
    this.occlusion,
  }) : assert(columns > 0),
       assert(rows > 0),
       assert(tileSize > 0),
       assert(padding >= 0);

  /// Tile grid dimensions.
  final int columns;
  final int rows;

  /// Edge length of a tile's content area, in texels.
  final int tileSize;

  /// Gutter of (typically edge-replicated) texels around each tile, in texels.
  final int padding;

  /// Packed PBR maps, all sharing the same grid layout. Any may be null.
  final gpu.Texture? baseColor;
  final gpu.Texture? metallicRoughness;
  final gpu.Texture? normal;
  final gpu.Texture? occlusion;

  /// Total number of tiles.
  int get tileCount => columns * rows;

  int get _cellSize => tileSize + 2 * padding;

  /// Atlas dimensions in texels (including the padding gutters).
  int get width => columns * _cellSize;
  int get height => rows * _cellSize;

  /// The atlas-space UV box of tile [index]'s content area as
  /// `(minU, minV, maxU, maxV)`, inset past the padding gutter so sampling
  /// stays inside the tile. Tiles are row-major with a top-left origin.
  Vector4 tileBounds(int index) {
    assert(index >= 0 && index < tileCount);
    final col = index % columns;
    final row = index ~/ columns;
    final x0 = col * _cellSize + padding;
    final y0 = row * _cellSize + padding;
    final w = width.toDouble();
    final h = height.toDouble();
    return Vector4(x0 / w, y0 / h, (x0 + tileSize) / w, (y0 + tileSize) / h);
  }

  /// Maps a within-tile coordinate ([u], [v], each in `[0, 1]` with (0, 0) at
  /// the tile's top-left) to an atlas UV for tile [index].
  Vector2 tileUv(int index, double u, double v) {
    final bounds = tileBounds(index);
    return Vector2(
      bounds.x + (bounds.z - bounds.x) * u,
      bounds.y + (bounds.w - bounds.y) * v,
    );
  }

  /// Builds a [PhysicallyBasedMaterial] bound to this atlas's maps. The factors
  /// are left at their identity defaults so the textures drive the result; the
  /// caller picks alpha mode, vertex-color weight, and so on.
  PhysicallyBasedMaterial toMaterial() {
    return PhysicallyBasedMaterial(
      baseColorTexture: baseColor,
      metallicRoughnessTexture: metallicRoughness,
      normalTexture: normal,
      occlusionTexture: occlusion,
    );
  }
}
