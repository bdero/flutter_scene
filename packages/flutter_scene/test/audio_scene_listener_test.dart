// Covers which camera the audio listener follows when no AudioListener is
// mounted.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('follows the first on-screen view camera', () {
    final renderScene = RenderScene();
    expect(renderScene.listenerCamera, isNull);

    final offscreen = PerspectiveCamera(position: Vector3(1, 0, 0));
    final screen = PerspectiveCamera(position: Vector3(0, 10, 0));
    renderScene.recordRenderedViews([
      RenderView(camera: offscreen, target: RenderTexture(width: 4, height: 4)),
      RenderView(camera: screen),
    ]);
    expect(renderScene.listenerCamera, same(screen));

    // With only offscreen views, the first one stands in.
    renderScene.recordRenderedViews([
      RenderView(camera: offscreen, target: RenderTexture(width: 4, height: 4)),
    ]);
    expect(renderScene.listenerCamera, same(offscreen));
  });

  test('a scene camera wins over the rendered view camera', () {
    final renderScene = RenderScene();
    renderScene.recordRenderedViews([RenderView(camera: PerspectiveCamera())]);
    final explicit = PerspectiveCamera(position: Vector3(5, 0, 0));
    renderScene.cameraOverride = explicit;
    expect(renderScene.listenerCamera, same(explicit));
  });
}
