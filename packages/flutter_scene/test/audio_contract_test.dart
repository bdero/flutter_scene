// Contract-level audio tests against a fake backend: engine discovery,
// listener resolution and pose math, velocity derivation, clip-source
// playback lifecycle, buses, and the fscene codec round-trip.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/realize/audio_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class FakeClip implements AudioClip {
  FakeClip(this.assetKey);
  final String assetKey;

  @override
  Duration? get duration => const Duration(seconds: 1);

  bool disposed = false;

  @override
  bool get isDisposed => disposed;

  @override
  void dispose() => disposed = true;
}

class FakeBus implements AudioBus {
  FakeBus(this.name, this.parent);

  @override
  final String name;

  @override
  final AudioBus? parent;

  @override
  double volume = 1.0;
}

class FakeVoice implements AudioVoice {
  FakeVoice(this.clip);
  final FakeClip clip;

  bool started = false;
  bool stopped = false;
  bool paused = false;
  bool finished = false;
  AudioBus? routedBus;
  bool? positionalMode;
  final List<Vector3> positions = [];
  final List<Vector3> velocities = [];
  AudioAttenuation? lastAttenuation;

  @override
  bool get isPlaying => started && !stopped && !finished;

  @override
  bool get isPaused => paused || !started;

  @override
  void start() => started = true;

  @override
  void pause() => paused = true;

  @override
  void resume() => paused = false;

  @override
  void stop() => stopped = true;

  @override
  double volume = 1.0;

  @override
  double pitch = 1.0;

  bool looping = false;

  @override
  void setBus(AudioBus? bus) => routedBus = bus;

  @override
  void setPositional(bool positional) => positionalMode = positional;

  @override
  void update3d(
    Vector3 position,
    Vector3 velocity,
    AudioAttenuation attenuation,
  ) {
    positions.add(position.clone());
    velocities.add(velocity.clone());
    lastAttenuation = attenuation;
  }
}

class FakeAudioEngine extends AudioEngine {
  final FakeBus master = FakeBus('master', null);
  final List<FakeVoice> voices = [];
  final List<String> loadedAssets = [];
  Vector3? listenerPosition;
  Vector3? listenerForward;
  Vector3? listenerUp;
  Vector3? listenerVelocity;
  int commits = 0;

  @override
  String get backendName => 'fake';

  @override
  AudioBus get masterBus => master;

  @override
  AudioBus onCreateBus(String name, AudioBus parent) => FakeBus(name, parent);

  @override
  Future<AudioClip> loadClip(String assetKey) async {
    loadedAssets.add(assetKey);
    return FakeClip(assetKey);
  }

  @override
  AudioVoice createVoice(AudioClip clip) {
    final voice = FakeVoice(clip as FakeClip);
    voices.add(voice);
    return voice;
  }

  @override
  void onSyncListener(
    Vector3 position,
    Vector3 forward,
    Vector3 up,
    Vector3 velocity,
  ) {
    listenerPosition = position.clone();
    listenerForward = forward.clone();
    listenerUp = up.clone();
    listenerVelocity = velocity.clone();
  }

  @override
  void onFrameCommit(double deltaSeconds) => commits++;
}

class FakeCamera extends Camera {
  @override
  Vector3 get position => Vector3(1, 2, 3);

  @override
  Vector3 get forward => Vector3(0, 0, 1);

  @override
  Vector3 get up => Vector3(0, 1, 0);

  @override
  CameraProjection get projection => PerspectiveProjection();

  @override
  Matrix4 getViewMatrix() => Matrix4.identity();
}

