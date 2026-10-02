import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// The channel/resolver data model and TRS plumbing are internal; tests
// reach them directly.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show
        AnimationChannel,
        AnimationProperty,
        BindKey,
        DecomposedTransform,
        PropertyResolver,
        RotationTimelineResolver,
        TranslationTimelineResolver;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'fixtures/retarget_rigs.dart';

/// One bone of a synthetic rig: its parent, its rest position relative to
/// the rig root, and optionally a mirrored scale.
typedef _Bone = (String name, String? parent, Vector3 position);

/// A small humanoid, positions in meters relative to the rig root, Y up,
/// facing +Z, arms out in a T-pose.
List<_Bone> _humanoid({
  String hips = 'Hips',
  List<String> spine = const ['Spine', 'Spine1', 'Spine2'],
  String neck = 'Neck',
  String head = 'Head',
  String Function(String side, String part)? limb,
  double legScale = 1,
  double armScale = 1,
  double armDrop = 0,
}) {
  final name =
      limb ??
      (side, part) =>
          '$side${const {'shoulder': 'Shoulder', 'upperArm': 'Arm', 'lowerArm': 'ForeArm', 'hand': 'Hand', 'upperLeg': 'UpLeg', 'lowerLeg': 'Leg', 'foot': 'Foot', 'toes': 'ToeBase'}[part]}';
  final bones = <_Bone>[(hips, null, Vector3(0, 1.0 * legScale, 0))];
  var parent = hips;
  for (var i = 0; i < spine.length; i++) {
    final y = 1.0 * legScale + 0.42 * (i + 1) / (spine.length + 1);
    bones.add((spine[i], parent, Vector3(0, y, 0)));
    parent = spine[i];
  }
  final chestTop = parent;
  final shoulderY = 1.0 * legScale + 0.45;
  bones.add((neck, chestTop, Vector3(0, shoulderY + 0.07, 0)));
  bones.add((head, neck, Vector3(0, shoulderY + 0.17, 0)));
  for (final (side, x) in const [('Left', 1.0), ('Right', -1.0)]) {
    final drop = armDrop;
    Vector3 arm(double reach) => Vector3(
      x * (0.05 + reach * cos(drop)),
      shoulderY - reach * sin(drop),
      0,
    );
    bones.add((
      name(side, 'shoulder'),
      chestTop,
      Vector3(x * 0.05, shoulderY, 0),
    ));
    bones.add((
      name(side, 'upperArm'),
      name(side, 'shoulder'),
      arm(0.13 * armScale),
    ));
    bones.add((
      name(side, 'lowerArm'),
      name(side, 'upperArm'),
      arm(0.40 * armScale),
    ));
    bones.add((
      name(side, 'hand'),
      name(side, 'lowerArm'),
      arm(0.65 * armScale),
    ));
    final top = 0.95 * legScale;
    bones.add((name(side, 'upperLeg'), hips, Vector3(x * 0.1, top, 0)));
    bones.add((
      name(side, 'lowerLeg'),
      name(side, 'upperLeg'),
      Vector3(x * 0.1, top * 0.53, 0),
    ));
    bones.add((
      name(side, 'foot'),
      name(side, 'lowerLeg'),
      Vector3(x * 0.1, top * 0.08, 0),
    ));
    bones.add((
      name(side, 'toes'),
      name(side, 'foot'),
      Vector3(x * 0.1, 0.02, 0.12),
    ));
  }
  return bones;
}

/// Builds [bones] under a root, giving each bone the rest rotation
/// [restRotation] picks (random rolls make every bone's frame differ from
/// its source's) and placing it so its root-space position holds.
Node _buildRig(
  List<_Bone> bones, {
  Quaternion Function(String name)? restRotation,
  Map<String, Vector3> scales = const {},
  Matrix4? armature,
}) {
  final root = Node(name: 'rig');
  Node top = root;
  if (armature != null) {
    top = Node(name: 'Armature', localTransform: armature);
    root.add(top);
  }
  final nodes = <String, Node>{};
  for (final (name, parent, position) in bones) {
    final parentNode = parent == null ? top : nodes[parent]!;
    final parentGlobal = parentNode.globalTransform;
    final local = Matrix4.inverted(parentGlobal).transformed3(position);
    final node = Node(name: name);
    node.setLocalTransformTrs(
      DecomposedTransform(
        translation: local,
        rotation: restRotation?.call(name) ?? Quaternion.identity(),
        scale: scales[name] ?? Vector3.all(1),
      ),
    );
    parentNode.add(node);
    nodes[name] = node;
  }
  return root;
}

Quaternion _randomRotation(Random random) => Quaternion.axisAngle(
  Vector3(
    random.nextDouble() - 0.5,
    random.nextDouble() - 0.5,
    random.nextDouble() - 0.5,
  ).normalized(),
  random.nextDouble() * pi,
);

