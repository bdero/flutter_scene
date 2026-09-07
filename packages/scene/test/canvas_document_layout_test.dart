/// Solving a canvas layout from the document, which is what the editor draws.
library;

import 'package:scene/scene.dart';
import 'package:test/test.dart';

/// A document with a 1000 x 600 screen-space canvas at its root.
({SceneDocument document, LocalId canvas}) _canvasDocument() {
  final document = SceneDocument();
  final canvas = document.newId();
  document.addNode(
    NodeSpec(
      id: canvas,
      name: 'HUD',
      components: [
        ComponentSpec(
          canvasComponentType,
          properties: {
            'referenceWidth': const DoubleValue(1000),
            'referenceHeight': const DoubleValue(600),
          },
        ),
      ],
    ),
    root: true,
  );
  return (document: document, canvas: canvas);
}

/// Adds a node with a rect transform under [parent] and returns its id.
LocalId _rect(
  SceneDocument document,
  LocalId parent,
  String name,
  Map<String, double> values,
) {
  final id = document.newId();
  document.addNode(
    NodeSpec(
      id: id,
      name: name,
      components: [
        ComponentSpec(
          rectTransformComponentType,
          properties: {
            for (final entry in values.entries)
              entry.key: DoubleValue(entry.value),
          },
        ),
      ],
    ),
  );
  document.node(parent)!.children.add(id);
  return id;
}

const _stretch = {
  'anchorMinX': 0.0,
  'anchorMinY': 0.0,
  'anchorMaxX': 1.0,
  'anchorMaxY': 1.0,
  'sizeDeltaX': 0.0,
  'sizeDeltaY': 0.0,
};

void main() {
  test('a canvas node reports the size its layout is authored against', () {
    final built = _canvasDocument();
    final rect = canvasRectOf(built.document.node(built.canvas)!)!;

    expect(rect.width, 1000);
    expect(rect.height, 600);
  });

  test('a world-space canvas reports its world size instead', () {
    final document = SceneDocument();
    final id = document.newId();
    document.addNode(
      NodeSpec(
        id: id,
        name: 'Sign',
        components: [
          ComponentSpec(
            canvasComponentType,
            properties: {
              'renderMode': const StringValue('worldSpace'),
              'worldWidth': const DoubleValue(2.4),
              'worldHeight': const DoubleValue(1.2),
            },
          ),
        ],
      ),
      root: true,
    );

    final rect = canvasRectOf(document.node(id)!)!;
    expect(rect.width, 2.4);
    expect(rect.height, 1.2);
  });

  test('a node that is not a canvas has no canvas rectangle', () {
    final document = SceneDocument();
    final id = document.newId();
    document.addNode(NodeSpec(id: id, name: 'Plain'), root: true);

    expect(canvasRectOf(document.node(id)!), isNull);
    expect(isCanvasNode(document.node(id)!), isFalse);
    expect(solveCanvasLayout(document, id), isEmpty);
  });

  test('children solve against their parent, parents first', () {
    final built = _canvasDocument();
    final document = built.document;
    final panel = _rect(document, built.canvas, 'Panel', {
      ..._stretch,
      'sizeDeltaX': -200.0,
      'sizeDeltaY': -200.0,
    });
    _rect(document, panel, 'Badge', {
      'anchorMinX': 1.0,
      'anchorMinY': 1.0,
      'anchorMaxX': 1.0,
      'anchorMaxY': 1.0,
      'pivotX': 1.0,
      'pivotY': 1.0,
      'anchoredX': -8.0,
      'anchoredY': -8.0,
      'sizeDeltaX': 120.0,
      'sizeDeltaY': 32.0,
    });

    final solved = solveCanvasLayout(document, built.canvas);

    expect(solved.map((s) => document.node(s.node)!.name), [
      'Panel',
      'Badge',
    ], reason: 'parents before children, which is also draw order');
    expect(solved[0].depth, 1);
    expect(solved[1].depth, 2);
    // The panel is inset 100 a side; the badge sits 8 inside its top-right.
    expect(solved[0].rect.left, 100);
    expect(solved[1].rect.right, 900 - 8);
    expect(solved[1].rect.top, 500 - 8);
  });

  test('a grouping node passes its parent rectangle down', () {
    final built = _canvasDocument();
    final document = built.document;
    final panel = _rect(document, built.canvas, 'Panel', {
      ..._stretch,
      'sizeDeltaX': -200.0,
      'sizeDeltaY': -200.0,
    });
    // No rect transform: a plain node used only for grouping.
    final group = document.newId();
    document.addNode(NodeSpec(id: group, name: 'Group'));
    document.node(panel)!.children.add(group);
    _rect(document, group, 'Label', _stretch);

    final solved = solveCanvasLayout(document, built.canvas);

    expect(solved.map((s) => document.node(s.node)!.name), ['Panel', 'Label']);
    // Measured against the panel, not the canvas, and not counted as a level.
    expect(solved.last.rect.left, 100);
    expect(solved.last.rect.width, 800);
    expect(solved.last.depth, 2);
  });

  test('a nested canvas is left for its own pass', () {
    final built = _canvasDocument();
    final document = built.document;
    final inner = document.newId();
    document.addNode(
      NodeSpec(
        id: inner,
        name: 'Inner',
        components: [ComponentSpec(canvasComponentType)],
      ),
    );
    document.node(built.canvas)!.children.add(inner);
    _rect(document, inner, 'Chip', _stretch);

    expect(solveCanvasLayout(document, built.canvas), isEmpty);
    expect(solveCanvasLayout(document, inner), hasLength(1));
  });

  test('a cycle in the document terminates', () {
    // A hand-edited or partially merged file can name a child that is also an
    // ancestor. The walk has to come back rather than recurse forever.
    final built = _canvasDocument();
    final document = built.document;
    final panel = _rect(document, built.canvas, 'Panel', _stretch);
    document.node(panel)!.children.add(panel);
    document.node(panel)!.children.add(built.canvas);

    expect(solveCanvasLayout(document, built.canvas).map((s) => s.node), [
      panel,
    ]);
  });

  test('missing properties fall back to the component defaults', () {
    // A document written before a field existed, or one that omits defaults,
    // must solve to the same rectangle the component would.
    final built = _canvasDocument();
    final document = built.document;
    _rect(document, built.canvas, 'Bare', const {});

    final solved = solveCanvasLayout(document, built.canvas).single;

    // Centred, 100 x 100: the rectTransform defaults.
    expect(solved.rect.left, 450);
    expect(solved.rect.bottom, 250);
    expect(solved.rect.width, 100);
    expect(solved.rect.height, 100);
  });
}
