part of '../animation.dart';

/// How the root bone's translation track transfers to the target rig.
/// {@category Animation}
enum RootTranslation {
  /// Scale the motion away from rest by the target's hip height over the
  /// source's, so a shorter character takes shorter steps.
  scaleByHipHeight,

  /// Copy the motion away from rest unscaled, in rig root units.
  copy,

  /// Drop it, keeping the root at its rest position (in-place playback).
  none,
}

/// What an [AnimationRetargeter] paired and what it could not carry over,
/// accumulated across every clip it has rewritten.
/// {@category Animation}
class RetargetReport {
  RetargetReport._();

  final Map<String, String> _pairs = {};
  final Set<String> _unmappedSourceBones = {};
  final Set<String> _sampledBones = {};
  final Set<String> _incompatibleBones = {};
  int _droppedTranslationTracks = 0;
  int _droppedScaleTracks = 0;
  String? _rootBone;
  double _rootScale = 1;

  /// Source bone name for each paired target bone name.
  Map<String, String> get pairs => Map.unmodifiable(_pairs);

  /// Source bones that carry keys but pair with no target bone and sit on
  /// no paired bone's chain, so their motion is lost.
  Set<String> get unmappedSourceBones => Set.unmodifiable(_unmappedSourceBones);

  /// Target bones whose keys were resampled rather than rewritten exactly,
  /// because animated source bones between them and their paired ancestor
  /// have no target counterpart (three source spine bones onto two).
  Set<String> get sampledBones => Set.unmodifiable(_sampledBones);

  /// Target bones left unpaired because their source bone does not sit
  /// under the source of their paired ancestor.
  Set<String> get incompatibleBones => Set.unmodifiable(_incompatibleBones);

  /// Translation tracks dropped (every non-root one unless
  /// [AnimationRetargeter.keepNonRootTranslation]).
  int get droppedTranslationTracks => _droppedTranslationTracks;

  /// Scale tracks dropped (all of them unless [AnimationRetargeter.keepScale]).
  int get droppedScaleTracks => _droppedScaleTracks;

  /// The target bone whose translation follows the source root, or null
  /// when no clip has moved one yet.
  String? get rootBone => _rootBone;

  /// The factor applied to the root's motion.
  double get rootScale => _rootScale;

  @override
  String toString() {
    final lines = [
      'RetargetReport: ${_pairs.length} paired bones',
      if (_rootBone != null)
        '  root: $_rootBone (motion scale ${_rootScale.toStringAsFixed(3)})',
      if (_sampledBones.isNotEmpty) '  resampled: ${_sampledBones.join(', ')}',
      if (_unmappedSourceBones.isNotEmpty)
        '  unmapped source: ${_unmappedSourceBones.join(', ')}',
      if (_incompatibleBones.isNotEmpty)
        '  incompatible: ${_incompatibleBones.join(', ')}',
      if (_droppedTranslationTracks > 0)
        '  dropped translation tracks: $_droppedTranslationTracks',
      if (_droppedScaleTracks > 0)
        '  dropped scale tracks: $_droppedScaleTracks',
    ];
    return lines.join('\n');
  }
}

/// Rewrites clips authored on one skeleton so they play on another with
/// different bone names, proportions, and rest orientations.
///
/// Each paired bone's world rotation away from rest follows its source
/// bone's. For a one-to-one chain that reduces to two constant rotations per
/// bone, so keys are rewritten exactly, the result plays identically to a
/// per-frame retarget at every time, and the cost is paid once per clip.
/// Build one per rig pair and reuse it; rewritten clips are cached.
///
/// ```dart
/// final retargeter = AnimationRetargeter(
///   source: RetargetRig.fromNode(library),
///   target: RetargetRig.fromNode(hero),
/// );
/// hero.createAnimationClip(
///   retargeter.retarget(library.findAnimationByName('Walk')!),
/// )..loop = true..play();
/// ```
///
/// Rotation transfer assumes bones carry uniform scale. A non-uniformly
/// scaled parent shears its children's frames, which the transfer only
/// approximates.
///
/// Bones pair by, in order, an explicit [boneMap] entry, a shared
/// [HumanoidBone] slot, then an identical name. Unpaired target bones stay at
/// rest. Morph weight channels pass through to the target node of the same
/// (or mapped) name.
/// {@category Animation}
class AnimationRetargeter {
  /// Pairs [source] with [target].
  ///
  /// [boneMap] maps source bone names to target bone names and wins over
  /// humanoid and name pairing. [rootTranslation] picks how the root (the
  /// hips on humanoids) moves; other translation and all scale tracks drop
  /// unless [keepNonRootTranslation] or [keepScale] is set, since they would
  /// stretch the target toward the source's proportions. [alignStance]
  /// first swings the target's limbs to point the way the source's rest
  /// points (A-pose against T-pose); leave it off when both rests share a
  /// stance. Bones that need resampling get at least [sampleRate] keys per
  /// second.
  AnimationRetargeter({
    required this.source,
    required this.target,
    Map<String, String> boneMap = const {},
    this.rootTranslation = RootTranslation.scaleByHipHeight,
    this.keepNonRootTranslation = false,
    this.keepScale = false,
    this.alignStance = false,
    this.sampleRate = 30,
  }) : boneMap = Map.unmodifiable(boneMap) {
    _pairBones();
    _prepareTargetReference();
    _prepareChains();
  }

