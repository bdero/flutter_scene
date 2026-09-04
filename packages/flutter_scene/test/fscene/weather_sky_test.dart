// The weather sky's document round trip: a cloud layer and its storm controls
// survive JSON, and the transient parts of a storm do not get saved into it.

import 'package:flutter_scene/fscene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

WeatherSkySpec? skyOf(SceneDocument doc) {
  final ref = doc.stage.environmentRef;
  final resource = ref == null ? null : doc.resource(ref);
  final source = resource is EnvironmentResource
      ? resource.skybox?.source
      : null;
  return source is WeatherSkySpec ? source : null;
}

SceneDocument documentWithWeather(WeatherSkySpec sky) {
  final doc = SceneDocument();
  final env = doc.addResource(
    EnvironmentResource(doc.newId(), name: 'Environment')
      ..skybox = SkyboxSpec(sky),
  );
  doc.stage.environmentRef = env.id;
  return doc;
}

void main() {
  test('the defaults are a partly cloudy, un-stormy day', () {
    final sky = WeatherSkySpec();
    expect(sky.coverage, greaterThan(0), reason: 'some cloud out of the box');
    expect(sky.coverage, lessThan(1), reason: 'not overcast');
    expect(sky.stormDarkening, 0);
    expect(sky.wind.length, greaterThan(0), reason: 'clouds drift by default');
  });

  test('every cloud and storm field round-trips through JSON', () {
    final doc = documentWithWeather(
      WeatherSkySpec(
        sunDirection: Vector3(0.1, 0.9, 0.2),
        coverage: 0.82,
        density: 0.6,
        altitude: 2.4,
        detail: 0.9,
        softness: 0.04,
        seed: 4242,
        wind: Vector2(-1.5, 0.75),
        cloudColor: Vector3(0.9, 0.85, 0.95),
        cloudShading: 0.33,
        stormDarkening: 0.7,
        turbidity: 14,
        energy: 1.4,
      ),
    );

    final restored = readFscene(writeFscene(doc));
    final sky = skyOf(restored);
    expect(sky, isNotNull, reason: 'decoded as a weather sky, not a fallback');
    expect(sky!.coverage, closeTo(0.82, 1e-6));
    expect(sky.density, closeTo(0.6, 1e-6));
    expect(sky.altitude, closeTo(2.4, 1e-6));
    expect(sky.detail, closeTo(0.9, 1e-6));
    expect(sky.softness, closeTo(0.04, 1e-6));
    expect(sky.seed, 4242);
    expect(sky.wind.x, closeTo(-1.5, 1e-6));
    expect(sky.wind.y, closeTo(0.75, 1e-6));
    expect(sky.cloudColor.y, closeTo(0.85, 1e-6));
    expect(sky.cloudShading, closeTo(0.33, 1e-6));
    expect(sky.stormDarkening, closeTo(0.7, 1e-6));
    expect(sky.turbidity, closeTo(14, 1e-6));
    expect(sky.energy, closeTo(1.4, 1e-6));
    expect(sky.sunDirection.y, closeTo(0.9, 1e-6));
  });

  test('the encoded form names itself, so an older reader can tell', () {
    final json = writeFscene(documentWithWeather(WeatherSkySpec()));
    expect(json, contains('"type": "weather"'));
  });

  test('a second round trip is byte-identical', () {
    final doc = documentWithWeather(WeatherSkySpec(coverage: 0.31, seed: 7));
    final once = writeFscene(doc);
    expect(writeFscene(readFscene(once)), once);
  });
}
