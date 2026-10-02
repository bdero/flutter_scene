import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Animation, Matrix4;
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/animation.dart'
    show AnimationChannel, AnimationProperty, BindKey, PropertyResolver;
// ignore: implementation_imports
import 'package:flutter_scene/src/components/materials_variants_component.dart'
    show MaterialsVariantBinding;
// ignore: implementation_imports
import 'package:flutter_scene/src/widgets/declarative.dart'
    show SceneAnimationBinder, SceneModelLoadGate;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// SceneModel widget tests. Sources override [SceneModelSource.createNode]
/// to produce GPU-free hand-built node trees, so the full
/// load/template-cache/clone/variant/animation path runs headless.

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

/// Counts template imports across all fake sources, mirroring the shared
/// template cache's behavior.
int importCalls = 0;

/// A source that imports a hand-built template, keyed like an app source.
class _FakeSource extends SceneModelSource {
  _FakeSource(this.key, {Node Function()? buildTemplate})
    : _buildTemplate = buildTemplate ?? _buildDefaultTemplate;

  final String key;
  final Node Function() _buildTemplate;

  @override
  String get cacheKey => 'fake:$key';

  @override
  Future<Uint8List> load() async => Uint8List(0);

  @override
  Future<Node> createNode() async {
    importCalls++;
    return _buildTemplate();
  }
}

/// A source whose import completes on demand, to hold the widget in its
/// loading phase.
class _GatedSource extends _FakeSource {
  _GatedSource(super.key);
  final Completer<void> gate = Completer<void>();

  @override
  Future<Node> createNode() async {
    await gate.future;
    return super.createNode();
  }
}

class _FailingSource extends SceneModelSource {
  _FailingSource(this.key);
  final String key;

  @override
  String get cacheKey => 'failing:$key';

  @override
  Future<Uint8List> load() async => throw StateError('no bytes for $key');
}

/// A source that fails on the first import and succeeds after, for the
/// failed-imports-are-not-cached path.
class _FlakySource extends _FakeSource {
  _FlakySource(super.key);

  @override
  Future<Node> createNode() async {
    importCalls++;
    if (importCalls == 1) throw StateError('flaky');
    return _buildDefaultTemplate();
  }
}

