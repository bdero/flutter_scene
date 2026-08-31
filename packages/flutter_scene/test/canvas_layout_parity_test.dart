// The document walk and the live-node walk must agree.
//
// There are two of them because they serve different moments: the editor
// draws what the document says right now, before any of it is realized, and
// the runtime lays out live nodes. They share solveRect, so the arithmetic
// cannot drift, but the two walks are separate code and the defaults are
// written twice -- once in the components, once in the document reader. This
// is what catches them diverging.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart' as doc;

/// The same layout, built twice: once as live nodes, once as a document.
({Node canvas, doc.SceneDocument document, doc.LocalId documentCanvas})
_bothForms() {
  // Live form.
  final canvasNode = Node()..name = 'HUD';
  canvasNode.addComponent(
    CanvasComponent(referenceWidth: 1000, referenceHeight: 600),
  );
  final panelNode = Node()..name = 'Panel';
  panelNode.addComponent(RectTransformComponent.stretch(inset: 100));
  final badgeNode = Node()..name = 'Badge';
  badgeNode.addComponent(
    RectTransformComponent(
      anchorMinX: 1,
      anchorMinY: 1,
      anchorMaxX: 1,
      anchorMaxY: 1,
      pivotX: 1,
      pivotY: 1,
      anchoredX: -8,
      anchoredY: -8,
      sizeDeltaX: 120,
      sizeDeltaY: 32,
    ),
  );
  panelNode.add(badgeNode);
  canvasNode.add(panelNode);

  // Document form.
  final document = doc.SceneDocument();
  final canvasId = document.newId();
  document.addNode(
    doc.NodeSpec(
      id: canvasId,
      name: 'HUD',
      components: [
        doc.ComponentSpec(
          doc.canvasComponentType,
          properties: {
            'referenceWidth': const doc.DoubleValue(1000),
            'referenceHeight': const doc.DoubleValue(600),
          },
        ),
      ],
    ),
    root: true,
  );
  final panelId = document.newId();
  document.addNode(
    doc.NodeSpec(
      id: panelId,
      name: 'Panel',
      components: [
        doc.ComponentSpec(
          doc.rectTransformComponentType,
          properties: {
            'anchorMinX': const doc.DoubleValue(0),
            'anchorMinY': const doc.DoubleValue(0),
            'anchorMaxX': const doc.DoubleValue(1),
            'anchorMaxY': const doc.DoubleValue(1),
            'sizeDeltaX': const doc.DoubleValue(-200),
            'sizeDeltaY': const doc.DoubleValue(-200),
          },
        ),
      ],
    ),
  );
  document.node(canvasId)!.children.add(panelId);
  final badgeId = document.newId();
  document.addNode(
    doc.NodeSpec(
      id: badgeId,
      name: 'Badge',
      components: [
        doc.ComponentSpec(
          doc.rectTransformComponentType,
          properties: {
            'anchorMinX': const doc.DoubleValue(1),
            'anchorMinY': const doc.DoubleValue(1),
            'anchorMaxX': const doc.DoubleValue(1),
            'anchorMaxY': const doc.DoubleValue(1),
            'pivotX': const doc.DoubleValue(1),
            'pivotY': const doc.DoubleValue(1),
            'anchoredX': const doc.DoubleValue(-8),
            'anchoredY': const doc.DoubleValue(-8),
            'sizeDeltaX': const doc.DoubleValue(120),
            'sizeDeltaY': const doc.DoubleValue(32),
          },
        ),
      ],
    ),
  );
  document.node(panelId)!.children.add(badgeId);

  return (canvas: canvasNode, document: document, documentCanvas: canvasId);
}

void main() {
  test('both walks solve the same rectangles in the same order', () {
    final built = _bothForms();

    final live = layOutCanvas(built.canvas, viewWidth: 1000, viewHeight: 600);
    final fromDocument = doc.solveCanvasLayout(
      built.document,
      built.documentCanvas,
    );

    expect(fromDocument, hasLength(live.length));
    for (var i = 0; i < live.length; i++) {
      expect(
        built.document.node(fromDocument[i].node)!.name,
        live[i].node.name,
        reason: 'entry $i is a different node',
      );
      expect(
        fromDocument[i].rect,
        live[i].rect,
        reason: 'entry $i (${live[i].node.name}) solved differently',
      );
    }
  });

  test('the two agree on the canvas rectangle itself', () {
    final built = _bothForms();

    expect(
      doc.canvasRectOf(built.document.node(built.documentCanvas)!),
      built.canvas.getComponent<CanvasComponent>()!.rect(
        viewWidth: 1234,
        viewHeight: 567,
      ),
    );
  });

  test('and on the defaults, which are written in both places', () {
    // A bare rect transform: the component's field defaults on one side, the
    // document reader's fallbacks on the other.
    final liveCanvas = Node()..name = 'C';
    liveCanvas.addComponent(
      CanvasComponent(referenceWidth: 1000, referenceHeight: 600),
    );
    liveCanvas.add(Node()..addComponent(RectTransformComponent()));

    final document = doc.SceneDocument();
    final canvasId = document.newId();
    document.addNode(
      doc.NodeSpec(
        id: canvasId,
        name: 'C',
        components: [
          doc.ComponentSpec(
            doc.canvasComponentType,
            properties: {
              'referenceWidth': const doc.DoubleValue(1000),
              'referenceHeight': const doc.DoubleValue(600),
            },
          ),
        ],
      ),
      root: true,
    );
    final bareId = document.newId();
    document.addNode(
      doc.NodeSpec(
        id: bareId,
        name: 'Bare',
        components: [doc.ComponentSpec(doc.rectTransformComponentType)],
      ),
    );
    document.node(canvasId)!.children.add(bareId);

    expect(
      doc.solveCanvasLayout(document, canvasId).single.rect,
      layOutCanvas(liveCanvas, viewWidth: 1000, viewHeight: 600).single.rect,
    );
  });
}
