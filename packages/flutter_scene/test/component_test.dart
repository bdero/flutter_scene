import 'package:flutter_scene/scene.dart';
import 'package:test/test.dart';

/// Records the order of lifecycle hook calls for assertions.
class RecordingComponent extends Component {
  final List<String> log = [];

  @override
  void onAttach() => log.add('attach');

  @override
  void onDetach() => log.add('detach');
}

class OtherComponent extends Component {}

void main() {
  group('Node component collection', () {
    test('addComponent fires onAttach and sets the owner', () {
      final node = Node();
      final component = RecordingComponent();

      expect(component.isAttached, isFalse);
      node.addComponent(component);

      expect(component.isAttached, isTrue);
      expect(identical(component.node, node), isTrue);
      expect(component.log, ['attach']);
    });

    test('removeComponent fires onDetach and clears the owner', () {
      final node = Node();
      final component = RecordingComponent();
      node.addComponent(component);
      node.removeComponent(component);

      expect(component.isAttached, isFalse);
      expect(component.log, ['attach', 'detach']);
    });

    test('adding an already-attached component throws', () {
      final node = Node();
      final other = Node();
      final component = RecordingComponent();
      node.addComponent(component);

      expect(() => node.addComponent(component), throwsException);
      expect(() => other.addComponent(component), throwsException);
    });

    test('removing a component not attached here throws', () {
      final node = Node();
      expect(() => node.removeComponent(RecordingComponent()), throwsException);
    });

    test('getComponent returns the first component of the type', () {
      final node = Node();
      final first = RecordingComponent();
      final second = RecordingComponent();
      node.addComponent(first);
      node.addComponent(second);
      node.addComponent(OtherComponent());

      expect(identical(node.getComponent<RecordingComponent>(), first), isTrue);
      expect(node.getComponent<OtherComponent>(), isNotNull);
    });

    test('getComponent returns null when no component matches', () {
      expect(Node().getComponent<RecordingComponent>(), isNull);
    });

    test('getComponents returns every match in attach order', () {
      final node = Node();
      final first = RecordingComponent();
      final second = RecordingComponent();
      node.addComponent(first);
      node.addComponent(OtherComponent());
      node.addComponent(second);

      expect(node.getComponents<RecordingComponent>().toList(), [
        first,
        second,
      ]);
    });

    test('a component is enabled and unloaded by default', () {
      final component = RecordingComponent();
      expect(component.enabled, isTrue);
      expect(component.isMounted, isFalse);
      expect(component.isLoaded, isFalse);
    });
  });
}
