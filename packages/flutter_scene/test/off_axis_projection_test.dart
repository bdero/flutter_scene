import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/camera.dart'
    show buildRasterProjectionMatrix, lookAtViewMatrix;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A camera at the origin looking down -Z with +Y up, so view space is world
// space with the look direction mapped to the engine's +z view depth.
class _FixedCamera extends Camera {
  _FixedCamera(this.projection);

  @override
  final CameraProjection projection;

  @override
  Vector3 get position => Vector3.zero();

  @override
  Vector3 get forward => Vector3(0, 0, -1);

  @override
  Vector3 get up => Vector3(0, 1, 0);

  @override
  Matrix4 getViewMatrix() =>
      lookAtViewMatrix(Vector3.zero(), Vector3(0, 0, -1), Vector3(0, 1, 0));
}

Matcher _closeToMatrix(Matrix4 expected, {double epsilon = 1e-6}) =>
    predicate<Matrix4>((actual) {
      for (var i = 0; i < 16; i++) {
        if ((actual.storage[i] - expected.storage[i]).abs() > epsilon) {
          return false;
        }
      }
      return true;
    }, 'matches $expected');

void main() {
  group('OffAxisProjection', () {
    test('the symmetric frustum equals PerspectiveProjection', () {
      const fov = 70 * degrees2Radians;
      const aspect = 1.6;
      final perspective = PerspectiveProjection(
        fovRadiansY: fov,
        near: 0.25,
        far: 400,
      );
      final offAxis = OffAxisProjection.symmetric(
        fovRadiansY: fov,
        aspectRatio: aspect,
        near: 0.25,
        far: 400,
      );
      expect(
        offAxis.getProjectionMatrix(aspect),
        _closeToMatrix(perspective.getProjectionMatrix(aspect)),
      );
      expect(offAxis.fovRadiansY, closeTo(fov, 1e-12));
      expect(offAxis.aspectRatio, closeTo(aspect, 1e-12));
      // The tangents fix the shape; the aspect argument changes nothing.
      expect(
        offAxis.getProjectionMatrix(0.5),
        _closeToMatrix(offAxis.getProjectionMatrix(aspect)),
      );
    });

    test('an asymmetric frustum puts its edges where the tangents say', () {
      final projection = OffAxisProjection(
        tanLeft: -0.4,
        tanRight: 1.2,
        tanDown: -0.9,
        tanUp: 0.3,
        near: 0.1,
        far: 100,
      );
      final camera = _FixedCamera(projection);
      const size = ui.Size(200, 100);
      // Points on each frustum edge ten units ahead land on the matching
      // screen edge, so the view axis is off centre in the image. Built from
      // the camera's own basis so the test does not assume which world axis
      // is screen right.
      final ahead = camera.forward * 10.0;
      final right = camera.right;
      final up = camera.up;
      final uvRight = camera.projectToScreenUv(ahead + right * 12.0, size)!;
      final uvLeft = camera.projectToScreenUv(ahead - right * 4.0, size)!;
      final uvTop = camera.projectToScreenUv(ahead + up * 3.0, size)!;
      final uvBottom = camera.projectToScreenUv(ahead - up * 9.0, size)!;
      expect(uvRight.x, closeTo(1.0, 1e-6));
      expect(uvLeft.x, closeTo(0.0, 1e-6));
      expect(uvTop.y, closeTo(0.0, 1e-6));
      expect(uvBottom.y, closeTo(1.0, 1e-6));
      // The axis itself is a quarter of the way across and three quarters
      // down, not the centre.
      final axis = camera.projectToScreenUv(ahead, size)!;
      expect(axis.x, closeTo(0.4 / 1.6, 1e-6));
      expect(axis.y, closeTo(1.0 - 0.9 / 1.2, 1e-6));
      // Unprojecting the top-right screen corner returns a ray along the
      // frustum's top-right edge.
      final ray = camera.screenPointToRay(const ui.Offset(200, 0), size);
      final dir = ray.direction.normalized();
      final depth = dir.dot(camera.forward);
      expect(dir.dot(right) / depth, closeTo(1.2, 1e-6));
      expect(dir.dot(up) / depth, closeTo(0.3, 1e-6));
    });

    test('fromAngles takes XrFovf-style half angles', () {
      final projection = OffAxisProjection.fromAngles(
        left: -0.8,
        right: 0.7,
        down: -0.6,
        up: 0.6,
      );
      expect(projection.tanLeft, closeTo(math.tan(-0.8), 1e-12));
      expect(projection.tanRight, closeTo(math.tan(0.7), 1e-12));
      expect(projection.tanDown, closeTo(math.tan(-0.6), 1e-12));
      expect(projection.tanUp, closeTo(math.tan(0.6), 1e-12));
    });

    test('fromMatrix reads the engine convention back', () {
      final original = OffAxisProjection(
        tanLeft: -0.35,
        tanRight: 0.95,
        tanDown: -0.7,
        tanUp: 0.5,
        near: 0.2,
        far: 250,
      );
      final decoded = OffAxisProjection.fromMatrix(
        original.getProjectionMatrix(1.0),
      );
      expect(decoded.tanLeft, closeTo(-0.35, 1e-6));
      expect(decoded.tanRight, closeTo(0.95, 1e-6));
      expect(decoded.tanDown, closeTo(-0.7, 1e-6));
      expect(decoded.tanUp, closeTo(0.5, 1e-6));
      expect(decoded.near, closeTo(0.2, 1e-6));
      // The far plane decodes from two float32 terms, so it is good to
      // about one part in ten thousand.
      expect(decoded.far, closeTo(250, 0.05));
      final infinite = OffAxisProjection.fromMatrix(
        OffAxisProjection.symmetric(
          far: double.infinity,
        ).getProjectionMatrix(1.0),
      );
      expect(infinite.far, double.infinity);
    });

    test('fromMatrix reads an OpenGL frustum matrix back', () {
      // The convention WebXR's XRView.projectionMatrix uses, built by
      // vector_math's OpenGL frustum.
      const near = 0.1;
      const far = 1000.0;
      final gl = makeFrustumMatrix(
        -0.4 * near,
        1.2 * near,
        -0.9 * near,
        0.3 * near,
        near,
        far,
      );
      final decoded = OffAxisProjection.fromMatrix(gl);
      expect(decoded.tanLeft, closeTo(-0.4, 1e-6));
      expect(decoded.tanRight, closeTo(1.2, 1e-6));
      expect(decoded.tanDown, closeTo(-0.9, 1e-6));
      expect(decoded.tanUp, closeTo(0.3, 1e-6));
      expect(decoded.near, closeTo(near, 1e-6));
      expect(decoded.far, closeTo(far, 0.5));
      // A caller who knows better can replace the decoded planes.
      final overridden = OffAxisProjection.fromMatrix(gl, near: 0.05, far: 50);
      expect(overridden.near, 0.05);
      expect(overridden.far, 50);
    });

    test('fromMatrix rejects a parallel projection', () {
      final ortho = OrthographicProjection().getProjectionMatrix(1.0);
      expect(() => OffAxisProjection.fromMatrix(ortho), throwsArgumentError);
    });

    test('the raster projection honors near fitting and reversed depth', () {
      final projection = OffAxisProjection(
        tanLeft: -0.5,
        tanRight: 0.5,
        tanDown: -0.5,
        tanUp: 0.5,
        near: 0.1,
        far: 100,
      );
      const size = ui.Size(100, 100);
      final fitted = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: false,
        near: 2.0,
      )!;
      // Depth 0 now sits at the fitted plane, not the authored one.
      final atFitted = fitted.transform(Vector4(0, 0, 2.0, 1));
      expect(atFitted.z / atFitted.w, closeTo(0.0, 1e-6));
      final reversed = buildRasterProjectionMatrix(
        projection,
        size,
        reversed: true,
      )!;
      final atNear = reversed.transform(Vector4(0, 0, 0.1, 1));
      final atFar = reversed.transform(Vector4(0, 0, 100, 1));
      expect(atNear.z / atNear.w, closeTo(1.0, 1e-6));
      expect(atFar.z / atFar.w, closeTo(0.0, 1e-6));
    });

    test('ProjectionParams reads the off-axis terms exactly', () {
      final projection = OffAxisProjection(
        tanLeft: -0.4,
        tanRight: 1.2,
        tanDown: -0.9,
        tanUp: 0.3,
        near: 0.1,
        far: 100,
      );
      final params = ProjectionParams.of(projection, const ui.Size(1, 1));
      final fromMatrix = ProjectionParams.fromMatrix(
        projection.getProjectionMatrix(1.0),
      );
      expect(params.orthographic, isFalse);
      expect(params.scaleX, closeTo(0.8, 1e-12));
      expect(params.scaleY, closeTo(0.6, 1e-12));
      expect(params.offsetX, closeTo(fromMatrix.offsetX, 1e-6));
      expect(params.offsetY, closeTo(fromMatrix.offsetY, 1e-6));
      expect(params.near, 0.1);
      expect(params.far, 100);
    });
  });
}
