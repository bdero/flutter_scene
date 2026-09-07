// Covers SceneSelection: the modifier conventions, selection order, and
// notification only on a real change.

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SceneSelection', () {
    late Node a;
    late Node b;
    late Node c;
    late SceneSelection selection;
    late int notifications;

    setUp(() {
      a = Node(name: 'a');
      b = Node(name: 'b');
      c = Node(name: 'c');
      selection = SceneSelection();
      notifications = 0;
      selection.addListener(() => notifications++);
    });

    test('starts empty', () {
      expect(selection.isEmpty, isTrue);
      expect(selection.primary, isNull);
      expect(selection.length, 0);
    });

    test('selectOnly replaces', () {
      selection.selectOnly(a);
      selection.selectOnly(b);
      expect(selection.nodes, [b]);
      expect(notifications, 2);
    });

    test('add extends and keeps selection order', () {
      selection.selectOnly(b);
      selection.add(a);
      selection.add(c);
      expect(selection.nodes.toList(), [b, a, c]);
      expect(selection.primary, b);
    });

    test('toggle adds then removes', () {
      selection.toggle(a);
      expect(selection.contains(a), isTrue);
      selection.toggle(a);
      expect(selection.contains(a), isFalse);
      expect(notifications, 2);
    });

    test('does not notify when nothing changes', () {
      selection.selectOnly(a);
      expect(notifications, 1);

      selection.selectOnly(a);
      selection.add(a);
      selection.remove(b);
      selection.setAll([a]);
      expect(notifications, 1);
    });

    test('setAll notifies when the set genuinely differs', () {
      selection.setAll([a, b]);
      expect(notifications, 1);
      // Same members, different order: the same selection.
      selection.setAll([b, a]);
      expect(notifications, 1);
      selection.setAll([b, c]);
      expect(notifications, 2);
    });

    test('clear empties once', () {
      selection.setAll([a, b]);
      selection.clear();
      selection.clear();
      expect(selection.isEmpty, isTrue);
      expect(notifications, 2);
    });

    test('pruneDetached drops nodes that left the scene', () {
      final root = Node();
      final live = Node(name: 'live');
      final removed = Node(name: 'removed');
      root.add(live);
      root.add(removed);
      root.debugMountInto(RenderScene());

      selection.setAll([live, removed]);
      selection.pruneDetached();
      expect(selection.length, 2, reason: 'both are still in the scene');

      root.remove(removed);
      selection.pruneDetached();
      expect(selection.nodes.toList(), [live]);
    });

    test('pruneDetached leaves a live selection alone', () {
      final root = Node();
      final live = Node(name: 'live');
      root.add(live);
      root.debugMountInto(RenderScene());

      selection.selectOnly(live);
      final before = notifications;
      selection.pruneDetached();
      expect(selection.length, 1);
      expect(notifications, before, reason: 'no change, no notification');
    });
  });
}
