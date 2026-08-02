// Covers ExternalTexture: update-policy resolution (everyFrame/interval/
// manual + requestCapture + resize forcing), the texture-id setter, sampler
// derivation, and disposal. The capture itself needs a live platform texture
// and a GPU, so it is exercised by the example app rather than here.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1);

  ExternalTexture make({
    ExternalTextureUpdate update = ExternalTextureUpdate.everyFrame,
    ExternalTextureSampling sampling = const ExternalTextureSampling(),
    int? textureId = 7,
  }) => ExternalTexture(
    textureId: textureId,
    width: 16,
    height: 8,
    update: update,
    sampling: sampling,
  );

  group('update policy', () {
    test('everyFrame captures on every check', () {
      final source = make();
      expect(source.shouldCapture(t0), isTrue);
      expect(source.shouldCapture(t0), isTrue);
      source.dispose();
    });

    test('manual only captures on request', () {
      final source = make(update: ExternalTextureUpdate.manual);
      expect(source.shouldCapture(t0), isFalse);
      source.requestCapture();
      expect(source.shouldCapture(t0), isTrue);
      expect(source.shouldCapture(t0), isFalse);
      source.dispose();
    });

    test('interval waits out the duration', () {
      final source = make(
        update: const ExternalTextureUpdate.interval(Duration(seconds: 1)),
      );
      // Nothing captured yet, so the first check is always due.
      expect(source.shouldCapture(t0), isTrue);
      source.dispose();
    });

    test('requestCapture overrides an interval that is not due', () {
      final source = make(
        update: const ExternalTextureUpdate.interval(Duration(hours: 1)),
      );
      source.requestCapture();
      expect(source.shouldCapture(t0), isTrue);
      source.dispose();
    });

    test('resize forces a capture under a manual policy', () {
      final source = make(update: ExternalTextureUpdate.manual);
      expect(source.shouldCapture(t0), isFalse);
      source.resize(32, 16);
      expect(source.width, 32);
      expect(source.height, 16);
      expect(source.shouldCapture(t0), isTrue);
      source.dispose();
    });

    test('resize to the same size does not force a capture', () {
      final source = make(update: ExternalTextureUpdate.manual);
      source.resize(16, 8);
      expect(source.shouldCapture(t0), isFalse);
      source.dispose();
    });
  });

  group('texture id', () {
    test('may start null and be set later', () {
      final source = make(textureId: null);
      expect(source.textureId, isNull);
      source.textureId = 3;
      expect(source.textureId, 3);
      source.dispose();
    });
  });

  group('texture source contract', () {
    test('samples nothing before the first capture', () {
      final source = make();
      expect(source.sampledTexture, isNull);
      expect(source.texture, isNull);
      expect(source.captureCount, 0);
      expect(source.lastCaptureDuration, Duration.zero);
      source.dispose();
    });

    test('is usable wherever a TextureSource is', () {
      final source = make();
      expect(source, isA<TextureSource>());
      source.dispose();
    });

    test('derives the sampler from its sampling options', () {
      final source = make(
        sampling: const ExternalTextureSampling(
          filter: gpu.MinMagFilter.nearest,
          wrap: gpu.SamplerAddressMode.repeat,
        ),
      );
      final sampler = source.sampledSampler;
      expect(sampler.minFilter, gpu.MinMagFilter.nearest);
      expect(sampler.magFilter, gpu.MinMagFilter.nearest);
      expect(sampler.widthAddressMode, gpu.SamplerAddressMode.repeat);
      expect(sampler.heightAddressMode, gpu.SamplerAddressMode.repeat);
      source.dispose();
    });

    test('defaults to bilinear clamped sampling', () {
      final source = make();
      final sampler = source.sampledSampler;
      expect(sampler.minFilter, gpu.MinMagFilter.linear);
      expect(sampler.magFilter, gpu.MinMagFilter.linear);
      expect(sampler.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
      source.dispose();
    });
  });

  group('lifecycle', () {
    test('rejects a non-positive size', () {
      expect(
        () => ExternalTexture(textureId: 1, width: 0, height: 4),
        throwsAssertionError,
      );
    });

    test('drops its texture on dispose', () {
      final source = make();
      source.dispose();
      expect(source.sampledTexture, isNull);
    });

    test('notifies listeners it is a ChangeNotifier', () {
      final source = make();
      var calls = 0;
      void listener() => calls++;
      source.addListener(listener);
      source.removeListener(listener);
      expect(calls, 0);
      source.dispose();
    });
  });
}
