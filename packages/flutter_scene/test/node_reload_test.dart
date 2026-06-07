// Tests for in-place model hot reload: Node.reloadFromTemplate swaps a node's
// contents while preserving its identity, and live AnimationClips re-bind to
// the new subtree (by node name) keeping their playback state. No GPU context
// is required: these use mesh-less nodes and a hand-built translation
// animation.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A template: root "Model" with a child "Bone" and a "Move" animation that
/// translates Bone to x=10 at t=1.
Node _buildTemplate() {
  final root = Node(name: 'Model')..add(Node(name: 'Bone'));
  root.addParsedAnimation(
    Animation(
      name: 'Move',
      channels: [
        AnimationChannel(
          bindTarget: BindKey(
            nodeName: 'Bone',
            property: AnimationProperty.translation,
          ),
          resolver: PropertyResolver.makeTranslationTimeline(
            [0.0, 1.0],
            [Vector3.zero(), Vector3(10, 0, 0)],
          ),
        ),
      ],
    ),
  );
  return root;
}

double _boneX(Node model) =>
    model.getChildByName('Bone')!.localTransform.getTranslation().x;

void main() {
  test('reloadFromTemplate preserves node identity, swaps contents', () {
    final instance = _buildTemplate().clone();
    final oldBone = instance.getChildByName('Bone')!;

    instance.reloadFromTemplate(_buildTemplate());

    final newBone = instance.getChildByName('Bone')!;
    expect(newBone, isNot(same(oldBone))); // contents replaced
    expect(instance.children, isNot(contains(oldBone))); // old detached
    expect(oldBone.parent, isNull);
  });

  test('a playing clip re-binds to the swapped subtree, keeping playback', () {
    final instance = _buildTemplate().clone();

    final clip = instance.createAnimationClip(
      instance.findAnimationByName('Move')!,
    )..play();
    clip.seek(1.0);
    instance.scenePrePass(0); // apply at t=1
    expect(_boneX(instance), closeTo(10, 1e-6));

    instance.reloadFromTemplate(_buildTemplate());

    // Playback state is carried on the same clip object.
    expect(clip.playbackTime, closeTo(1.0, 1e-9));
    expect(clip.playing, isTrue);

    // The clip now drives the new Bone node.
    instance.scenePrePass(0);
    expect(_boneX(instance), closeTo(10, 1e-6));
  });

  test('clip keeps animating across reload when left running', () {
    final instance = _buildTemplate().clone();
    final clip = instance.createAnimationClip(
      instance.findAnimationByName('Move')!,
    )..play();

    instance.scenePrePass(0.5); // halfway: x ~= 5
    expect(_boneX(instance), closeTo(5, 1e-6));

    instance.reloadFromTemplate(_buildTemplate());

    instance.scenePrePass(0.5); // now at t=1: x ~= 10
    expect(clip.playbackTime, closeTo(1.0, 1e-9));
    expect(_boneX(instance), closeTo(10, 1e-6));
  });
}
