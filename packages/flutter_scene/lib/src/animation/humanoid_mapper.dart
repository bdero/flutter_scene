part of '../animation.dart';

/// A bone name broken into lowercase words, with its side and number pulled
/// out: `mixamorig:LeftHandIndex1` reads as side left, number 1, words
/// `[hand, index]`.
class _BoneWords {
  _BoneWords(this.words, this.side, this.number);

  final List<String> words;

  /// -1 left, 1 right, 0 neither.
  final int side;

  final int? number;

  String get core => words.join();

  factory _BoneWords.parse(String name) {
    var text = name;
    // Namespaces such as "mixamorig:" or "Armature|".
    final cut = text.lastIndexOf(RegExp(r'[:|]'));
    if (cut >= 0) text = text.substring(cut + 1);
    text = text
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Za-z])(\d)'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'(\d)([A-Za-z])'), (m) => '${m[1]} ${m[2]}');
    final tokens = text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    // Exporter prefixes that carry no meaning (VRoid's J_Bip_C_, Rigify's
    // DEF-, 3ds Max's Bip01).
    while (tokens.isNotEmpty && _prefixWords.contains(tokens.first)) {
      tokens.removeAt(0);
    }
    var side = 0;
    int? number;
    final words = <String>[];
    for (final token in tokens) {
      if (token == 'left' || token == 'l') {
        side = -1;
      } else if (token == 'right' || token == 'r') {
        side = 1;
      } else if (int.tryParse(token) case final n?) {
        number ??= n;
      } else {
        words.add(token);
      }
    }
    return _BoneWords(words, side, number);
  }

  static const _prefixWords = {
    'mixamorig',
    'def',
    'org',
    'j',
    'bip',
    'bip01',
    'bip001',
    'c',
  };
}

const _torsoSynonyms = <String, HumanoidBone>{
  'hips': HumanoidBone.hips,
  'hip': HumanoidBone.hips,
  'pelvis': HumanoidBone.hips,
  'chest': HumanoidBone.chest,
  'upperchest': HumanoidBone.upperChest,
  'neck': HumanoidBone.neck,
  'head': HumanoidBone.head,
  'jaw': HumanoidBone.jaw,
};

/// Left-side slots by core word; the right side is the matching right slot.
const _limbSynonyms = <String, HumanoidBone>{
  'shoulder': HumanoidBone.leftShoulder,
  'clavicle': HumanoidBone.leftShoulder,
  'collar': HumanoidBone.leftShoulder,
  'collarbone': HumanoidBone.leftShoulder,
  'upperarm': HumanoidBone.leftUpperArm,
  'uparm': HumanoidBone.leftUpperArm,
  // Mixamo's "Arm" is the upper arm and its "Leg" the lower leg.
  'arm': HumanoidBone.leftUpperArm,
  'lowerarm': HumanoidBone.leftLowerArm,
  'forearm': HumanoidBone.leftLowerArm,
  'lowarm': HumanoidBone.leftLowerArm,
  'hand': HumanoidBone.leftHand,
  'wrist': HumanoidBone.leftHand,
  'upperleg': HumanoidBone.leftUpperLeg,
  'upleg': HumanoidBone.leftUpperLeg,
  'thigh': HumanoidBone.leftUpperLeg,
  'lowerleg': HumanoidBone.leftLowerLeg,
  'leg': HumanoidBone.leftLowerLeg,
  'calf': HumanoidBone.leftLowerLeg,
  'shin': HumanoidBone.leftLowerLeg,
  'lowleg': HumanoidBone.leftLowerLeg,
  'foot': HumanoidBone.leftFoot,
  'ankle': HumanoidBone.leftFoot,
  'toes': HumanoidBone.leftToes,
  'toe': HumanoidBone.leftToes,
  'toebase': HumanoidBone.leftToes,
  'ball': HumanoidBone.leftToes,
  'eye': HumanoidBone.leftEye,
};

const _fingerNames = {
  'thumb': 0,
  'index': 1,
  'middle': 2,
  'ring': 3,
  'little': 4,
  'pinky': 4,
  'pinkie': 4,
};

/// Words that may sit beside a finger name without changing what it is
/// ("LeftHandIndex1", Rigify's "f_index.01.L").
const _fingerFillers = {'hand', 'f', 'finger', 'fingers'};

/// The three slots of finger [finger] (0 thumb to 4 little) on [side].
List<HumanoidBone> _fingerSlots(int side, int finger) {
  final first =
      (side < 0
              ? HumanoidBone.leftThumbMetacarpal
              : HumanoidBone.rightThumbMetacarpal)
          .index +
      finger * 3;
  return HumanoidBone.values.sublist(first, first + 3);
}

HumanoidBone _rightOf(HumanoidBone left) =>
    HumanoidBone.values.byName('right${left.name.substring(4)}');

