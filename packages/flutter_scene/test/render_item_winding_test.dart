import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {}
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {}
}

void main() {
  test('render winding combines geometry source and node transform parity', () {
    final geometry = _StubGeometry();
    final item = RenderItem(geometry: geometry, material: _StubMaterial());

    item.refreshWinding(false);
    expect(item.windingFlipped, isFalse);

    geometry.sourceWindingFlipped = true;
    item.refreshWinding(false);
    expect(item.windingFlipped, isTrue);

    item.refreshWinding(true);
    expect(item.windingFlipped, isFalse);
  });

  test('selected geometry uses its own source winding', () {
    final baseGeometry = _StubGeometry();
    final selectedGeometry = _StubGeometry()..sourceWindingFlipped = true;
    final item = RenderItem(geometry: baseGeometry, material: _StubMaterial())
      ..refreshWinding(false);

    expect(item.windingFor(baseGeometry), isFalse);
    expect(item.windingFor(selectedGeometry), isTrue);

    baseGeometry.sourceWindingFlipped = true;
    selectedGeometry.sourceWindingFlipped = false;
    item.refreshWinding(false);

    expect(item.windingFor(baseGeometry), isTrue);
    expect(item.windingFor(selectedGeometry), isFalse);
  });
}