  /// The rig the clips were authored on.
  final RetargetRig source;

  /// The rig the clips will play on.
  final RetargetRig target;

  /// Explicit source to target bone name pairs.
  final Map<String, String> boneMap;

  /// How the root bone's translation transfers.
  final RootTranslation rootTranslation;

  /// Whether translation tracks below the root carry over (as rest-relative
  /// offsets scaled like the root's).
  final bool keepNonRootTranslation;

  /// Whether scale tracks carry over (as ratios against the source rest).
  final bool keepScale;

  /// Whether the target's limbs are first swung to the source's rest stance.
  final bool alignStance;

  /// Minimum keys per second for bones whose keys are resampled.
  final double sampleRate;

  /// What has been paired and dropped so far.
  final RetargetReport report = RetargetReport._();

  final Map<Animation, Animation> _cache = Map.identity();

  /// Paired source bone for each target bone index.
  final Map<int, int> _sourceOf = {};

  /// For each paired target bone, the source bones from just below its
  /// paired ancestor's source down to its own source, top first.
  final Map<int, List<int>> _chains = {};

  /// The target's reference pose (its rest, or the aligned stance).
  late List<Matrix4> _targetGlobals;
  late List<Matrix3> _targetOrients;

  /// Local rotations of the aligned stance that differ from the target's
  /// rest; empty unless [alignStance].
  final Map<int, Quaternion> _alignedRotations = {};

  /// Returns a new [Animation] whose channels drive [target]'s bones.
  Animation retarget(Animation clip) {
    final cached = _cache[clip];
    if (cached != null) return cached;

    final rotations = <int, RotationTimelineResolver>{};
    final translations = <int, TranslationTimelineResolver>{};
    final scales = <int, ScaleTimelineResolver>{};
    final channels = <AnimationChannel>[];
    final keyed = <int>{};
    for (final channel in clip.channels) {
      final key = channel.bindTarget;
      if (key.property == AnimationProperty.weights) {
        final name = boneMap[key.nodeName] ?? key.nodeName;
        if (target._indexOf(name) != null) {
          channels.add(
            AnimationChannel(
              bindTarget: BindKey(nodeName: name, property: key.property),
              resolver: channel.resolver,
            ),
          );
        }
        continue;
      }
      final bone = source._indexOf(key.nodeName);
      if (bone == null) {
        report._unmappedSourceBones.add(key.nodeName);
        continue;
      }
      keyed.add(bone);
      switch ((key.property, channel.resolver)) {
        case (AnimationProperty.rotation, RotationTimelineResolver r):
          rotations.putIfAbsent(bone, () => r);
        case (AnimationProperty.translation, TranslationTimelineResolver r):
          translations.putIfAbsent(bone, () => r);
        case (AnimationProperty.scale, ScaleTimelineResolver r):
          scales.putIfAbsent(bone, () => r);
        default:
          break;
      }
    }

    final consumed = <int>{};
    final root = _rootBone(translations);
    for (final MapEntry(key: bone, value: chain) in _chains.entries) {
      consumed.addAll(chain);
      final name = target._bones[bone].name;
      final from = _sourceOf[bone]!;
      final rotation = _retargetRotation(bone, chain, rotations, clip.endTime);
      if (rotation != null) {
        channels.add(
          AnimationChannel(
            bindTarget: BindKey(
              nodeName: name,
              property: AnimationProperty.rotation,
            ),
            resolver: rotation,
          ),
        );
      }
      final translation = translations[from];
      if (translation != null) {
        final carry = bone == root
            ? rootTranslation != RootTranslation.none
            : keepNonRootTranslation;
        if (carry) {
          channels.add(
            AnimationChannel(
              bindTarget: BindKey(
                nodeName: name,
                property: AnimationProperty.translation,
              ),
              resolver: _retargetTranslation(bone, translation),
            ),
          );
        } else if (bone != root) {
          report._droppedTranslationTracks++;
        }
      }
      final scale = scales[from];
      if (scale != null) {
        if (keepScale) {
          channels.add(
            AnimationChannel(
              bindTarget: BindKey(
                nodeName: name,
                property: AnimationProperty.scale,
              ),
              resolver: _retargetScale(bone, scale),
            ),
          );
        } else {
          report._droppedScaleTracks++;
        }
      }
    }
    for (final bone in keyed) {
      if (!consumed.contains(bone)) {
        report._unmappedSourceBones.add(source._bones[bone].name);
      }
    }

    final result = Animation._withEndTime(
      name: clip.name,
      channels: channels,
      endTime: clip.endTime,
    );
    _cache[clip] = result;
    return result;
  }

