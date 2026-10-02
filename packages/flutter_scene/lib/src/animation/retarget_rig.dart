part of '../animation.dart';

/// One node of a [RetargetRig], in depth-first order under the rig root.
class _RigBone {
  _RigBone(this.name, this.parent, this.depth, this.rest);

  final String name;

  /// Index of the parent bone, or -1 for a child of the rig root.
  final int parent;

  /// Number of bones above this one.
  final int depth;

  DecomposedTransform rest;
}

/// The rest pose of a skeleton, the frame of reference a clip's keys are
/// relative to.
///
/// Capture one per rig (the rig a clip was authored on and the rig it should
/// play on) and hand both to an [AnimationRetargeter]. Capture before the rig
/// plays anything, or after only through the same root it plays from, so the
/// recorded rest is the bind pose and not a mid-animation pose.
///
/// Every named node under the root counts as a bone. When a humanoid map is
/// detected or supplied, [humanoid] names the bone filling each
/// [HumanoidBone] slot, which lets differently named humanoids pair up.
/// {@category Animation}
class RetargetRig {
  RetargetRig._(
    this._bones, {
    Map<HumanoidBone, String>? humanoid,
    required bool autoMapHumanoid,
  }) {
    for (var i = 0; i < _bones.length; i++) {
      _byName.putIfAbsent(_bones[i].name, () => i);
    }
    _computePose();
    _mapHumanoid(humanoid, autoMapHumanoid);
  }

  /// Snapshots the rest pose of every node under [root], relative to [root].
  ///
  /// Nodes already bound by an animation player use the bind pose the player
  /// recorded, so capturing a rig that is playing still sees its rest.
  /// [humanoid] overrides or extends the detected humanoid map; set
  /// [autoMapHumanoid] to false to use only [humanoid].
  factory RetargetRig.fromNode(
    Node root, {
    Map<HumanoidBone, String>? humanoid,
    bool autoMapHumanoid = true,
  }) {
    return RetargetRig._(
      _collectBones(root, (_) => null),
      humanoid: humanoid,
      autoMapHumanoid: autoMapHumanoid,
    );
  }

  /// Like [RetargetRig.fromNode], but takes each joint's rest from [skin]'s
  /// inverse bind matrices (the stance the mesh was modeled in) instead of
  /// the joint nodes' transforms.
  ///
  /// Use this when the node rest was flattened or posed after export. The
  /// inverse bind matrices are taken to be relative to [root], which holds
  /// for imported models whose skin root is the import root.
  factory RetargetRig.fromSkin(
    Node root,
    Skin skin, {
    Map<HumanoidBone, String>? humanoid,
    bool autoMapHumanoid = true,
  }) {
    final bindGlobals = <Node, Matrix4>{};
    for (var i = 0; i < skin.joints.length; i++) {
      final joint = skin.joints[i];
      if (joint == null || i >= skin.inverseBindMatrices.length) continue;
      bindGlobals[joint] = Matrix4.inverted(skin.inverseBindMatrices[i]);
    }
    return RetargetRig._(
      _collectBones(root, (node) => bindGlobals[node]),
      humanoid: humanoid,
      autoMapHumanoid: autoMapHumanoid,
    );
  }

  final List<_RigBone> _bones;
  final Map<String, int> _byName = {};

  /// Rest transform of each bone relative to the rig root.
  late List<Matrix4> _globals;

  /// Rest orientation of each bone relative to the rig root: the product of
  /// every local rotation and scale sign above and including the bone.
  /// Proper rotations except where an odd number of mirrored axes sits on
  /// the chain.
  late List<Matrix3> _orients;

  final Map<HumanoidBone, int> _humanoid = {};
  final List<String> _humanoidIssues = [];

  /// The names of the rig's bones, in depth-first order.
  List<String> get boneNames => [for (final bone in _bones) bone.name];

