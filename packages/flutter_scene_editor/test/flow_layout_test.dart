// Where the flow canvas puts things. This is the arithmetic hit testing and
// painting both depend on, and it needs no widget to check.

import 'package:flutter/material.dart';
import 'package:flutter_scene/flow.dart';
import 'package:flutter_scene_editor/src/panels/flow_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

void main() {
  final registry = sceneFlowRegistry();

  ({FlowGraph graph, FlowLayout layout}) rig() {
    final graph = FlowGraph();
    return (graph: graph, layout: FlowLayout(graph, registry));
  }

  group('node bounds', () {
    test('a node is as tall as its longer pin column', () {
      final r = rig();
      // Branch has two inputs (exec, condition) and two outputs.
      final small = r.graph.add('flow.branch');
      // Play Animation has four inputs and two outputs.
      final large = r.graph.add('scene.playAnimation');
      expect(
        r.layout.boundsOf(large).height,
        greaterThan(r.layout.boundsOf(small).height),
      );
    });

    test('bounds follow the node position', () {
      final r = rig();
      final node = r.graph.add('math.add', position: Vector2(50, 70));
      final bounds = r.layout.boundsOf(node);
      expect(bounds.left, 50);
      expect(bounds.top, 70);
      expect(bounds.width, flowNodeWidth);
    });

    test('an unknown type still has a body, so it can be seen and deleted', () {
      final r = rig();
      final node = r.graph.add('does.not.exist');
      expect(r.layout.boundsOf(node).height, greaterThan(0));
    });
  });

  group('pin placement', () {
    test('inputs run down the left edge and outputs down the right', () {
      final r = rig();
      final node = r.graph.add('flow.branch', position: Vector2(0, 0));
      final input = r.layout.portCentre(node.id, 'condition')!;
      final output = r.layout.portCentre(node.id, 'true')!;
      expect(input.dx, 0);
      expect(output.dx, flowNodeWidth);
    });

    test('pins stack in declaration order', () {
      final r = rig();
      final node = r.graph.add('vector.make', position: Vector2(0, 0));
      final x = r.layout.portCentre(node.id, 'x')!;
      final y = r.layout.portCentre(node.id, 'y')!;
      final z = r.layout.portCentre(node.id, 'z')!;
      expect(y.dy - x.dy, flowRowHeight);
      expect(z.dy - y.dy, flowRowHeight);
    });

    test('an unknown node or pin has no centre', () {
      final r = rig();
      final node = r.graph.add('math.add');
      expect(r.layout.portCentre(node.id, 'nope'), isNull);
      expect(r.layout.portCentre(9999, 'value'), isNull);
    });
  });

  group('hit testing', () {
    test('a pin is grabbed within its radius and not beyond', () {
      final r = rig();
      final node = r.graph.add('math.add', position: Vector2(0, 0));
      final centre = r.layout.portCentre(node.id, 'a')!;
      expect(r.layout.portAt(centre)?.pin, 'a');
      expect(
        r.layout.portAt(centre + const Offset(flowGrabRadius - 1, 0))?.pin,
        'a',
      );
      expect(
        r.layout.portAt(centre + const Offset(flowGrabRadius + 6, 0)),
        isNull,
      );
    });

    test('a pin knows whether it is an input', () {
      final r = rig();
      final node = r.graph.add('math.add', position: Vector2(0, 0));
      expect(r.layout.portAt(r.layout.portCentre(node.id, 'a')!)!.isInput,
          isTrue);
      expect(
        r.layout.portAt(r.layout.portCentre(node.id, 'value')!)!.isInput,
        isFalse,
      );
    });

    test('the node under the pointer is found, empty canvas is not', () {
      final r = rig();
      final node = r.graph.add('math.add', position: Vector2(100, 100));
      expect(r.layout.nodeAt(const Offset(110, 110)), node.id);
      expect(r.layout.nodeAt(const Offset(-40, -40)), isNull);
    });

    test('the node on top wins where two overlap', () {
      final r = rig();
      final under = r.graph.add('math.add', position: Vector2(0, 0));
      final over = r.graph.add('math.add', position: Vector2(4, 4));
      expect(
        r.layout.nodeAt(const Offset(20, 20)),
        over.id,
        reason: 'later nodes paint over earlier ones, so they hit first',
      );
      expect(under.id, isNot(over.id));
    });
  });

  group('wire colours', () {
    test('exec is the pale one, so the spine of a graph reads first', () {
      final exec = flowTypeColor(FlowType.exec);
      expect(exec.computeLuminance(), greaterThan(0.7));
    });

    test('every type has its own colour', () {
      final seen = <Color>{};
      for (final type in FlowType.values) {
        expect(seen.add(flowTypeColor(type)), isTrue, reason: type.name);
      }
    });
  });
}
