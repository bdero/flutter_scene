import 'dart:math';

import 'package:flutter/material.dart' hide Animation;
import 'package:flutter_scene/scene.dart';
// The clip is authored in code, which needs the channel types the public
// API does not export.
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, AnimationProperty, BindKey, PropertyResolver;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

/// One walk cycle, authored once, playing on three skeletons.
///
/// The left figure owns the clip. The other two have different bone names,
/// proportions, bone orientations, and spine lengths, and the right one
/// rests in an A-pose. [AnimationRetargeter] rewrites the clip for each, so
/// all three walk alike; turn retargeting off to see the raw clip fail on
/// them. While running, the example logs how far each target's limbs point
/// from the source's every second.
class ExampleRetarget extends StatefulWidget {
  const ExampleRetarget({super.key});

  @override
  State<ExampleRetarget> createState() => _ExampleRetargetState();
}

/// A bone's name, parent, and rest position relative to the figure's root.
typedef _Bone = (String name, String? parent, vm.Vector3 position);

class _ExampleRetargetState extends State<ExampleRetarget> {
  final Scene scene = Scene();

  late final Node _library;
  late final Node _stocky;
  late final Node _tall;
  late final Animation _walk;
  AnimationClip? _sourceClip;
  final Map<Node, AnimationClip> _targetClips = {};
  final Map<Node, RetargetReport> _reports = {};

  bool _retarget = true;
  bool _alignStance = true;
  RootTranslation _rootTranslation = RootTranslation.scaleByHipHeight;
  double _sinceLog = 0;