/// A clip that rotates every named bone through three random poses away
/// from its rest and moves [hips] around.
Animation _randomClip(Node rig, Random random, {String hips = 'Hips'}) {
  final channels = <AnimationChannel>[];
  void visit(Node node) {
    for (final child in node.children) {
      final rest = child.localTransformTrs!;
      channels.add(
        AnimationChannel(
          bindTarget: BindKey(
            nodeName: child.name,
            property: AnimationProperty.rotation,
          ),
          resolver: PropertyResolver.makeRotationTimeline(
            [0, 0.5, 1],
            [
              for (var k = 0; k < 3; k++)
                (rest.rotation *
                      Quaternion.axisAngle(
                        Vector3(
                          random.nextDouble() - 0.5,
                          random.nextDouble() - 0.5,
                          random.nextDouble() - 0.5,
                        ).normalized(),
                        random.nextDouble() * 1.2,
                      ))
                  ..normalize(),
            ],
          ),
        ),
      );
      if (child.name == hips) {
        channels.add(
          AnimationChannel(
            bindTarget: BindKey(nodeName: hips),
            resolver: PropertyResolver.makeTranslationTimeline(
              [0, 0.5, 1],
              [
                rest.translation,
                rest.translation + Vector3(0.3, -0.1, 0.2),
                rest.translation + Vector3(-0.2, 0.05, 0.4),
              ],
            ),
          ),
        );
      }
      visit(child);
    }
  }

  visit(rig);
  return Animation(name: 'random', channels: channels);
}

/// Poses [rig] with [animation] at [time].
void _pose(Node rig, Animation animation, double time) {
  rig.createAnimationClip(animation)
    ..weight = 1
    ..seek(time);
  rig.scenePrePass(0);
}

Node _find(Node rig, String name) => rig.getChildByName(name)!;

Matrix3 _linear(Node node) => node.globalTransform.getRotation();

/// The world rotation that took [node] from [rest] to where it is now.
Matrix3 _worldDelta(Node node, Matrix3 rest) =>
    _linear(node)..multiply(Matrix3.copy(rest)..invert());

double _maxDiff(Matrix3 a, Matrix3 b) {
  var d = 0.0;
  for (var i = 0; i < 9; i++) {
    d = max(d, (a.storage[i] - b.storage[i]).abs());
  }
  return d;
}

/// Asserts each paired target bone's world rotation away from rest matches
/// its source bone's, across [times].
void _expectMatchingDeltas(
  List<_Bone> sourceBones,
  List<_Bone> targetBones,
  Node Function() buildSource,
  Node Function() buildTarget,
  AnimationRetargeter Function(Node, Node) retargeter,
  Map<String, String> pairs, {
  List<double> times = const [0.0, 0.17, 0.5, 0.73, 1.0],
  double tolerance = 2e-4,
}) {
  final random = Random(7);
  final sourceRig = buildSource();
  final targetRig = buildTarget();
  final clip = _randomClip(sourceRig, random);
  final retargeted = retargeter(sourceRig, targetRig).retarget(clip);
  final sourceRest = {
    for (final s in pairs.values) s: _linear(_find(sourceRig, s)),
  };
  final targetRest = {
    for (final t in pairs.keys) t: _linear(_find(targetRig, t)),
  };
  for (final time in times) {
    final source = buildSource();
    final target = buildTarget();
    _pose(source, clip, time);
    _pose(target, retargeted, time);
    for (final MapEntry(key: t, value: s) in pairs.entries) {
      final diff = _maxDiff(
        _worldDelta(_find(target, t), targetRest[t]!),
        _worldDelta(_find(source, s), sourceRest[s]!),
      );
      expect(diff, lessThan(tolerance), reason: '$t <- $s at t=$time');
    }
  }
}

String _vrmLimb(String side, String part) =>
    '${side.toLowerCase()}${part[0].toUpperCase()}${part.substring(1)}';

Node _rigFromNames(List<(String, String?)> bones) {
  final root = Node(name: 'rig');
  final nodes = <String, Node>{};
  for (final (name, parent) in bones) {
    final node = Node(name: name);
    nodes.putIfAbsent(name, () => node);
    (parent == null ? root : nodes[parent]!).add(node);
  }
  return root;
}

