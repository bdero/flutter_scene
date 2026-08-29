/// Weather as one named thing, rather than five cloud numbers.
///
/// "Overcast" is a coverage, a density, a softness, a turbidity and a storm
/// darkening, and nobody holds the five of them in their head. Naming the
/// combination is what lets weather be set from a menu, from a script, or
/// from a graph, and be the same weather in all three.
///
/// A preset also says what falls out of the sky it describes, by naming the
/// VFX preset for it and whether it carries lightning. It does not spawn
/// those itself -- an emitter is a node in a scene, which is the caller's to
/// place -- but it means the rain that comes with "Rain" is the same rain
/// whoever asked for it.
library;

import 'package:flutter_scene/src/kit/environment/water_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_sources.dart';

/// One named weather state: what the sky does, and what comes out of it.
/// {@category Gameplay kit}
class WeatherPreset {
  const WeatherPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.coverage,
    required this.stormDarkening,
    required this.turbidity,
    this.softness = 0.12,
    this.density = 0.95,
    this.effect,
    this.lightning = false,
    this.choppiness = 1.0,
  });

  /// A stable id, which is what a document, a script or a graph names.
  final String id;

  /// The name shown to a person.
  final String name;

  /// What the weather is, in a line.
  final String description;

  /// How much of the sky the clouds take, `0` clear to `1` overcast.
  final double coverage;

  /// How much the storm drains the light out of the sky.
  final double stormDarkening;

  /// Aerosol density: how hazy the air reads.
  final double turbidity;

  /// How soft the cloud edges are.
  final double softness;

  /// How opaque the clouds are where they are thickest.
  final double density;

  /// The VFX preset that falls out of this sky, or null when the weather is
  /// nothing but sky. Resolve it with `vfxPresetById`.
  final String? effect;

  /// Whether this weather carries lightning, which is a
  /// [LightningComponent] driving the sky's flash and the thunder after it.
  final bool lightning;

  /// How hard the water runs under this weather: `0` glassy, `1` the waves as
  /// authored, above that a sea getting up.
  ///
  /// Water that stays glassy through a thunderstorm is the thing that gives
  /// a weather system away, and the two are the same weather, so the state
  /// carries both rather than leaving the sea to be remembered separately.
  final double choppiness;

  /// Puts [sky] into this weather. The sun is left where it is: what time it
  /// is and what the weather is doing are two different questions.
  void applyTo(WeatherSkySource sky) {
    sky
      ..coverage = coverage
      ..density = density
      ..softness = softness
      ..turbidity = turbidity
      ..stormDarkening = stormDarkening;
  }
}

/// The shipped weather states, driest first.
/// {@category Gameplay kit}
const List<WeatherPreset> weatherPresets = [
  WeatherPreset(
    id: 'clear',
    name: 'Clear',
    description: 'Open sky, a few high wisps.',
    coverage: 0.12,
    stormDarkening: 0,
    turbidity: 6,
    softness: 0.2,
    density: 0.7,
    choppiness: 0.45,
  ),
  WeatherPreset(
    id: 'fair',
    name: 'Fair',
    description: 'Scattered cloud with clear gaps.',
    coverage: 0.45,
    stormDarkening: 0,
    turbidity: 10,
    choppiness: 0.8,
  ),
  WeatherPreset(
    id: 'overcast',
    name: 'Overcast',
    description: 'A solid deck and flat, grey light.',
    coverage: 0.92,
    stormDarkening: 0.45,
    turbidity: 14,
    softness: 0.28,
    choppiness: 1.0,
  ),
  WeatherPreset(
    id: 'fog',
    name: 'Fog',
    description: 'Low cloud, plus drifting ground fog.',
    coverage: 0.7,
    stormDarkening: 0.3,
    turbidity: 18,
    softness: 0.35,
    effect: 'groundFog',
    choppiness: 0.5,
  ),
  WeatherPreset(
    id: 'rain',
    name: 'Rain',
    description: 'Heavy cloud and falling rain.',
    coverage: 0.95,
    stormDarkening: 0.55,
    turbidity: 16,
    softness: 0.3,
    effect: 'rain',
    choppiness: 1.5,
  ),
  WeatherPreset(
    id: 'storm',
    name: 'Thunderstorm',
    description: 'Rain, gloom, and lightning with its thunder.',
    coverage: 1.0,
    stormDarkening: 0.8,
    turbidity: 18,
    softness: 0.22,
    effect: 'rain',
    lightning: true,
    choppiness: 2.2,
  ),
  WeatherPreset(
    id: 'snow',
    name: 'Snow',
    description: 'Flat white cloud and drifting flakes.',
    coverage: 0.9,
    stormDarkening: 0.35,
    turbidity: 8,
    softness: 0.34,
    effect: 'snow',
    choppiness: 0.7,
  ),
];

/// The preset with [id], or null when nothing matches.
/// {@category Gameplay kit}
WeatherPreset? weatherPresetById(String id) {
  for (final preset in weatherPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// Puts [scene]'s sky into [preset], and its water with it.
///
/// Returns false when the scene's skybox is not a [WeatherSkySource], which
/// is the one sky that has clouds to change: there is no weather to set on a
/// gradient. The water is raised or calmed either way -- a sea that stays
/// glassy through a thunderstorm is the thing that gives a weather system
/// away, and it is the same weather.
///
/// Emitters are left alone: an effect already raining goes on raining, since
/// spawning and removing nodes is the caller's to decide.
/// {@category Gameplay kit}
bool setSceneWeather(Scene scene, WeatherPreset preset) {
  setWaterChoppiness(scene.root, preset.choppiness);
  final source = scene.skybox?.source;
  if (source is! WeatherSkySource) return false;
  preset.applyTo(source);
  return true;
}

/// Sets [choppiness] on every water surface under [root].
///
/// Returns how many it found, so a caller can tell "the weather changed and
/// there is no water" from "the weather changed and the water ignored it".
/// {@category Gameplay kit}
int setWaterChoppiness(Node root, double choppiness) {
  var found = 0;
  void visit(Node node) {
    final water = node.getComponent<WaterComponent>();
    if (water != null) {
      water.choppiness = choppiness;
      found++;
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(root);
  return found;
}
