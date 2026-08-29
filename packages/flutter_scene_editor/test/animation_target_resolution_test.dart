// Pins the animation preview's name→node resolution semantics — the exact
// behavior the runtime clip binder has (AnimationClip._bindToTarget): a bind
// name equal to the bound node's own name resolves to the node itself,
// otherwise it is a descendant lookup. This is the regression for keyframe
// channels targeting bones directly (keyPose / setAnimationKeyframe(s) record
// the bone's own name as the binding fallback), which used to be skipped
// because a descendant-only lookup never finds the node itself.
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/src/controller/animation_target_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

(Node, Node) _rig() {
  final bone = Node(name: 'Bone_001');
  final armature = Node(name: 'Armature')
    ..add(Node(name: 'Mesh_root')..add(bone));
  return (armature, bone);
}

void main() {
  test('a targetName equal to the live node resolves to the node itself', () {
    final (armature, bone) = _rig();
    // The channel targets the bone node directly and stores the bone's own
    // name as the binding fallback — the shape that keyPose /
    // `setAnimationKeyframe` author. Descendant-only lookups used to miss
    // this and drop the channel.
    expect(resolveChannelTarget(bone, 'Bone_001'), same(bone));
    // The channel targets the armature, not a bone inside it.
    expect(resolveChannelTarget(armature, 'Armature'), same(armature));
  });

  test('a targetName naming a descendant resolves to that descendant', () {
    final (armature, bone) = _rig();
    // The channel targets the armature but names a bone inside it — a bone
    // inside an imported prefab instance, whose instance node has a different
    // name than the bone it drives.
    expect(resolveChannelTarget(armature, 'Bone_001'), same(bone));
  });

  test('an unmatched targetName resolves to null', () {
    final (armature, _) = _rig();
    expect(
      resolveChannelTarget(armature, 'NoSuchNode'),
      isNull,
      reason: 'a name matching neither the node nor a descendant is a miss',
    );
  });

  test('a null targetName leaves the live node unchanged', () {
    final (armature, _) = _rig();
    // Document-id-bound channels carry no name fallback and need no
    // resolution; the node they already bound to is what they drive.
    expect(resolveChannelTarget(armature, null), same(armature));
  });
}
