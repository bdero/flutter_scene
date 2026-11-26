// ScenePresentation.domCanvas mounts a canvas platform view on the web and is
// a no-op elsewhere. Rendering through it is covered by
// test/gpu/present_to_canvas_browser_test.dart.
//
// ignore_for_file: implementation_imports

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/widgets/scene_view_dom_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

Scene? _tryScene() {
  try {
    return Scene();
  } catch (_) {
    return null;
  }
}

Widget _sized(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: SizedBox(width: 200, height: 200, child: child)),
);

void main() {
  test('a DOM canvas is available only on the web', () {
    expect(sceneDomCanvasSupported, kIsWeb);
  });

  testWidgets('domCanvas mounts a canvas only on the web', (tester) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No GPU context');
      return;
    }
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          autoTick: false,
          webPresentation: ScenePresentation.domCanvas,
        ),
      ),
    );
    expect(
      find.byType(HtmlElementView),
      kIsWeb ? findsOneWidget : findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    scene.dispose();
  });

  testWidgets('flutterCanvas and viewsBuilder mount no canvas', (tester) async {
    final scene = _tryScene();
    if (scene == null) {
      markTestSkipped('No GPU context');
      return;
    }
    await tester.pumpWidget(_sized(SceneView(scene, autoTick: false)));
    expect(find.byType(HtmlElementView), findsNothing);
    await tester.pumpWidget(
      _sized(
        SceneView(
          scene,
          autoTick: false,
          webPresentation: ScenePresentation.domCanvas,
          viewsBuilder: (_) => [RenderView(camera: PerspectiveCamera())],
        ),
      ),
    );
    expect(find.byType(HtmlElementView), findsNothing);
    await tester.pumpWidget(const SizedBox());
    scene.dispose();
  });
}
