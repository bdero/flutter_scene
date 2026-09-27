import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gpu = _gpuAvailable();
  const a = Size(64, 32);
  const b = Size(48, 24);
  const c = Size(32, 16);

  group('Surface', () {
    test('a toggling size reuses its targets', () {
      final surface = Surface();
      final ringA = {
        surface.getNextSwapchainColorTexture(a),
        surface.getNextSwapchainColorTexture(a),
      };
      final poolA = surface.transientTexturePool();
      surface.getNextSwapchainColorTexture(b);
      final poolB = surface.transientTexturePool();
      expect(identical(poolA, poolB), isFalse);

      // Back to a: the same ring and pool, nothing new.
      final again = {
        surface.getNextSwapchainColorTexture(a),
        surface.getNextSwapchainColorTexture(a),
      };
      expect(again, ringA);
      expect(identical(surface.transientTexturePool(), poolA), isTrue);
    });

    test('a switch forgets the previous output', () {
      final surface = Surface();
      surface.getNextSwapchainColorTexture(a);
      expect(surface.lastSwapchainColorTexture(), isNotNull);
      surface.getNextSwapchainColorTexture(b);
      // b's first frame has no previous b output.
      final first = surface.lastSwapchainColorTexture();
      surface.getNextSwapchainColorTexture(a);
      expect(identical(surface.lastSwapchainColorTexture(), first), isFalse);
    });

    test('only the two most recent sizes are kept', () {
      final surface = Surface();
      final firstA = surface.getNextSwapchainColorTexture(a);
      surface.getNextSwapchainColorTexture(b);
      surface.getNextSwapchainColorTexture(c);
      // a was evicted by c, so it reallocates.
      final secondA = surface.getNextSwapchainColorTexture(a);
      expect(identical(firstA, secondA), isFalse);
    });

    test('an idle size is released', () {
      final surface = Surface();
      final firstA = surface.getNextSwapchainColorTexture(a);
      for (var i = 0; i < 300; i++) {
        surface.getNextSwapchainColorTexture(b);
      }
      final secondA = surface.getNextSwapchainColorTexture(a);
      expect(identical(firstA, secondA), isFalse);
    });
  }, skip: gpu ? false : 'Requires a GPU device.');
}
