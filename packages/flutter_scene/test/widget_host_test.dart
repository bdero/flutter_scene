// Covers WidgetHost: mounting a scene's WidgetComponent subtrees outside a
// SceneView. Constructing a Scene needs a GPU context, so the mount, unmount,
// and zero-footprint checks also run against the hosting widget WidgetHost
// wraps, fed by a bare RenderScene, which needs none.

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/widgets/widget_component_host.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gpu_available.dart';

class _PanelA extends StatelessWidget {
  const _PanelA();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _PanelB extends StatelessWidget {
  const _PanelB();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

WidgetComponent _component(Widget child, Size size) =>
    WidgetComponent(child: child, size: size);

/// A loose Stack with a sized sibling, so the host's footprint shows up in
/// the Stack's size.
Widget _inStack(Key stackKey, Widget host) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: Stack(
      key: stackKey,
      children: [const SizedBox(width: 50, height: 40), host],
    ),
  ),
);

void main() {
  group('hosting widget (no GPU)', () {
    late RenderScene renderScene;
    late WidgetComponent a;
    late WidgetComponent b;

    setUp(() {
      renderScene = RenderScene();
      a = _component(const _PanelA(), const Size(200, 100));
      b = _component(const _PanelB(), const Size(80, 60));
      renderScene.addWidgetComponent(a);
      renderScene.addWidgetComponent(b);
    });

    Widget host() =>
        SizedBox.shrink(child: WidgetComponentHosts(renderScene: renderScene));

    testWidgets('mounts one subtree per component at its capture size', (
      tester,
    ) async {
      await tester.pumpWidget(_inStack(UniqueKey(), host()));

      expect(find.byType(_PanelA), findsOneWidget);
      expect(find.byType(_PanelB), findsOneWidget);
      expect(find.byType(WidgetTexture), findsNWidgets(2));
      expect(tester.getSize(find.byType(_PanelA)), const Size(200, 100));
      expect(tester.getSize(find.byType(_PanelB)), const Size(80, 60));
    });

    testWidgets('unmounts a subtree when its component leaves', (tester) async {
      await tester.pumpWidget(_inStack(UniqueKey(), host()));

      renderScene.removeWidgetComponent(b);
      await tester.pump();

      expect(find.byType(_PanelA), findsOneWidget);
      expect(find.byType(_PanelB), findsNothing);
      expect(find.byType(WidgetTexture), findsOneWidget);
    });

    testWidgets('mounts a subtree when a component arrives', (tester) async {
      renderScene.removeWidgetComponent(b);
      await tester.pumpWidget(_inStack(UniqueKey(), host()));
      expect(find.byType(_PanelB), findsNothing);

      renderScene.addWidgetComponent(b);
      await tester.pump();

      expect(find.byType(_PanelB), findsOneWidget);
    });

    testWidgets('takes no layout space inside a Stack', (tester) async {
      final stackKey = UniqueKey();
      await tester.pumpWidget(_inStack(stackKey, host()));

      expect(tester.getSize(find.byType(WidgetComponentHosts)), Size.zero);
      // The sized sibling alone decides the Stack's size.
      expect(tester.getSize(find.byKey(stackKey)), const Size(50, 40));
    });
  });

  group('WidgetHost', () {
    testWidgets('hosts a scene\'s components and follows removals', (
      tester,
    ) async {
      if (!gpuAvailable()) {
        markTestSkipped('No Impeller GPU context');
        return;
      }
      final scene = Scene();
      final a = _component(const _PanelA(), const Size(200, 100));
      final b = _component(const _PanelB(), const Size(80, 60));
      final nodeB = Node(name: 'b')..addComponent(b);
      scene.add(Node(name: 'a')..addComponent(a));
      scene.add(nodeB);

      final stackKey = UniqueKey();
      await tester.pumpWidget(_inStack(stackKey, WidgetHost(scene: scene)));

      expect(find.byType(_PanelA), findsOneWidget);
      expect(find.byType(_PanelB), findsOneWidget);
      expect(tester.getSize(find.byType(WidgetHost)), Size.zero);
      expect(tester.getSize(find.byKey(stackKey)), const Size(50, 40));

      scene.remove(nodeB);
      await tester.pump();

      expect(find.byType(_PanelA), findsOneWidget);
      expect(find.byType(_PanelB), findsNothing);
    });
  });
}