  @override
  void initState() {
    super.initState();
    final random = Random(3);
    _library = _figure(
      _skeleton(),
      color: vm.Vector4(0.85, 0.85, 0.88, 1),
      offset: -1.6,
    );
    // VRM-style names, a two-bone spine, shorter legs, and every bone's
    // frame rolled at random.
    _stocky = _figure(
      _skeleton(
        names: _vrmNames,
        spine: const ['spine', 'chest'],
        legScale: 0.8,
        armScale: 0.85,
      ),
      color: vm.Vector4(0.36, 0.72, 0.95, 1),
      offset: 0,
      roll: (_) => _randomRotation(random),
    );
    // The source's names, but longer limbs, rolled frames, and an A-pose.
    _tall = _figure(
      _skeleton(legScale: 1.25, armScale: 1.2, armDrop: 0.7),
      color: vm.Vector4(0.96, 0.62, 0.30, 1),
      offset: 1.6,
      roll: (_) => _randomRotation(random),
    );
    _walk = _walkCycle(_library);
    scene
      ..add(_library)
      ..add(_stocky)
      ..add(_tall)
      ..add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(6, 0.02, 2)),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.2, 0.21, 0.24, 1)
              ..roughnessFactor = 0.9,
          ),
          localTransform: vm.Matrix4.translationValues(0, -0.01, 0),
        ),
      );
    _sourceClip = _library.createAnimationClip(_walk)
      ..loop = true
      ..play();
    _rebuildTargets();
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  /// Recreates the targets' clips for the current settings, in step with
  /// the source.
  void _rebuildTargets() {
    for (final MapEntry(key: figure, value: clip) in _targetClips.entries) {
      figure.removeAnimationClip(clip);
    }
    _targetClips.clear();
    _reports.clear();
    final time = _sourceClip?.playbackTime ?? 0;
    for (final figure in [_stocky, _tall]) {
      var animation = _walk;
      if (_retarget) {
        final retargeter = AnimationRetargeter(
          source: RetargetRig.fromNode(_library),
          target: RetargetRig.fromNode(figure),
          rootTranslation: _rootTranslation,
          alignStance: _alignStance,
        );
        animation = retargeter.retarget(_walk);
        _reports[figure] = retargeter.report;
      }
      _targetClips[figure] = figure.createAnimationClip(animation)
        ..loop = true
        ..seek(time)
        ..play();
    }
  }

  void _update(void Function() change) {
    setState(change);
    _rebuildTargets();
  }

  /// Logs the worst angle between each target limb and the source's, so a
  /// run leaves evidence that the retarget holds.
  void _logLimbs(double deltaSeconds) {
    _sinceLog += deltaSeconds;
    if (_sinceLog < 1) return;
    _sinceLog = 0;
    String worst(Node figure, Map<String, String> names) {
      var degrees = 0.0;
      for (final (from, to) in _limbs) {
        final source = _direction(_library, from, to);
        final target = _direction(figure, names[from]!, names[to]!);
        degrees = max(degrees, acos(source.dot(target).clamp(-1.0, 1.0)));
      }
      return (degrees * 180 / pi).toStringAsFixed(3);
    }

    debugPrint(
      'retarget: retarget=$_retarget alignStance=$_alignStance '
      'max limb deviation from source, '
      'stocky=${worst(_stocky, _vrmNameMap)} deg, '
      'tall=${worst(_tall, _identityNames)} deg',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) => PerspectiveCamera(
              position: vm.Vector3(0.6, 1.6, 5.2),
              target: vm.Vector3(0, 1.0, 0),
            ),
            onTick: (elapsed, deltaSeconds) {
              exampleSettings.applyTo(scene);
              _logLimbs(deltaSeconds);
            },
          ),
        ),
        ExampleOverlay.bottomLeftPanel(child: _controls()),
      ],
    );
  }

  Widget _controls() {
    const white = TextStyle(color: Colors.white);
    final dim = TextStyle(color: Colors.white.withValues(alpha: 0.7));
    Widget toggle(String label, bool value, void Function(bool) set) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => _update(() => set(v ?? false)),
          side: const BorderSide(color: Colors.white70),
          checkColor: Colors.black,
          activeColor: Colors.white,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: white),
      ],
    );
    return ExamplePanelCard(
      icon: Icons.accessibility_new,
      title: 'Retargeting',
      width: 320,
      maxBodyHeight: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Left owns the walk. Middle has other names, a shorter spine, '
            'and rolled bones; right rests in an A-pose.',
            style: dim,
          ),
          toggle('Retarget', _retarget, (v) => _retarget = v),
          toggle('Align stance', _alignStance, (v) => _alignStance = v),
          const SizedBox(height: 4),
          Text('Root motion', style: dim),
          Wrap(
            spacing: 6,
            children: [
              for (final mode in RootTranslation.values)
                ChoiceChip(
                  label: Text(mode.name),
                  selected: _rootTranslation == mode,
                  onSelected: (_) => _update(() => _rootTranslation = mode),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (label, figure) in [('Middle', _stocky), ('Right', _tall)])
            if (_reports[figure] case final report?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$label: ${report.pairs.length} bones paired'
                  '${report.sampledBones.isEmpty ? '' : ', resampled ${report.sampledBones.join(', ')}'}'
                  ', root motion x${report.rootScale.toStringAsFixed(2)}',
                  style: dim,
                ),
              ),
        ],
      ),
    );
  }
}

/// Limb segments the log compares, by source bone name.
const _limbs = [
  ('LeftUpLeg', 'LeftLeg'),
  ('LeftLeg', 'LeftFoot'),
  ('RightUpLeg', 'RightLeg'),
  ('RightLeg', 'RightFoot'),
  ('LeftArm', 'LeftForeArm'),
  ('LeftForeArm', 'LeftHand'),
  ('RightArm', 'RightForeArm'),
  ('RightForeArm', 'RightHand'),
];

final _identityNames = {
  for (final (a, b) in _limbs) ...{a: a, b: b},
};

const _vrmNameMap = {
  'LeftUpLeg': 'leftUpperLeg',
  'LeftLeg': 'leftLowerLeg',
  'LeftFoot': 'leftFoot',
  'RightUpLeg': 'rightUpperLeg',
  'RightLeg': 'rightLowerLeg',
  'RightFoot': 'rightFoot',
  'LeftArm': 'leftUpperArm',
  'LeftForeArm': 'leftLowerArm',
  'LeftHand': 'leftHand',
  'RightArm': 'rightUpperArm',
  'RightForeArm': 'rightLowerArm',
  'RightHand': 'rightHand',
};

