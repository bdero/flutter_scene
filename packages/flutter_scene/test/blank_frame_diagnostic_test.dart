// The "nothing was drawn" frame diagnostic. Four distinct mistakes all
// produce an identical blank frame; when a frame issues zero draw calls the
// engine prints once, naming the cause it can tell apart. Scene.renderViews
// needs a GPU context, so the cause attribution and the once-only latch are
// tested here through the pure Scene.debugEmptyFrameDiagnosis, the same logic
// the render path calls inside an assert.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

// Facts for a frame that drew nothing with visible meshes present, so each
// test overrides only the field for the cause it exercises.
({String? message, bool warned}) diagnose({
  bool warned = false,
  bool drewSomething = false,
  bool regionEmpty = false,
  bool noViews = false,
  bool noScreenViews = false,
  int meshCount = 1,
  int visibleMeshCount = 1,
  bool anyLayerMaskZero = false,
  List<int> screenViewMasks = const [0xFFFFFFFF],
  int visibleLayersUnion = 0x1,
}) {
  return Scene.debugEmptyFrameDiagnosis(
    warned: warned,
    drewSomething: drewSomething,
    regionEmpty: regionEmpty,
    noViews: noViews,
    noScreenViews: noScreenViews,
    meshCount: meshCount,
    visibleMeshCount: visibleMeshCount,
    anyLayerMaskZero: anyLayerMaskZero,
    screenViewMasks: screenViewMasks,
    visibleLayersUnion: visibleLayersUnion,
  );
}

void main() {
  group('cause attribution', () {
    test('no views supplied', () {
      final r = diagnose(noViews: true);
      expect(r.message, contains('No RenderViews were supplied'));
    });

    test('empty draw region', () {
      final r = diagnose(regionEmpty: true);
      expect(r.message, contains('draw region is zero-sized'));
    });

    test('no on-screen views (every view has a target)', () {
      final r = diagnose(noScreenViews: true);
      expect(r.message, contains('Every RenderView has a target'));
    });

    test('scene holds no meshes', () {
      final r = diagnose(meshCount: 0, visibleMeshCount: 0);
      expect(r.message, contains('holds no meshes'));
    });

    test('every mesh hidden', () {
      final r = diagnose(visibleMeshCount: 0);
      expect(r.message, contains('Every mesh in the scene is hidden'));
    });

    test('a layer mask of zero', () {
      final r = diagnose(anyLayerMaskZero: true, screenViewMasks: const [0]);
      expect(r.message, contains('layerMask is 0'));
    });

    test('layer mask matched no visible node', () {
      final r = diagnose(screenViewMasks: const [0x4], visibleLayersUnion: 0x1);
      expect(r.message, contains('No visible node is on any view layerMask'));
      // The message names both sides so the mismatch is fixable from it.
      expect(r.message, contains('0x4'));
      expect(r.message, contains('0x1'));
    });

    test('every blank cause is labelled a zero-draw frame', () {
      final r = diagnose(noViews: true);
      expect(r.message, contains('zero draw calls'));
    });
  });

  group('latch', () {
    test('a blank frame warns once, then stays silent', () {
      final first = diagnose(warned: false, meshCount: 0);
      expect(first.message, isNotNull);
      expect(first.warned, isTrue);

      final second = diagnose(warned: first.warned, meshCount: 0);
      expect(second.message, isNull);
      expect(second.warned, isTrue);
    });

    test('a drawing frame prints nothing and clears the latch', () {
      final r = diagnose(warned: true, drewSomething: true);
      expect(r.message, isNull);
      expect(r.warned, isFalse);
    });

    test('a regression after a drawing frame warns again', () {
      // draws -> latch clear
      final drew = diagnose(warned: true, drewSomething: true);
      expect(drew.warned, isFalse);
      // blank again -> warns once more
      final blankAgain = diagnose(warned: drew.warned, meshCount: 0);
      expect(blankAgain.message, isNotNull);
      expect(blankAgain.warned, isTrue);
    });
  });
}