  void _pairBones() {
    final used = <int>{};
    void pair(int targetBone, int sourceBone) {
      if (_sourceOf.containsKey(targetBone) || used.contains(sourceBone)) {
        return;
      }
      _sourceOf[targetBone] = sourceBone;
      used.add(sourceBone);
    }

    for (final MapEntry(key: from, value: to) in boneMap.entries) {
      final s = source._indexOf(from);
      final t = target._indexOf(to);
      if (s != null && t != null) pair(t, s);
    }
    for (final MapEntry(key: slot, value: s) in source._humanoid.entries) {
      final t = target._humanoid[slot];
      if (t != null) pair(t, s);
    }
    for (var t = 0; t < target._bones.length; t++) {
      final name = target._bones[t].name;
      if (name.isEmpty) continue;
      final s = source._indexOf(name);
      if (s != null) pair(t, s);
    }
  }

  /// Records each paired bone's source chain, dropping pairs whose source
  /// does not sit under the source of their nearest paired ancestor (the
  /// hierarchy would have to cross over). Runs parents first, so a dropped
  /// pair re-anchors its descendants.
  void _prepareChains() {
    for (var t = 0; t < target._bones.length; t++) {
      final s = _sourceOf[t];
      if (s == null) continue;
      final anchor = _anchorOf(t);
      if (!source._isAncestor(anchor, s)) {
        _sourceOf.remove(t);
        report._incompatibleBones.add(target._bones[t].name);
        continue;
      }
      final chain = <int>[];
      for (var b = s; b != anchor; b = source._bones[b].parent) {
        chain.insert(0, b);
      }
      _chains[t] = chain;
      report._pairs[target._bones[t].name] = source._bones[s].name;
    }
  }

  /// The source of [targetBone]'s nearest paired ancestor, or -1.
  int _anchorOf(int targetBone) {
    final ancestor = target._ancestorWhere(targetBone, _sourceOf.containsKey);
    return ancestor < 0 ? -1 : _sourceOf[ancestor]!;
  }

  /// The paired target bone whose translation follows the source root: the
  /// hips when both rigs map them, otherwise the shallowest paired bone
  /// whose source carries a translation track.
  int? _rootBone(Map<int, TranslationTimelineResolver> translations) {
    final sourceHips = source._humanoid[HumanoidBone.hips];
    final targetHips = target._humanoid[HumanoidBone.hips];
    int? root;
    if (sourceHips != null &&
        targetHips != null &&
        _sourceOf[targetHips] == sourceHips) {
      root = targetHips;
    } else {
      for (final t in _chains.keys) {
        if (!translations.containsKey(_sourceOf[t])) continue;
        if (root == null ||
            target._bones[t].depth < target._bones[root].depth) {
          root = t;
        }
      }
    }
    if (root != null) {
      report._rootBone = target._bones[root].name;
      report._rootScale = _rootScale;
    }
    return root;
  }

  double get _rootScale {
    if (rootTranslation != RootTranslation.scaleByHipHeight) return 1;
    final from = source.hipHeight;
    final to = target.hipHeight;
    if (from == null || to == null) return 1;
    return to / from;
  }

