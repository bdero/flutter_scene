// What a storm actually drives. A LightningComponent computes a flash whether
// or not anything is listening, so the failure mode is silence: strikes fire,
// thunder callbacks run, and nothing on screen moves.

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A storm that strikes on the first tick.
LightningComponent _eager({double lightIntensity = 12}) => LightningComponent(
  minInterval: 0.01,
  maxInterval: 0.01,
  minDistance: 100,
  maxDistance: 100,
  lightIntensity: lightIntensity,
);

void main() {
  test('a light on the storm node is adopted, and flashed', () {
    // The authoring gesture: the light and the storm on one node. A document
    // cannot reference a live light, so this is how the two are associated.
    final node = Node(name: 'Storm');
    final light = DirectionalLight(intensity: 1);
    node.addComponent(
      DirectionalLightComponent.aimed(light, Vector3(0, -1, 0)),
    );
    final storm = _eager();
    node.addComponent(storm);
    storm.onMount();

    expect(storm.light, same(light), reason: 'the light was not adopted');
    storm.update(0.02);
    expect(
      light.intensity,
      greaterThan(1),
      reason: 'a strike did not brighten the light it adopted',
    );
  });

  test('a light added after mount is picked up on the next tick', () {
    final node = Node(name: 'Storm');
    final storm = _eager();
    node.addComponent(storm);
    storm.onMount();
    expect(storm.light, isNull);

    final light = DirectionalLight(intensity: 1);
    node.addComponent(
      DirectionalLightComponent.aimed(light, Vector3(0, -1, 0)),
    );
    storm.update(0.02);
    expect(storm.light, same(light));
  });

  test('an explicit light is never replaced by one found on the node', () {
    final node = Node(name: 'Storm');
    final chosen = DirectionalLight(intensity: 1);
    final other = DirectionalLight(intensity: 1);
    node.addComponent(
      DirectionalLightComponent.aimed(other, Vector3(0, -1, 0)),
    );
    final storm = LightningComponent(light: chosen, minInterval: 0.01);
    node.addComponent(storm);
    storm.onMount();
    expect(storm.light, same(chosen));
  });

  test('a storm with nothing to flash says so, once', () {
    // The reported bug: add a Lightning object to a scene with an ordinary
    // sky and no light, and nothing whatsoever happens.
    final messages = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = previous);

    final storm = _eager();
    Node(name: 'Storm').addComponent(storm);
    storm.onMount();
    for (var i = 0; i < 5; i++) {
      storm.update(0.02);
    }

    expect(messages, hasLength(1), reason: 'said nothing, or said it a lot');
    expect(messages.single, contains('nothing to flash'));
  });

  test('a storm that drives something stays quiet', () {
    final messages = <String?>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = previous);

    final storm = LightningComponent(
      sky: WeatherSkySource(),
      minInterval: 0.01,
    );
    Node(name: 'Storm').addComponent(storm);
    storm.onMount();
    for (var i = 0; i < 5; i++) {
      storm.update(0.02);
    }
    expect(messages, isEmpty);
  });

  test('unmounting restores the light it borrowed', () {
    final node = Node(name: 'Storm');
    final light = DirectionalLight(intensity: 2);
    node.addComponent(
      DirectionalLightComponent.aimed(light, Vector3(0, -1, 0)),
    );
    final storm = _eager();
    node.addComponent(storm);
    storm.onMount();
    storm.update(0.02);
    expect(light.intensity, greaterThan(2));
    storm.onUnmount();
    expect(light.intensity, 2);
  });
}
