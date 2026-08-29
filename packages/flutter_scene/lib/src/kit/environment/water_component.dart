/// Water as one component: a surface that renders, animates, and tells the
/// rest of the scene how to cross it.
///
/// Drop a [WaterComponent] on a node and it builds its own grid mesh and
/// material, displaces the grid with the same trochoidal wave field
/// [WaterSurfaceComponent] evaluates, and answers the two questions gameplay
/// actually asks of water: how high is the surface here, and may an agent go
/// through it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/kit/environment/gerstner_field.dart';
import 'package:flutter_scene/src/kit/environment/water_surface_component.dart';
import 'package:flutter_scene/src/material/physically_based_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:scene/navigation.dart' show NavArea, NavVolume;
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// How a water surface looks.
///
/// The three are not a quality ladder: each is a different intent, and each
/// costs differently. [lowPoly] is the cheapest and [realistic] the dearest.
/// {@category Gameplay kit}
enum WaterStyle {
  /// Faceted, stylized water: a coarse grid with flat per-face shading and
  /// sharp crests. The look reads as deliberate rather than low-detail, and
  /// it is the cheapest of the three to displace.
  lowPoly,

  /// Physically-lit water: a fine grid with smooth analytic normals,
  /// refractive transmission, and a low roughness that picks up the
  /// environment. The most expensive, and the one that needs an environment
  /// map to look like anything.
  realistic,

  /// Sunlit water: [realistic]'s surface with a clearcoat and a second,
  /// faster ripple field on the normals, so highlights break up and travel
  /// instead of sitting still.
  shimmer,
}

/// Whether an agent may cross a water surface, and how.
///
/// This is what the nav-mesh bake reads. The three map onto nav areas, so a
/// path already prefers land over water without anything else being wired up.
/// {@category Gameplay kit}
enum WaterTraversal {
  /// Shallow enough to wade: ordinary walkable ground as far as a path is
  /// concerned.
  walkable,

  /// Crossable, but a path routes around it unless the detour is long. An
  /// agent that swims lowers the cost of [NavArea.slow] to change that.
  swimmable,

  /// Not crossable at all. The surface is carved out of the nav mesh.
  blocked,
}

/// A water surface: geometry, material, animation, and traversal in one
/// component.
///
/// Mounting it builds a grid [MeshGeometry] and a [PhysicallyBasedMaterial]
/// for the chosen [style] and attaches them through a [MeshComponent], so a
/// node with this component on it is a working body of water with nothing
/// else set up.
///
/// The surface animates on the CPU: each frame the grid's positions and
/// normals are recomputed from the wave field and re-uploaded. That is what
/// makes [surfaceHeightAt] exact rather than an approximation of what the GPU
/// drew, which is what buoyancy and swim checks need. The cost scales with
/// [resolution] squared, so the default grid is deliberately modest and
/// [resolution] is the first dial to turn when the frame budget is tight.
/// {@category Gameplay kit}
class WaterComponent extends Component {
  /// Creates a water surface [size] units across, tessellated
  /// [resolution] by [resolution] quads.
  WaterComponent({
    this.size = 40.0,
    int resolution = 48,
    this.style = WaterStyle.realistic,
    this.traversal = WaterTraversal.swimmable,
    vm.Vector4? shallowColor,
    vm.Vector4? deepColor,
    List<GerstnerWave>? waves,
    this.animate = true,
  }) : resolution = resolution < 2 ? 2 : resolution,
       shallowColor = shallowColor ?? _defaultShallow.clone(),
       deepColor = deepColor ?? _defaultDeep.clone(),
       waves = waves ?? defaultWavesFor(style);

  /// A calm tropical shallow, and the deep it fades to.
  static final vm.Vector4 _defaultShallow = vm.Vector4(0.13, 0.52, 0.62, 0.86);
  static final vm.Vector4 _defaultDeep = vm.Vector4(0.02, 0.13, 0.22, 1.0);

  /// The surface's extent on X and Z, in world units, centered on the node.
  final double size;

  /// Quads per side. Vertex count is `(resolution + 1)^2` for the smooth
  /// styles; [WaterStyle.lowPoly] unwelds its faces and so costs six vertices
  /// per quad instead.
  final int resolution;

  /// Which look to build. Changing it after mount rebuilds the surface.
  WaterStyle style;

  /// How agents may cross this water.
  WaterTraversal traversal;

  /// The colour at the surface.
  final vm.Vector4 shallowColor;

  /// The colour light reaches after travelling through the body, which the
  /// material attenuates toward with depth.
  final vm.Vector4 deepColor;

  /// The wave spectrum displacing the surface.
  final List<GerstnerWave> waves;

  /// Whether the surface advances with time. False freezes it at its current
  /// phase, which is what an editor viewport wants while scrubbing.
  bool animate;