  /// The target's local rotation keys for [bone], or null when nothing on
  /// its source chain rotates.
  ///
  /// With `L` a rest orientation relative to the rig root and `Σ` a bone's
  /// scale signs, keeping the bone's world rotation away from rest equal to
  /// its source's gives `R_t = L_t(parent)⁻¹ · L_s(anchor) · Π(R·Σ over the
  /// chain) · L_s(source)⁻¹ · L_t(bone) · Σ_t`. When only the chain's last
  /// bone rotates, that is `A · R_s · B` with constant `A` and `B`, which
  /// commutes with slerp, so each key is rewritten in place.
  // TODO(retarget-nonuniform-scale): orientations drop scale magnitudes, so a
  // non-uniformly scaled ancestor's shear is lost. Carry the full linear
  // transform through the chain and polar-decompose per key to make it exact.
  RotationTimelineResolver? _retargetRotation(
    int bone,
    List<int> chain,
    Map<int, RotationTimelineResolver> rotations,
    double endTime,
  ) {
    final animated = [
      for (final b in chain)
        if (rotations.containsKey(b)) b,
    ];
    if (animated.isEmpty) {
      // An aligned bone must still hold its aligned pose, since its
      // children's keys assume it.
      final aligned = _alignedRotations[bone];
      if (aligned == null) return null;
      return RotationTimelineResolver._([0, endTime], [aligned, aligned]);
    }
    final s = chain.last;
    final parent = target._bones[bone].parent;
    final targetParent = parent < 0
        ? Matrix3.identity()
        : _targetOrients[parent];
    final post = _scaleSigns(source._bones[s].rest)
      ..multiply(_transposed(source._orients[s]))
      ..multiply(_targetOrients[bone])
      ..multiply(_scaleSigns(target._bones[bone].rest));

    if (animated.length == 1 && animated.single == s) {
      final sourceParent = source._bones[s].parent;
      final pre = _transposed(targetParent)
        ..multiply(
          sourceParent < 0 ? Matrix3.identity() : source._orients[sourceParent],
        );
      final (qa, qb) = _properPair(pre, post);
      final keys = rotations[s]!;
      return RotationTimelineResolver._(keys._times, [
        for (final q in keys._values) (qa * q * qb)..normalize(),
      ]);
    }

    report._sampledBones.add(target._bones[bone].name);
    final anchor = source._bones[chain.first].parent;
    final pre = _transposed(targetParent)
      ..multiply(anchor < 0 ? Matrix3.identity() : source._orients[anchor]);
    final times = _sampleTimes([
      for (final b in animated) rotations[b]!,
    ], endTime);
    final values = <Quaternion>[];
    for (final time in times) {
      final m = pre.clone();
      for (final b in chain) {
        final keys = rotations[b];
        final r = keys == null
            ? source._bones[b].rest.rotation
            : _sampleRotation(keys, time);
        m.multiply(r.asRotationMatrix());
        // The source bone's own signs lead [post].
        if (b != s) m.multiply(_scaleSigns(source._bones[b].rest));
      }
      m.multiply(post);
      if (m.determinant() < 0) _negate(m);
      values.add(Quaternion.fromRotation(m)..normalize());
    }
    return RotationTimelineResolver._(times, values);
  }

  /// `p_t = p_t,rest + T⁻¹ · (k · S · (p_s - p_s,rest))`, with `S` and `T`
  /// the full rest transforms of each bone's parent (so a 0.01 armature
  /// converts centimeters) and `k` the root scale. Affine, so it commutes
  /// with lerp and keys are rewritten in place.
  TranslationTimelineResolver _retargetTranslation(
    int bone,
    TranslationTimelineResolver keys,
  ) {
    final s = _sourceOf[bone]!;
    final sourceParent = source._bones[s].parent;
    final targetParent = target._bones[bone].parent;
    final toWorld = sourceParent < 0
        ? Matrix3.identity()
        : source._globals[sourceParent].getRotation();
    final fromWorld = targetParent < 0
        ? Matrix3.identity()
        : (_targetGlobals[targetParent].getRotation()..invert());
    final map = fromWorld..multiply(toWorld);
    final k = _rootScale;
    final sourceRest = source._bones[s].rest.translation;
    final targetRest = target._bones[bone].rest.translation;
    return TranslationTimelineResolver._(keys._times, [
      for (final p in keys._values)
        targetRest + map.transformed((p - sourceRest)..scale(k)),
    ]);
  }

  /// Carries scale as a per-axis ratio against the source rest.
  ScaleTimelineResolver _retargetScale(int bone, ScaleTimelineResolver keys) {
    final sourceRest = source._bones[_sourceOf[bone]!].rest.scale;
    final targetRest = target._bones[bone].rest.scale;
    double ratio(double v, double rest) => rest == 0 ? 1 : v / rest;
    return ScaleTimelineResolver._(keys._times, [
      for (final v in keys._values)
        Vector3(
          targetRest.x * ratio(v.x, sourceRest.x),
          targetRest.y * ratio(v.y, sourceRest.y),
          targetRest.z * ratio(v.z, sourceRest.z),
        ),
    ]);
  }