String _vrmNames(String side, String part) =>
    '${side.toLowerCase()}${part[0].toUpperCase()}${part.substring(1)}';

String _mixamoNames(String side, String part) =>
    '$side${const {'shoulder': 'Shoulder', 'upperArm': 'Arm', 'lowerArm': 'ForeArm', 'hand': 'Hand', 'upperLeg': 'UpLeg', 'lowerLeg': 'Leg', 'foot': 'Foot', 'toes': 'ToeBase'}[part]}';

/// A humanoid in meters, Y up, facing +Z, arms out (lowered by [armDrop]).
List<_Bone> _skeleton({
  String Function(String side, String part) names = _mixamoNames,
  List<String> spine = const ['Spine', 'Spine1', 'Spine2'],
  double legScale = 1,
  double armScale = 1,
  double armDrop = 0,
}) {
  final hips = names == _mixamoNames ? 'Hips' : 'hips';
  final neck = names == _mixamoNames ? 'Neck' : 'neck';
  final head = names == _mixamoNames ? 'Head' : 'head';
  final hipY = legScale;
  final bones = <_Bone>[(hips, null, vm.Vector3(0, hipY, 0))];
  var parent = hips;
  for (var i = 0; i < spine.length; i++) {
    bones.add((
      spine[i],
      parent,
      vm.Vector3(0, hipY + 0.42 * (i + 1) / (spine.length + 1), 0),
    ));
    parent = spine[i];
  }
  final shoulderY = hipY + 0.45;
  bones
    ..add((neck, parent, vm.Vector3(0, shoulderY + 0.07, 0)))
    ..add((head, neck, vm.Vector3(0, shoulderY + 0.17, 0)));
  for (final (side, x) in const [('Left', 1.0), ('Right', -1.0)]) {
    vm.Vector3 arm(double reach) => vm.Vector3(
      x * (0.06 + reach * cos(armDrop)),
      shoulderY - reach * sin(armDrop),
      0,
    );
    final top = 0.95 * legScale;
    bones.addAll([
      (names(side, 'shoulder'), parent, vm.Vector3(x * 0.06, shoulderY, 0)),
      (names(side, 'upperArm'), names(side, 'shoulder'), arm(0.12 * armScale)),
      (names(side, 'lowerArm'), names(side, 'upperArm'), arm(0.40 * armScale)),
      (names(side, 'hand'), names(side, 'lowerArm'), arm(0.64 * armScale)),
      (names(side, 'upperLeg'), hips, vm.Vector3(x * 0.1, top, 0)),
      (
        names(side, 'lowerLeg'),
        names(side, 'upperLeg'),
        vm.Vector3(x * 0.1, top * 0.53, 0),
      ),
      (
        names(side, 'foot'),
        names(side, 'lowerLeg'),
        vm.Vector3(x * 0.1, top * 0.08, 0),
      ),
      (
        names(side, 'toes'),
        names(side, 'foot'),
        vm.Vector3(x * 0.1, 0.02, 0.12),
      ),
    ]);
  }
  return bones;
}

vm.Quaternion _randomRotation(Random random) => vm.Quaternion.axisAngle(
  vm.Vector3(
    random.nextDouble() - 0.5,
    random.nextDouble() - 0.5,
    random.nextDouble() - 0.5,
  ).normalized(),
  random.nextDouble() * pi,
);

