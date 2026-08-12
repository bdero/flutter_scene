// Covers the UI-facing codecs and registries: the widget slot registry
// (register/lookup/reset), widget component realize+serialize through a
// named slot (missing slots skip the component; hand-built components do
// not serialize), semantics data round-trips including the properties-mode
// bare spec, and the audio engine backend registry wired through a fake
// engine. GPU-free throughout; components are created but never mounted.

import 'dart:typed_data';

import 'package:flutter/semantics.dart' show SemanticsProperties;
import 'package:flutter/widgets.dart' show Size, SizedBox, Text, TextDirection;
import 'package:flutter_scene/src/audio/audio_bus.dart';
import 'package:flutter_scene/src/audio/audio_clip.dart';
import 'package:flutter_scene/src/audio/audio_engine.dart';
import 'package:flutter_scene/src/audio/audio_voice.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/semantics_component.dart';
import 'package:flutter_scene/src/components/widget_component.dart';
import 'package:flutter_scene/src/fscene/realize/audio_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/ui_codecs.dart';
import 'package:flutter_scene/src/widget_texture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart' show propertyValuesEqual;
import 'package:vector_math/vector_math.dart';

class _FakeBus implements AudioBus {
  _FakeBus(this.name);

  @override
  final String name;

  @override
  AudioBus? get parent => null;

  @override
  double volume = 1.0;
}

class _FakeAudioEngine extends AudioEngine {
  _FakeAudioEngine(this.config);

  final Map<String, PropertyValue> config;
  final _FakeBus _master = _FakeBus('master');

  @override
  String get backendName => 'fake';

  @override
  AudioBus get masterBus => _master;

  @override
  AudioBus onCreateBus(String name, AudioBus parent) => _FakeBus(name);

  @override
  Future<AudioClip> loadClip(String assetKey) => throw UnimplementedError();

  @override
  Future<AudioClip> loadClipFromBytes(String key, Uint8List bytes) =>
      throw UnimplementedError();

  @override
  AudioVoice createVoice(AudioClip clip) => throw UnimplementedError();

  @override
  void onSyncListener(
    Vector3 position,
    Vector3 forward,
    Vector3 up,
    Vector3 velocity,
  ) {}
}

Map<String, PropertyValue> _serialized(
  ComponentCodec codec,
  Component component,
) {
  final spec = codec.serialize(component, SerializeContext(SceneDocument()));
  expect(spec, isNotNull);
  return spec!.properties;
}

