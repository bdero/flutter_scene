/// Bends a limb onto a target after the animation has posed it.
library;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/animation/two_bone_ik.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_scene/src/node.dart';

/// Solves the limb `root -> mid -> tip` so its tip reaches a target, every
/// frame, after the clip has played.
///
/// This runs in [Component.lateUpdate] rather than [Component.update], which
/// is the whole point: correcting a pose in `update` reads last frame's bones
/// and is overwritten by the animation player moments later.
///
/// The bones are named, not held, so a rig swapped underneath (a model hot
/// reload, a prefab re-instanced) is picked up rather than leaving the
/// constraint driving nodes that are no longer in the scene.
///
/// ```dart
/// character.addComponent(
///   IkConstraintComponent(
///     rootBone: 'thigh.L',
///     midBone: 'shin.L',
///     tipBone: 'foot.L',
///     // Plant the foot on the terrain under it.
///     target: (foot) => Vector3(
///       foot.x,
///       terrain.heightAtWorld(foot.x, foot.z),
///       foot.z,
///     ),
///   ),
/// );
/// ```
/// {@category Animation}
class IkConstraintComponent extends Component {
  /// Constrains the limb named by [rootBone], [midBone] and [tipBone].
  ///
  /// [target] is asked each frame where the tip should be, given where it
  /// currently is in world space. [pole] optionally says which way the joint
  /// bends; without it the animated pose decides.
  IkConstraintComponent({
    required this.rootBone,
    required this.midBone,
    required this.tipBone,
    required this.target,
    this.pole,
    this.weight = 1.0,
    this.softness = 0.01,
  });

  /// The upper bone's node name.
  final String rootBone;

  /// The middle joint's node name.
  final String midBone;

  /// The tip's node name — the foot, or the hand.
  final String tipBone;

  /// Where the tip should be, asked each frame with where it currently is.
  /// Returning null leaves the limb alone for that frame, which is how a
  /// foot stops being planted while its owner is in the air.
  final Vector3? Function(Vector3 tipWorldPosition) target;

  /// World-space hint for which way the joint bends.
  final Vector3? Function()? pole;

  /// How much of the solve to apply, `0` to `1`. Fading this rather than
  /// switching the constraint off avoids the limb snapping when it engages.
  double weight;

  /// How far short of locked-straight the limb stops.
  double softness;

  Node? _root;
  Node? _mid;
  Node? _tip;
  bool _reported = false;

  @override
  bool get wantsLateUpdate => true;

  @override
  void lateUpdate(double deltaSeconds) {
    if (!isAttached || weight <= 0) return;
    if (!_bind()) return;

    final root = _root!;
    final mid = _mid!;
    final tip = _tip!;

    final rootPosition = root.globalTransform.getTranslation();
    final midPosition = mid.globalTransform.getTranslation();
    final tipPosition = tip.globalTransform.getTranslation();

    final desired = target(tipPosition);
    if (desired == null) return;

    final solution = solveTwoBoneIk(
      rootPosition: rootPosition,
      midPosition: midPosition,
      tipPosition: tipPosition,
      target: desired,
      pole: pole?.call(),
      softness: softness,
    );

    final blend = weight.clamp(0.0, 1.0);
    _applyWorldRotation(root, solution.root, blend);
    _applyWorldRotation(mid, solution.mid, blend);
  }

  /// Applies a world-space delta [rotation] to [node]'s local rotation,
  /// eased in by [blend].
  ///
  /// The delta arrives in world space but a node's rotation is local, so it
  /// is carried across by the parent's world rotation. Skipping that makes a
  /// limb on a turned character bend in the wrong direction, which only shows
  /// up once something faces away from +Z.
  void _applyWorldRotation(Node node, Quaternion rotation, double blend) {
    final delta = blend >= 1.0
        ? rotation
        : Quaternion.identity().slerp(rotation, blend);
    // Through the transform matrix a node's rotation composes into, (a * b)
    // applies b first, so a node's world rotation is parent * local. A
    // world-space delta D therefore becomes the local delta
    // (P-inverse * D * P), applied before the current rotation.
    //
    // Note this is the opposite order to Quaternion.rotated, which turns the
    // other way for the same quaternion. Only the matrix reading matters
    // here, because that is what Node.rotation feeds.
    final parent = node.parent;
    final localDelta = parent == null
        ? delta
        : () {
            final parentRotation = Quaternion.fromRotation(
              parent.globalTransform.getRotation(),
            )..normalize();
            return parentRotation.inverted() * delta * parentRotation;
          }();
    node.rotation = localDelta * node.rotation;
  }

  /// Resolves the three bone names, reporting once if any is missing.
  bool _bind() {
    if (_root != null && _mid != null && _tip != null) return true;
    _root = node.getChildByName(rootBone) ?? _named(rootBone);
    _mid = node.getChildByName(midBone) ?? _named(midBone);
    _tip = node.getChildByName(tipBone) ?? _named(tipBone);
    if (_root != null && _mid != null && _tip != null) return true;
    if (!_reported) {
      _reported = true;
      final missing = [
        if (_root == null) rootBone,
        if (_mid == null) midBone,
        if (_tip == null) tipBone,
      ].join(', ');
      debugPrint(
        'IkConstraintComponent: no bone named $missing under '
        '"${node.name}"; the limb is left alone',
      );
    }
    return false;
  }

  Node? _named(String name) {
    Node? found;
    void search(Node current) {
      if (found != null) return;
      if (current.name == name) {
        found = current;
        return;
      }
      for (final child in current.children) {
        search(child);
      }
    }

    search(node);
    return found;
  }

  @override
  void onDetach() {
    _root = null;
    _mid = null;
    _tip = null;
    _reported = false;
  }
}