/// Builds root -> child, mounts an engine on the root, and returns both.
(Node, FakeAudioEngine) engineTree() {
  final root = Node();
  final engine = FakeAudioEngine();
  root.addComponent(engine);
  engine.mount();
  return (root, engine);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('AudioEngine.findAncestor', () {
    test('resolves through ancestors and misses siblings', () {
      final (root, engine) = engineTree();
      final child = Node();
      final grandchild = Node();
      root.add(child);
      child.add(grandchild);
      expect(AudioEngine.findAncestor(grandchild), same(engine));
      expect(AudioEngine.findAncestor(Node()), isNull);
    });
  });

  group('buses', () {
    test('createBus routes into master by default and findBus resolves', () {
      final (_, engine) = engineTree();
      final sfx = engine.createBus('sfx');
      expect(sfx.parent, same(engine.masterBus));
      expect(engine.findBus('sfx'), same(sfx));
      expect(engine.findBus('master'), same(engine.masterBus));
      expect(engine.findBus('missing'), isNull);
      expect(() => engine.createBus('sfx'), throwsArgumentError);
      expect(() => engine.createBus('master'), throwsArgumentError);
    });

    test('masterVolume is the master bus volume', () {
      final (_, engine) = engineTree();
      engine.masterVolume = 0.5;
      expect(engine.master.volume, 0.5);
    });
  });

  group('listener resolution', () {
    test('falls back to the camera when no listener is mounted', () async {
      final (_, engine) = engineTree();
      await pump();
      engine.frameSync(1 / 60, fallbackCamera: FakeCamera());
      expect(engine.listenerPosition, Vector3(1, 2, 3));
      expect(engine.listenerForward, Vector3(0, 0, 1));
      expect(engine.commits, 1);
    });

    test('prefers a mounted AudioListener and derives its pose', () async {
      final (root, engine) = engineTree();
      await pump();
      final earNode = Node();
      root.add(earNode);
      earNode.localTransform = Matrix4.translation(Vector3(5, 0, 0));
      final listener = AudioListener();
      earNode.addComponent(listener);
      listener.mount();

      engine.frameSync(1 / 60, fallbackCamera: FakeCamera());
      expect(engine.listenerPosition, Vector3(5, 0, 0));
      expect(engine.listenerForward!.z, closeTo(1.0, 1e-6));
      expect(engine.listenerUp!.y, closeTo(1.0, 1e-6));

      // Velocity is finite-differenced across frames.
      earNode.localTransform = Matrix4.translation(Vector3(6, 0, 0));
      engine.frameSync(0.5, fallbackCamera: FakeCamera());
      expect(engine.listenerVelocity!.x, closeTo(2.0, 1e-6));

      // Unmounting reverts to the camera fallback.
      listener.unmount();
      engine.frameSync(1 / 60, fallbackCamera: FakeCamera());
      expect(engine.listenerPosition, Vector3(1, 2, 3));
    });

    test('skips sync while the engine is disabled', () {
      final (_, engine) = engineTree();
      engine.enabled = false;
      engine.frameSync(1 / 60, fallbackCamera: FakeCamera());
      expect(engine.commits, 0);
    });
  });

  group('playOneShot', () {
    test('spatializes at a position and starts the voice', () {
      final (_, engine) = engineTree();
      final clip = FakeClip('a');
      final voice =
          engine.playOneShot(clip, position: Vector3(1, 1, 1), volume: 0.5)
              as FakeVoice;
      expect(voice.started, isTrue);
      expect(voice.positionalMode, isTrue);
      expect(voice.positions.single, Vector3(1, 1, 1));
      expect(voice.volume, 0.5);
    });

    test('plays flat without a position', () {
      final (_, engine) = engineTree();
      final voice = engine.playOneShot(FakeClip('a')) as FakeVoice;
      expect(voice.positionalMode, isFalse);
      expect(voice.positions, isEmpty);
    });
  });

  group('ClipAudioSource', () {
    test('loads its asset, honors autoplay, and syncs transforms', () async {
      final (root, engine) = engineTree();
      final soundNode = Node();
      root.add(soundNode);
      soundNode.localTransform = Matrix4.translation(Vector3(0, 0, 9));
      final source = ClipAudioSource(asset: 'sounds/loop.ogg', autoplay: true);
      soundNode.addComponent(source);
      source.mount();
      await pump();

      expect(engine.loadedAssets, ['sounds/loop.ogg']);
      final voice = engine.voices.single;
      expect(voice.started, isTrue);
      expect(source.isPlaying, isTrue);

      source.tick(1 / 60);
      expect(voice.positions.last, Vector3(0, 0, 9));

      soundNode.localTransform = Matrix4.translation(Vector3(0, 0, 10));
      source.tick(0.5);
      expect(voice.velocities.last.z, closeTo(2.0, 1e-6));
    });

    test('play before load is deferred, not dropped', () async {
      final (root, engine) = engineTree();
      final source = ClipAudioSource(asset: 'late.ogg');
      final soundNode = Node();
      root.add(soundNode);
      soundNode.addComponent(source);
      source.play();
      expect(engine.voices, isEmpty);
      source.mount();
      await pump();
      expect(engine.voices, hasLength(1));
    });

    test('pause resumes mid-voice, stop rewinds to a fresh voice', () async {
      final (root, engine) = engineTree();
      final soundNode = Node();
      root.add(soundNode);
      final source = ClipAudioSource(asset: 'a.ogg', autoplay: true);
      soundNode.addComponent(source);
      source.mount();
      await pump();

      final first = engine.voices.single;
      source.pause();
      expect(first.paused, isTrue);
      expect(source.isPlaying, isFalse);
      source.play();
      expect(first.paused, isFalse);
      expect(engine.voices, hasLength(1));

      source.stop();
      expect(first.stopped, isTrue);
      source.play();
      expect(engine.voices, hasLength(2));
    });

    test('a naturally finished voice reads as stopped', () async {
      final (root, engine) = engineTree();
      final soundNode = Node();
      root.add(soundNode);
      final source = ClipAudioSource(asset: 'a.ogg', autoplay: true);
      soundNode.addComponent(source);
      source.mount();
      await pump();

      engine.voices.single.finished = true;
      expect(source.isPlaying, isFalse);
    });

    test(
      'routes through a named bus and applies settings to the voice',
      () async {
        final (root, engine) = engineTree();
        final sfx = engine.createBus('sfx');
        final soundNode = Node();
        root.add(soundNode);
        final source = ClipAudioSource(
          asset: 'a.ogg',
          autoplay: true,
          busName: 'sfx',
          volume: 0.25,
          pitch: 2.0,
          looping: true,
        );
        soundNode.addComponent(source);
        source.mount();
        await pump();

        final voice = engine.voices.single;
        expect(voice.routedBus, same(sfx));
        expect(voice.volume, 0.25);
        expect(voice.pitch, 2.0);
        expect(voice.looping, isTrue);

        source.volume = 0.75;
        expect(voice.volume, 0.75);
      },
    );

    test('unmount stops the voice and detach disposes an owned clip', () async {
      final (root, engine) = engineTree();
      final soundNode = Node();
      root.add(soundNode);
      final source = ClipAudioSource(asset: 'a.ogg', autoplay: true);
      soundNode.addComponent(source);
      source.mount();
      await pump();

      final voice = engine.voices.single;
      final clip = source.clip as FakeClip;
      source.unmount();
      expect(voice.stopped, isTrue);
      soundNode.removeComponent(source);
      expect(clip.disposed, isTrue);
    });
  });

  group('fscene codecs', () {
    test('audioSource realizes from a spec and round-trips', () {
      final registry = FsceneComponentRegistry()
        ..register(AudioSourceCodec())
        ..register(AudioListenerCodec());
      final document = SceneDocument();
      final context = RealizeContext(document);

      final spec = ComponentSpec(
        'audioSource',
        properties: {
          'asset': const StringValue('sounds/fire.ogg'),
          'autoplay': const BoolValue(true),
          'looping': const BoolValue(true),
          'volume': const DoubleValue(0.8),
          'rolloff': const StringValue('linear'),
          'maxDistance': const DoubleValue(42.0),
          'bus': const StringValue('sfx'),
        },
      );

      final component = registry.realize(spec, context) as ClipAudioSource;
      expect(component.asset, 'sounds/fire.ogg');
      expect(component.autoplay, isTrue);
      expect(component.looping, isTrue);
      expect(component.volume, 0.8);
      expect(component.pitch, 1.0);
      expect(component.attenuation.rolloff, AudioRolloff.linear);
      expect(component.attenuation.maxDistance, 42.0);
      expect(component.busName, 'sfx');

      final serialized = registry.serialize(
        component,
        SerializeContext(document),
      )!;
      expect(serialized.type, 'audioSource');
      expect(
        (serialized.properties['asset']! as StringValue).value,
        'sounds/fire.ogg',
      );
      expect(
        (serialized.properties['rolloff']! as StringValue).value,
        'linear',
      );
      expect((serialized.properties['bus']! as StringValue).value, 'sfx');
    });

    test('audioListener realizes with no properties', () {
      final registry = FsceneComponentRegistry()
        ..register(AudioListenerCodec());
      final context = RealizeContext(SceneDocument());
      final component = registry.realize(
        ComponentSpec('audioListener'),
        context,
      );
      expect(component, isA<AudioListener>());
    });
  });
}