void main() {
  group('widget slot registry', () {
    tearDown(debugResetWidgetSlots);

    test('register, look up, and reset', () {
      expect(widgetSlotBuilder('hud'), isNull);
      registerWidgetSlot('hud', () => const SizedBox());
      expect(widgetSlotBuilder('hud'), isNotNull);
      registerWidgetSlot('hud', () => const Text('x'));
      expect(widgetSlotBuilder('hud')!(), isA<Text>());
      debugResetWidgetSlots();
      expect(widgetSlotBuilder('hud'), isNull);
    });
  });

  group('WidgetCodec', () {
    final codec = WidgetCodec();
    tearDown(debugResetWidgetSlots);

    test('a missing slot skips the component (the scene still loads)', () {
      final spec = ComponentSpec(
        'widget',
        properties: {'slot': const StringValue('unregistered')},
      );
      expect(codec.realize(spec, RealizeContext(SceneDocument())), isNull);
    });

    test('a registered slot realizes and the name round-trips', () {
      registerWidgetSlot('hud', () => const SizedBox(width: 8));
      final spec = ComponentSpec(
        'widget',
        properties: {'slot': const StringValue('hud')},
      );
      final component =
          codec.realize(spec, RealizeContext(SceneDocument()))
              as WidgetComponent;
      expect(component.child, isA<SizedBox>());
      expect(component.size.width, 256);
      expect(component.pixelRatio, 1.0);
      expect(component.worldHeight, 1.0);
      expect(component.updatePolicy, WidgetUpdatePolicy.everyFrame);
      expect(component.input, WidgetInput.automatic);
      expect(component.occlusionHiding, isFalse);

      // All defaults serialize to the slot alone (delta persistence).
      expect(_serialized(codec, component).keys, ['slot']);
    });

    test('configured values round trip, including the interval policy', () {
      registerWidgetSlot('panel', () => const SizedBox());
      final spec = ComponentSpec(
        'widget',
        properties: {
          'slot': const StringValue('panel'),
          'size': Vec2Value(Vector2(200, 100)),
          'pixelRatio': const DoubleValue(2.0),
          'worldHeight': const DoubleValue(3.0),
          'updatePolicy': MapValue({
            'kind': const StringValue('interval'),
            'milliseconds': const IntValue(250),
          }),
          'input': const StringValue('manual'),
          'occlusionHiding': const BoolValue(true),
        },
      );
      final component =
          codec.realize(spec, RealizeContext(SceneDocument()))
              as WidgetComponent;
      expect(component.size.width, 200);
      expect(component.size.height, 100);
      expect(component.pixelRatio, 2.0);
      expect(component.worldHeight, 3.0);
      expect(
        component.updatePolicy.interval,
        const Duration(milliseconds: 250),
      );
      expect(component.input, WidgetInput.manual);
      expect(component.occlusionHiding, isTrue);

      final props = _serialized(codec, component);
      expect(props.keys.toSet(), spec.properties.keys.toSet());
      for (final key in spec.properties.keys) {
        expect(
          propertyValuesEqual(props[key], spec.properties[key]),
          isTrue,
          reason: '$key did not round-trip',
        );
      }
    });

    test('the manual policy round-trips', () {
      registerWidgetSlot('panel', () => const SizedBox());
      final spec = ComponentSpec(
        'widget',
        properties: {
          'slot': const StringValue('panel'),
          'updatePolicy': MapValue({'kind': const StringValue('manual')}),
        },
      );
      final component =
          codec.realize(spec, RealizeContext(SceneDocument()))
              as WidgetComponent;
      expect(component.updatePolicy, WidgetUpdatePolicy.manual);
      final props = _serialized(codec, component);
      final policy = (props['updatePolicy']! as MapValue).values;
      expect((policy['kind']! as StringValue).value, 'manual');
    });

    test(
      'a hand-built widget component (no slot stamp) does not serialize',
      () {
        final component = WidgetComponent(
          child: const SizedBox(),
          size: const Size(10, 10),
        );
        expect(
          codec.serialize(component, SerializeContext(SceneDocument())),
          isNull,
        );
      },
    );
  });

  group('SemanticsCodec', () {
    final codec = SemanticsCodec();

    test('an empty spec realizes the defaults and serializes empty', () {
      final component =
          codec.realize(
                ComponentSpec('semantics'),
                RealizeContext(SceneDocument()),
              )
              as SemanticsComponent;
      expect(component.label, isNull);
      expect(component.button, isFalse);
      expect(component.sortOrder, isNull);
      expect(component.textDirection, isNull);
      expect(component.occlusionHiding, isFalse);
      expect(_serialized(codec, component), isEmpty);
    });

    test('data fields round trip', () {
      final spec = ComponentSpec(
        'semantics',
        properties: {
          'label': const StringValue('Power switch'),
          'value': const StringValue('On'),
          'hint': const StringValue('Toggles the power'),
          'button': const BoolValue(true),
          'sortOrder': const DoubleValue(2.0),
          'textDirection': const StringValue('rtl'),
          'occlusionHiding': const BoolValue(true),
        },
      );
      final component =
          codec.realize(spec, RealizeContext(SceneDocument()))
              as SemanticsComponent;
      expect(component.label, 'Power switch');
      expect(component.value, 'On');
      expect(component.hint, 'Toggles the power');
      expect(component.button, isTrue);
      expect(component.sortOrder, 2.0);
      expect(component.textDirection, TextDirection.rtl);
      expect(component.occlusionHiding, isTrue);

      final props = _serialized(codec, component);
      expect(props.keys.toSet(), spec.properties.keys.toSet());
      for (final key in spec.properties.keys) {
        expect(
          propertyValuesEqual(props[key], spec.properties[key]),
          isTrue,
          reason: '$key did not round-trip',
        );
      }
    });

    test('properties mode serializes as a bare spec', () {
      final component = SemanticsComponent(
        properties: const SemanticsProperties(label: 'Dial'),
      );
      final spec = codec.serialize(
        component,
        SerializeContext(SceneDocument()),
      );
      expect(spec, isNotNull);
      expect(spec!.type, 'semantics');
      expect(spec.properties, isEmpty);
    });
  });

  group('audio engine backend registry', () {
    test('register and look up', () {
      expect(audioEngineBackendFactory('never-registered'), isNull);
      registerAudioEngineBackend('test-probe', _FakeAudioEngine.new);
      expect(audioEngineBackendFactory('test-probe'), isNotNull);
    });
  });

  group('AudioEngineCodec', () {
    final codec = AudioEngineCodec();

    test('an unregistered backend skips the component', () {
      final spec = ComponentSpec(
        'audioEngine',
        properties: {'backend': const StringValue('not-a-backend')},
      );
      expect(codec.realize(spec, RealizeContext(SceneDocument())), isNull);
    });

    test('a missing backend id skips the component', () {
      expect(
        codec.realize(
          ComponentSpec('audioEngine'),
          RealizeContext(SceneDocument()),
        ),
        isNull,
      );
    });

    test('the factory receives the config and everything round-trips', () {
      registerAudioEngineBackend('test-fake', _FakeAudioEngine.new);
      final spec = ComponentSpec(
        'audioEngine',
        properties: {
          'backend': const StringValue('test-fake'),
          'masterVolume': const DoubleValue(0.5),
          'config': MapValue({
            'maxChannels': const IntValue(64),
            'liveUpdate': const BoolValue(true),
          }),
        },
      );
      final engine =
          codec.realize(spec, RealizeContext(SceneDocument()))
              as _FakeAudioEngine;
      expect((engine.config['maxChannels']! as IntValue).value, 64);
      expect((engine.config['liveUpdate']! as BoolValue).value, isTrue);
      expect(engine.masterVolume, 0.5);

      final props = _serialized(codec, engine);
      expect(props.keys.toSet(), spec.properties.keys.toSet());
      for (final key in spec.properties.keys) {
        expect(
          propertyValuesEqual(props[key], spec.properties[key]),
          isTrue,
          reason: '$key did not round-trip',
        );
      }
    });

    test('a default-volume engine serializes only its backend id', () {
      registerAudioEngineBackend('test-fake', _FakeAudioEngine.new);
      final engine = codec.realize(
        ComponentSpec(
          'audioEngine',
          properties: {'backend': const StringValue('test-fake')},
        ),
        RealizeContext(SceneDocument()),
      )!;
      expect(_serialized(codec, engine).keys, ['backend']);
    });

    test('a hand-built engine serializes its self-reported name', () {
      final engine = _FakeAudioEngine(const {});
      final props = _serialized(codec, engine);
      expect((props['backend']! as StringValue).value, 'fake');
      expect(props.containsKey('config'), isFalse);
    });
  });
}
