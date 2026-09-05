// The canvas and rectTransform codecs: what a document carries for a UI
// layout, and what it does with values it should not have been given.

import 'package:flutter_scene/src/components/canvas_component.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/rect_transform_component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

void main() {
  final registry = defaultComponentRegistry();
  final doc = SceneDocument();

  T realize<T extends Component>(
    String type, [
    Map<String, PropertyValue> properties = const {},
  ]) =>
      registry
              .codecFor(type)!
              .realize(
                ComponentSpec(type, properties: properties),
                RealizeContext(doc),
              )!
          as T;

  Map<String, PropertyValue> serialize(String type, Component component) =>
      registry
          .codecFor(type)!
          .serialize(component, SerializeContext(doc))!
          .properties;

  /// PropertyValue does not implement ==, so assertions unwrap it.
  Object? written(String type, Component component, String key) =>
      switch (serialize(type, component)[key]) {
        StringValue(:final value) => value,
        DoubleValue(:final value) => value,
        IntValue(:final value) => value,
        final other => other,
      };

  group('both components are registered', () {
    test('under the UI category', () {
      for (final type in ['canvas', 'rectTransform']) {
        final codec = registry.codecFor(type);
        expect(codec, isNotNull, reason: type);
        expect(codec!.category, 'UI', reason: type);
      }
    });
  });

  group('canvas', () {
    test('defaults to an overlay at a 1920x1080 reference', () {
      final canvas = realize<CanvasComponent>('canvas');

      expect(canvas.renderMode, CanvasRenderMode.screenSpaceOverlay);
      expect(canvas.referenceWidth, 1920);
      expect(canvas.referenceHeight, 1080);
    });

    test('the render mode round-trips by name', () {
      final canvas = realize<CanvasComponent>('canvas', {
        'renderMode': const StringValue('worldSpace'),
        'worldWidth': const DoubleValue(2.4),
      });

      expect(canvas.renderMode, CanvasRenderMode.worldSpace);
      expect(canvas.worldWidth, 2.4);
      expect(written('canvas', canvas, 'renderMode'), 'worldSpace');
    });

    test('an unrecognized render mode keeps the default', () {
      // A document from a later version, or a typo. Losing the canvas
      // entirely over one unknown word would be worse than drawing it as an
      // overlay.
      final canvas = realize<CanvasComponent>('canvas', {
        'renderMode': const StringValue('holographic'),
      });

      expect(canvas.renderMode, CanvasRenderMode.screenSpaceOverlay);
    });

    test('a zero reference size is refused, not divided by', () {
      // scaleFor divides by the reference size; a zero would make every
      // layout infinite.
      final canvas = realize<CanvasComponent>('canvas', {
        'referenceWidth': const DoubleValue(0),
        'referenceHeight': const DoubleValue(-100),
      });

      expect(canvas.referenceWidth, greaterThan(0));
      expect(canvas.referenceHeight, greaterThan(0));
      expect(canvas.scaleFor(viewWidth: 100, viewHeight: 100).isFinite, isTrue);
    });
  });

  group('rectTransform', () {
    test('defaults to a centred 100x100', () {
      final transform = realize<RectTransformComponent>('rectTransform');

      expect(
        transform.solveIn(const UiRect.size(1000, 600)),
        const UiRect(left: 450, bottom: 250, width: 100, height: 100),
      );
    });

    test('all ten numbers round-trip', () {
      final transform = realize<RectTransformComponent>('rectTransform', {
        'anchorMinX': const DoubleValue(0),
        'anchorMinY': const DoubleValue(0.25),
        'anchorMaxX': const DoubleValue(1),
        'anchorMaxY': const DoubleValue(0.75),
        'pivotX': const DoubleValue(0),
        'pivotY': const DoubleValue(1),
        'anchoredX': const DoubleValue(12),
        'anchoredY': const DoubleValue(-8),
        'sizeDeltaX': const DoubleValue(-40),
        'sizeDeltaY': const DoubleValue(-16),
      });

      Object? out(String key) => written('rectTransform', transform, key);
      expect(out('anchorMinY'), 0.25);
      expect(out('anchorMaxY'), 0.75);
      expect(out('pivotY'), 1.0);
      expect(out('anchoredX'), 12.0);
      expect(out('anchoredY'), -8.0);
      expect(out('sizeDeltaX'), -40.0);

      // And it still solves to the rectangle those numbers describe.
      final rect = transform.solveIn(const UiRect.size(1000, 600));
      expect(rect.width, 960);
      expect(rect.height, 284);
    });

    test('an anchor outside 0..1 is kept, not clamped', () {
      // Anchoring beyond the parent is unusual but meaningful, and silently
      // rewriting it on load would change a layout the author committed.
      final transform = realize<RectTransformComponent>('rectTransform', {
        'anchorMinX': const DoubleValue(-0.5),
        'anchorMaxX': const DoubleValue(1.5),
      });

      expect(transform.anchorMinX, -0.5);
      expect(transform.anchorMaxX, 1.5);
      expect(written('rectTransform', transform, 'anchorMinX'), -0.5);
    });
  });
}