void main() {
  group('rotation transfer', () {
    test('retargeting onto the same rig reproduces the keys', () {
      final bones = _humanoid();
      final rig = _buildRig(bones);
      final clip = _randomClip(rig, Random(1));
      final out = AnimationRetargeter(
        source: RetargetRig.fromNode(rig),
        target: RetargetRig.fromNode(rig),
      ).retarget(clip);
      for (final channel in clip.channels) {
        if (channel.bindTarget.property != AnimationProperty.rotation) {
          continue;
        }
        final match = out.channels.firstWhere(
          (c) =>
              c.bindTarget.nodeName == channel.bindTarget.nodeName &&
              c.bindTarget.property == AnimationProperty.rotation,
        );
        final a = (channel.resolver as RotationTimelineResolver).values;
        final b = (match.resolver as RotationTimelineResolver).values;
        for (var k = 0; k < a.length; k++) {
          expect(a[k].dot(b[k]).abs(), closeTo(1, 1e-5));
        }
      }
    });

    test('a key at the source rest lands on the target rest', () {
      final random = Random(2);
      final source = _buildRig(_humanoid());
      final target = _buildRig(
        _humanoid(),
        restRotation: (_) => _randomRotation(random),
      );
      final restClip = Animation(
        name: 'rest',
        channels: [
          for (final name in RetargetRig.fromNode(source).boneNames)
            AnimationChannel(
              bindTarget: BindKey(
                nodeName: name,
                property: AnimationProperty.rotation,
              ),
              resolver: PropertyResolver.makeRotationTimeline(
                [0, 1],
                [
                  _find(source, name).localTransformTrs!.rotation,
                  _find(source, name).localTransformTrs!.rotation,
                ],
              ),
            ),
        ],
      );
      final out = AnimationRetargeter(
        source: RetargetRig.fromNode(source),
        target: RetargetRig.fromNode(target),
      ).retarget(restClip);
      for (final channel in out.channels) {
        final rest = _find(
          target,
          channel.bindTarget.nodeName,
        ).localTransformTrs!.rotation;
        for (final q in (channel.resolver as RotationTimelineResolver).values) {
          expect(q.dot(rest).abs(), closeTo(1, 1e-5));
        }
      }
    });

    test('world rotations follow the source across renames, rolls, and '
        'proportions', () {
      final random = Random(3);
      final rolls = <String, Quaternion>{};
      final sourceBones = _humanoid();
      final targetBones = _humanoid(
        hips: 'pelvis',
        spine: const ['spine', 'chest', 'upperChest'],
        neck: 'neck',
        head: 'head',
        limb: _vrmLimb,
        legScale: 1.3,
        armScale: 0.8,
      );
      final pairs = {
        'pelvis': 'Hips',
        'spine': 'Spine',
        'chest': 'Spine1',
        'upperChest': 'Spine2',
        'neck': 'Neck',
        'head': 'Head',
        'leftUpperArm': 'LeftArm',
        'leftLowerArm': 'LeftForeArm',
        'leftHand': 'LeftHand',
        'rightLowerLeg': 'RightLeg',
        'rightFoot': 'RightFoot',
        'rightToes': 'RightToeBase',
      };
      _expectMatchingDeltas(
        sourceBones,
        targetBones,
        () => _buildRig(sourceBones),
        () => _buildRig(
          targetBones,
          restRotation: (name) =>
              rolls.putIfAbsent(name, () => _randomRotation(random)),
        ),
        (s, t) => AnimationRetargeter(
          source: RetargetRig.fromNode(s),
          target: RetargetRig.fromNode(t),
        ),
        pairs,
      );
    });

    test('mirrored target bones still follow the source', () {
      final random = Random(4);
      final rolls = <String, Quaternion>{};
      final bones = _humanoid();
      _expectMatchingDeltas(
        bones,
        bones,
        () => _buildRig(bones),
        () => _buildRig(
          bones,
          restRotation: (name) =>
              rolls.putIfAbsent(name, () => _randomRotation(random)),
          scales: {
            'LeftShoulder': Vector3(-1, 1, 1),
            'LeftForeArm': Vector3(1, -1, 1),
            'RightUpLeg': Vector3(1, 1, -1),
          },
        ),
        (s, t) => AnimationRetargeter(
          source: RetargetRig.fromNode(s),
          target: RetargetRig.fromNode(t),
        ),
        const {
          'LeftShoulder': 'LeftShoulder',
          'LeftArm': 'LeftArm',
          'LeftForeArm': 'LeftForeArm',
          'LeftHand': 'LeftHand',
          'RightUpLeg': 'RightUpLeg',
          'RightLeg': 'RightLeg',
        },
      );
    });

    test('mirrored source bones carry over', () {
      final random = Random(5);
      final rolls = <String, Quaternion>{};
      final bones = _humanoid();
      _expectMatchingDeltas(
        bones,
        bones,
        () => _buildRig(bones, scales: {'RightShoulder': Vector3(-1, 1, 1)}),
        () => _buildRig(
          bones,
          restRotation: (name) =>
              rolls.putIfAbsent(name, () => _randomRotation(random)),
        ),
        (s, t) => AnimationRetargeter(
          source: RetargetRig.fromNode(s),
          target: RetargetRig.fromNode(t),
        ),
        const {
          'RightShoulder': 'RightShoulder',
          'RightArm': 'RightArm',
          'RightForeArm': 'RightForeArm',
        },
      );
    });

    test('slerp commutes with the constant rewrite', () {
      final random = Random(6);
      for (var i = 0; i < 50; i++) {
        final a = _randomRotation(random);
        final b = _randomRotation(random);
        final q1 = _randomRotation(random);
        final q2 = _randomRotation(random);
        final t = random.nextDouble();
        final direct = a * q1.slerp(q2, t) * b;
        final rewritten = (a * q1 * b).slerp(a * q2 * b, t);
        expect(direct.dot(rewritten).abs(), closeTo(1, 1e-5));
      }
    });
  });

  group('chains without a one-to-one match', () {
    test('a spine with fewer bones resamples and keeps world rotations', () {
      final random = Random(8);
      final rolls = <String, Quaternion>{};
      final sourceBones = _humanoid();
      final targetBones = _humanoid(spine: const ['Spine', 'Spine1']);
      final retargeter = AnimationRetargeter(
        source: RetargetRig.fromNode(_buildRig(sourceBones)),
        target: RetargetRig.fromNode(_buildRig(targetBones)),
      );
      retargeter.retarget(_randomClip(_buildRig(sourceBones), Random(9)));
      expect(retargeter.report.sampledBones, contains('Neck'));
      expect(retargeter.report.sampledBones, isNot(contains('Spine1')));
      _expectMatchingDeltas(
        sourceBones,
        targetBones,
        () => _buildRig(sourceBones),
        () => _buildRig(
          targetBones,
          restRotation: (name) =>
              rolls.putIfAbsent(name, () => _randomRotation(random)),
        ),
        (s, t) => AnimationRetargeter(
          source: RetargetRig.fromNode(s),
          target: RetargetRig.fromNode(t),
          sampleRate: 240,
        ),
        const {
          'Spine1': 'Spine1',
          'Neck': 'Neck',
          'LeftShoulder': 'LeftShoulder',
          'LeftArm': 'LeftArm',
        },
        // Exact at the samples, slerp between them.
        times: const [0.0, 0.5, 1.0],
        tolerance: 1e-3,
      );
    });

    test('crossed pairings are reported and left at rest', () {
      final bones = _humanoid();
      final rig = _buildRig(bones);
      final retargeter = AnimationRetargeter(
        source: RetargetRig.fromNode(rig, autoMapHumanoid: false),
        target: RetargetRig.fromNode(rig, autoMapHumanoid: false),
        // The left hand's source would sit outside its paired ancestor's.
        boneMap: const {'RightHand': 'LeftHand'},
      );
      expect(retargeter.report.incompatibleBones, contains('LeftHand'));
      expect(retargeter.report.pairs, isNot(contains('LeftHand')));
    });
  });

  group('translation', () {
    test('a taller target scales the hips motion by hip height', () {
      final source = _buildRig(_humanoid());
      final target = _buildRig(_humanoid(legScale: 2));
      final clip = _randomClip(source, Random(10));
      final retargeter = AnimationRetargeter(
        source: RetargetRig.fromNode(source),
        target: RetargetRig.fromNode(target),
      );
      final out = retargeter.retarget(clip);
      expect(retargeter.report.rootBone, 'Hips');
      final ratio =
          RetargetRig.fromNode(target).hipHeight! /
          RetargetRig.fromNode(source).hipHeight!;
      expect(retargeter.report.rootScale, closeTo(ratio, 1e-9));
      final sourceKeys = _translations(clip, 'Hips');
      final targetKeys = _translations(out, 'Hips');
      final sourceRest = _find(source, 'Hips').localTransformTrs!.translation;
      final targetRest = _find(target, 'Hips').localTransformTrs!.translation;
      for (var k = 0; k < sourceKeys.length; k++) {
        final moved = (sourceKeys[k] - sourceRest)..scale(ratio);
        expect((targetKeys[k] - targetRest - moved).length, lessThan(1e-5));
      }
    });

    test('a centimeter armature converts to the target units', () {
      // A Z-up armature scaled to centimeters, as Mixamo exports.
      final armature = Matrix4.compose(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(1, 0, 0), -pi / 2),
        Vector3.all(0.01),
      );
      final bones = _humanoid();
      final source = _buildRig(bones, armature: armature);
      final target = _buildRig(bones);
      final hips = _find(source, 'Hips');
      final rest = hips.localTransformTrs!.translation;
      // 100 armature units along armature X is one meter along world X.
      final clip = Animation(
        name: 'step',
        channels: [
          AnimationChannel(
            bindTarget: BindKey(nodeName: 'Hips'),
            resolver: PropertyResolver.makeTranslationTimeline(
              [0, 1],
              [rest, rest + Vector3(100, 0, 0)],
            ),
          ),
        ],
      );
      final out = AnimationRetargeter(
        source: RetargetRig.fromNode(source),
        target: RetargetRig.fromNode(target),
        rootTranslation: RootTranslation.copy,
      ).retarget(clip);
      final keys = _translations(out, 'Hips');
      expect((keys[1] - keys[0] - Vector3(1, 0, 0)).length, lessThan(1e-4));
    });

    test('non-root translation and scale drop by default', () {
      final rig = _buildRig(_humanoid());
      final clip = Animation(
        name: 'stretch',
        channels: [
          AnimationChannel(
            bindTarget: BindKey(nodeName: 'LeftArm'),
            resolver: PropertyResolver.makeTranslationTimeline(
              [0, 1],
              [Vector3.zero(), Vector3(0, 1, 0)],
            ),
          ),
          AnimationChannel(
            bindTarget: BindKey(
              nodeName: 'LeftArm',
              property: AnimationProperty.scale,
            ),
            resolver: PropertyResolver.makeScaleTimeline(
              [0, 1],
              [Vector3.all(1), Vector3.all(2)],
            ),
          ),
        ],
      );
      final retargeter = AnimationRetargeter(
        source: RetargetRig.fromNode(rig),
        target: RetargetRig.fromNode(rig),
      );
      expect(retargeter.retarget(clip).channels, isEmpty);
      expect(retargeter.report.droppedTranslationTracks, 1);
      expect(retargeter.report.droppedScaleTracks, 1);
      final keeping = AnimationRetargeter(
        source: RetargetRig.fromNode(rig),
        target: RetargetRig.fromNode(rig),
        keepNonRootTranslation: true,
        keepScale: true,
      );
      expect(keeping.retarget(clip).channels, hasLength(2));
    });

    test('RootTranslation.none keeps the hips in place', () {
      final rig = _buildRig(_humanoid());
      final out = AnimationRetargeter(
        source: RetargetRig.fromNode(rig),
        target: RetargetRig.fromNode(rig),
        rootTranslation: RootTranslation.none,
      ).retarget(_randomClip(rig, Random(11)));
      expect(
        out.channels.where(
          (c) => c.bindTarget.property == AnimationProperty.translation,
        ),
        isEmpty,
      );
    });
  });

  group('rest capture', () {
    test('a rig captured mid-playback still sees its bind pose', () {
      final rig = _buildRig(_humanoid());
      final restHeight = RetargetRig.fromNode(rig).hipHeight!;
      final hips = _find(rig, 'Hips').localTransformTrs!.translation;
      rig
          .createAnimationClip(
            Animation(
              name: 'lift',
              channels: [
                AnimationChannel(
                  bindTarget: BindKey(nodeName: 'Hips'),
                  resolver: PropertyResolver.makeTranslationTimeline(
                    [0, 1],
                    [hips + Vector3(0, 1, 0), hips + Vector3(0, 1, 0)],
                  ),
                ),
              ],
            ),
          )
          .play();
      rig.scenePrePass(0.5);
      expect(
        _find(rig, 'Hips').localTransformTrs!.translation.y,
        closeTo(hips.y + 1, 1e-6),
      );
      expect(RetargetRig.fromNode(rig).hipHeight, closeTo(restHeight, 1e-6));
    });

    test('fromSkin reads joints from the inverse bind matrices', () {
      final rig = _buildRig(_humanoid());
      final shin = _find(rig, 'LeftLeg');
      final bindGlobal = shin.globalTransform.clone();
      // Stretch the left shin away from the bind pose the skin recorded,
      // which lowers the left foot.
      final rest = shin.localTransformTrs!;
      shin.setLocalTransformTrs(
        DecomposedTransform(
          translation: rest.translation + Vector3(0, -0.5, 0),
          rotation: rest.rotation,
          scale: rest.scale,
        ),
      );
      final skin = Skin()
        ..joints.add(shin)
        ..inverseBindMatrices.add(Matrix4.inverted(bindGlobal));
      expect(
        RetargetRig.fromNode(rig).hipHeight,
        closeTo(_humanoidHipHeight() + 0.5, 1e-5),
      );
      expect(
        RetargetRig.fromSkin(rig, skin).hipHeight,
        closeTo(_humanoidHipHeight(), 1e-5),
      );
    });
  });

  group('stance', () {
    test('alignStance swings an A-pose target onto a T-pose source', () {
      final source = _buildRig(_humanoid());
      final target = _buildRig(_humanoid(armDrop: pi / 4));
      final restClip = Animation(
        name: 'rest',
        channels: [
          for (final name in const ['LeftArm', 'LeftForeArm'])
            AnimationChannel(
              bindTarget: BindKey(
                nodeName: name,
                property: AnimationProperty.rotation,
              ),
              resolver: PropertyResolver.makeRotationTimeline(
                [0, 1],
                [Quaternion.identity(), Quaternion.identity()],
              ),
            ),
        ],
      );
      Vector3 armDirection(Node rig) {
        final upper = _find(rig, 'LeftArm').globalTransform.getTranslation();
        final lower = _find(
          rig,
          'LeftForeArm',
        ).globalTransform.getTranslation();
        return (lower - upper).normalized();
      }

      for (final align in const [false, true]) {
        final posed = _buildRig(_humanoid(armDrop: pi / 4));
        _pose(
          posed,
          AnimationRetargeter(
            source: RetargetRig.fromNode(source),
            target: RetargetRig.fromNode(target),
            alignStance: align,
          ).retarget(restClip),
          0.5,
        );
        final direction = armDirection(posed);
        if (align) {
          expect(direction.dot(Vector3(1, 0, 0)), closeTo(1, 1e-4));
        } else {
          expect(direction.dot(Vector3(1, 0, 0)), closeTo(cos(pi / 4), 1e-4));
        }
      }
    });
  });

  group('clip bookkeeping', () {
    test('keeps the source length, caches, and passes weights through', () {
      final rig = _buildRig(_humanoid());
      final clip = Animation(
        name: 'long',
        channels: [
          AnimationChannel(
            bindTarget: BindKey(nodeName: 'NotABone'),
            resolver: PropertyResolver.makeTranslationTimeline(
              [0, 4],
              [Vector3.zero(), Vector3(1, 0, 0)],
            ),
          ),
          AnimationChannel(
            bindTarget: BindKey(
              nodeName: 'Head',
              property: AnimationProperty.weights,
            ),
            resolver: PropertyResolver.makeMorphWeightsTimeline(
              [0, 1],
              Float32List.fromList([0, 1]),
              targetCount: 1,
            ),
          ),
        ],
      );
      final retargeter = AnimationRetargeter(
        source: RetargetRig.fromNode(rig),
        target: RetargetRig.fromNode(rig),
      );
      final out = retargeter.retarget(clip);
      expect(out.endTime, 4);
      expect(identical(retargeter.retarget(clip), out), isTrue);
      expect(
        out.channels.single.bindTarget.property,
        AnimationProperty.weights,
      );
      expect(retargeter.report.unmappedSourceBones, contains('NotABone'));
    });

    test('an explicit bone map pairs bones the names do not', () {
      final source = _buildRig(_humanoid());
      final target = _buildRig(_humanoid(head: 'Skull'));
      final noMap = AnimationRetargeter(
        source: RetargetRig.fromNode(source, autoMapHumanoid: false),
        target: RetargetRig.fromNode(target, autoMapHumanoid: false),
      );
      expect(noMap.report.pairs, isNot(contains('Skull')));
      final mapped = AnimationRetargeter(
        source: RetargetRig.fromNode(source, autoMapHumanoid: false),
        target: RetargetRig.fromNode(target, autoMapHumanoid: false),
        boneMap: const {'Head': 'Skull'},
      );
      expect(mapped.report.pairs['Skull'], 'Head');
    });
  });

  group('humanoid auto-mapping', () {
    void expectHumanoid(
      List<(String, String?)> bones,
      Map<HumanoidBone, String> expected, {
      bool complete = true,
    }) {
      final rig = RetargetRig.fromNode(_rigFromNames(bones));
      if (complete) {
        expect(rig.missingRequired, isEmpty, reason: '${rig.humanoidIssues}');
      }
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(rig.humanoid[key], value, reason: key.name);
      }
    }

    test('maps a prefixed Mixamo rig', () {
      expectHumanoid(mixamoPrefixedRig, const {
        HumanoidBone.hips: 'mixamorigHips',
        HumanoidBone.spine: 'mixamorigSpine',
        HumanoidBone.chest: 'mixamorigSpine1',
        HumanoidBone.upperChest: 'mixamorigSpine2',
        HumanoidBone.leftUpperArm: 'mixamorigLeftArm',
        HumanoidBone.leftLowerLeg: 'mixamorigLeftLeg',
        HumanoidBone.leftThumbMetacarpal: 'mixamorigLeftHandThumb1',
        HumanoidBone.leftThumbDistal: 'mixamorigLeftHandThumb3',
        HumanoidBone.rightIndexProximal: 'mixamorigRightHandIndex1',
      });
    });

    test('maps a Meshy rig whose spine counts down', () {
      expectHumanoid(meshyRig, const {
        HumanoidBone.spine: 'Spine02',
        HumanoidBone.chest: 'Spine01',
        HumanoidBone.upperChest: 'Spine',
        HumanoidBone.neck: 'neck',
        HumanoidBone.leftToes: 'LeftToeBase',
      });
    });

    test('maps a VRM-style rig', () {
      expectHumanoid(vrmStyleRig, const {
        HumanoidBone.hips: 'pelvis',
        HumanoidBone.spine: 'spine',
        HumanoidBone.chest: 'chest',
        HumanoidBone.leftLowerArm: 'leftForeArm',
        HumanoidBone.rightLowerLeg: 'rightLowerLeg',
      });
    });

    test('maps a game rig and skips its helper bones', () {
      expectHumanoid(godotDemoRig, const {
        HumanoidBone.hips: 'hips',
        HumanoidBone.spine: 'spine1',
        HumanoidBone.chest: 'chest',
        HumanoidBone.neck: 'neck',
        HumanoidBone.head: 'head.001',
        HumanoidBone.leftLowerArm: 'forearm.L',
        HumanoidBone.leftIndexProximal: 'f_index.01.L',
        HumanoidBone.leftThumbDistal: 'thumb.03.L',
      });
    });

    test('maps the UE5 mannequin', () {
      expectHumanoid(_mannequin, const {
        HumanoidBone.hips: 'pelvis',
        HumanoidBone.spine: 'spine_01',
        HumanoidBone.chest: 'spine_02',
        HumanoidBone.upperChest: 'spine_05',
        HumanoidBone.neck: 'neck_01',
        HumanoidBone.leftShoulder: 'clavicle_l',
        HumanoidBone.leftUpperLeg: 'thigh_l',
        HumanoidBone.leftToes: 'ball_l',
        HumanoidBone.leftIndexProximal: 'index_01_l',
        HumanoidBone.rightLittleDistal: 'pinky_03_r',
      });
    });

    test('maps a Rigify deform skeleton', () {
      expectHumanoid(_rigify, const {
        HumanoidBone.hips: 'DEF-spine',
        HumanoidBone.spine: 'DEF-spine.001',
        HumanoidBone.upperChest: 'DEF-spine.003',
        HumanoidBone.head: 'DEF-spine.006',
        HumanoidBone.leftUpperArm: 'DEF-upper_arm.L',
        HumanoidBone.leftLowerArm: 'DEF-forearm.L',
        HumanoidBone.leftUpperLeg: 'DEF-thigh.L',
        HumanoidBone.leftLowerLeg: 'DEF-shin.L',
        HumanoidBone.leftMiddleIntermediate: 'DEF-f_middle.02.L',
      });
    });

    test('maps a VRoid rig', () {
      expectHumanoid(_vroid, const {
        HumanoidBone.hips: 'J_Bip_C_Hips',
        HumanoidBone.upperChest: 'J_Bip_C_UpperChest',
        HumanoidBone.leftUpperLeg: 'J_Bip_L_UpperLeg',
        HumanoidBone.rightHand: 'J_Bip_R_Hand',
        HumanoidBone.rightRingIntermediate: 'J_Bip_R_Ring2',
      });
    });

    test('reports a rig that is not humanoid', () {
      final rig = RetargetRig.fromNode(_rigFromNames(dashRig));
      expect(rig.missingRequired, contains(HumanoidBone.hips));
      expect(rig.hipHeight, isNull);
    });

    test('drops and reports a mapping nested in the wrong place', () {
      final rig = RetargetRig.fromNode(
        _rigFromNames(meshyRig),
        humanoid: const {HumanoidBone.leftHand: 'headfront'},
      );
      expect(rig.humanoid[HumanoidBone.leftHand], isNull);
      expect(rig.humanoidIssues.single, startsWith('leftHand'));
      expect(rig.missingRequired, [HumanoidBone.leftHand]);
    });

    test('a bone reassigned by an override leaves its old slot', () {
      final rig = RetargetRig.fromNode(
        _rigFromNames(meshyRig),
        humanoid: const {HumanoidBone.leftHand: 'RightForeArm'},
      );
      expect(rig.humanoid[HumanoidBone.rightLowerArm], isNull);
      expect(rig.humanoid[HumanoidBone.leftHand], isNull);
      expect(rig.humanoid[HumanoidBone.rightHand], 'RightHand');
      expect(
        rig.missingRequired,
        unorderedEquals([HumanoidBone.leftHand, HumanoidBone.rightLowerArm]),
      );
    });

    test('pairs two differently named humanoids by slot', () {
      final retargeter = AnimationRetargeter(
        source: RetargetRig.fromNode(_rigFromNames(mixamoPrefixedRig)),
        target: RetargetRig.fromNode(_rigFromNames(vrmStyleRig)),
      );
      expect(retargeter.report.pairs, containsPair('pelvis', 'mixamorigHips'));
      expect(
        retargeter.report.pairs,
        containsPair('leftForeArm', 'mixamorigLeftForeArm'),
      );
      expect(retargeter.report.pairs, hasLength(19));
    });
  });
}