/// Maps [bones] onto the humanoid slots by name, falling back on hierarchy
/// where names are ambiguous (spine numbering runs either direction across
/// exporters). The rig validates the result afterwards.
Map<HumanoidBone, int> _autoMapHumanoid(List<_RigBone> bones) {
  final words = [for (final bone in bones) _BoneWords.parse(bone.name)];
  final candidates = <HumanoidBone, List<int>>{};
  final spineFamily = <int>[];
  final fingers = <(int, int), List<int>>{};

  void add(HumanoidBone slot, int bone) => (candidates[slot] ??= []).add(bone);

  for (var i = 0; i < bones.length; i++) {
    final w = words[i];
    if (w.words.isEmpty) continue;
    final finger = _fingerOf(w);
    if (finger != null) {
      if (w.side != 0) (fingers[(w.side, finger)] ??= []).add(i);
      continue;
    }
    final core = w.core;
    if (core == 'spine') {
      if (w.side == 0) spineFamily.add(i);
      continue;
    }
    final torso = _torsoSynonyms[core];
    if (torso != null) {
      if (w.side == 0) add(torso, i);
      continue;
    }
    final limb = _limbSynonyms[core];
    if (limb != null && w.side != 0) {
      add(w.side < 0 ? limb : _rightOf(limb), i);
    }
  }

  // The shallowest candidate wins, which skips twist and helper segments
  // that repeat a limb's name further down (Rigify's "thigh.L.001").
  int? pick(HumanoidBone slot, {int under = -1}) {
    int? best;
    for (final i in candidates[slot] ?? const <int>[]) {
      if (under >= 0 && !_isUnder(bones, under, i)) continue;
      if (best == null || bones[i].depth < bones[best].depth) best = i;
    }
    return best;
  }

  final result = <HumanoidBone, int>{};
  final rigifyTorso = _rigifyTorso(bones);
  if (rigifyTorso != null) {
    result.addAll(rigifyTorso);
  } else {
    // A rig with no hips-named bone often calls its pelvis the first spine
    // bone (Rigify, some game rigs).
    final hips = pick(HumanoidBone.hips) ?? _shallowest(bones, spineFamily);
    if (hips != null) {
      result[HumanoidBone.hips] = hips;
      _mapTorso(bones, hips, pick, result);
    }
  }

  // Limbs search the whole body below the hips rather than a guessed chest
  // bone, since shoulders do not always hang from the last spine bone;
  // validation catches a limb nested in the wrong place.
  final hips = result[HumanoidBone.hips] ?? -1;
  for (final side in const [-1, 1]) {
    HumanoidBone slot(HumanoidBone left) => side < 0 ? left : _rightOf(left);
    void chain(List<HumanoidBone> leftSlots, int start) {
      var under = start;
      for (final left in leftSlots) {
        final bone = pick(slot(left), under: under);
        if (bone == null) continue;
        result[slot(left)] = bone;
        under = bone;
      }
    }

    chain(const [
      HumanoidBone.leftShoulder,
      HumanoidBone.leftUpperArm,
      HumanoidBone.leftLowerArm,
      HumanoidBone.leftHand,
    ], hips);
    chain(const [
      HumanoidBone.leftUpperLeg,
      HumanoidBone.leftLowerLeg,
      HumanoidBone.leftFoot,
      HumanoidBone.leftToes,
    ], hips);
    final head = result[HumanoidBone.head] ?? -1;
    final eye = pick(slot(HumanoidBone.leftEye), under: head);
    if (eye != null) result[slot(HumanoidBone.leftEye)] = eye;

    final hand = result[slot(HumanoidBone.leftHand)];
    if (hand == null) continue;
    for (var finger = 0; finger < 5; finger++) {
      final chainBones = _fingerChain(bones, fingers[(side, finger)], hand);
      if (chainBones == null) continue;
      final slots = _fingerSlots(side, finger);
      for (var k = 0; k < 3; k++) {
        result[slots[k]] = chainBones[k];
      }
    }
  }
  final head = result[HumanoidBone.head];
  if (head != null) {
    final jaw = pick(HumanoidBone.jaw, under: head);
    if (jaw != null) result[HumanoidBone.jaw] = jaw;
  }
  return result;
}

