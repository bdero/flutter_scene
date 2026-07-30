// Covers .fscene render-target serialization: the renderTexture resource
// kind and views array (JSON round-trip, GPU-free), and realizing views
// into a live Scene plus serializing them back (GPU-gated, Scene
// construction reads backend capabilities).

import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/realize/stage.dart';
import 'package:flutter_scene/src/fscene/realize/views.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

// Builds: world (root) -> eye (camera), plus a render texture targeted by
// a view from the eye.
SceneDocument _documentWithView() {
  final doc = SceneDocument();
  final world = doc.createNode(name: 'world', root: true);
  final eye = doc.createNode(
    name: 'eye',
    components: [
      ComponentSpec(
        'camera',
        properties: {'fovRadiansY': const DoubleValue(1.2)},
      ),
    ],
  );
  world.children.add(eye.id);

  final target = doc.addResource(
    RenderTextureResource(
      doc.newId(),
      width: 64,
      height: 32,
      update: 'interval',
      intervalMilliseconds: 250,
      filter: 'nearest',
      wrap: 'repeat',
    ),
  );
  doc.views.add(
    RenderViewSpec(
      cameraNode: eye.id,
      target: target.id,
      layerMask: 0x3,
      order: -1,
      antiAliasingMode: 'fxaa',
      renderScale: 0.5,
      filterQuality: 'none',
    ),
  );
  return doc;
}

void main() {
  test('render texture resources and views round-trip through JSON', () {
    final doc = _documentWithView();
    doc.stage.antiAliasingMode = 'msaa';
    doc.stage.renderScale = 1.5;
    doc.stage.filterQuality = 'high';

    final restored = readFscene(writeFscene(doc));

    final target = restored.resources.values
        .whereType<RenderTextureResource>()
        .single;
    expect(target.width, 64);
    expect(target.height, 32);
    expect(target.update, 'interval');
    expect(target.intervalMilliseconds, 250);
    expect(target.filter, 'nearest');
    expect(target.wrap, 'repeat');

    final view = restored.views.single;
    expect(view.target, target.id);
    expect(view.layerMask, 0x3);
    expect(view.order, -1);
    expect(view.antiAliasingMode, 'fxaa');
    expect(view.renderScale, 0.5);
    expect(view.filterQuality, 'none');

    expect(restored.stage.antiAliasingMode, 'msaa');
    expect(restored.stage.renderScale, 1.5);
    expect(restored.stage.filterQuality, 'high');
  });

  if (!_gpuAvailable()) {
    test(
      'render view realize suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('views realize into the scene and serialize back', () {
    final doc = _documentWithView();
    final root = realizeScene(doc);
    final scene = Scene();
    scene.add(root);
    realizeViews(doc, scene, root);

    final view = scene.views.single;
    expect(view.camera, isA<NodeCamera>());
    expect((view.camera as NodeCamera).node.name, 'eye');
    expect(view.layerMask, 0x3);
    expect(view.order, -1);
    expect(view.antiAliasingMode, AntiAliasingMode.fxaa);
    expect(view.renderScale, 0.5);

    final target = view.target!;
    expect(target.width, 64);
    expect(target.height, 32);
    expect(target.update.kindName, 'interval');
    expect(target.update.intervalDuration, const Duration(milliseconds: 250));
    expect(target.sampling.filter.name, 'nearest');

    // The producing view and a material sampling the same resource id
    // share one live handle.
    final rtId = doc.resources.values
        .whereType<RenderTextureResource>()
        .single
        .id;
    expect(realizeRenderTexture(doc, rtId), same(target));

    // Round-trip: serialize the graph, stage, and views into a new
    // document, and confirm the view's wiring survives.
    final back = serializeScene(root);
    serializeStage(scene, back);
    serializeViews(scene, back);

    final restoredView = back.views.single;
    expect(back.node(restoredView.cameraNode)!.name, 'eye');
    expect(restoredView.antiAliasingMode, 'fxaa');
    expect(restoredView.renderScale, 0.5);
    final restoredTarget =
        back.resource(restoredView.target!)! as RenderTextureResource;
    expect(restoredTarget.width, 64);
    expect(restoredTarget.update, 'interval');
    expect(restoredTarget.intervalMilliseconds, 250);
    expect(restoredTarget.filter, 'nearest');
    expect(back.featuresUsed, contains('renderTextures'));
  });

  test('a hand-built scene with views serializes camera and target', () {
    final scene = Scene();
    final cameraNode = Node()..name = 'cam';
    final component = CameraComponent();
    cameraNode.addComponent(component);
    scene.add(cameraNode);

    final target = RenderTexture(width: 16, height: 16);
    scene.views.add(RenderView(camera: component.toCamera(), target: target));

    final doc = serializeScene(scene.root);
    serializeViews(scene, doc);

    final view = doc.views.single;
    expect(doc.node(view.cameraNode)!.name, 'cam');
    final spec = doc.resource(view.target!)! as RenderTextureResource;
    expect(spec.width, 16);
    expect(spec.update, 'everyFrame');
  });
}
