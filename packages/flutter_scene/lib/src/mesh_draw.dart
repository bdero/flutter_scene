import 'package:vector_math/vector_math.dart';

/// The kind of pass a [MeshDrawSelector] chooses for.
/// {@category Geometry}
enum MeshDrawPass {
  /// The opaque and translucent color passes.
  color,

  /// The camera depth prepass.
  depth,

  /// A shadow map.
  shadow,
}

/// What a [MeshDrawSelector] sees for one draw.
///
/// The renderer reuses one instance across draws, so a selector must not
/// keep it.
/// {@category Geometry}
final class MeshDrawContext {
  /// Creates a context. The renderer builds these; tests may too.
  MeshDrawContext({
    required this.pass,
    required this.cameraPosition,
    required this.primaryView,
  });

  /// The pass being encoded.
  MeshDrawPass pass;

  /// The world-space position of the camera rendering the pass. Spot and
  /// point shadow maps shared by a frame's views take its screen view's
  /// camera, so a render texture shows the shadows the screen view sees.
  Vector3 cameraPosition;

  /// Whether the pass renders for a screen view's camera. False for texture
  /// views, reflection captures, and shadow maps.
  bool primaryView;
}

/// The part of a mesh to draw.
///
/// A null [instanceCount] draws every instance, and a null [indexCount] every
/// index from [firstIndex]. For geometry without indices the index range
/// counts vertices.
/// {@category Geometry}
final class MeshDrawSelection {
  /// Selects [instanceCount] instances (a prefix of the instance list) and
  /// [indexCount] indices from [firstIndex].
  const MeshDrawSelection({
    this.instanceCount,
    this.firstIndex = 0,
    this.indexCount,
  }) : assert(instanceCount == null || instanceCount >= 0),
       assert(firstIndex >= 0),
       assert(indexCount == null || indexCount >= 0);

  /// Draws everything.
  static const all = MeshDrawSelection();

  /// How many leading instances draw, or null for all.
  final int? instanceCount;

  /// The first index (or vertex) drawn.
  final int firstIndex;

  /// How many indices (or vertices) draw, or null for the rest.
  final int? indexCount;

  /// Whether this selection draws the whole mesh.
  bool get isAll =>
      instanceCount == null && firstIndex == 0 && indexCount == null;
}

/// Picks the part of a mesh a draw uses, for level of detail that depends on
/// the pass or camera: fewer instances far away, a coarse index range in
/// shadow maps. Runs for every draw of the mesh, so it should be cheap.
/// {@category Geometry}
typedef MeshDrawSelector = MeshDrawSelection Function(MeshDrawContext context);

/// A mesh part that may carry a [MeshDrawSelector]. Render items read it
/// through this so a selector assigned later still applies.
abstract interface class MeshDrawSource {
  /// The selector, or null to draw everything.
  MeshDrawSelector? get drawSelector;
}
