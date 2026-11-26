import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/components/point_light_component.dart';
import 'package:flutter_scene/src/components/spot_light_component.dart';
import 'package:flutter_scene/src/render/contact_shadow_pass.dart';
import 'package:flutter_scene/src/render/shadow_caster_selection.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';

/// How many lights besides the primary directional light share the
/// screen-space shadow mask (its g, b, and a channels).
const int kContactShadowLightChannels = kContactShadowChannels - 1;

/// Hands the screen-space shadow mask's g, b, and a channels to the
/// opted-in lights besides the primary directional light, once per frame.
///
/// The lights whose reach looks largest on screen win, ranked like shadow
/// casters (see [selectShadowCasters]) with last frame's holders favored in
/// near-ties. A light keeps its channel while it stays picked, so the mask
/// does not reshuffle when another light joins or leaves.
class ContactShadowChannels {
  final List<Object?> _holders = List<Object?>.filled(
    kContactShadowLightChannels,
    null,
  );
  bool _warnedOverflow = false;

  /// The light holding each channel (g, b, a): a [DirectionalLightComponent],
  /// [PointLightComponent], or [SpotLightComponent], or null when free.
  List<Object?> get holders => _holders;

  /// The channel [light] holds (1 g, 2 b, 3 a), or 0 for none.
  int channelOf(Object light) {
    for (var i = 0; i < _holders.length; i++) {
      if (identical(_holders[i], light)) return i + 1;
    }
    return 0;
  }

  /// Picks this frame's holders from the lights with contact shadows on.
  /// [primary] always takes channel r and is skipped here. A null [views]
  /// skips the visibility test and keeps list order.
  void update({
    required List<DirectionalLightComponent> directionals,
    required DirectionalLightComponent? primary,
    required List<PointLightComponent> points,
    required List<SpotLightComponent> spots,
    ShadowViewVolumes? views,
  }) {
    final lights = <Object>[
      for (final light in directionals)
        if (!identical(light, primary) && light.light.contactShadows) light,
      for (final light in points)
        if (light.light.contactShadows) light,
      for (final light in spots)
        if (light.light.contactShadows) light,
    ];
    final selection = selectShadowCasters<Object>(
      lights,
      budget: kContactShadowLightChannels,
      castsShadow: (_) => true,
      bounds: _bounds,
      views: views,
      previous: {
        for (final holder in _holders)
          if (holder != null) holder,
      },
    );
    final picked = selection.casters;
    for (var i = 0; i < _holders.length; i++) {
      final holder = _holders[i];
      if (holder != null && !picked.any((l) => identical(l, holder))) {
        _holders[i] = null;
      }
    }
    for (final light in picked) {
      if (channelOf(light) != 0) continue;
      _holders[_holders.indexOf(null)] = light;
    }
    assert(() {
      if (selection.dropped.isNotEmpty && !_warnedOverflow) {
        _warnedOverflow = true;
        debugPrint(
          'flutter_scene: more than $kContactShadowLightChannels lights '
          'besides the primary directional light have contactShadows on; '
          'the ones that look smallest on screen get none.',
        );
      }
      return true;
    }());
  }

  /// Frees every channel.
  void clear() => _holders.fillRange(0, _holders.length, null);

  static Sphere _bounds(Object light) => switch (light) {
    final PointLightComponent point => Sphere.centerRadius(
      point.worldPosition,
      point.light.range,
    ),
    final SpotLightComponent spot => spotInfluenceBounds(spot),
    _ => Sphere.centerRadius(Vector3.zero(), 0.0),
  };
}

/// [holder]'s contact-shadow march for a camera at [eye] with view basis
/// [right], [up], and [forward], or null for a light with no contact shadow.
ContactShadowLight? contactShadowLightInView(
  Object? holder, {
  required Vector3 eye,
  required Vector3 right,
  required Vector3 up,
  required Vector3 forward,
}) {
  Vector3 toView(Vector3 world) =>
      viewDirection(world - eye, right, up, forward);
  switch (holder) {
    case final DirectionalLightComponent directional:
      return ContactShadowLight.directional(
        viewDirection(-directional.worldDirection, right, up, forward),
        directional.light.contactShadowDistance,
      );
    case final PointLightComponent point:
      final range = point.light.range;
      return ContactShadowLight(
        type: ContactShadowLightType.point,
        vector: toView(point.worldPosition),
        distance: point.light.contactShadowDistance,
        inverseRange: range > 0.0 ? 1.0 / range : 0.0,
      );
    case final SpotLightComponent spot:
      final range = spot.light.range;
      return ContactShadowLight(
        type: ContactShadowLightType.spot,
        vector: toView(spot.worldPosition),
        distance: spot.light.contactShadowDistance,
        inverseRange: range > 0.0 ? 1.0 / range : 0.0,
        outerConeCos: math.cos(spot.light.outerConeAngle),
        axis: viewDirection(
          spot.worldDirection.normalized(),
          right,
          up,
          forward,
        ),
      );
  }
  return null;
}