  /// The bone filling each humanoid slot.
  Map<HumanoidBone, String> get humanoid => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _humanoid.entries)
      key: _bones[value].name,
  });

  /// Required humanoid slots that no bone fills. Empty for a complete
  /// humanoid; a rig that is not humanoid at all lists every required slot.
  List<HumanoidBone> get missingRequired => [
    for (final slot in HumanoidBone.values)
      if (slot.isRequired && !_humanoid.containsKey(slot)) slot,
  ];

  /// Problems found while mapping the humanoid slots: names that do not
  /// exist and mappings whose bones are not nested the way the humanoid
  /// hierarchy requires (those are left unmapped).
  List<String> get humanoidIssues => List.unmodifiable(_humanoidIssues);

  /// Rest height of the hips, in rig root units: above the lower foot when
  /// both feet are mapped, otherwise above the rig root. Null when the hips
  /// are not mapped or do not sit above that reference.
  double? get hipHeight {
    final hips = _humanoid[HumanoidBone.hips];
    if (hips == null) return null;
    var floor = 0.0;
    final left = _humanoid[HumanoidBone.leftFoot];
    final right = _humanoid[HumanoidBone.rightFoot];
    if (left != null && right != null) {
      floor = min(_positionOf(left).y, _positionOf(right).y);
    }
    final height = _positionOf(hips).y - floor;
    return height > 1e-6 ? height : null;
  }

  Vector3 _positionOf(int bone) => _globals[bone].getTranslation();

  int? _indexOf(String name) => _byName[name];

  /// The nearest ancestor of [bone] for which [test] holds, or -1.
  int _ancestorWhere(int bone, bool Function(int) test) {
    for (var b = _bones[bone].parent; b >= 0; b = _bones[b].parent) {
      if (test(b)) return b;
    }
    return -1;
  }

  bool _isAncestor(int ancestor, int bone) {
    if (ancestor < 0) return true;
    for (var b = _bones[bone].parent; b >= 0; b = _bones[b].parent) {
      if (b == ancestor) return true;
    }
    return false;
  }

  void _computePose() {
    _globals = List.filled(_bones.length, Matrix4.identity());
    _orients = List.filled(_bones.length, Matrix3.identity());
    for (var i = 0; i < _bones.length; i++) {
      final bone = _bones[i];
      final local = bone.rest.toMatrix4();
      final orient = _rotationWithSigns(bone.rest);
      if (bone.parent < 0) {
        _globals[i] = local;
        _orients[i] = orient;
      } else {
        _globals[i] = _globals[bone.parent].multiplied(local);
        _orients[i] = _orients[bone.parent].multiplied(orient);
      }
    }
  }

  void _mapHumanoid(Map<HumanoidBone, String>? overrides, bool auto) {
    if (auto) {
      _humanoid.addAll(_autoMapHumanoid(_bones));
    }
    if (overrides != null) {
      for (final MapEntry(:key, :value) in overrides.entries) {
        final index = _byName[value];
        if (index == null) {
          _humanoidIssues.add('$key: no bone named "$value"');
          continue;
        }
        // A bone fills one slot; the override wins.
        final displaced = [
          for (final MapEntry(key: slot, value: bone) in _humanoid.entries)
            if (bone == index && slot != key) slot,
        ];
        for (final slot in displaced) {
          _humanoid.remove(slot);
          _humanoidIssues.add(
            '${slot.name}: "$value" was reassigned to ${key.name}',
          );
        }
        _humanoid[key] = index;
      }
    }
    _validateHumanoid();
  }

  /// Drops slots whose bone is not nested under the bone of the slot's
  /// nearest mapped humanoid ancestor, the way the humanoid hierarchy
  /// nests them. Runs top down, so dropping a slot re-anchors its children.
  void _validateHumanoid() {
    final slotOf = <int, HumanoidBone>{
      for (final MapEntry(:key, :value) in _humanoid.entries) value: key,
    };
    for (final slot in HumanoidBone.values) {
      final bone = _humanoid[slot];
      if (bone == null) continue;
      var expectedSlot = slot.parent;
      while (expectedSlot != null && !_humanoid.containsKey(expectedSlot)) {
        expectedSlot = expectedSlot.parent;
      }
      final expected = expectedSlot == null ? -1 : _humanoid[expectedSlot]!;
      final actual = _ancestorWhere(bone, slotOf.containsKey);
      if (actual == expected) continue;
      final actualName = actual < 0 ? 'none' : '"${_bones[actual].name}"';
      final expectedName = expected < 0 ? 'none' : '"${_bones[expected].name}"';
      _humanoidIssues.add(
        '${slot.name}: "${_bones[bone].name}" has nearest mapped ancestor '
        '$actualName, expected $expectedName; left unmapped',
      );
      _humanoid.remove(slot);
      slotOf.remove(bone);
    }
  }

  /// Walks [root]'s subtree in the same depth-first order
  /// [Node.getChildByName] searches, so a duplicated name resolves to the
  /// same node a clip would bind.
  static List<_RigBone> _collectBones(
    Node root,
    Matrix4? Function(Node) bindGlobal,
  ) {
    final players = <AnimationPlayer>[
      for (Node? n = root; n != null; n = n.parent)
        if (n.internalAnimationPlayer != null) n.internalAnimationPlayer!,
    ];
    final bones = <_RigBone>[];
    final globals = <Matrix4>[];
    void visit(Node node, int parent, int depth) {
      final player = node.internalAnimationPlayer;
      if (player != null && !players.contains(player)) players.add(player);
      DecomposedTransform? rest;
      for (final p in players) {
        rest = p._targetTransforms[node]?.bindPose;
        if (rest != null) break;
      }
      rest = (rest ?? AnimationPlayer._bindPoseOf(node)).clone();
      final parentGlobal = parent < 0 ? Matrix4.identity() : globals[parent];
      final override = bindGlobal(node);
      if (override != null) {
        rest = DecomposedTransform.fromMatrix(
          Matrix4.inverted(parentGlobal).multiplied(override),
        );
      }
      final index = bones.length;
      bones.add(_RigBone(node.name, parent, depth, rest));
      globals.add(parentGlobal.multiplied(rest.toMatrix4()));
      for (final child in node.children) {
        visit(child, index, depth + 1);
      }
    }

    for (final child in root.children) {
      visit(child, -1, 0);
    }
    return bones;
  }
}

/// The rotation of [trs] times the signs of its scale, the orientation a
/// mirrored bone hands its children. Scale magnitudes are dropped.
Matrix3 _rotationWithSigns(DecomposedTransform trs) {
  return trs.rotation.asRotationMatrix()..multiply(_scaleSigns(trs));
}

/// The sign matrix of [trs]'s scale.
Matrix3 _scaleSigns(DecomposedTransform trs) {
  final s = trs.scale;
  return Matrix3.zero()..setDiagonal(
    Vector3(s.x < 0 ? -1.0 : 1.0, s.y < 0 ? -1.0 : 1.0, s.z < 0 ? -1.0 : 1.0),
  );
}