/// Builds a template like the runtime importer would. A root carrying a
/// variants component, parsed animations, and a punctual light, over a child
/// with a mesh.
Node _buildDefaultTemplate({List<String> variants = const ['a', 'b']}) {
  final defaultMaterial = _FakeMaterial('default');
  final variantMaterial = _FakeMaterial('variant-b');
  final primitive = MeshPrimitive(_FakeGeometry(), defaultMaterial);
  final child = Node(name: 'shoe')
    ..mesh = Mesh.primitives(primitives: [primitive]);
  final light = Node(name: 'lamp')
    ..addComponent(PointLightComponent(PointLight(intensity: 3.0, range: 5.0)));
  final root = Node(name: 'root')
    ..add(child)
    ..add(light);
  if (variants.isNotEmpty) {
    root.addComponent(
      MaterialsVariantsComponent.internal(variants, [
        MaterialsVariantBinding(
          node: child,
          primitiveIndex: 0,
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

/// A spine chain whose bones are named [names] (hips first), standing on
/// Y, with an optional clip that bends the second bone.
Node _chainTemplate(List<String> names, {String? clipName}) {
  final root = Node(name: 'root');
  var parent = root;
  for (var i = 0; i < names.length; i++) {
    final bone = Node(
      name: names[i],
      localTransform: Matrix4.translationValues(0, i == 0 ? 1.0 : 0.2, 0),
    );
    parent.add(bone);
    parent = bone;
  }
  if (clipName != null) {
    final bend = Quaternion.axisAngle(Vector3(0, 0, 1), 0.8);
    root.addParsedAnimation(
      Animation(
        name: clipName,
        channels: [
          AnimationChannel(
            bindTarget: BindKey(
              nodeName: names[1],
              property: AnimationProperty.rotation,
            ),
            resolver: PropertyResolver.makeRotationTimeline(
              [0, 1],
              [bend, bend],
            ),
          ),
        ],
      ),
    );
  }
  return root;
}

const _libraryBones = ['Hips', 'Spine', 'Neck', 'Head'];
const _modelBones = ['pelvis', 'spine', 'neck', 'head'];

void main() {
  late Node sceneRoot;

  setUp(() {
    sceneRoot = Node(name: 'scene-root');
    importCalls = 0;
    SceneModel.debugClearModelTemplateCache();
  });

  tearDown(SceneModel.debugClearModelTemplateCache);

  Widget host(List<Widget> children) =>
      SceneSubtree(parent: sceneRoot, children: children);

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

      gated.gate.complete();
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
          SceneModel.from(_FakeSource('m'), onLoaded: roots.add),
          SceneModel.from(_FakeSource('m'), onLoaded: roots.add),
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

    testWidgets('clones carry importer-attached components', (tester) async {
      final roots = <Node>[];
      await tester.pumpWidget(
        host([SceneModel.from(_FakeSource('m'), onLoaded: roots.add)]),
      );
      await tester.pump();
      await tester.pump();
      final lamp = roots.single.getChildByName('lamp')!;
      final component = lamp.getComponent<PointLightComponent>();
      expect(component, isNotNull);
      expect(component!.light.intensity, 3.0);
    });

    testWidgets('the template is evicted when the last user unmounts', (
      tester,
    ) async {
      await tester.pumpWidget(
        host([
          SceneModel.from(_FakeSource('m')),
          SceneModel.from(_FakeSource('m')),
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(importCalls, 1);

      // Dropping one keeps the template alive for the other.
      await tester.pumpWidget(host([SceneModel.from(_FakeSource('m'))]));
      await tester.pumpWidget(
        host([
          SceneModel.from(_FakeSource('m')),
          SceneModel.from(_FakeSource('m')),
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(importCalls, 1);

      // Dropping all evicts; the next mount imports again.
      await tester.pumpWidget(host([]));
      await tester.pumpWidget(host([SceneModel.from(_FakeSource('m'))]));
      await tester.pump();
      await tester.pump();
      expect(importCalls, 2);
    });

    testWidgets('a failed import is not cached; a retry imports again', (
      tester,
    ) async {
      await tester.pumpWidget(host([SceneModel.from(_FlakySource('m'))]));
      await tester.pump();
      await tester.pump();
      expect(importCalls, 1);

      await tester.pumpWidget(host([]));
      final roots = <Node>[];
      await tester.pumpWidget(
        host([SceneModel.from(_FlakySource('m'), onLoaded: roots.add)]),
      );
      await tester.pump();
      await tester.pump();
      expect(importCalls, 2);
      expect(roots, hasLength(1));
    });

    testWidgets(
      'a stale holder releasing after a hot-reload evict+reacquire does not '
      'evict the replacement entry',
      (tester) async {
        const keyA = ValueKey('a');
        const keyB = ValueKey('b');
        const keyC = ValueKey('c');

        // A's load is held open on the gate, so it is still the sole holder
        // of the original cache entry when that entry is evicted below.
        final gated = _GatedSource('shared');
        await tester.pumpWidget(host([SceneModel.from(gated, key: keyA)]));
        await tester.pump();

        // Simulate the hot-reload path (evict the cache key, independent of
        // any live holder) without the asset-bundle machinery it normally
        // runs through.
        SceneModel.debugEvictModelTemplateCache(gated.cacheKey);

        // A's load resolves after the evict, against the entry it originally
        // acquired (the cache holds no entry, and later a different one,
        // under the same key by then).
        gated.gate.complete();
        await tester.pump();
        await tester.pump();
        expect(importCalls, 1);

        // B acquires under the same key post-evict: a fresh entry, a second
        // import.
        await tester.pumpWidget(
          host([
            SceneModel.from(gated, key: keyA),
            SceneModel.from(_FakeSource('shared'), key: keyB),
          ]),
        );
        await tester.pump();
        await tester.pump();
        expect(importCalls, 2);

        // A unmounts and releases the lease it acquired before the evict.
        // With the bug, that release decrements (and, at refcount zero,
        // evicts) whatever entry currently sits under "shared" -- B's --
        // even though A never held a reference to it.
        await tester.pumpWidget(
          host([SceneModel.from(_FakeSource('shared'), key: keyB)]),
        );
        await tester.pump();
        await tester.pump();

        // C mounts under the same key while B is still live. If A's stale
        // release wrongly tore down B's entry, the cache is empty and C
        // re-imports; with the fix B's entry is untouched and C reuses it.
        await tester.pumpWidget(
          host([
            SceneModel.from(_FakeSource('shared'), key: keyB),
            SceneModel.from(_FakeSource('shared'), key: keyC),
          ]),
        );
        await tester.pump();
        await tester.pump();
        expect(importCalls, 2);
      },
    );

    testWidgets(
      'a throw after the lease handoff (an onLoaded callback) does not '
      'double-release the shared template entry',
      (tester) async {
        const keyA = ValueKey('a');
        const keyB = ValueKey('b');
        const keyC = ValueKey('c');

        // A's onLoaded throws after the lease was handed to the widget; B
        // shares the entry. A's load lands in the catch branch holding a
        // lease that dispose will also release.
        await tester.pumpWidget(
          host([
            SceneModel.from(
              _FakeSource('shared'),
              key: keyA,
              onLoaded: (_) => throw StateError('onLoaded'),
            ),
            SceneModel.from(_FakeSource('shared'), key: keyB),
          ]),
        );
        await tester.pump();
        await tester.pump();
        expect(importCalls, 1);

        // A unmounts and releases its held lease. A second release from the
        // catch branch would have already decremented the shared refcount,
        // so this one would hit zero and evict the entry B still uses.
        await tester.pumpWidget(
          host([SceneModel.from(_FakeSource('shared'), key: keyB)]),
        );
        await tester.pump();

        // C mounts under the same key while B is live. If the entry was
        // wrongly evicted, C re-imports; otherwise it reuses B's entry.
        await tester.pumpWidget(
          host([
            SceneModel.from(_FakeSource('shared'), key: keyB),
            SceneModel.from(_FakeSource('shared'), key: keyC),
          ]),
        );
        await tester.pump();
        await tester.pump();
        expect(importCalls, 1);
      },
    );
  });

  group('variants on clones', () {
    testWidgets('variant selection applies to the instance, not the shared '
        'template', (tester) async {
      final roots = <Node>[];
      await tester.pumpWidget(
        host([
          SceneModel.from(_FakeSource('m'), variant: 'b', onLoaded: roots.add),
          SceneModel.from(_FakeSource('m'), onLoaded: roots.add),
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
        host([SceneModel.from(_FakeSource('m'), onLoaded: roots.add)]),
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
        host([SceneModel.from(_FakeSource('m'), variant: 'b')]),
      );
      expect((primitive.material as _FakeMaterial).label, 'variant-b');
    });
  });

  group('animations', () {
    testWidgets('specs flow to clips on load', (tester) async {
      final roots = <Node>[];
      await tester.pumpWidget(
        host([
          SceneModel.from(
            _FakeSource('m'),
            animations: const [
              SceneAnimationSpec('Spin', weight: 0.5, speed: 2.0),
            ],
            onLoaded: roots.add,
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      final binder = SceneAnimationBinder()..bind(roots.single);
      binder.apply(const [SceneAnimationSpec('Spin')]);
      expect(binder.clips.containsKey('Spin'), isTrue);
    });
  });

  group('animation source', () {
    testWidgets('plays a library clip retargeted onto the model', (
      tester,
    ) async {
      final roots = <Node>[];
      await tester.pumpWidget(
        host([
          SceneModel.from(
            _FakeSource(
              'dancer',
              buildTemplate: () => _chainTemplate(_modelBones),
            ),
            animationSource: _FakeSource(
              'moves',
              buildTemplate: () =>
                  _chainTemplate(_libraryBones, clipName: 'Walk'),
            ),
            animations: const [SceneAnimationSpec('Walk')],
            onLoaded: roots.add,
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      final spine = roots.single.getChildByName('spine')!;
      final rest = spine.localTransform.clone();
      sceneRoot.scenePrePass(0.5);
      expect(spine.localTransform, isNot(rest));
    });
  });

  group('component lifecycle', () {
    testWidgets('a stable component survives unmount and remount', (
      tester,
    ) async {
      final spin = _CountingComponent();
      Widget build(bool show) => host([
        if (show) SceneNode(name: 'n', components: [spin]),
      ]);

      await tester.pumpWidget(build(true));
      expect(spin.attaches, 1);
      expect(spin.isAttached, isTrue);

      // Unmounting detaches the component (running onDetach cleanup)...
      await tester.pumpWidget(build(false));
      expect(spin.detaches, 1);
      expect(spin.isAttached, isFalse);

      // ...so the same instance can attach again on the next mount.
      await tester.pumpWidget(build(true));
      expect(spin.attaches, 2);
      expect(
        sceneRoot.children.single.getComponent<_CountingComponent>(),
        spin,
      );
    });
  });

  group('SceneAnimationBinder', () {
    late Node root;
    late SceneAnimationBinder binder;

    setUp(() {
      root = _buildDefaultTemplate();
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

    test('a removed spec stops its clip and unregisters it', () {
      binder.apply(const [
        SceneAnimationSpec('Spin'),
        SceneAnimationSpec('Wave'),
      ]);
      final wave = binder.clips['Wave']!;
      binder.apply(const [SceneAnimationSpec('Spin')]);
      expect(wave.playing, isFalse);
      expect(binder.clips.containsKey('Wave'), isFalse);
      expect(binder.clips.containsKey('Spin'), isTrue);
      // Re-adding creates a fresh registration rather than resurrecting the
      // stopped clip.
      binder.apply(const [
        SceneAnimationSpec('Spin'),
        SceneAnimationSpec('Wave'),
      ]);
      expect(identical(binder.clips['Wave'], wave), isFalse);
    });

    test('unknown names warn without throwing and known ones still apply', () {
      binder.apply(const [
        SceneAnimationSpec('Nope'),
        SceneAnimationSpec('Spin'),
      ]);
      expect(binder.clips.containsKey('Nope'), isFalse);
      expect(binder.clips.containsKey('Spin'), isTrue);
    });

    test('names the model lacks come from the library, retargeted', () {
      final model = _chainTemplate(_modelBones);
      final library = _chainTemplate(_libraryBones, clipName: 'Walk');
      binder
        ..bind(model)
        ..setLibrary(library)
        ..apply(const [SceneAnimationSpec('Walk')]);
      expect(binder.clips.containsKey('Walk'), isTrue);
      final spine = model.getChildByName('spine')!;
      final rest = spine.localTransform.clone();
      model.scenePrePass(0.5);
      expect(spine.localTransform, isNot(rest));
    });

    test('a name the model has itself wins over the library', () {
      // The model's own Walk is empty; the library's would bend the spine.
      final model = _chainTemplate(_modelBones)
        ..addParsedAnimation(Animation(name: 'Walk'));
      binder
        ..bind(model)
        ..setLibrary(_chainTemplate(_libraryBones, clipName: 'Walk'))
        ..apply(const [SceneAnimationSpec('Walk')]);
      final spine = model.getChildByName('spine')!;
      final rest = spine.localTransform.clone();
      model.scenePrePass(0.5);
      expect(spine.localTransform, rest);
    });

    test('dropping the library removes the clips it supplied', () {
      final model = _chainTemplate(_modelBones);
      binder
        ..bind(model)
        ..setLibrary(_chainTemplate(_libraryBones, clipName: 'Walk'))
        ..apply(const [SceneAnimationSpec('Walk')]);
      final walk = binder.clips['Walk']!;
      binder.setLibrary(null);
      expect(binder.clips.containsKey('Walk'), isFalse);
      expect(walk.playing, isFalse);
      binder.apply(const [SceneAnimationSpec('Walk')]);
      expect(binder.clips.containsKey('Walk'), isFalse);
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

  group('SceneModelLoadGate', () {
    test(
      'settle only resolves the gate for the generation that is current',
      () async {
        final group = ResourceGroup();
        final gate = SceneModelLoadGate();
        gate.register(group, alreadySettled: false);

        // Generation 1 (a source change's superseded first load) resolving
        // after the widget has already moved on to generation 2 must not
        // settle the gate on generation 2's behalf.
        gate.settle(1, 2);
        await Future<void>.value();
        expect(group.isReady, isFalse);

        // The generation that is actually current settles it.
        gate.settle(2, 2);
        await Future<void>.value();
        expect(group.isReady, isTrue);
      },
    );

    test('forceSettle resolves the gate regardless of generation', () async {
      final group = ResourceGroup();
      final gate = SceneModelLoadGate();
      gate.register(group, alreadySettled: false);

      gate.forceSettle();
      await Future<void>.value();
      expect(group.isReady, isTrue);
    });

    test('register only arms once; later calls (and groups) are ignored', () {
      final first = ResourceGroup();
      final second = ResourceGroup();
      final gate = SceneModelLoadGate();

      gate.register(first, alreadySettled: false);
      gate.register(second, alreadySettled: false);

      expect(first.total, 1);
      expect(second.total, 0);
    });

    test('a null group is a safe no-op throughout', () {
      final gate = SceneModelLoadGate();
      expect(() => gate.register(null, alreadySettled: false), returnsNormally);
      expect(() => gate.settle(1, 1), returnsNormally);
      expect(() => gate.forceSettle(), returnsNormally);
    });

    test('alreadySettled registers a pre-completed load', () async {
      final group = ResourceGroup();
      final gate = SceneModelLoadGate();
      gate.register(group, alreadySettled: true);
      await Future<void>.value();
      expect(group.isReady, isTrue);
    });
  });

  group('MaterialsVariantsComponent.rebindClone', () {
    test('rebinds to the clone and leaves the template untouched', () {
      final template = _buildDefaultTemplate();
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
      final template = _buildDefaultTemplate(variants: const []);
      final clone = template.clone();
      expect(MaterialsVariantsComponent.rebindClone(template, clone), isNull);
      expect(clone.getComponent<MaterialsVariantsComponent>(), isNull);
    });
  });
}

class _CountingComponent extends Component {
  int attaches = 0;
  int detaches = 0;

  @override
  void onAttach() => attaches++;

  @override
  void onDetach() => detaches++;
}
