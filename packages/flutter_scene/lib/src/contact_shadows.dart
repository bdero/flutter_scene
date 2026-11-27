import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/render/render_quality.dart';

/// Scene-wide quality settings for screen-space contact shadows.
///
/// Reachable through `Scene.contactShadows`. Contact shadows are opted into
/// per light (`DirectionalLight.contactShadows`, `PointLight.contactShadows`,
/// `SpotLight.contactShadows`); these settings shape how every opted-in light
/// marches. A short ray from each visible surface toward the light walks the
/// camera's depth buffer, catching the small-scale contact (a foot on the
/// floor, a cup on a table) that shadow-map resolution and bias miss.
///
/// Everything drawn into the depth prepass casts, including objects whose
/// shadow maps are off, and opaque surfaces receive. Translucent surfaces do
/// not, since the depth buffer belongs to whatever is behind them. Off-screen
/// casters cast nothing, so the shadow fades out toward the screen edges.
/// {@category Lighting and environment}
class ContactShadowSettings {
  /// Steps each ray takes, at most 16. Null picks one from the scene's
  /// effective `RenderQualityTier` (16 on high, 8 otherwise). A ray covering
  /// fewer pixels than this takes one step per pixel.
  int? sampleCount;

  /// The deepest an occluder may sit in front of the ray, in world units,
  /// and still cast. Keeps a surface far in front of the ray (a wall behind a
  /// thin pole, as the camera sees it) from shadowing through it.
  double thickness = 0.1;

  /// The view depth, in world units, beyond which surfaces get no contact
  /// shadow.
  double maxDistance = 50.0;

  /// The view-depth range, in world units, over which contact shadows fade
  /// out before [maxDistance].
  double fadeRange = 5.0;

  /// How dark a full contact shadow is, from 0 (off) to 1.
  double opacity = 1.0;

  /// How the primary directional light marches. The wavefront kernel runs
  /// only where the device runs compute, and never on
  /// [RenderQualityTier.low].
  // TODO(contact-shadows-wavefront): export once it costs no more than the
  // fragment march; it measured about 2x on Metal, WebGPU, and Mali.
  @internal
  ContactShadowMethod method = ContactShadowMethod.fragment;

  /// The steps per ray in effect for [tier].
  @internal
  int stepsFor(RenderQualityTier tier) {
    final count = sampleCount;
    if (count != null) return count.clamp(2, maxContactShadowSteps);
    return tier == RenderQualityTier.high ? 16 : 8;
  }
}

/// How the primary directional light's contact shadow is marched. Not
/// exported; see [ContactShadowSettings.method].
enum ContactShadowMethod {
  /// A per-pixel march in the fragment pass, on every backend.
  fragment,

  /// The wavefront compute kernel, where the device runs compute.
  wavefront,
}

/// The march's constant loop bound (`MAX_CONTACT_STEPS` in
/// `flutter_scene_contact_shadows.frag`).
@internal
const int maxContactShadowSteps = 16;
