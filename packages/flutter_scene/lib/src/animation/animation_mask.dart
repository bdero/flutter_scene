/// Which bones a clip is allowed to move.
///
/// The piece that lets a character aim while running. A mask names part of
/// the skeleton, a clip carries one, and the clip's influence is scaled per
/// node by what the mask says: the aim clip drives the spine and arms at full
/// weight and the legs at none, so the run underneath it keeps them.
///
/// Masks are by node name rather than by node, because a mask outlives the
/// skeleton it was authored against: it is saved with the scene, applies to
/// every character sharing a rig, and survives a re-import that replaced
/// every Node object.
part of '../animation.dart';

/// A per-node weight, from the names of the nodes it covers.
///
/// The usual shape is a root name with [includeDescendants], because a rig is
/// a tree and "the upper body" means a joint and everything under it.
/// {@category Animation}
class AnimationMask {
  /// Creates a mask covering [nodeNames] at [weight], and everything under
  /// them when [includeDescendants].
  ///
  /// Nodes outside the mask get [outsideWeight], which is zero for the usual
  /// "only these bones" and can be raised for a partial blend -- an upper
  /// body at full strength over legs that still feel a little of the same
  /// clip.
  AnimationMask(
    Iterable<String> nodeNames, {
    this.includeDescendants = true,
    this.weight = 1.0,
    this.outsideWeight = 0.0,
  }) : nodeNames = Set<String>.unmodifiable(nodeNames);

  /// A mask that lets everything through, which is what a clip with no mask
  /// behaves like.
  static final AnimationMask everything = AnimationMask(
    const [],
    outsideWeight: 1.0,
  );

  /// The names the mask is anchored on.
  final Set<String> nodeNames;

  /// Whether a named node's subtree is covered too.
  final bool includeDescendants;

  /// The weight inside the mask.
  final double weight;

  /// The weight outside it.
  final double outsideWeight;

  /// The weight this mask gives [node].
  ///
  /// Walks up to the nearest named ancestor when [includeDescendants], so a
  /// mask naming one spine joint covers the whole upper body without listing
  /// every finger.
  double weightFor(Node node) {
    if (nodeNames.contains(node.name)) return weight;
    if (includeDescendants) {
      Node? walk = node.parent;
      while (walk != null) {
        if (nodeNames.contains(walk.name)) return weight;
        walk = walk.parent;
      }
    }
    return outsideWeight;
  }

  /// Whether this mask changes anything, so a clip carrying a mask that
  /// covers everything at full weight can skip the per-node work.
  bool get isUniform => nodeNames.isEmpty || (weight == outsideWeight);

  /// The uniform weight, when [isUniform].
  double get uniformWeight => nodeNames.isEmpty ? outsideWeight : weight;

  /// A mask covering the same nodes at a different strength.
  AnimationMask scaled(double factor) => AnimationMask(
    nodeNames,
    includeDescendants: includeDescendants,
    weight: weight * factor,
    outsideWeight: outsideWeight * factor,
  );

  @override
  String toString() =>
      'AnimationMask(${nodeNames.length} nodes, weight $weight, '
      'outside $outsideWeight)';
}