/// Fills spine, chest, upperChest, neck, and head from the bones on the
/// path from [hips] to the head, by position rather than by number, since
/// exporters number the spine both upward (Mixamo's Spine, Spine1, Spine2)
/// and downward (Meshy's Spine02, Spine01, Spine).
void _mapTorso(
  List<_RigBone> bones,
  int hips,
  int? Function(HumanoidBone, {int under}) pick,
  Map<HumanoidBone, int> result,
) {
  final head = pick(HumanoidBone.head, under: hips);
  if (head == null) return;
  result[HumanoidBone.head] = head;
  final path = <int>[];
  for (var b = bones[head].parent; b >= 0 && b != hips; b = bones[b].parent) {
    path.insert(0, b);
  }
  // The shallowest neck on the path; a second neck segment stays unmapped.
  final neck = path.cast<int?>().firstWhere(
    (b) => _isCandidate(bones, b!, 'neck'),
    orElse: () => null,
  );
  final torso = neck == null ? path : path.sublist(0, path.indexOf(neck));
  if (neck != null) result[HumanoidBone.neck] = neck;

  final chest = torso.cast<int?>().firstWhere(
    (b) => _isCandidate(bones, b!, 'chest'),
    orElse: () => null,
  );
  final upperChest = torso.cast<int?>().firstWhere(
    (b) => _isCandidate(bones, b!, 'upperchest'),
    orElse: () => null,
  );
  final rest = [
    for (final b in torso)
      if (b != chest && b != upperChest) b,
  ];
  if (chest == null && upperChest == null) {
    if (rest.isNotEmpty) result[HumanoidBone.spine] = rest.first;
    if (rest.length >= 2) result[HumanoidBone.chest] = rest[1];
    if (rest.length >= 3) result[HumanoidBone.upperChest] = rest.last;
    return;
  }
  final split = torso.indexOf(chest ?? upperChest!);
  final below = [
    for (final b in rest)
      if (torso.indexOf(b) < split) b,
  ];
  final above = [
    for (final b in rest)
      if (torso.indexOf(b) > split) b,
  ];
  if (below.isNotEmpty) result[HumanoidBone.spine] = below.first;
  if (chest != null) result[HumanoidBone.chest] = chest;
  if (upperChest != null) {
    result[HumanoidBone.upperChest] = upperChest;
  } else if (above.isNotEmpty) {
    result[HumanoidBone.upperChest] = above.last;
  }
}

bool _isCandidate(List<_RigBone> bones, int bone, String core) {
  final w = _BoneWords.parse(bones[bone].name);
  return w.side == 0 && w.core == core;
}

/// Rigify's deform torso names every bone "spine": spine is the pelvis,
/// spine.001 to .003 the spine, .004 and .005 the neck, .006 the head.
Map<HumanoidBone, int>? _rigifyTorso(List<_RigBone> bones) {
  final bySuffix = <int, int>{};
  final pattern = RegExp(r'^(?:DEF-|ORG-)?spine(?:\.(\d{3}))?$');
  for (var i = 0; i < bones.length; i++) {
    final match = pattern.firstMatch(bones[i].name);
    if (match == null) continue;
    bySuffix.putIfAbsent(int.parse(match[1] ?? '0'), () => i);
  }
  if (!List.generate(7, (i) => i).every(bySuffix.containsKey)) return null;
  return {
    HumanoidBone.hips: bySuffix[0]!,
    HumanoidBone.spine: bySuffix[1]!,
    HumanoidBone.chest: bySuffix[2]!,
    HumanoidBone.upperChest: bySuffix[3]!,
    HumanoidBone.neck: bySuffix[4]!,
    HumanoidBone.head: bySuffix[6]!,
  };
}

/// The finger index (0 thumb to 4 little) a name denotes, or null.
int? _fingerOf(_BoneWords w) {
  int? finger;
  for (final word in w.words) {
    if (_fingerFillers.contains(word)) continue;
    final f = _fingerNames[word];
    // Any other word (metacarpal, scaler, twist, end) disqualifies it.
    if (f == null || finger != null) return null;
    finger = f;
  }
  return finger;
}

/// The three bones of one finger under [hand], or null unless exactly three
/// remain. A fourth is the tip marker (Mixamo's Index4) and is dropped.
List<int>? _fingerChain(List<_RigBone> bones, List<int>? found, int hand) {
  if (found == null) return null;
  final under = [
    for (final b in found)
      if (_isUnder(bones, hand, b)) b,
  ]..sort((a, b) => bones[a].depth.compareTo(bones[b].depth));
  if (under.length == 4) under.removeLast();
  if (under.length != 3) return null;
  // Each must hang from the one before it.
  for (var k = 1; k < 3; k++) {
    if (!_isUnder(bones, under[k - 1], under[k])) return null;
  }
  return under;
}

bool _isUnder(List<_RigBone> bones, int ancestor, int bone) {
  if (ancestor < 0) return true;
  for (var b = bones[bone].parent; b >= 0; b = bones[b].parent) {
    if (b == ancestor) return true;
  }
  return false;
}

int? _shallowest(List<_RigBone> bones, List<int> indices) {
  int? best;
  for (final i in indices) {
    if (best == null || bones[i].depth < bones[best].depth) best = i;
  }
  return best;
}