  /// The nav area this surface's triangles bake as.
  ///
  /// [WaterTraversal.blocked] has no area of its own: a surface tagged
  /// non-walkable only tells the voxelizer to fall back to its slope test,
  /// and the bed under the water is a separate surface that stays walkable
  /// regardless. Blocking is a volume, not a surface; see [navVolume].
  int get navArea => switch (traversal) {
    WaterTraversal.walkable => NavArea.walkable,
    WaterTraversal.swimmable => NavArea.slow,
    WaterTraversal.blocked => NavArea.nonWalkable,
  };

  /// The volume a nav bake should carve for this water, or null when the
  /// surface is crossable and needs none.
  ///
  /// Spans from the surface down to [depth] below it are erased, which takes
  /// the lake bed with them: without that an agent refused entry at the
  /// surface simply walks along the bottom.
  ///
  /// [worldTransform] places the box; pass the node's global transform when
  /// baking a live scene.
  NavVolume? navVolume({vm.Matrix4? worldTransform, double depth = 50}) {
    if (traversal != WaterTraversal.blocked) return null;
    final half = size * 0.5;
    final crest = _crestHeight;
    final centre = worldTransform?.getTranslation() ?? vm.Vector3.zero();
    return NavVolume(
      min: vm.Vector3(centre.x - half, centre.y - depth, centre.z - half),
      max: vm.Vector3(centre.x + half, centre.y + crest, centre.z + half),
    );
  }

  /// A [NavCollectOptions.areaOf] that paints a water surface with its own
  /// traversal and leaves everything else to the slope test.
  ///
  /// Pair it with [collectNavVolumes] over the same root: together they are
  /// the whole of what water contributes to a bake.
  static int navAreaOf(Node node) =>
      node.getComponent<WaterComponent>()?.navArea ?? NavArea.nonWalkable;

