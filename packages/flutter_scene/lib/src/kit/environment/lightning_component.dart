/// Storm driver: lightning, the flash it throws across the sky, and the
/// thunder that arrives after it.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_sources.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// One strike, as it is happening.
/// {@category Gameplay kit}
class LightningStrike {
  LightningStrike({
    required this.distance,
    required this.thunderDelay,
    required this.intensity,
  });

  /// How far away the bolt was, in world units. Drawn from the component's
  /// range, and what sets [thunderDelay].
  final double distance;

  /// Seconds until the thunder should be heard.
  final double thunderDelay;

  /// Peak brightness of this strike, `0` to `1`.
  final double intensity;
}

/// Drives a storm: schedules lightning strikes, flashes the sky and a light,
/// and reports the thunder that follows.
///
/// Attach it to a node alongside the sky it drives. Each strike picks a
/// distance, and the thunder is delayed by how long sound takes to cover it,
/// which is the whole reason a distant storm feels distant: the flash and the
/// crack arrive together only when the bolt is on top of you.
///
/// The flash itself is a short multi-peak envelope rather than a single fade.
/// Real lightning is several return strokes in quick succession, and a single
/// ramp down reads as a camera flash instead.
/// {@category Gameplay kit}
class LightningComponent extends Component {
  LightningComponent({
    this.sky,
    this.light,
    this.minInterval = 4.0,
    this.maxInterval = 14.0,
    this.minDistance = 300.0,
    this.maxDistance = 4000.0,
    this.speedOfSound = 343.0,
    this.flashDuration = 0.42,
    this.lightIntensity = 12.0,
    this.stormDarkening = 0.7,
    this.onThunder,
    this.onStrike,
    int seed = 20260828,
  }) : _random = math.Random(seed),
       assert(minInterval > 0),
       assert(maxInterval >= minInterval),
       assert(minDistance > 0),
       assert(maxDistance >= minDistance) {
    _scheduleNext();
  }

  /// The sky whose flash and overcast this drives.
  ///
  /// Left null, the component finds the scene's own skybox on mount when it
  /// is a [WeatherSkySource], which is what makes a storm work as an authored
  /// component rather than only as one wired up in code. Still null after
  /// that (no scene, or a sky with no clouds) it fires strikes and thunder
  /// without a flash, which is a storm heard from indoors.
  WeatherSkySource? sky;

  /// A light flashed with each strike, its intensity scaled by the envelope.
  /// Its rest intensity is captured on the first frame and restored between
  /// strikes.
  ///
  /// Left null, the component adopts a [DirectionalLightComponent] on its own
  /// node, the same way [sky] finds the scene's. A document cannot point at a
  /// a live light, so putting the light on the storm's node is how the two are
  /// associated -- and it is what makes a strike visible under a clear sky,
  /// where there are no clouds to flash.
  DirectionalLight? light;

  /// The shortest and longest gap between strikes, in seconds.
  double minInterval;
  double maxInterval;

  /// The nearest and furthest a bolt can be, in world units. The distance sets
  /// both how loud the strike reads and how long the thunder takes.
  double minDistance;
  double maxDistance;

  /// How fast sound travels, in world units per second. The default is metres
  /// per second in air; scale it with the world's units.
  double speedOfSound;

  /// How long the flash envelope lasts.
  double flashDuration;

  /// Peak intensity the [light] reaches at the top of a strike.
  double lightIntensity;

  /// The overcast the sky is held at while this component is enabled.
  double stormDarkening;

  /// Called when a strike's thunder should be heard, so an application can
  /// play a clip. The strike carries its distance, so the sound can be
  /// attenuated and pitched for it.
  void Function(LightningStrike strike)? onThunder;

  /// Called the moment a bolt fires, before its thunder.
  void Function(LightningStrike strike)? onStrike;

  final math.Random _random;

  double _untilNext = 0;
  double _flashAge = double.infinity;
  double _flashPeak = 0;
  LightningStrike? _current;
  final List<({double at, LightningStrike strike})> _pendingThunder = [];
  double? _restLightIntensity;

  /// The current flash value, `0` to `1`. This is what the sky reads.
  double get flash => _flashEnvelope(_flashAge) * _flashPeak;

  /// Seconds until the next scheduled strike.
  double get untilNextStrike => _untilNext;

  /// The strike currently flashing, or null between them.
  LightningStrike? get currentStrike => _current;

  /// Fires a strike now, ahead of the schedule.
  ///
  /// For a scripted moment: the bolt that hits the tower on cue. The schedule
  /// carries on from here.
  LightningStrike strike({double? distance}) {
    final at =
        distance ??
        minDistance + _random.nextDouble() * (maxDistance - minDistance);
    // Nearer bolts are brighter, on an inverse-square falloff normalized so
    // one at [minDistance] is full.
    final falloff = (minDistance / at) * (minDistance / at);
    final struck = LightningStrike(
      distance: at,
      thunderDelay: at / speedOfSound,
      intensity: falloff.clamp(0.08, 1.0),
    );
    _current = struck;
    _flashAge = 0;
    _flashPeak = struck.intensity;
    _pendingThunder.add((at: struck.thunderDelay, strike: struck));
    onStrike?.call(struck);
    _scheduleNext();
    return struck;
  }