  /// The target pose the rotation constants are built against: its rest,
  /// or with [alignStance] its rest with each single-child limb bone swung
  /// so it points toward its paired child the way the source's rest does.
  void _prepareTargetReference() {
    final rests = [for (final bone in target._bones) bone.rest.clone()];
    if (alignStance) {
      final children = <int, List<int>>{};
      for (final t in _sourceOf.keys) {
        final ancestor = target._ancestorWhere(t, _sourceOf.containsKey);
        if (ancestor >= 0) (children[ancestor] ??= []).add(t);
      }
      for (var t = 0; t < target._bones.length; t++) {
        final kids = children[t];
        if (kids == null || kids.length != 1) continue;
        final (globals, orients) = _poseOf(target._bones, rests);
        final child = kids.single;
        final have =
            globals[child].getTranslation() - globals[t].getTranslation();
        final want =
            source._positionOf(_sourceOf[child]!) -
            source._positionOf(_sourceOf[t]!);
        if (have.length2 < 1e-12 || want.length2 < 1e-12) continue;
        final swing = Quaternion.fromTwoVectors(
          have.normalized(),
          want.normalized(),
        ).asRotationMatrix();
        final parent = target._bones[t].parent;
        final frame = parent < 0 ? Matrix3.identity() : orients[parent];
        // Express the world swing in the parent's frame and apply it ahead
        // of the bone's own rotation.
        final local = _transposed(frame)
          ..multiply(swing)
          ..multiply(frame)
          ..multiply(rests[t].rotation.asRotationMatrix());
        rests[t].rotation = Quaternion.fromRotation(local)..normalize();
      }
    }
    final (globals, orients) = _poseOf(target._bones, rests);
    _targetGlobals = globals;
    _targetOrients = orients;
    for (var t = 0; t < rests.length; t++) {
      final rest = target._bones[t].rest.rotation;
      if (rests[t].rotation.dot(rest).abs() < 1 - 1e-9) {
        _alignedRotations[t] = rests[t].rotation;
      }
    }
  }

  /// Rest-relative-to-root transforms and orientations of [bones] posed at
  /// [rests].
  static (List<Matrix4>, List<Matrix3>) _poseOf(
    List<_RigBone> bones,
    List<DecomposedTransform> rests,
  ) {
    final globals = <Matrix4>[];
    final orients = <Matrix3>[];
    for (var i = 0; i < bones.length; i++) {
      final parent = bones[i].parent;
      final local = rests[i].toMatrix4();
      final orient = _rotationWithSigns(rests[i]);
      globals.add(parent < 0 ? local : globals[parent].multiplied(local));
      orients.add(parent < 0 ? orient : orients[parent].multiplied(orient));
    }
    return (globals, orients);
  }

  /// Every key time of [tracks], with extra samples so no gap exceeds
  /// `1 / sampleRate`.
  List<double> _sampleTimes(
    List<RotationTimelineResolver> tracks,
    double endTime,
  ) {
    final keys = <double>{0, endTime};
    for (final track in tracks) {
      keys.addAll(track._times);
    }
    final sorted = keys.toList()..sort();
    final step = sampleRate > 0 ? 1 / sampleRate : double.infinity;
    final times = <double>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0) {
        final gap = sorted[i] - sorted[i - 1];
        final extra = (gap / step).ceil() - 1;
        for (var k = 1; k <= extra; k++) {
          times.add(sorted[i - 1] + gap * k / (extra + 1));
        }
      }
      times.add(sorted[i]);
    }
    return times;
  }
}

/// The rotation [keys] evaluates to at [time], matching
/// [RotationTimelineResolver.apply].
Quaternion _sampleRotation(RotationTimelineResolver keys, double time) {
  final key = keys._getTimelineKey(time);
  final value = keys._values[key.index];
  if (key.lerp < 1) return keys._values[key.index - 1].slerp(value, key.lerp);
  return value;
}

/// [a] and [b] as quaternions. Their determinants always match (each is the
/// product of the sign flips on the chains it spans), so when both mirror,
/// negating both leaves `a · r · b` unchanged and makes each a rotation.
(Quaternion, Quaternion) _properPair(Matrix3 a, Matrix3 b) {
  if (a.determinant() < 0) {
    _negate(a);
    _negate(b);
  }
  return (
    Quaternion.fromRotation(a)..normalize(),
    Quaternion.fromRotation(b)..normalize(),
  );
}

Matrix3 _transposed(Matrix3 m) => m.clone()..transpose();

void _negate(Matrix3 m) {
  final storage = m.storage;
  for (var i = 0; i < storage.length; i++) {
    storage[i] = -storage[i];
  }
}
