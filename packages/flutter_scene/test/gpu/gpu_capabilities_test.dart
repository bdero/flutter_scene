// ignore_for_file: implementation_imports
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/shared/gpu_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

GpuCapabilities _caps({
  bool textureToImage = false,
  bool imageToTexture = false,
  bool presentAsImage = false,
  bool compute = false,
}) => GpuCapabilities(
  textureToImage: textureToImage,
  imageToTexture: imageToTexture,
  presentAsImage: presentAsImage,
  compute: compute,
);

void main() {
  group('GpuCapabilities.hostTier', () {
    test('is full when textures cross both ways', () {
      expect(
        _caps(textureToImage: true, imageToTexture: true).hostTier,
        GpuHostTier.full,
      );
    });

    // The WebGL2 backend's shape: it can hand a texture to Flutter, but
    // browsers do not share textures across WebGL contexts so nothing comes
    // back.
    test('is presentOnly when only the outbound direction works', () {
      expect(_caps(textureToImage: true).hostTier, GpuHostTier.presentOnly);
      expect(_caps(presentAsImage: true).hostTier, GpuHostTier.presentOnly);
    });

    test('is headless when output cannot reach Flutter at all', () {
      expect(_caps().hostTier, GpuHostTier.headless);
      expect(_caps(compute: true).hostTier, GpuHostTier.headless);
    });

    test('does not let imageToTexture alone imply a usable host', () {
      // Inbound without outbound is not a configuration any backend has, but
      // the tier should not claim full for it.
      expect(_caps(imageToTexture: true).hostTier, GpuHostTier.headless);
    });
  });

  group('GpuCapabilities.toString', () {
    test('names the tier and every flag', () {
      final text = _caps(textureToImage: true, imageToTexture: true).toString();
      expect(text, contains('full'));
      expect(text, contains('textureToImage: true'));
      expect(text, contains('imageToTexture: true'));
      expect(text, contains('presentAsImage: false'));
      expect(text, contains('compute: false'));
    });
  });

  // These run against whichever backend the shim's conditional export selects,
  // which under `flutter test` is the native one. They assert the invariants
  // every backend owes callers rather than one backend's specific answers.
  group('the active backend', () {
    test('reports a tier consistent with its own flags', () {
      final caps = gpu.gpuHost.capabilities;
      if (caps.imageToTexture && caps.textureToImage) {
        expect(caps.hostTier, GpuHostTier.full);
      } else if (caps.textureToImage || caps.presentAsImage) {
        expect(caps.hostTier, GpuHostTier.presentOnly);
      } else {
        expect(caps.hostTier, GpuHostTier.headless);
      }
    });

    test('never claims compute, which no backend implements yet', () {
      expect(gpu.gpuHost.capabilities.compute, isFalse);
    });

    test('exposes a host tier without touching a GPU context', () {
      // Reading capabilities must never construct a context, since that throws
      // where Impeller is unavailable.
      expect(gpu.gpuHost.capabilities.hostTier, isA<GpuHostTier>());
    });

    test('imageToTexture returns null rather than throwing', () async {
      // The contract callers depend on: an unwrappable image is a routine
      // answer, handled by reading back rather than by catching.
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder);
      final image = await recorder.endRecording().toImage(1, 1);
      addTearDown(image.dispose);
      expect(gpu.gpuHost.imageToTexture(image), isNull);
    });
  });
}