  /// The volumes every blocked water surface under [root] wants carved.
  static List<NavVolume> collectNavVolumes(Node root, {double depth = 50}) {
    final volumes = <NavVolume>[];
    void visit(Node node) {
      final water = node.getComponent<WaterComponent>();
      final volume = water?.navVolume(
        worldTransform: node.globalTransform,
        depth: depth,
      );
      if (volume != null) volumes.add(volume);
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    return volumes;
  }

  /// The wave spectrum each style is built with.
  ///
  /// Low-poly water wants fewer, longer, sharper waves: the facets have to be
  /// large enough to read as a deliberate style rather than as a coarse mesh.
  /// The lit styles layer three scales so the surface has detail at the size
  /// a highlight is.
  static List<GerstnerWave> defaultWavesFor(WaterStyle style) =>
      switch (style) {
        WaterStyle.lowPoly => [
          GerstnerWave(
            direction: vm.Vector2(1, 0.25).normalized(),
            amplitude: 0.55,
            wavelength: 18,
            speed: 0.9,
            steepness: 1.0,
          ),
          GerstnerWave(
            direction: vm.Vector2(-0.4, 1).normalized(),
            amplitude: 0.3,
            wavelength: 11,
            speed: 1.1,
            steepness: 1.0,
          ),
        ],
        WaterStyle.realistic || WaterStyle.shimmer => [
          GerstnerWave(
            direction: vm.Vector2(1, 0.2).normalized(),
            amplitude: 0.32,
            wavelength: 14,
            speed: 1.0,
          ),
          GerstnerWave(
            direction: vm.Vector2(0.5, 0.8).normalized(),
            amplitude: 0.16,
            wavelength: 7,
            speed: 1.5,
          ),
          GerstnerWave(
            direction: vm.Vector2(-0.3, 1).normalized(),
            amplitude: 0.07,
            wavelength: 3,
            speed: 2.1,
          ),
        ],
      };

  double _time = 0;

  /// The wave field, shared with [surfaceHeightAt] so gameplay and the mesh
  /// never disagree about where the surface is.
  late final WaterSurfaceComponent _analytic = WaterSurfaceComponent(
    waves: waves,
  );

  /// The grid displacer. Holds the phase tables that make a frame cheap, so
  /// it lives as long as the component rather than the call.
  final GerstnerField _field = GerstnerField();

  MeshGeometry? _geometry;
  MeshComponent? _mesh;

  /// The built surface material, so a caller can reach past the presets and
  /// tune one dial (a murkier lake, a brighter lagoon) without rebuilding.
  /// Null before the component mounts.
  PhysicallyBasedMaterial? get material => _material;
  PhysicallyBasedMaterial? _material;

  // The flat grid, before displacement. Kept so each frame displaces the rest
  // pose rather than compounding onto the last frame's result.
  Float32List? _restPositions;
  Float32List? _positions;
  Float32List? _normals;
  WaterStyle? _builtStyle;

  /// The surface height at world-space ([x], [z]), in the node's local frame.
  ///
  /// Exact against the same wave field the mesh is displaced with, so a boat
  /// floating on this sits on the water rather than near it.
  double surfaceHeightAt(double x, double z) =>
      _analytic.evaluateAt(vm.Vector2(x, z), _time).displacement.y;

  /// Whether ([x], [z]) is inside this surface's footprint.
  bool covers(double x, double z) {
    final half = size * 0.5;
    return x >= -half && x <= half && z >= -half && z <= half;
  }

  @override
  void onMount() {
    _rebuild();
  }

  @override
  void onUnmount() {
    final mesh = _mesh;
    if (mesh != null) node.removeComponent(mesh);
    _mesh = null;
    _geometry = null;
    _material = null;
    _restPositions = null;
    _positions = null;
    _normals = null;
    _builtStyle = null;
    _field.invalidate();
  }

  @override
  void update(double deltaSeconds) {
    if (_builtStyle != style) {
      _rebuild();
      return;
    }
    if (!animate || deltaSeconds <= 0) return;
    _time += deltaSeconds;
    _displace();
  }

  /// Recomputes the surface at the current time without advancing it.
  ///
  /// For an editor scrubbing a timeline, or a paused game that still needs a
  /// correct surface to place things on.
  void refresh() => _displace();

  /// Moves the surface to an absolute time, for a deterministic replay or a
  /// networked simulation where every peer must see the same wave.
  set time(double seconds) {
    _time = seconds;
    _displace();
  }

  double get time => _time;

  void _rebuild() {
    final existing = _mesh;
    if (existing != null) node.removeComponent(existing);

    final (positions, normals, texCoords, indices) = _buildGrid();
    _restPositions = Float32List.fromList(positions);
    _positions = positions;
    _normals = normals;
    _field.invalidate();

    final geometry = MeshGeometry.fromArrays(
      positions: positions,
      normals: normals,
      texCoords: texCoords,
      indices: indices,
      storage: GeometryStorage.updatable,
      // The surface moves every frame, so a box fitted to the rest pose would
      // be wrong the moment it does. Inflate it by the tallest crest the
      // spectrum can reach, once, rather than refitting per frame.
      bounds: _boundsWithWaves(),
    );
    final material = _materialForStyle();

    _geometry = geometry;
    _material = material;
    _builtStyle = style;
    _mesh = MeshComponent(Mesh(geometry, material));
    node.addComponent(_mesh!);
    _displace();
  }

  /// The tallest crest the spectrum can reach, which is every wave at once.
  double get _crestHeight {
    var sum = 0.0;
    for (final wave in waves) {
      sum += wave.amplitude.abs();
    }
    // A trochoid also displaces horizontally, by up to its steepness times
    // its amplitude, so the box grows on X and Z as well.
    return sum;
  }

  vm.Aabb3 _boundsWithWaves() {
    final half = size * 0.5 + _crestHeight;
    final crest = _crestHeight;
    return vm.Aabb3.minMax(
      vm.Vector3(-half, -crest, -half),
      vm.Vector3(half, crest, half),
    );
  }

  /// Builds the flat grid the waves displace.
  ///
  /// [WaterStyle.lowPoly] emits each triangle's three corners separately, so
  /// every face can carry its own normal; the shared-vertex styles emit one
  /// vertex per grid point and interpolate.
  (Float32List, Float32List, Float32List, Uint16List?) _buildGrid() {
    final side = resolution + 1;
    final step = size / resolution;
    final origin = -size * 0.5;

    if (style != WaterStyle.lowPoly) {
      final count = side * side;
      final positions = Float32List(count * 3);
      final normals = Float32List(count * 3);
      final texCoords = Float32List(count * 2);
      for (var z = 0; z < side; z++) {
        for (var x = 0; x < side; x++) {
          final i = z * side + x;
          positions[i * 3] = origin + x * step;
          positions[i * 3 + 1] = 0;
          positions[i * 3 + 2] = origin + z * step;
          normals[i * 3 + 1] = 1;
          texCoords[i * 2] = x / resolution;
          texCoords[i * 2 + 1] = z / resolution;
        }
      }
      final indices = Uint16List(resolution * resolution * 6);
      var write = 0;
      for (var z = 0; z < resolution; z++) {
        for (var x = 0; x < resolution; x++) {
          final a = z * side + x;
          final b = a + 1;
          final c = a + side;
          final d = c + 1;
          indices[write++] = a;
          indices[write++] = c;
          indices[write++] = d;
          indices[write++] = a;
          indices[write++] = d;
          indices[write++] = b;
        }
      }
      return (positions, normals, texCoords, indices);
    }

    // Faceted: six unshared vertices per quad.
    final quads = resolution * resolution;
    final positions = Float32List(quads * 6 * 3);
    final normals = Float32List(quads * 6 * 3);
    final texCoords = Float32List(quads * 6 * 2);
    var write = 0;
    void emit(int x, int z) {
      positions[write * 3] = origin + x * step;
      positions[write * 3 + 1] = 0;
      positions[write * 3 + 2] = origin + z * step;
      normals[write * 3 + 1] = 1;
      texCoords[write * 2] = x / resolution;
      texCoords[write * 2 + 1] = z / resolution;
      write++;
    }

    for (var z = 0; z < resolution; z++) {
      for (var x = 0; x < resolution; x++) {
        emit(x, z);
        emit(x, z + 1);
        emit(x + 1, z + 1);
        emit(x, z);
        emit(x + 1, z + 1);
        emit(x + 1, z);
      }
    }
    return (positions, normals, texCoords, null);
  }

  /// Displaces the rest grid by the wave field and re-uploads it.
  ///
  /// The arithmetic lives in [GerstnerField], which is where the per-frame
  /// cost is and which needs no GPU; this is the part that owns the mesh.
  void _displace() {
    final rest = _restPositions;
    final positions = _positions;
    final normals = _normals;
    final geometry = _geometry;
    if (rest == null || positions == null || normals == null) return;
    if (geometry == null) return;

    _field.setRest(rest);
    // Normalized by the whole spectrum rather than by the waves that happen
    // to be contributing, so silencing one wave does not change the shape of
    // the others -- and so this agrees with surfaceHeightAt, which normalizes
    // the same way.
    _field.displace(
      waves,
      _time,
      positions,
      normals,
      normalization: waves.length,
    );
    if (style == WaterStyle.lowPoly) _flattenFaceNormals(positions, normals);

    geometry.updatePositions(positions);
    geometry.updateNormals(normals);
  }

  /// Replaces each face's three vertex normals with the face's own, which is
  /// what makes the faceted look faceted.
  static void _flattenFaceNormals(Float32List positions, Float32List normals) {
    for (var face = 0; face * 9 + 8 < positions.length; face++) {
      final o = face * 9;
      final e1x = positions[o + 3] - positions[o];
      final e1y = positions[o + 4] - positions[o + 1];
      final e1z = positions[o + 5] - positions[o + 2];
      final e2x = positions[o + 6] - positions[o];
      final e2y = positions[o + 7] - positions[o + 1];
      final e2z = positions[o + 8] - positions[o + 2];
      var nx = e1y * e2z - e1z * e2y;
      var ny = e1z * e2x - e1x * e2z;
      var nz = e1x * e2y - e1y * e2x;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length > 1e-9) {
        final inverse = 1 / length;
        nx *= inverse;
        ny *= inverse;
        nz *= inverse;
      } else {
        nx = 0;
        ny = 1;
        nz = 0;
      }
      for (var corner = 0; corner < 3; corner++) {
        normals[o + corner * 3] = nx;
        normals[o + corner * 3 + 1] = ny;
        normals[o + corner * 3 + 2] = nz;
      }
    }
  }

