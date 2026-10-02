part of '../animation.dart';

/// A slot in the VRM 1.0 humanoid skeleton, the shared vocabulary
/// [RetargetRig] maps each rig's bones onto so clips can move between
/// differently named humanoids.
///
/// Fifteen slots are required for a rig to count as humanoid (see
/// [isRequired]); the rest are mapped when present.
/// {@category Animation}
enum HumanoidBone {
  /// The pelvis, the root of the humanoid hierarchy.
  hips,

  /// The first spine bone above the hips.
  spine,

  /// The spine bone above [spine].
  chest,

  /// The spine bone the shoulders and neck hang from.
  upperChest,

  /// The neck.
  neck,

  /// The head.
  head,

  /// The left eye.
  leftEye,

  /// The right eye.
  rightEye,

  /// The jaw.
  jaw,

  /// The left thigh.
  leftUpperLeg,

  /// The left shin.
  leftLowerLeg,

  /// The left ankle.
  leftFoot,

  /// The left toes.
  leftToes,

  /// The right thigh.
  rightUpperLeg,

  /// The right shin.
  rightLowerLeg,

  /// The right ankle.
  rightFoot,

  /// The right toes.
  rightToes,

  /// The left clavicle.
  leftShoulder,

  /// The left upper arm.
  leftUpperArm,

  /// The left forearm.
  leftLowerArm,

  /// The left wrist.
  leftHand,

  /// The right clavicle.
  rightShoulder,

  /// The right upper arm.
  rightUpperArm,

  /// The right forearm.
  rightLowerArm,

  /// The right wrist.
  rightHand,

  /// The left thumb's first bone.
  leftThumbMetacarpal,

  /// The left thumb's second bone.
  leftThumbProximal,

  /// The left thumb's tip bone.
  leftThumbDistal,

  /// The left index finger's first bone.
  leftIndexProximal,

  /// The left index finger's middle bone.
  leftIndexIntermediate,

  /// The left index finger's tip bone.
  leftIndexDistal,

  /// The left middle finger's first bone.
  leftMiddleProximal,

  /// The left middle finger's middle bone.
  leftMiddleIntermediate,

  /// The left middle finger's tip bone.
  leftMiddleDistal,

  /// The left ring finger's first bone.
  leftRingProximal,

  /// The left ring finger's middle bone.
  leftRingIntermediate,

  /// The left ring finger's tip bone.
  leftRingDistal,

  /// The left little finger's first bone.
  leftLittleProximal,

  /// The left little finger's middle bone.
  leftLittleIntermediate,

  /// The left little finger's tip bone.
  leftLittleDistal,

  /// The right thumb's first bone.
  rightThumbMetacarpal,

  /// The right thumb's second bone.
  rightThumbProximal,

  /// The right thumb's tip bone.
  rightThumbDistal,

  /// The right index finger's first bone.
  rightIndexProximal,

  /// The right index finger's middle bone.
  rightIndexIntermediate,

  /// The right index finger's tip bone.
  rightIndexDistal,

  /// The right middle finger's first bone.
  rightMiddleProximal,

  /// The right middle finger's middle bone.
  rightMiddleIntermediate,

  /// The right middle finger's tip bone.
  rightMiddleDistal,

  /// The right ring finger's first bone.
  rightRingProximal,

  /// The right ring finger's middle bone.
  rightRingIntermediate,

  /// The right ring finger's tip bone.
  rightRingDistal,

  /// The right little finger's first bone.
  rightLittleProximal,

  /// The right little finger's middle bone.
  rightLittleIntermediate,

  /// The right little finger's tip bone.
  rightLittleDistal;

  /// The slot this one hangs from in the humanoid hierarchy, or null for
  /// [hips].
  HumanoidBone? get parent => switch (this) {
    hips => null,
    spine => hips,
    chest => spine,
    upperChest => chest,
    neck => upperChest,
    head => neck,
    leftEye || rightEye || jaw => head,
    leftUpperLeg || rightUpperLeg => hips,
    leftLowerLeg => leftUpperLeg,
    rightLowerLeg => rightUpperLeg,
    leftFoot => leftLowerLeg,
    rightFoot => rightLowerLeg,
    leftToes => leftFoot,
    rightToes => rightFoot,
    leftShoulder || rightShoulder => upperChest,
    leftUpperArm => leftShoulder,
    rightUpperArm => rightShoulder,
    leftLowerArm => leftUpperArm,
    rightLowerArm => rightUpperArm,
    leftHand => leftLowerArm,
    rightHand => rightLowerArm,
    leftThumbMetacarpal ||
    leftIndexProximal ||
    leftMiddleProximal ||
    leftRingProximal ||
    leftLittleProximal => leftHand,
    rightThumbMetacarpal ||
    rightIndexProximal ||
    rightMiddleProximal ||
    rightRingProximal ||
    rightLittleProximal => rightHand,
    leftThumbProximal => leftThumbMetacarpal,
    leftThumbDistal => leftThumbProximal,
    leftIndexIntermediate => leftIndexProximal,
    leftIndexDistal => leftIndexIntermediate,
    leftMiddleIntermediate => leftMiddleProximal,
    leftMiddleDistal => leftMiddleIntermediate,
    leftRingIntermediate => leftRingProximal,
    leftRingDistal => leftRingIntermediate,
    leftLittleIntermediate => leftLittleProximal,
    leftLittleDistal => leftLittleIntermediate,
    rightThumbProximal => rightThumbMetacarpal,
    rightThumbDistal => rightThumbProximal,
    rightIndexIntermediate => rightIndexProximal,
    rightIndexDistal => rightIndexIntermediate,
    rightMiddleIntermediate => rightMiddleProximal,
    rightMiddleDistal => rightMiddleIntermediate,
    rightRingIntermediate => rightRingProximal,
    rightRingDistal => rightRingIntermediate,
    rightLittleIntermediate => rightLittleProximal,
    rightLittleDistal => rightLittleIntermediate,
  };

  /// Whether a rig must map this slot to count as humanoid.
  bool get isRequired => switch (this) {
    hips ||
    spine ||
    head ||
    leftUpperLeg ||
    leftLowerLeg ||
    leftFoot ||
    rightUpperLeg ||
    rightLowerLeg ||
    rightFoot ||
    leftUpperArm ||
    leftLowerArm ||
    leftHand ||
    rightUpperArm ||
    rightLowerArm ||
    rightHand => true,
    _ => false,
  };
}