/// Builds [bones] as a figure of boxes, one per bone segment, standing at
/// [offset] on X. [roll] gives each bone its rest rotation, which changes
/// its local frame but not where it sits.
Node _figure(
  List<_Bone> bones, {
  required vm.Vector4 color,
  required double offset,
  vm.Quaternion Function(String name)? roll,
}) {
  final root = Node(name: 'figure');
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = color
    ..roughnessFactor = 0.55;
  final joint = Mesh(
    IcosphereGeometry(radius: 0.035, subdivisions: 1),
    material,
  );
  final nodes = <String, Node>{};
  for (final (name, parent, position) in bones) {
    final parentNode = parent == null ? root : nodes[parent]!;
    final local = vm.Matrix4.inverted(
      parentNode.globalTransform,
    ).transformed3(position);
    final node = Node(
      name: name,
      localTransform: vm.Matrix4.compose(
        local,
        roll?.call(name) ?? vm.Quaternion.identity(),
        vm.Vector3.all(1),
      ),
    );
    parentNode.add(node);
    node.add(Node(mesh: joint));
    nodes[name] = node;
    // A box from the parent's origin to this bone, in the parent's frame.
    if (parent != null && local.length > 1e-4) {
      parentNode.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(0.05, local.length, 0.05)),
            material,
          ),
          localTransform: vm.Matrix4.compose(
            local * 0.5,
            vm.Quaternion.fromTwoVectors(
              vm.Vector3(0, 1, 0),
              local.normalized(),
            ),
            vm.Vector3.all(1),
          ),
        ),
      );
    }
  }
  root.localTransform = vm.Matrix4.translationValues(offset, 0, 0);
  return root;
}

/// A one-second walk in place on [figure], whose bones rest with identity
/// rotations, so every key is a plain rotation about the figure's axes.
Animation _walkCycle(Node figure) {
  const steps = 16;
  final times = [for (var i = 0; i <= steps; i++) i / steps];
  vm.Quaternion about(vm.Vector3 axis, double angle) =>
      vm.Quaternion.axisAngle(axis, angle);
  final x = vm.Vector3(1, 0, 0);
  final y = vm.Vector3(0, 1, 0);
  final z = vm.Vector3(0, 0, 1);
  final tracks = <String, vm.Quaternion Function(double phase)>{
    'LeftUpLeg': (p) => about(x, -0.55 * sin(p)),
    'RightUpLeg': (p) => about(x, 0.55 * sin(p)),
    // Knees bend through the forward swing, just after the foot leaves the
    // ground, and stay straight while it sweeps back under the body.
    'LeftLeg': (p) => about(x, 0.9 * max(0, cos(p + 0.4))),
    'RightLeg': (p) => about(x, 0.9 * max(0, -cos(p + 0.4))),
    'LeftFoot': (p) => about(x, -0.25 * sin(p)),
    'RightFoot': (p) => about(x, 0.25 * sin(p)),
    'Spine': (p) => about(y, 0.12 * sin(p)),
    'Spine2': (p) => about(y, -0.08 * sin(p)),
    'Head': (p) => about(y, -0.05 * sin(p)),
    // Arms come down from the T-pose and swing against the legs.
    'LeftArm': (p) => about(x, 0.5 * sin(p)) * about(z, -1.25),
    'RightArm': (p) => about(x, -0.5 * sin(p)) * about(z, 1.25),
    // Elbows bend the forearm forward, more as the arm swings forward.
    'LeftForeArm': (p) => about(y, -0.4 + 0.25 * sin(p)),
    'RightForeArm': (p) => about(y, 0.4 + 0.25 * sin(p)),
  };
  final hips = figure.getChildByName('Hips')!.localTransform.getTranslation();
  return Animation(
    name: 'Walk',
    channels: [
      for (final MapEntry(key: bone, value: pose) in tracks.entries)
        AnimationChannel(
          bindTarget: BindKey(
            nodeName: bone,
            property: AnimationProperty.rotation,
          ),
          resolver: PropertyResolver.makeRotationTimeline(times, [
            for (final t in times) pose(t * 2 * pi)..normalize(),
          ]),
        ),
      AnimationChannel(
        bindTarget: BindKey(nodeName: 'Hips'),
        resolver: PropertyResolver.makeTranslationTimeline(times, [
          for (final t in times)
            hips + vm.Vector3(0, 0.03 * cos(t * 4 * pi) - 0.03, 0),
        ]),
      ),
    ],
  );
}

/// The direction from bone [from] to bone [to], relative to [figure].
vm.Vector3 _direction(Node figure, String from, String to) {
  final inverse = vm.Matrix4.inverted(figure.globalTransform);
  vm.Vector3 at(String name) => inverse.transformed3(
    figure.getChildByName(name)!.globalTransform.getTranslation(),
  );
  return (at(to) - at(from)).normalized();
}