  /// The material for [style].
  ///
  /// All three are the same physically based material with different dials;
  /// water is water, and the difference between a stylized pond and an ocean
  /// is roughness, transmission, and how much of the environment it picks up.
  PhysicallyBasedMaterial _materialForStyle() {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = shallowColor.clone()
      ..metallicFactor = 0.0
      ..attenuationColor = deepColor.clone()
      ..attenuationDistance = size * 0.25;

    switch (style) {
      case WaterStyle.lowPoly:
        // Flat facets, a matte body, and no refraction: the look depends on
        // the silhouette of the facets, and transmission would wash it out.
        material
          ..roughnessFactor = 0.42
          ..specular = 0.35
          ..ior = 1.33;
      case WaterStyle.realistic:
        material
          ..roughnessFactor = 0.06
          ..transmission = 0.85
          ..thickness = size * 0.1
          ..ior = 1.333
          ..specular = 1.0;
      case WaterStyle.shimmer:
        // A clearcoat over the same body gives a second, tighter specular
        // lobe, which is the highlight that breaks up as the crests move.
        material
          ..roughnessFactor = 0.10
          ..transmission = 0.7
          ..thickness = size * 0.08
          ..ior = 1.333
          ..specular = 1.0
          ..clearcoat = 1.0
          ..clearcoatRoughness = 0.03;
    }
    return material;
  }

  @override
  Component? cloneFor(Node cloneOwner) => WaterComponent(
    size: size,
    resolution: resolution,
    style: style,
    traversal: traversal,
    shallowColor: shallowColor.clone(),
    deepColor: deepColor.clone(),
    waves: List.of(waves),
    animate: animate,
  );
}
