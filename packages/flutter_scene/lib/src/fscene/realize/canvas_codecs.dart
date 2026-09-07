/// Codecs for the layout components: canvases and the rectangles inside them.
///
/// Both are plain numbers, so both are declarative. The interesting part is
/// the grouping: a rect transform has ten fields that mean nothing read one
/// at a time, so they are grouped into anchors, pivot, position and size, and
/// the inspector draws them under those headings rather than as a list of ten
/// sliders.
library;

import 'package:flutter_scene/src/components/canvas_component.dart';
import 'package:flutter_scene/src/components/rect_transform_component.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';

/// Codec for [CanvasComponent].
class CanvasCodec extends DeclarativeComponentCodec<CanvasComponent> {
  @override
  String get type => 'canvas';

  @override
  String? get category => 'UI';

  @override
  CanvasComponent create(PropertyReader props) => CanvasComponent();

  @override
  List<ComponentField<CanvasComponent>> get fields => [
    ComponentField.enumString<CanvasComponent, CanvasRenderMode>(
      'renderMode',
      values: CanvasRenderMode.values,
      defaultValue: CanvasRenderMode.screenSpaceOverlay,
      doc: 'Whether the canvas is drawn over the frame or sits in the scene.',
      get: (c) => c.renderMode,
      set: (c, v) => c.renderMode = v,
    ),
    ComponentField.number(
      'referenceWidth',
      defaultValue: 1920.0,
      group: 'Reference size',
      doc: 'Width the layout was authored against, in canvas units.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.referenceWidth,
      set: (c, v) => c.referenceWidth = v <= 0 ? 1 : v,
    ),
    ComponentField.number(
      'referenceHeight',
      defaultValue: 1080.0,
      group: 'Reference size',
      doc: 'Height the layout was authored against, in canvas units.',
      constraints: const [Range.nonNegative()],
      get: (c) => c.referenceHeight,
      set: (c, v) => c.referenceHeight = v <= 0 ? 1 : v,
    ),
    ComponentField.number(
      'worldWidth',
      defaultValue: 1.6,
      group: 'World size',
      doc: 'Width in world units, for a worldSpace canvas.',
      constraints: const [Range.nonNegative(), SoftRange(0, 20)],
      get: (c) => c.worldWidth,
      set: (c, v) => c.worldWidth = v < 0 ? 0 : v,
    ),
    ComponentField.number(
      'worldHeight',
      defaultValue: 0.9,
      group: 'World size',
      doc: 'Height in world units, for a worldSpace canvas.',
      constraints: const [Range.nonNegative(), SoftRange(0, 20)],
      get: (c) => c.worldHeight,
      set: (c, v) => c.worldHeight = v < 0 ? 0 : v,
    ),
    ComponentField.number(
      'cameraDistance',
      defaultValue: 1.0,
      doc: 'Distance in front of the camera, for a screenSpaceCamera canvas.',
      constraints: const [Range.nonNegative(), SoftRange(0, 20)],
      get: (c) => c.cameraDistance,
      set: (c, v) => c.cameraDistance = v,
    ),
    ComponentField.integer(
      'sortOrder',
      defaultValue: 0,
      doc: 'Draw order between canvases, low to high.',
      get: (c) => c.sortOrder,
      set: (c, v) => c.sortOrder = v,
    ),
  ];
}

/// Codec for [RectTransformComponent].
class RectTransformCodec
    extends DeclarativeComponentCodec<RectTransformComponent> {
  @override
  String get type => 'rectTransform';

  @override
  String? get category => 'UI';

  @override
  RectTransformComponent create(PropertyReader props) =>
      RectTransformComponent();

  /// A grouped 0..1 fraction, which is what eight of the ten fields are.
  ComponentField<RectTransformComponent> _fraction(
    String name, {
    required String group,
    required String doc,
    required double defaultValue,
    required double Function(RectTransformComponent) get,
    required void Function(RectTransformComponent, double) set,
  }) => ComponentField.number(
    name,
    defaultValue: defaultValue,
    group: group,
    doc: doc,
    // Not clamped: an anchor outside 0..1 attaches to a point beyond the
    // parent, which is unusual but meaningful, and clamping it would silently
    // rewrite a layout on load.
    constraints: const [SoftRange(0, 1)],
    get: get,
    set: set,
  );

  @override
  List<ComponentField<RectTransformComponent>> get fields => [
    _fraction(
      'anchorMinX',
      group: 'Anchors',
      doc: 'Left edge of the anchor region, as a fraction of the parent.',
      defaultValue: 0.5,
      get: (c) => c.anchorMinX,
      set: (c, v) => c.anchorMinX = v,
    ),
    _fraction(
      'anchorMinY',
      group: 'Anchors',
      doc: 'Bottom edge of the anchor region, as a fraction of the parent.',
      defaultValue: 0.5,
      get: (c) => c.anchorMinY,
      set: (c, v) => c.anchorMinY = v,
    ),
    _fraction(
      'anchorMaxX',
      group: 'Anchors',
      doc: 'Right edge of the anchor region, as a fraction of the parent.',
      defaultValue: 0.5,
      get: (c) => c.anchorMaxX,
      set: (c, v) => c.anchorMaxX = v,
    ),
    _fraction(
      'anchorMaxY',
      group: 'Anchors',
      doc: 'Top edge of the anchor region, as a fraction of the parent.',
      defaultValue: 0.5,
      get: (c) => c.anchorMaxY,
      set: (c, v) => c.anchorMaxY = v,
    ),
    _fraction(
      'pivotX',
      group: 'Pivot',
      doc: 'The point across this rectangle that its position places.',
      defaultValue: 0.5,
      get: (c) => c.pivotX,
      set: (c, v) => c.pivotX = v,
    ),
    _fraction(
      'pivotY',
      group: 'Pivot',
      doc: 'The point up this rectangle that its position places.',
      defaultValue: 0.5,
      get: (c) => c.pivotY,
      set: (c, v) => c.pivotY = v,
    ),
    ComponentField.number(
      'anchoredX',
      defaultValue: 0.0,
      group: 'Position',
      doc: "The pivot's horizontal offset from the anchor point.",
      get: (c) => c.anchoredX,
      set: (c, v) => c.anchoredX = v,
    ),
    ComponentField.number(
      'anchoredY',
      defaultValue: 0.0,
      group: 'Position',
      doc: "The pivot's vertical offset from the anchor point.",
      get: (c) => c.anchoredY,
      set: (c, v) => c.anchoredY = v,
    ),
    ComponentField.number(
      'sizeDeltaX',
      defaultValue: 100.0,
      group: 'Size',
      doc:
          'Width beyond the anchor region; the width outright when the '
          'anchors meet.',
      get: (c) => c.sizeDeltaX,
      set: (c, v) => c.sizeDeltaX = v,
    ),
    ComponentField.number(
      'sizeDeltaY',
      defaultValue: 100.0,
      group: 'Size',
      doc:
          'Height beyond the anchor region; the height outright when the '
          'anchors meet.',
      get: (c) => c.sizeDeltaY,
      set: (c, v) => c.sizeDeltaY = v,
    ),
  ];
}