double _humanoidHipHeight() {
  final bones = _humanoid();
  final hips = bones.first.$3.y;
  final foot = bones.firstWhere((b) => b.$1 == 'LeftFoot').$3.y;
  return hips - foot;
}

List<Vector3> _translations(Animation clip, String bone) {
  final channel = clip.channels.firstWhere(
    (c) =>
        c.bindTarget.nodeName == bone &&
        c.bindTarget.property == AnimationProperty.translation,
  );
  return (channel.resolver as TranslationTimelineResolver).values;
}

/// The UE5 mannequin's deform skeleton, twist and IK bones included.
final _mannequin = <(String, String?)>[
  ('root', null),
  ('pelvis', 'root'),
  ('spine_01', 'pelvis'),
  ('spine_02', 'spine_01'),
  ('spine_03', 'spine_02'),
  ('spine_04', 'spine_03'),
  ('spine_05', 'spine_04'),
  ('neck_01', 'spine_05'),
  ('neck_02', 'neck_01'),
  ('head', 'neck_02'),
  for (final s in const ['l', 'r']) ...[
    ('clavicle_$s', 'spine_05'),
    ('upperarm_$s', 'clavicle_$s'),
    ('upperarm_twist_01_$s', 'upperarm_$s'),
    ('lowerarm_$s', 'upperarm_$s'),
    ('lowerarm_twist_01_$s', 'lowerarm_$s'),
    ('hand_$s', 'lowerarm_$s'),
    ('thumb_01_$s', 'hand_$s'),
    ('thumb_02_$s', 'thumb_01_$s'),
    ('thumb_03_$s', 'thumb_02_$s'),
    for (final f in const ['index', 'middle', 'ring', 'pinky']) ...[
      ('${f}_metacarpal_$s', 'hand_$s'),
      ('${f}_01_$s', '${f}_metacarpal_$s'),
      ('${f}_02_$s', '${f}_01_$s'),
      ('${f}_03_$s', '${f}_02_$s'),
    ],
    ('thigh_$s', 'pelvis'),
    ('thigh_twist_01_$s', 'thigh_$s'),
    ('calf_$s', 'thigh_$s'),
    ('calf_twist_01_$s', 'calf_$s'),
    ('foot_$s', 'calf_$s'),
    ('ball_$s', 'foot_$s'),
  ],
  ('ik_foot_root', 'root'),
  ('ik_foot_l', 'ik_foot_root'),
  ('ik_foot_r', 'ik_foot_root'),
];

