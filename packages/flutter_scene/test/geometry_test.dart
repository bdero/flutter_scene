// Geometry.primitiveType: default and round-trip. The render-pass
// wiring that consumes it (SceneEncoder, ShadowEncoder) draws to the
// GPU and is exercised by the example app rather than here.

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Geometry that skips shader-library and GPU access, so the base-class
/// state can be exercised without a Flutter GPU context.
class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

void main() {
  test('primitiveType defaults to a triangle list', () {
    expect(_StubGeometry().primitiveType, gpu.PrimitiveType.triangle);
  });

  test('primitiveType is mutable', () {
    final geometry = _StubGeometry()
      ..primitiveType = gpu.PrimitiveType.lineStrip;
    expect(geometry.primitiveType, gpu.PrimitiveType.lineStrip);
  });
}
