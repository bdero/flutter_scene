import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// The matrix WebXR's XRView.projectionMatrix carries: OpenGL clip space, so
// clip w is -z and depth runs -1..1, built from four edge tangents the way a
// headset lens states them.
Matrix4 glProjection({
  required double tanLeft,
  required double tanRight,
  required double tanDown,
  required double tanUp,
  required double near,
  required double far,
}) {
  final width = tanRight - tanLeft;
  final height = tanUp - tanDown;
  return Matrix4(
    2.0 / width,
    0.0,
    0.0,
    0.0,
    0.0,
    2.0 / height,
    0.0,
    0.0,
    (tanRight + tanLeft) / width,
    (tanUp + tanDown) / height,
    -(far + near) / (far - near),
    -1.0,
    0.0,
    0.0,
    -2.0 * far * near / (far - near),
    0.0,
  );
}

void main() {
  // A Quest-like left eye, wider on the outside (left) than the inside.
  final left = math.tan(-50 * degrees2Radians);
  final right = math.tan(40 * degrees2Radians);
  final down = math.tan(-48 * degrees2Radians);
  final up = math.tan(46 * degrees2Radians);
  const near = 0.1;
  const far = 1000.0;
  final matrix = glProjection(
    tanLeft: left,
    tanRight: right,
    tanDown: down,
    tanUp: up,
    near: near,
    far: far,
  );

  test('OffAxisProjection.fromMatrix recovers a WebXR lens', () {
    final projection = OffAxisProjection.fromMatrix(matrix);
    expect(projection.tanLeft, closeTo(left, 1e-6));
    expect(projection.tanRight, closeTo(right, 1e-6));
    expect(projection.tanDown, closeTo(down, 1e-6));
    expect(projection.tanUp, closeTo(up, 1e-6));
    expect(projection.near, closeTo(near, 1e-6));
    // The matrix is float32, and far is recovered from the tiny difference
    // between two depth terms, so only a relative check is meaningful.
    expect(projection.far, closeTo(far, far * 1e-3));
  });

  test('the recovered lens projects a point where the GL matrix did', () {
    final projection = OffAxisProjection.fromMatrix(matrix);
    // The engine's view space looks down +z, GL's down -z.
    final engine = projection.getProjectionMatrix(1.0);
    final glPoint = Vector4(0.7, -0.4, -5.0, 1.0);
    final enginePoint = Vector4(0.7, -0.4, 5.0, 1.0);
    final glClip = matrix.transform(glPoint);
    final engineClip = engine.transform(enginePoint);
    expect(engineClip.x / engineClip.w, closeTo(glClip.x / glClip.w, 1e-6));
    expect(engineClip.y / engineClip.w, closeTo(glClip.y / glClip.w, 1e-6));
  });

  test('XrView.setProjectionFromMatrix rewrites the held projection', () {
    final view = XrView(eye: XrEye.left);
    final held = view.projection;
    view.setProjectionFromMatrix(matrix);
    expect(identical(view.projection, held), isTrue);
    expect(held.tanLeft, closeTo(left, 1e-6));
    expect(held.tanUp, closeTo(up, 1e-6));
    expect(held.near, closeTo(near, 1e-6));
  });

  test('an infinite far plane decodes as infinity', () {
    final infinite = glProjection(
      tanLeft: left,
      tanRight: right,
      tanDown: down,
      tanUp: up,
      near: near,
      far: 1e12,
    );
    // Snap the depth terms to the exact infinite-far form.
    infinite.setEntry(2, 2, -1.0);
    infinite.setEntry(2, 3, -2.0 * near);
    final projection = OffAxisProjection.fromMatrix(infinite);
    expect(projection.far, double.infinity);
    expect(projection.near, closeTo(near, 1e-6));
  });
}
