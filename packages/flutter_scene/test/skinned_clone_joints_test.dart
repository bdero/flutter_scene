// Regression test for cloned skinned meshes rendering as a single body.
// Clones share one skinned geometry, so per-frame joint state must ride
// the render items and be applied to the geometry per draw; writing it
// into the shared geometry during the pre-pass made every clone draw the
// last-updated skeleton (at that skeleton's position, since skinned draws
// use an identity model transform). GPU-gated like the other render
// suites, since joints textures are real GPU textures.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_scene.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

/// Records every [setJointsTexture] call so the test can assert which
/// skeleton each draw would bind.
class _RecordingGeometry extends Geometry {
  final List<(gpu.Texture?, int)> jointsCalls = [];

  @override
  void setJointsTexture(gpu.Texture? texture, int width) {
    jointsCalls.add((texture, width));
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) => throw UnsupportedError('Stub geometry is not renderable');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('Stub material is not renderable');
}

/// A node with a mesh, a one-joint skin, and the joint as a child, so
/// [Node.clone] re-binds each clone's skin to its own joint.
Node _skinnedTemplate(Geometry geometry) {
  final joint = Node(name: 'joint');
  final template = Node(mesh: Mesh(geometry, _StubMaterial()));
  template.add(joint);
  template.skin = Skin()
    ..joints.add(joint)
    ..inverseBindMatrices.add(Matrix4.identity());
  return template;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gpuAvailable = _gpuAvailable();

  RenderItem itemOf(RenderScene renderScene, Node node) =>
      renderScene.items.singleWhere((item) => identical(item.sourceNode, node));

  test('cloned skinned nodes carry their own joints textures', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);

    final geometry = _RecordingGeometry();
    final template = _skinnedTemplate(geometry);
    final a = template.clone();
    final b = template.clone();
    root.add(a);
    root.add(b);
    root.scenePrePass(0.0);

    final itemA = itemOf(renderScene, a);
    final itemB = itemOf(renderScene, b);

    // The geometry (the heavy GPU resource) stays shared across clones...
    expect(itemA.geometry, same(geometry));
    expect(itemB.geometry, same(geometry));
    // ...so per-skeleton state must not be written into it by the pre-pass.
    expect(geometry.jointsCalls, isEmpty);

    // Each clone's item carries its own skin's texture.
    expect(itemA.jointsTexture, isNotNull);
    expect(itemB.jointsTexture, isNotNull);
    expect(itemA.jointsTexture, isNot(same(itemB.jointsTexture)));
    expect(itemA.jointsTextureWidth, greaterThan(0));
  }, skip: gpuAvailable ? false : 'no GPU context in this environment');

  test('applyJointsTexture binds each item\'s own skeleton per draw', () {
    final renderScene = RenderScene();
    final root = Node()..debugMountInto(renderScene);

    final geometry = _RecordingGeometry();
    final template = _skinnedTemplate(geometry);
    final a = template.clone();
    final b = template.clone();
    root.add(a);
    root.add(b);
    root.scenePrePass(0.0);

    final itemA = itemOf(renderScene, a);
    final itemB = itemOf(renderScene, b);

    // The render passes call this immediately before each draw's bind.
    itemA.applyJointsTexture(geometry);
    itemB.applyJointsTexture(geometry);
    expect(geometry.jointsCalls, [
      (itemA.jointsTexture, itemA.jointsTextureWidth),
      (itemB.jointsTexture, itemB.jointsTextureWidth),
    ]);
  }, skip: gpuAvailable ? false : 'no GPU context in this environment');

  test('applyJointsTexture is a no-op for unskinned items', () {
    final geometry = _RecordingGeometry();
    final item = RenderItem(geometry: geometry, material: _StubMaterial());
    item.applyJointsTexture(geometry);
    expect(geometry.jointsCalls, isEmpty);
  });
}
