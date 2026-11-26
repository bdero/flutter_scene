// ignore_for_file: implementation_imports
// Covers the contact shadow pass's CPU side: the ContactShadowInfo layout
// flutter_scene_contact_shadows.frag reads, and the step counts each quality
// tier resolves to.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/contact_shadow_channels.dart';
import 'package:flutter_scene/src/render/contact_shadow_pass.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/render/shadow_caster_selection.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

PointLightComponent _point(Vector3 at, {bool contact = true}) {
  final component = PointLightComponent(
    PointLight(range: 1.0, contactShadows: contact),
  );
  Node(localTransform: Matrix4.translation(at)).addComponent(component);
  return component;
}

void main() {
  test('steps resolve from the tier unless set', () {
    final settings = ContactShadowSettings();
    expect(settings.stepsFor(RenderQualityTier.high), 16);
    expect(settings.stepsFor(RenderQualityTier.medium), 8);
    expect(settings.stepsFor(RenderQualityTier.low), 8);
    settings.sampleCount = 40;
    expect(settings.stepsFor(RenderQualityTier.low), 16);
    settings.sampleCount = 1;
    expect(settings.stepsFor(RenderQualityTier.high), 2);
  });

  test('ContactShadowInfo packs the block the shader declares', () {
    final settings = ContactShadowSettings()
      ..thickness = 0.2
      ..maxDistance = 40.0
      ..fadeRange = 4.0
      ..opacity = 0.5;
    const projection = ProjectionParams(
      scaleX: 0.75,
      scaleY: 0.5,
      near: 0.1,
      far: 100.0,
      offsetX: 0.25,
      offsetY: -0.125,
      orthographic: false,
    );
    final info = ContactShadowPass.packInfo(
      width: 200,
      height: 100,
      projection: projection,
      settings: settings,
      steps: 12,
      channels: [
        ContactShadowLight.directional(Vector3(0, 2, 0), 0.3),
        null,
        ContactShadowLight(
          type: ContactShadowLightType.spot,
          vector: Vector3(1, 2, 3),
          distance: 0.5,
          inverseRange: 0.25,
          outerConeCos: 0.75,
          axis: Vector3(0, 0, 1),
        ),
      ],
      temporalNoiseFrame: 19,
      packDepth: true,
    );
    expect(info, hasLength(72));
    // viewport, proj, proj_offset, depth_uv, settings, march.
    expect(info.sublist(0, 24), [
      200, 100, closeTo(1 / 200, 1e-9), closeTo(1 / 100, 1e-9), //
      0.75, 0.5, closeTo(0.1, 1e-7), 100, //
      0.25, -0.125, 0, 3, //
      1, 1, 0, 0, //
      closeTo(0.2, 1e-7), 40, 4, 0.5, //
      12, 1, 0, 0, //
    ]);
    // light_vector[4]: direction normalized, type 1 directional, 3 spot.
    expect(info.sublist(24, 40), [
      0, 1, 0, 1, //
      0, 0, 0, 0, //
      1, 2, 3, 3, //
      0, 0, 0, 0, //
    ]);
    // light_params[4].
    expect(info.sublist(40, 56), [
      closeTo(0.3, 1e-7), 0, -1, 0, //
      0, 0, 0, 0, //
      0.5, 0.25, 0.75, 0, //
      0, 0, 0, 0, //
    ]);
    // light_axis[4].
    expect(info.sublist(56, 72), [
      0, 0, 0, 0, //
      0, 0, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 0, //
    ]);
  });

  group('channels', () {
    final views = ShadowViewVolumes(eyes: [Vector3.zero()]);

    test('the three largest on screen win', () {
      final near = _point(Vector3(0, 0, -2));
      final mid = _point(Vector3(0, 0, -4));
      final far = _point(Vector3(0, 0, -8));
      final farthest = _point(Vector3(0, 0, -16));
      final off = _point(Vector3(0, 0, -1), contact: false);
      final channels = ContactShadowChannels()
        ..update(
          directionals: const [],
          primary: null,
          points: [farthest, off, far, mid, near],
          spots: const [],
          views: views,
        );
      expect(channels.channelOf(farthest), 0);
      expect(channels.channelOf(off), 0);
      expect(
        {
          channels.channelOf(near),
          channels.channelOf(mid),
          channels.channelOf(far),
        },
        {1, 2, 3},
      );
    });

    test('a holder keeps its channel while others come and go', () {
      final a = _point(Vector3(0, 0, -2));
      final b = _point(Vector3(0, 0, -3));
      final c = _point(Vector3(0, 0, -4));
      final channels = ContactShadowChannels();
      void update(List<PointLightComponent> points) => channels.update(
        directionals: const [],
        primary: null,
        points: points,
        spots: const [],
        views: views,
      );
      update([a, b]);
      final channelOfB = channels.channelOf(b);
      update([b, c]);
      expect(channels.channelOf(a), 0);
      expect(channels.channelOf(b), channelOfB);
      expect(channels.channelOf(c), isNot(0));
      expect(channels.channelOf(c), isNot(channelOfB));
    });

    test('the primary directional light is not a candidate', () {
      final sun = DirectionalLightComponent(
        DirectionalLight(contactShadows: true),
      );
      final other = DirectionalLightComponent(
        DirectionalLight(contactShadows: true),
      );
      Node().addComponent(sun);
      Node().addComponent(other);
      final channels = ContactShadowChannels()
        ..update(
          directionals: [sun, other],
          primary: sun,
          points: const [],
          spots: const [],
          views: views,
        );
      expect(channels.channelOf(sun), 0);
      expect(channels.channelOf(other), 1);
    });

    test('light rows carry their channel in texel 10', () {
      final a = _point(Vector3(0, 0, -2));
      final b = _point(Vector3(0, 0, -3));
      final (params, count) = PunctualLightBuffer.packLights(
        directionals: const [],
        points: [a, b],
        spots: const [],
        contactChannelOf: (light) => identical(light, b) ? 3 : 0,
      );
      expect(count, 2);
      expect(params[40], 0.0);
      expect(params[48 + 40], 3.0);
    });
  });
}