/// A Rigify deform skeleton, with its segmented limbs.
final _rigify = <(String, String?)>[
  ('DEF-spine', null),
  ('DEF-spine.001', 'DEF-spine'),
  ('DEF-spine.002', 'DEF-spine.001'),
  ('DEF-spine.003', 'DEF-spine.002'),
  ('DEF-spine.004', 'DEF-spine.003'),
  ('DEF-spine.005', 'DEF-spine.004'),
  ('DEF-spine.006', 'DEF-spine.005'),
  for (final s in const ['L', 'R']) ...[
    ('DEF-shoulder.$s', 'DEF-spine.003'),
    ('DEF-upper_arm.$s', 'DEF-shoulder.$s'),
    ('DEF-upper_arm.$s.001', 'DEF-upper_arm.$s'),
    ('DEF-forearm.$s', 'DEF-upper_arm.$s.001'),
    ('DEF-forearm.$s.001', 'DEF-forearm.$s'),
    ('DEF-hand.$s', 'DEF-forearm.$s.001'),
    ('DEF-thumb.01.$s', 'DEF-hand.$s'),
    ('DEF-thumb.02.$s', 'DEF-thumb.01.$s'),
    ('DEF-thumb.03.$s', 'DEF-thumb.02.$s'),
    for (final f in const ['index', 'middle', 'ring', 'pinky']) ...[
      ('DEF-palm.$f.$s', 'DEF-hand.$s'),
      ('DEF-f_$f.01.$s', 'DEF-palm.$f.$s'),
      ('DEF-f_$f.02.$s', 'DEF-f_$f.01.$s'),
      ('DEF-f_$f.03.$s', 'DEF-f_$f.02.$s'),
    ],
    ('DEF-thigh.$s', 'DEF-spine'),
    ('DEF-thigh.$s.001', 'DEF-thigh.$s'),
    ('DEF-shin.$s', 'DEF-thigh.$s.001'),
    ('DEF-shin.$s.001', 'DEF-shin.$s'),
    ('DEF-foot.$s', 'DEF-shin.$s.001'),
    ('DEF-toe.$s', 'DEF-foot.$s'),
  ],
];

