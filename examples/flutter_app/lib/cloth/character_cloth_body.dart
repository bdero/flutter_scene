// Cloth colliders fitted to an animated character's skeleton.

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'cloth_solver.dart';

/// One capsule spanning two bones. A limb is `from` to `to`; a blob is the
/// same bone twice.
class ClothBone {
  const ClothBone(this.from, this.to, this.radius);

  final String from;
  final String to;
  final double radius;
}

/// Dash's body as capsules on his bones.
///
/// The sizes are measured off the model, not guessed. Fitting a sphere to the
/// vertices of his torso (which the mesh skins to the `Head` bone) gives a
/// centre of `(0, 1.44, 0.06)` and a radius of `1.0`, with the wing tips at
/// `x = +-0.97` falling inside it. So Dash really is one big sphere, plus a
/// beak, a crest, and thin legs, and that is what this describes.
const List<ClothBone> dashClothBones = [
  ClothBone('Body', 'Body', 1.0),
  // The beak runs forward to z = 1.46 and the crest up to y = 2.92, both just
  // past what the torso sphere covers.
  ClothBone('Head', 'BottomBeak', 0.32),
  ClothBone('Head', 'Tuft', 0.34),
  // Below the sphere, which bottoms out at y = 0.44.
  ClothBone('Body', 'Foot.L', 0.20),
  ClothBone('Body', 'Foot.R', 0.20),
  ClothBone('Foot.L', 'Toes.L', 0.20),
  ClothBone('Foot.R', 'Toes.R', 0.20),
];

/// A cloth collider that follows a character's animated bones.
///
/// Every bone the description names is looked up once in the model subtree;
/// [update] then reads their world transforms, which the animation player has
/// already posed for this frame, so the cloth is parted by the legs and the
/// beak as they swing rather than by a static shell.
class CharacterClothBody {
  CharacterClothBody({List<ClothBone> bones = dashClothBones})
    : _bones = bones,
      _capsules = [
        for (final bone in bones)
          ClothCapsule(
            start: Vector3.zero(),
            end: Vector3.zero(),
            radius: bone.radius,
          ),
      ] {
    collider = ClothColliderSet(_capsules);
  }

  final List<ClothBone> _bones;
  final List<ClothCapsule> _capsules;

  /// Add this to a solver's [ClothSolver.colliders].
  late final ClothColliderSet collider;

  final Map<String, Node> _nodes = {};
  bool _bound = false;

  /// Whether every named bone was found and the body is tracking.
  bool get isBound => _bound;

  /// Looks up the bones under [root]. Returns false until the model has
  /// loaded, so a caller can keep retrying each frame.
  bool bind(Node root) {
    _nodes.clear();
    final wanted = <String>{
      for (final bone in _bones) ...[bone.from, bone.to],
    };
    _collect(root, wanted);
    _bound = _nodes.length == wanted.length;
    return _bound;
  }

  void _collect(Node node, Set<String> wanted) {
    if (wanted.contains(node.name)) _nodes[node.name] = node;
    for (final child in node.children) {
      _collect(child, wanted);
    }
  }

  /// Re-poses the capsules from the bones' current world transforms, and
  /// refreshes the set's bounding sphere.
  void update() {
    if (!_bound) return;
    var centre = Vector3.zero();
    for (var i = 0; i < _bones.length; i++) {
      final bone = _bones[i];
      final from = _nodes[bone.from]!.globalTransform.getTranslation();
      final to = _nodes[bone.to]!.globalTransform.getTranslation();
      _capsules[i].placeAt(from, to);
      if (i == 0) centre = from;
    }

    // Cover both the sweep's start and its end, since the bound gates the
    // whole body for every substep in between.
    var reach = 0.0;
    for (final capsule in _capsules) {
      for (final point in capsule.sweepPoints) {
        reach = math.max(reach, centre.distanceTo(point) + capsule.radius);
      }
    }
    collider.setBounds(centre, reach);
  }
}
