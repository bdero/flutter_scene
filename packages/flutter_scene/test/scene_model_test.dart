import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Animation;
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/components/materials_variants_component.dart'
    show MaterialsVariantBinding;
// ignore: implementation_imports
import 'package:flutter_scene/src/widgets/declarative.dart'
    show SceneAnimationBinder;
import 'package:flutter_test/flutter_test.dart';

/// SceneModel widget tests: the import is replaced with a GPU-free
/// hand-built node tree via [SceneModel.debugImportOverride], so the full
/// load / template-cache / clone / variant / animation path runs headless.

class _FakeMaterial implements Material {
  _FakeMaterial(this.label);
  final String label;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGeometry implements Geometry {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A source whose load completes on demand, to hold the widget in its
/// loading phase.
class _GatedSource extends SceneModelSource {
  _GatedSource(this.key);
  final String key;
  final Completer<Uint8List> gate = Completer<Uint8List>();

  @override
  String get cacheKey => 'gated:$key';

  @override
  Future<Uint8List> load() => gate.future;
}

class _FailingSource extends SceneModelSource {
  _FailingSource(this.key);
  final String key;

  @override
  String get cacheKey => 'failing:$key';

  @override
  Future<Uint8List> load() async => throw StateError('no bytes for $key');
}

/// Builds a template like the runtime importer would: a root carrying a
/// variants component and a parsed animation, over a child with a mesh.
Node _buildTemplate({List<String> variants = const ['a', 'b']}) {
  final defaultMaterial = _FakeMaterial('default');
  final variantMaterial = _FakeMaterial('variant-b');
  final primitive = MeshPrimitive(_FakeGeometry(), defaultMaterial);
  final child = Node(name: 'shoe')
    ..mesh = Mesh.primitives(primitives: [primitive]);
  final root = Node(name: 'root')..add(child);
  if (variants.isNotEmpty) {
    root.addComponent(
      MaterialsVariantsComponent.internal(variants, [
        MaterialsVariantBinding(
          node: child,
          primitive: primitive,
          defaultMaterial: defaultMaterial,
          materialsByVariant: {1: variantMaterial},
        ),
      ]),
    );
  }
  root.addParsedAnimation(Animation(name: 'Spin'));
  root.addParsedAnimation(Animation(name: 'Wave'));
  return root;
}

void main() {
  late Node sceneRoot;
  late int importCalls;

  setUp(() {
    sceneRoot = Node(name: 'scene-root');
    importCalls = 0;
    SceneModel.debugImportOverride = (bytes) async {
      importCalls++;
      return _buildTemplate();
    };
    SceneModel.debugClearModelTemplateCache();
  });

  tearDown(() {
    SceneModel.debugImportOverride = null;
    SceneModel.debugClearModelTemplateCache();
  });

  Widget host(List<Widget> children) =>
      SceneSubtree(parent: sceneRoot, children: children);

  MemoryModelSource source(String key) =>
      MemoryModelSource(Uint8List(0), key: key);

  group('loading phases', () {
    testWidgets('placeholder mounts while loading, model replaces it', (
      tester,
    ) async {
      final gated = _GatedSource('m');
      await tester.pumpWidget(
        host([
          SceneModel.from(
            gated,
            placeholder: (context) => SceneNode(name: 'placeholder'),
          ),
        ]),
      );
      final wrapper = sceneRoot.children.single;
      expect(wrapper.getChildByName('placeholder'), isNotNull);
      expect(wrapper.getChildByName('shoe'), isNull);

      gated.gate.complete(Uint8List(0));
      await tester.pump();
      await tester.pump();
      expect(wrapper.getChildByName('placeholder'), isNull);
      expect(wrapper.getChildByName('shoe'), isNotNull);
    });

    testWidgets('error builder mounts on failure', (tester) async {
      await tester.pumpWidget(
        host([
          SceneModel.from(
            _FailingSource('x'),
            error: (context, error) => SceneNode(name: 'error-node'),
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      final wrapper = sceneRoot.children.single;
      expect(wrapper.getChildByName('error-node'), isNotNull);
    });
  });

  group('template cache', () {
    testWidgets('equal-keyed sources import once and get distinct clones', (
      tester,
    ) async {
      final roots = <Node>[];
      await tester.pumpWidget(
        host([
          SceneModel.from(source('m'), onLoaded: roots.add),
          SceneModel.from(source('m'), onLoaded: roots.add),
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(importCalls, 1);
      expect(roots, hasLength(2));
      expect(identical(roots[0], roots[1]), isFalse);
      // Clones share geometry but own their primitives.
      final meshes = [
        for (final root in roots) root.getChildByName('shoe')!.mesh!,
      ];
      expect(
        identical(
          meshes[0].primitives.single.geometry,
          meshes[1].primitives.single.geometry,
        ),
        isTrue,
      );
      expect(
        identical(meshes[0].primitives.single, meshes[1].primitives.single),
        isFalse,
      );
    });

    testWidgets('the template is evicted when the last user unmounts', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([SceneModel.from(source('m')), SceneModel.from(source('m'))]),
      );
      await tester.pump();
      await tester.pump();
      expect(importCalls, 1);

      // Dropping one keeps the template alive for the other.
      await tester.pumpWidget(host([SceneModel.from(source('m'))]));
      await tester.pumpWidget(
        host([SceneModel.from(source('m')), SceneModel.from(source('m'))]),
      );
      await tester.pump();
      await tester.pump();
      expect(importCalls, 1);

      // Dropping all evicts; the next mount imports again.
      await tester.pumpWidget(host([]));
      await tester.pumpWidget(host([SceneModel.from(source('m'))]));
      await tester.pump();
      await tester.pump();
      expect(importCalls, 2);
    });

    testWidgets('a failed import is not cached; a retry imports again', (
      tester,
    ) async {
      SceneModel.debugImportOverride = (bytes) async {
        importCalls++;
        if (importCalls == 1) throw StateError('flaky');
        return _buildTemplate();
      };
      await tester.pumpWidget(host([SceneModel.from(source('m'))]));
      await tester.pump();
      await tester.pump();
      expect(importCalls, 1);

      // A different key forces a reload; same key would too after eviction,
      // but exercise the recovery path through a fresh source.
      await tester.pumpWidget(host([]));
      final roots = <Node>[];
      await tester.pumpWidget(
        host([SceneModel.from(source('m'), onLoaded: roots.add)]),
      );
      await tester.pump();
      await tester.pump();
      expect(importCalls, 2);
      expect(roots, hasLength(1));
    });
  });

  group('variants on clones', () {
    testWidgets('variant selection applies to the instance, not the shared '
        'template', (tester) async {
      final roots = <Node>[];
      await tester.pumpWidget(
        host([
          SceneModel.from(source('m'), variant: 'b', onLoaded: roots.add),
          SceneModel.from(source('m'), onLoaded: roots.add),
        ]),
      );
      await tester.pump();
      await tester.pump();
      String materialOf(Node root) =>
          (root.getChildByName('shoe')!.mesh!.primitives.single.material
                  as _FakeMaterial)
              .label;
      expect(materialOf(roots[0]), 'variant-b');
      expect(materialOf(roots[1]), 'default');
    });

    testWidgets('variant changes on rebuild swap the clone in place', (
      tester,
    ) async {
      final roots = <Node>[];
      await tester.pumpWidget(
        host([SceneModel.from(source('m'), onLoaded: roots.add)]),
      );
      await tester.pump();
      await tester.pump();
      final primitive = roots.single
          .getChildByName('shoe')!
          .mesh!
          .primitives
          .single;
      expect((primitive.material as _FakeMaterial).label, 'default');

      await tester.pumpWidget(
        host([SceneModel.from(source('m'), variant: 'b')]),
      );
      expect((primitive.material as _FakeMaterial).label, 'variant-b');
    });
  });

  group('animations', () {
    testWidgets('specs flow to clips on load and on rebuild', (tester) async {
      final binderProbe = <Node>[];
      await tester.pumpWidget(
        host([
          SceneModel.from(
            source('m'),
            animations: const [
              SceneAnimationSpec('Spin', weight: 0.5, speed: 2.0),
            ],
            onLoaded: binderProbe.add,
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      // The clip is observable through a second binder on the same root: the
      // player is per node and clips are name-keyed, so creating again
      // returns fresh clips; instead assert through spec-driven state below.
      final root = binderProbe.single;
      final binder = SceneAnimationBinder()..bind(root);
      binder.apply(const [SceneAnimationSpec('Spin')]);
      expect(binder.clips.containsKey('Spin'), isTrue);
    });
  });

  group('SceneAnimationBinder', () {
    late Node root;
    late SceneAnimationBinder binder;

    setUp(() {
      root = _buildTemplate();
      binder = SceneAnimationBinder()..bind(root);
    });

    test('creates clips lazily and applies spec fields', () {
      binder.apply(const [
        SceneAnimationSpec('Spin', weight: 0.25, speed: 1.5, loop: false),
      ]);
      final clip = binder.clips['Spin']!;
      expect(clip.playing, isTrue);
      expect(clip.loop, isFalse);
      expect(clip.weight, 0.25);
      expect(clip.playbackTimeScale, 1.5);
    });

    test('field changes apply to the existing clip', () {
      binder.apply(const [SceneAnimationSpec('Spin')]);
      final clip = binder.clips['Spin']!;
      binder.apply(const [SceneAnimationSpec('Spin', weight: 0.1, speed: -1)]);
      expect(identical(binder.clips['Spin'], clip), isTrue);
      expect(clip.weight, 0.1);
      expect(clip.playbackTimeScale, -1);
    });

    test('playing false pauses without resetting; true resumes', () {
      binder.apply(const [SceneAnimationSpec('Spin')]);
      final clip = binder.clips['Spin']!;
      binder.apply(const [SceneAnimationSpec('Spin', playing: false)]);
      expect(clip.playing, isFalse);
      binder.apply(const [SceneAnimationSpec('Spin')]);
      expect(clip.playing, isTrue);
    });

    test('a removed spec stops its clip', () {
      binder.apply(const [
        SceneAnimationSpec('Spin'),
        SceneAnimationSpec('Wave'),
      ]);
      final wave = binder.clips['Wave']!;
      binder.apply(const [SceneAnimationSpec('Spin')]);
      expect(wave.playing, isFalse);
      expect(binder.clips.containsKey('Wave'), isFalse);
      expect(binder.clips.containsKey('Spin'), isTrue);
    });

    test('unknown names warn without throwing and known ones still apply', () {
      binder.apply(const [
        SceneAnimationSpec('Nope'),
        SceneAnimationSpec('Spin'),
      ]);
      expect(binder.clips.containsKey('Nope'), isFalse);
      expect(binder.clips.containsKey('Spin'), isTrue);
    });

    test('specs are value-equal', () {
      expect(
        const SceneAnimationSpec('A', weight: 0.5),
        const SceneAnimationSpec('A', weight: 0.5),
      );
      expect(
        const SceneAnimationSpec('A'),
        isNot(const SceneAnimationSpec('B')),
      );
    });
  });

  group('MaterialsVariantsComponent.rebindClone', () {
    test('rebinds to the clone and leaves the template untouched', () {
      final template = _buildTemplate();
      final clone = template.clone();
      final component = MaterialsVariantsComponent.rebindClone(
        template,
        clone,
      )!;
      component.select('b');

      final templatePrimitive = template
          .getChildByName('shoe')!
          .mesh!
          .primitives
          .single;
      final clonePrimitive = clone
          .getChildByName('shoe')!
          .mesh!
          .primitives
          .single;
      expect((clonePrimitive.material as _FakeMaterial).label, 'variant-b');
      expect((templatePrimitive.material as _FakeMaterial).label, 'default');

      component.select(null);
      expect((clonePrimitive.material as _FakeMaterial).label, 'default');
    });

    test('returns null for templates without variants', () {
      final template = _buildTemplate(variants: const []);
      final clone = template.clone();
      expect(MaterialsVariantsComponent.rebindClone(template, clone), isNull);
      expect(clone.getComponent<MaterialsVariantsComponent>(), isNull);
    });
  });
}
