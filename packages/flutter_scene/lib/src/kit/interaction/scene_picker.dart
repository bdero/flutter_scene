import 'dart:ui' show Offset, Rect, Size;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/raycast.dart';
import 'package:flutter_scene/src/scene.dart';

/// Answers "what did the player click on?" against a scene.
///
/// The engine already casts rays through scene geometry ([Scene.raycast],
/// [raycastNode]). This is the layer above it that games actually need: it
/// converts a pointer position into a ray, and — crucially — resolves the
/// *object* that was hit rather than the mesh node that happened to be under
/// the cursor.
///
/// That distinction is the whole reason this exists. A unit in a game is a
/// subtree: a root with a transform, and under it a body, a weapon, a hat.
/// Clicking the hat should select the unit. [selectableAt] walks up from the
/// hit toward the root and returns the first node that [isSelectable] accepts,
/// so the game works in terms of its own objects.
///
/// ```dart
/// final picker = ScenePicker.of(
///   scene,
///   isSelectable: (node) => node.name.startsWith('unit_'),
/// );
///
/// final unit = picker.selectableAt(
///   details.localPosition,
///   camera: scene.camera!,
///   viewSize: viewSize,
/// );
/// ```
///
/// A picker searches a [root] subtree rather than a whole scene, so a game can
/// keep several: one over the units, one over the terrain, one over the
/// placeable props. Narrowing the subtree is also the cheapest way to make
/// picking fast, since nothing outside it is ever tested.
/// {@category Picking and input}
class ScenePicker {
  /// Creates a picker over the [root] subtree.
  ///
  /// [isSelectable] marks the nodes that count as objects; the default treats
  /// [root]'s direct children as objects, which suits a scene where each thing
  /// is added at the top level. [layerMask], [where], and [maxDistance] narrow
  /// what the ray may hit at all, the same way [Scene.raycast] does.
  ScenePicker(
    this.root, {
    bool Function(Node node)? isSelectable,
    this.layerMask = 0xFFFFFFFF,
    this.where,
    this.maxDistance = double.infinity,
  }) : isSelectable = isSelectable ?? ((node) => node.parent == root);

  /// A picker over the whole of [scene].
  factory ScenePicker.of(
    Scene scene, {
    bool Function(Node node)? isSelectable,
    int layerMask = 0xFFFFFFFF,
    bool Function(Node node)? where,
    double maxDistance = double.infinity,
  }) => ScenePicker(
    scene.root,
    isSelectable: isSelectable,
    layerMask: layerMask,
    where: where,
    maxDistance: maxDistance,
  );

  /// The subtree this picker searches.
  final Node root;

  /// Which nodes count as objects the player can pick.
  bool Function(Node node) isSelectable;

  /// Layers the ray tests, against [Node.layers].
  int layerMask;

  /// Optional predicate excluding nodes from the ray entirely (the player's
  /// own model, a decorative overlay).
  bool Function(Node node)? where;

  /// How far the ray reaches, in world units.
  double maxDistance;

  /// The nearest geometry hit under [screenPosition], or null.
  SceneRaycastHit? hitAt(
    Offset screenPosition, {
    required Camera camera,
    required Size viewSize,
  }) => hitAlong(camera.screenPointToRay(screenPosition, viewSize));

  /// The nearest geometry hit along [ray], or null.
  SceneRaycastHit? hitAlong(Ray ray) => raycastNode(
    root,
    ray,
    maxDistance: maxDistance,
    layerMask: layerMask,
    where: where,
  );

  /// The object under [screenPosition], or null when the click landed on
  /// nothing pickable.
  Node? selectableAt(
    Offset screenPosition, {
    required Camera camera,
    required Size viewSize,
  }) => selectableAlong(camera.screenPointToRay(screenPosition, viewSize));

  /// The object along [ray], or null.
  Node? selectableAlong(Ray ray) {
    final hit = hitAlong(ray);
    return hit == null ? null : selectableOwnerOf(hit.node);
  }

  /// The object [node] belongs to: [node] itself when [isSelectable] accepts
  /// it, otherwise its nearest ancestor that does, or null when nothing on the
  /// way up to [root] qualifies.
  Node? selectableOwnerOf(Node node) {
    for (Node? walk = node; walk != null; walk = walk.parent) {
      if (isSelectable(walk)) return walk;
      if (identical(walk, root)) break;
    }
    return null;
  }

  /// The objects inside a screen-space rectangle: a drag-selection marquee.
  ///
  /// An object is caught when the centre of its world bounds projects inside
  /// [rect]. Testing the centre rather than the whole silhouette is the
  /// long-standing convention in strategy games, and it is the one that feels
  /// right: dragging a box catches the units *in* it, not every unit whose arm
  /// crosses its edge. Pass [requireFullyInside] to test all eight corners of
  /// the bounds instead, for a game where partial overlap should not count.
  ///
  /// Objects behind the camera are excluded, as are objects with no geometry
  /// (and so no bounds).
  List<Node> selectablesInScreenRect(
    Rect rect, {
    required Camera camera,
    required Size viewSize,
    bool requireFullyInside = false,
  }) => allSelectables()
      .where((node) {
        final bounds = node.combinedWorldBounds;
        if (bounds == null) return false;
        if (!requireFullyInside) {
          final screen = camera.worldToScreen(bounds.center, viewSize);
          return screen != null && rect.contains(screen);
        }
        for (final corner in _cornersOf(bounds)) {
          final screen = camera.worldToScreen(corner, viewSize);
          if (screen == null || !rect.contains(screen)) return false;
        }
        return true;
      })
      .toList(growable: false);

  /// Every node in the subtree that [isSelectable] accepts.
  List<Node> allSelectables() {
    final found = <Node>[];
    _collectSelectables(root, found);
    return found;
  }

  // Selectables do not nest: once a node qualifies, its subtree is part of
  // that object rather than a set of smaller objects, so the walk stops.
  void _collectSelectables(Node node, List<Node> into) {
    if (!identical(node, root) && isSelectable(node)) {
      into.add(node);
      return;
    }
    for (final child in node.children) {
      _collectSelectables(child, into);
    }
  }

  static List<Vector3> _cornersOf(Aabb3 bounds) {
    final min = bounds.min;
    final max = bounds.max;
    return <Vector3>[
      Vector3(min.x, min.y, min.z),
      Vector3(max.x, min.y, min.z),
      Vector3(min.x, max.y, min.z),
      Vector3(max.x, max.y, min.z),
      Vector3(min.x, min.y, max.z),
      Vector3(max.x, min.y, max.z),
      Vector3(min.x, max.y, max.z),
      Vector3(max.x, max.y, max.z),
    ];
  }
}
