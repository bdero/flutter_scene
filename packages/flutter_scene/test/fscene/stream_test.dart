// Covers lazy-subtree streaming: a LoadPolicy.lazy instance survives
// composition, realizes as a placeholder, and loads/unloads on demand. Uses
// component-less nodes so realization is GPU-free.

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/stream/stream.dart';
import 'package:flutter_test/flutter_test.dart';

// A single-root prefab: 'content' with a 'leaf' child (no components).
SceneDocument _prefab() {
  final doc = SceneDocument();
  final content = doc.createNode(name: 'content', root: true);
  final leaf = doc.createNode(name: 'leaf');
  content.children.add(leaf.id);
  return doc;
}

void main() {
  test('composeScene leaves a lazy instance unexpanded', () {
    final host = SceneDocument();
    host.createNode(name: 'placeholder', root: true).instance =
        PrefabInstanceSpec(source: const AssetRef('p'), load: LoadPolicy.lazy);

    // The lazy instance is the only one, so nothing is resolved or expanded.
    final composed = composeScene(
      host,
      resolve: (_) => throw StateError('a lazy instance must not resolve'),
    );
    expect(composed.node(host.rootNodes.single.id)!.instance, isNotNull);
  });

  test(
    'a lazy instance realizes as a placeholder, then loads and unloads',
    () async {
      final host = SceneDocument();
      final placeholder = host.createNode(name: 'placeholder', root: true);
      placeholder.instance = PrefabInstanceSpec(
        source: const AssetRef('p'),
        load: LoadPolicy.lazy,
      );

      final live = realizeScene(host).getChildByName('placeholder')!;
      expect(isLazySubtree(live), isTrue);
      expect(isSubtreeLoaded(live), isFalse);
      expect(live.children, isEmpty);

      await loadSubtree(live, load: (_) async => _prefab());
      expect(isSubtreeLoaded(live), isTrue);
      expect(live.getChildByName('leaf'), isNotNull);

      unloadSubtree(live);
      expect(live.children, isEmpty);
      expect(isLazySubtree(live), isTrue); // still a placeholder, reloadable
    },
  );

  test('eager instances still expand alongside a lazy one', () {
    final prefab = SceneDocument();
    prefab.createNode(name: 'eagerContent', root: true);

    final host = SceneDocument();
    host.createNode(name: 'eager', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
    );
    host.createNode(name: 'lazy', root: true).instance = PrefabInstanceSpec(
      source: const AssetRef('p'),
      load: LoadPolicy.lazy,
    );

    final composed = composeScene(host, resolve: (_) => prefab);
    // The eager instance expanded (its instance cleared); the lazy one did not
    // (its instance survives for the streaming layer).
    final lazy = composed.nodes.values.firstWhere((n) => n.name == 'lazy');
    final eager = composed.nodes.values.firstWhere((n) => n.name == 'eager');
    expect(lazy.instance, isNotNull);
    expect(eager.instance, isNull);
  });
}
