// Laying out a canvas subtree: which nodes get a rectangle, what they are
// measured against, and the order they come back in. GPU-free -- the layout
// is arithmetic over the node graph and does not touch the renderer.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

Node _node(String name, {Component? component}) {
  final node = Node()..name = name;
  if (component != null) node.addComponent(component);
  return node;
}

/// A canvas whose rectangle is exactly 1000 x 600, whatever the view.
Node _canvas({CanvasRenderMode mode = CanvasRenderMode.screenSpaceOverlay}) =>
    _node(
      'Canvas',
      component: CanvasComponent(
        renderMode: mode,
        referenceWidth: 1000,
        referenceHeight: 600,
      ),
    );

List<LaidOutRect> _layOut(Node canvas) =>
    layOutCanvas(canvas, viewWidth: 1000, viewHeight: 600);

void main() {
  group('what gets a rectangle', () {
    test('a node with a rect transform does, in canvas coordinates', () {
      final canvas = _canvas();
      canvas.add(
        _node('Panel', component: RectTransformComponent.stretch(inset: 50)),
      );

      final laidOut = _layOut(canvas);

      expect(laidOut, hasLength(1));
      expect(laidOut.single.node.name, 'Panel');
      expect(
        laidOut.single.rect,
        const UiRect(left: 50, bottom: 50, width: 900, height: 500),
      );
    });

    test('a node without one does not', () {
      final canvas = _canvas()..add(_node('Marker'));

      expect(_layOut(canvas), isEmpty);
    });

    test('a node with no canvas above it lays out nothing', () {
      // layOutCanvas is called on the canvas; handed a plain node it has no
      // rectangle to measure against and must not invent one.
      final plain = _node('NotACanvas')
        ..add(_node('Panel', component: RectTransformComponent()));

      expect(_layOut(plain), isEmpty);
    });
  });

  group('what a child is measured against', () {
    test('its parent rectangle, not the canvas', () {
      final canvas = _canvas();
      final panel = _node(
        'Panel',
        component: RectTransformComponent.stretch(inset: 100),
      );
      panel.add(
        _node(
          'Button',
          component: RectTransformComponent(
            anchorMinX: 0,
            anchorMinY: 0,
            anchorMaxX: 0,
            anchorMaxY: 0,
            pivotX: 0,
            pivotY: 0,
            anchoredX: 8,
            anchoredY: 8,
            sizeDeltaX: 60,
            sizeDeltaY: 24,
          ),
        ),
      );
      canvas.add(panel);

      final byName = {
        for (final entry in _layOut(canvas)) entry.node.name: entry.rect,
      };

      expect(byName['Panel']!.left, 100);
      // 100 from the panel's own offset, 8 more inside it.
      expect(byName['Button']!.left, 108);
      expect(byName['Button']!.bottom, 108);
    });

    test('a grouping node passes its parent rectangle straight down', () {
      // A node with no rect transform between a panel and its contents is a
      // grouping node; it must not break the chain.
      final canvas = _canvas();
      final panel = _node(
        'Panel',
        component: RectTransformComponent.stretch(inset: 100),
      );
      final group = _node('Group');
      group.add(
        _node('Label', component: RectTransformComponent.stretch(inset: 10)),
      );
      panel.add(group);
      canvas.add(panel);

      final byName = {
        for (final entry in _layOut(canvas)) entry.node.name: entry.rect,
      };

      expect(byName.keys, isNot(contains('Group')));
      // 100 for the panel, 10 more for the label: measured against the panel,
      // not against the canvas.
      expect(byName['Label']!.left, 110);
      expect(byName['Label']!.width, 780);
    });

    test('a nested canvas starts over at its own size', () {
      final outer = _canvas();
      final inner = _node(
        'Inner',
        component: CanvasComponent(referenceWidth: 200, referenceHeight: 100),
      )..add(_node('Chip', component: RectTransformComponent.stretch()));
      outer.add(inner);

      // The inner canvas and its subtree are left to their own pass.
      expect(_layOut(outer), isEmpty);

      final innerLaidOut = layOutCanvas(
        inner,
        viewWidth: 1000,
        viewHeight: 600,
      );
      expect(innerLaidOut.single.rect.width, 200);
      expect(innerLaidOut.single.rect.height, 100);
    });
  });

  group('order', () {
    test('parents come before children, siblings in scene order', () {
      // The draw order: a panel must be laid out, and drawn, before what sits
      // on top of it.
      final canvas = _canvas();
      final panel = _node('Panel', component: RectTransformComponent())
        ..add(_node('ChildA', component: RectTransformComponent()))
        ..add(_node('ChildB', component: RectTransformComponent()));
      canvas
        ..add(panel)
        ..add(_node('Sibling', component: RectTransformComponent()));

      expect(_layOut(canvas).map((e) => e.node.name), [
        'Panel',
        'ChildA',
        'ChildB',
        'Sibling',
      ]);
    });
  });

  group('the canvas rectangle', () {
    test('a screen-space canvas reports its reference size', () {
      final canvas = CanvasComponent(
        referenceWidth: 1920,
        referenceHeight: 1080,
      );

      // Not the view's size: children are positioned in the space the layout
      // was authored in, and the whole thing is scaled afterwards.
      final rect = canvas.rect(viewWidth: 800, viewHeight: 600);
      expect(rect.width, 1920);
      expect(rect.height, 1080);
    });

    test('a world-space canvas reports its world size', () {
      final canvas = CanvasComponent(
        renderMode: CanvasRenderMode.worldSpace,
        worldWidth: 1.6,
        worldHeight: 0.9,
      );

      final rect = canvas.rect(viewWidth: 800, viewHeight: 600);
      expect(rect.width, 1.6);
      expect(rect.height, 0.9);
    });
  });

  group('scaling to the view', () {
    test('takes the smaller ratio so the reference size always fits', () {
      final canvas = CanvasComponent(
        referenceWidth: 1000,
        referenceHeight: 1000,
      );

      // A wide window: height is the binding constraint.
      expect(canvas.scaleFor(viewWidth: 2000, viewHeight: 500), 0.5);
      // A tall one: width binds instead.
      expect(canvas.scaleFor(viewWidth: 500, viewHeight: 2000), 0.5);
      // Exact: no scaling.
      expect(canvas.scaleFor(viewWidth: 1000, viewHeight: 1000), 1.0);
    });

    test('a world-space canvas is not scaled to the view at all', () {
      final canvas = CanvasComponent(renderMode: CanvasRenderMode.worldSpace);

      expect(canvas.scaleFor(viewWidth: 123, viewHeight: 456), 1.0);
    });
  });
}
