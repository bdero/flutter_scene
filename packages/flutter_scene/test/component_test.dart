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

/// Counts [update] calls for tick-gating assertions.
class TickCountingComponent extends Component {
  int updateCalls = 0;
  double lastDelta = 0;

  @override
  void update(double deltaSeconds) {
    updateCalls++;
    lastDelta = deltaSeconds;
  }
}

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

  group('Node.mesh convenience', () {
    test('a node has no mesh by default', () {
      final node = Node();
      expect(node.mesh, isNull);
      expect(node.getComponent<MeshComponent>(), isNull);
    });

    test('the mesh constructor argument attaches a MeshComponent', () {
      final mesh = Mesh.primitives(primitives: []);
      final node = Node(mesh: mesh);

      final component = node.getComponent<MeshComponent>();
      expect(component, isNotNull);
      expect(identical(component!.mesh, mesh), isTrue);
      expect(identical(node.mesh, mesh), isTrue);
    });

    test('the mesh setter attaches a MeshComponent and round-trips', () {
      final mesh = Mesh.primitives(primitives: []);
      final node = Node();
      node.mesh = mesh;

      expect(identical(node.mesh, mesh), isTrue);
      expect(identical(node.getComponent<MeshComponent>()!.mesh, mesh), isTrue);
    });

    test('reassigning the mesh keeps a single MeshComponent', () {
      final node = Node(mesh: Mesh.primitives(primitives: []));
      final replacement = Mesh.primitives(primitives: []);
      node.mesh = replacement;

      expect(node.getComponents<MeshComponent>().length, 1);
      expect(identical(node.mesh, replacement), isTrue);
    });

    test('setting the mesh to null removes the MeshComponent', () {
      final node = Node(mesh: Mesh.primitives(primitives: []));
      node.mesh = null;

      expect(node.mesh, isNull);
      expect(node.getComponent<MeshComponent>(), isNull);
    });
  });

  group('component tick gating', () {
    test('tick is a no-op before the component is mounted', () {
      final component = TickCountingComponent();
      Node().addComponent(component);
      component.tick(1.0);
      expect(component.updateCalls, 0);
    });

    test('tick is deferred until onLoad completes', () async {
      final component = TickCountingComponent();
      Node().addComponent(component);
      component.mount();

      component.tick(1.0);
      expect(component.updateCalls, 0, reason: 'onLoad has not resolved yet');

      await Future<void>.delayed(Duration.zero);
      component.tick(0.5);
      expect(component.updateCalls, 1);
      expect(component.lastDelta, 0.5);
    });

    test('a disabled component does not tick', () async {
      final component = TickCountingComponent()..enabled = false;
      Node().addComponent(component);
      component.mount();
      await Future<void>.delayed(Duration.zero);

      component.tick(1.0);
      expect(component.updateCalls, 0);
    });
  });
}