/// A VRoid Studio export.
final _vroid = <(String, String?)>[
  ('Root', null),
  ('J_Bip_C_Hips', 'Root'),
  ('J_Bip_C_Spine', 'J_Bip_C_Hips'),
  ('J_Bip_C_Chest', 'J_Bip_C_Spine'),
  ('J_Bip_C_UpperChest', 'J_Bip_C_Chest'),
  ('J_Bip_C_Neck', 'J_Bip_C_UpperChest'),
  ('J_Bip_C_Head', 'J_Bip_C_Neck'),
  ('J_Adj_L_FaceEye', 'J_Bip_C_Head'),
  for (final s in const ['L', 'R']) ...[
    ('J_Bip_${s}_Shoulder', 'J_Bip_C_UpperChest'),
    ('J_Bip_${s}_UpperArm', 'J_Bip_${s}_Shoulder'),
    ('J_Bip_${s}_LowerArm', 'J_Bip_${s}_UpperArm'),
    ('J_Bip_${s}_Hand', 'J_Bip_${s}_LowerArm'),
    for (final f in const ['Thumb', 'Index', 'Middle', 'Ring', 'Little']) ...[
      ('J_Bip_${s}_${f}1', 'J_Bip_${s}_Hand'),
      ('J_Bip_${s}_${f}2', 'J_Bip_${s}_${f}1'),
      ('J_Bip_${s}_${f}3', 'J_Bip_${s}_${f}2'),
    ],
    ('J_Bip_${s}_UpperLeg', 'J_Bip_C_Hips'),
    ('J_Bip_${s}_LowerLeg', 'J_Bip_${s}_UpperLeg'),
    ('J_Bip_${s}_Foot', 'J_Bip_${s}_LowerLeg'),
    ('J_Bip_${s}_ToeBase', 'J_Bip_${s}_Foot'),
  ],
];
