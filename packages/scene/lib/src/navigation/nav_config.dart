import 'dart:math' as math;

/// What "walkable" means for one agent, in world units.
///
/// Everything downstream is derived from these: a nav mesh is not a property
/// of the level, it is a property of the level *plus* an agent. A knee-high
/// character and a tank disagree about every one of these numbers, so bake one
/// mesh per agent size rather than trying to serve both from one.
///
/// The two cell sizes are the resolution knobs, and they are the ones worth
/// tuning first. Everything is voxelized at [cellSize] horizontally and
/// [cellHeight] vertically, so halving [cellSize] quadruples both bake time
/// and memory. The usual starting point is a cell around a third of
/// [agentRadius] and a cell height around half of [agentMaxClimb], which is
/// fine enough to resolve a doorway and a step without paying for detail no
/// agent can use.
class NavMeshConfig {
  const NavMeshConfig({
    this.cellSize = 0.3,
    this.cellHeight = 0.2,
    this.agentRadius = 0.6,
    this.agentHeight = 2.0,
    this.agentMaxClimb = 0.9,
    this.agentMaxSlopeDegrees = 45.0,
    this.minRegionArea = 8.0,
    this.mergeRegionArea = 20.0,
    this.maxEdgeLength = 12.0,
    this.maxSimplificationError = 1.3,
    this.maxVertsPerPolygon = 6,
  }) : assert(cellSize > 0),
       assert(cellHeight > 0),
       assert(agentRadius >= 0),
       assert(agentHeight > 0),
       assert(agentMaxClimb >= 0),
       assert(agentMaxSlopeDegrees > 0 && agentMaxSlopeDegrees < 90),
       assert(maxVertsPerPolygon >= 3);

  /// Horizontal voxel size. The smallest gap the bake can resolve.
  final double cellSize;

  /// Vertical voxel size. The smallest height difference the bake can see, so
  /// it bounds how precisely a step or a ledge is placed.
  final double cellHeight;

  /// How far the agent's centre must stay from a wall. The walkable surface is
  /// eroded by this, which is what stops a path from clipping a corner.
  final double agentRadius;

  /// Vertical clearance the agent needs. Surfaces with less headroom than this
  /// are not walkable, so an agent never paths under a low beam it would hit.
  final double agentHeight;

  /// The tallest step the agent can walk up without jumping. Two surfaces
  /// within this of each other are connected; beyond it they are a ledge.
  final double agentMaxClimb;

  /// The steepest surface the agent can stand on. Anything steeper is a wall.
  final double agentMaxSlopeDegrees;

  /// Regions smaller than this many square world units are discarded as
  /// unreachable specks, the pebbles and window sills a bake would otherwise
  /// litter the mesh with.
  final double minRegionArea;

  /// Regions smaller than this are merged into a larger neighbour where one
  /// exists, rather than surviving as their own island.
  final double mergeRegionArea;

  /// The longest border edge kept before it is subdivided. Long edges along a
  /// wall are cheap but make for coarse polygons and worse paths near them.
  final double maxEdgeLength;

  /// How far, in voxels, a simplified contour may stray from the raw one.
  final double maxSimplificationError;

  /// The most vertices one nav polygon may have. Higher means fewer, larger
  /// polygons and a cheaper search; 6 is the usual balance.
  final int maxVertsPerPolygon;

  /// [agentMaxSlopeDegrees] as the cosine test the voxelizer actually uses: a
  /// triangle is walkable when its normal's Y component is at least this.
  double get walkableSlopeCosine =>
      math.cos(agentMaxSlopeDegrees * math.pi / 180.0);

  /// [agentHeight] in voxels, rounded up so a surface is never called walkable
  /// with less clearance than the agent needs.
  int get agentHeightCells => (agentHeight / cellHeight).ceil();

  /// [agentMaxClimb] in voxels, rounded down so a step is never called
  /// climbable when it is taller than the agent can manage.
  int get agentMaxClimbCells => (agentMaxClimb / cellHeight).floor();

  /// [agentRadius] in voxels, rounded up so erosion never leaves the agent
  /// closer to a wall than it asked for.
  int get agentRadiusCells => (agentRadius / cellSize).ceil();

  NavMeshConfig copyWith({
    double? cellSize,
    double? cellHeight,
    double? agentRadius,
    double? agentHeight,
    double? agentMaxClimb,
    double? agentMaxSlopeDegrees,
    double? minRegionArea,
    double? mergeRegionArea,
    double? maxEdgeLength,
    double? maxSimplificationError,
    int? maxVertsPerPolygon,
  }) => NavMeshConfig(
    cellSize: cellSize ?? this.cellSize,
    cellHeight: cellHeight ?? this.cellHeight,
    agentRadius: agentRadius ?? this.agentRadius,
    agentHeight: agentHeight ?? this.agentHeight,
    agentMaxClimb: agentMaxClimb ?? this.agentMaxClimb,
    agentMaxSlopeDegrees: agentMaxSlopeDegrees ?? this.agentMaxSlopeDegrees,
    minRegionArea: minRegionArea ?? this.minRegionArea,
    mergeRegionArea: mergeRegionArea ?? this.mergeRegionArea,
    maxEdgeLength: maxEdgeLength ?? this.maxEdgeLength,
    maxSimplificationError:
        maxSimplificationError ?? this.maxSimplificationError,
    maxVertsPerPolygon: maxVertsPerPolygon ?? this.maxVertsPerPolygon,
  );

  Map<String, Object?> toJson() => {
    'cellSize': cellSize,
    'cellHeight': cellHeight,
    'agentRadius': agentRadius,
    'agentHeight': agentHeight,
    'agentMaxClimb': agentMaxClimb,
    'agentMaxSlopeDegrees': agentMaxSlopeDegrees,
    'minRegionArea': minRegionArea,
    'mergeRegionArea': mergeRegionArea,
    'maxEdgeLength': maxEdgeLength,
    'maxSimplificationError': maxSimplificationError,
    'maxVertsPerPolygon': maxVertsPerPolygon,
  };

  static NavMeshConfig fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) {
      final raw = json[key];
      return raw is num ? raw.toDouble() : fallback;
    }

    const defaults = NavMeshConfig();
    return NavMeshConfig(
      cellSize: number('cellSize', defaults.cellSize),
      cellHeight: number('cellHeight', defaults.cellHeight),
      agentRadius: number('agentRadius', defaults.agentRadius),
      agentHeight: number('agentHeight', defaults.agentHeight),
      agentMaxClimb: number('agentMaxClimb', defaults.agentMaxClimb),
      agentMaxSlopeDegrees: number(
        'agentMaxSlopeDegrees',
        defaults.agentMaxSlopeDegrees,
      ),
      minRegionArea: number('minRegionArea', defaults.minRegionArea),
      mergeRegionArea: number('mergeRegionArea', defaults.mergeRegionArea),
      maxEdgeLength: number('maxEdgeLength', defaults.maxEdgeLength),
      maxSimplificationError: number(
        'maxSimplificationError',
        defaults.maxSimplificationError,
      ),
      maxVertsPerPolygon:
          (json['maxVertsPerPolygon'] as num?)?.toInt() ??
          defaults.maxVertsPerPolygon,
    );
  }
}