  void _scheduleNext() {
    _untilNext =
        minInterval + _random.nextDouble() * (maxInterval - minInterval);
  }

  /// The flash envelope over [age] seconds: three return strokes of falling
  /// brightness inside [flashDuration], then dark.
  ///
  /// A single ramp reads as a camera flash. The strokes are what make it read
  /// as lightning.
  double _flashEnvelope(double age) {
    if (age < 0 || age >= flashDuration) return 0;
    final t = age / flashDuration;
    // Three strokes at 0, 0.22, and 0.55 of the envelope, each a fast attack
    // and a slower decay, under an overall fade.
    var value = 0.0;
    for (final stroke in const [
      (at: 0.0, weight: 1.0),
      (at: 0.22, weight: 0.55),
      (at: 0.55, weight: 0.3),
    ]) {
      final since = t - stroke.at;
      if (since < 0) continue;
      value = math.max(value, stroke.weight * math.exp(-since * 26));
    }
    return value * (1 - t * t);
  }

  @override
  void onMount() {
    sky ??= _sceneSky();
    light ??= _ownLight();
  }

  /// A directional light on this node, which is what a strike flashes.
  DirectionalLight? _ownLight() {
    if (!isAttached) return null;
    return node.getComponent<DirectionalLightComponent>()?.light;
  }

  /// Whether the storm has said, once, that it has nothing to flash.
  bool _warnedAboutNothingToFlash = false;

  /// The scene's skybox, when it is a weather sky.
  WeatherSkySource? _sceneSky() {
    if (!isAttached) return null;
    final owner = node.internalRenderScene?.owner;
    if (owner is! Scene) return null;
    final source = owner.skybox?.source;
    return source is WeatherSkySource ? source : null;
  }

  @override
  void update(double deltaSeconds) {
    if (deltaSeconds <= 0) return;
    // A sky or a light assigned after mount (the editor swapping the stage's
    // skybox under a live scene, or a light added to the node) is picked up on
    // the next tick rather than never.
    sky ??= _sceneSky();
    light ??= _ownLight();

    // A storm with neither is a storm nobody can see: it goes on scheduling
    // strikes and calling back for thunder, and nothing on screen moves. Said
    // once, because it is a setup mistake rather than a per-frame one.
    if (sky == null && light == null && !_warnedAboutNothingToFlash) {
      _warnedAboutNothingToFlash = true;
      debugPrint(
        'flutter_scene: a lightning component has nothing to flash. Give the '
        'scene a weather sky for the clouds to light up, or put a directional '
        "light on the storm's own node for the flash.",
      );
    }

    final target = sky;
    if (target != null) {
      target
        ..stormDarkening = stormDarkening
        ..advance(deltaSeconds);
    }

    _untilNext -= deltaSeconds;
    if (_untilNext <= 0) strike();

    if (_flashAge < flashDuration) _flashAge += deltaSeconds;
    final value = flash;
    target?.flash = value;

    final flashed = light;
    if (flashed != null) {
      _restLightIntensity ??= flashed.intensity;
      flashed.intensity = _restLightIntensity! + lightIntensity * value;
    }

    if (_pendingThunder.isNotEmpty) {
      for (var i = _pendingThunder.length - 1; i >= 0; i--) {
        final pending = _pendingThunder[i];
        final remaining = pending.at - deltaSeconds;
        if (remaining <= 0) {
          _pendingThunder.removeAt(i);
          onThunder?.call(pending.strike);
        } else {
          _pendingThunder[i] = (at: remaining, strike: pending.strike);
        }
      }
    }
  }

  @override
  void onUnmount() {
    // Leave the sky and the light as they were: a component removed mid-flash
    // must not strand a white sky.
    sky
      ?..flash = 0
      ..stormDarkening = 0;
    final rest = _restLightIntensity;
    if (rest != null) light?.intensity = rest;
    _restLightIntensity = null;
    _pendingThunder.clear();
  }

  @override
  Component? cloneFor(Node cloneOwner) => LightningComponent(
    sky: sky,
    light: light,
    minInterval: minInterval,
    maxInterval: maxInterval,
    minDistance: minDistance,
    maxDistance: maxDistance,
    speedOfSound: speedOfSound,
    flashDuration: flashDuration,
    lightIntensity: lightIntensity,
    stormDarkening: stormDarkening,
    onThunder: onThunder,
    onStrike: onStrike,
  );
}

/// A [vm.Vector3] sun direction from a time of day and a latitude, so a sky
/// can be driven by a clock rather than by a vector.
///
/// [hour] is on a 24-hour clock; noon puts the sun at its highest. [tilt]
/// leans the arc away from straight overhead, which is what makes a winter
/// noon low and a tropical one vertical.
/// {@category Lighting and environment}
vm.Vector3 sunDirectionForHour(double hour, {double tilt = 0.35}) {
  // Midnight is straight down, noon straight up, with the arc swung through
  // east and west.
  final angle = (hour / 24) * 2 * math.pi - math.pi / 2;
  return vm.Vector3(
    math.cos(angle),
    math.sin(angle),
    math.sin(tilt) * math.cos(angle * 0.5),
  )..normalize();
}
