// Covers the orthographic projection: size modes, zoom, offset, and clip
// mapping; the projection terms the renderer derives from any projection
// matrix; picking rays; framing; cascaded shadow fitting; the orbit
// controller's zoom mapping; and `.fscene` realization.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fscene/realize/builtin_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/render/planar_reflection.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_scene/src/render/viewport_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart' show ComponentPropertyDef;
import 'package:vector_math/vector_math.dart';

Vector3 _clip(Matrix4 m, Vector3 p) {
  final c = m.transform(Vector4(p.x, p.y, p.z, 1.0));
  return Vector3(c.x / c.w, c.y / c.w, c.z / c.w);
}

void main() {
  group('OrthographicSize', () {
    test('height and width hold one axis and follow the aspect', () {
      final h = const OrthographicSize.height(
        10,
      ).visibleSize(const ui.Size(2.0, 1));
      expect(h.x, 20);
      expect(h.y, 10);
      final w = const OrthographicSize.width(
        10,
      ).visibleSize(const ui.Size(2.0, 1));
      expect(w.x, 10);
      expect(w.y, 5);
    });

    test('contain keeps the whole area visible', () {
      const size = OrthographicSize.contain(16, 9);
      final wide = size.visibleSize(const ui.Size(3.0, 1));
      expect(wide.x, closeTo(27, 1e-5));
      expect(wide.y, 9);
      final tall = size.visibleSize(const ui.Size(1.0, 1));
      expect(tall.x, 16);
      expect(tall.y, 16);
    });

    test('cover fills the view from the area', () {
      const size = OrthographicSize.cover(16, 9);
      final wide = size.visibleSize(const ui.Size(3.0, 1));
      expect(wide.x, 16);
      expect(wide.y, closeTo(16 / 3, 1e-5));
      final tall = size.visibleSize(const ui.Size(1.0, 1));
      expect(tall.x, 9);
      expect(tall.y, 9);
    });

    test('stretch ignores the aspect', () {
      final s = const OrthographicSize.stretch(
        4,
        3,
      ).visibleSize(const ui.Size(10, 1));
      expect(s.x, 4);
      expect(s.y, 3);
    });
  });

  group('OrthographicProjection', () {
    test('maps the volume onto clip space', () {
      final projection = OrthographicProjection(
        size: const OrthographicSize.height(10),
        near: -5,
        far: 45,
      );
      final m = projection.getProjectionMatrix(2.0);
      final near = _clip(m, Vector3(10, 5, -5));
      expect(near.x, closeTo(1, 1e-5));
      expect(near.y, closeTo(1, 1e-5));
      expect(near.z, closeTo(0, 1e-5));
      final far = _clip(m, Vector3(-10, -5, 45));
      expect(far.x, closeTo(-1, 1e-5));
      expect(far.y, closeTo(-1, 1e-5));
      expect(far.z, closeTo(1, 1e-5));
      // No perspective divide.
      expect(m.entry(3, 2), 0);
      expect(m.entry(3, 3), 1);
    });

    test('zoom divides the extent and offset shifts the axis', () {
      final projection = OrthographicProjection(
        size: const OrthographicSize.height(10),
        zoom: 2,
        offset: Vector2(3, -1),
      );
      expect(projection.visibleSize(const ui.Size(1.0, 1)), Vector2(5, 5));
      final m = projection.getProjectionMatrix(1.0);
      final center = _clip(m, Vector3(3, -1, 10));
      expect(center.x, closeTo(0, 1e-5));
      expect(center.y, closeTo(0, 1e-5));
      final corner = _clip(m, Vector3(5.5, 1.5, 10));
      expect(corner.x, closeTo(1, 1e-5));
      expect(corner.y, closeTo(1, 1e-5));
    });

    test('bounds describes an explicit off-center volume', () {
      final projection = OrthographicProjection.bounds(
        left: -2,
        right: 6,
        bottom: 1,
        top: 5,
        near: 0,
        far: 10,
      );
      final m = projection.getProjectionMatrix(123.0);
      final lowCorner = _clip(m, Vector3(-2, 1, 0));
      final highCorner = _clip(m, Vector3(6, 5, 10));
      expect(lowCorner.x, closeTo(-1, 1e-5));
      expect(lowCorner.y, closeTo(-1, 1e-5));
      expect(highCorner.x, closeTo(1, 1e-5));
      expect(highCorner.y, closeTo(1, 1e-5));
      expect(highCorner.z, closeTo(1, 1e-5));
    });

    test('matchingPerspective frames the plane at the given distance', () {
      const fov = 60 * degrees2Radians;
      final ortho = OrthographicProjection.matchingPerspective(
        fovRadiansY: fov,
        distance: 8,
      );
      final perspective = PerspectiveProjection(fovRadiansY: fov);
      final top = Vector3(0, 8 * math.tan(fov / 2), 8);
      expect(
        _clip(ortho.getProjectionMatrix(1.5), top).y,
        closeTo(_clip(perspective.getProjectionMatrix(1.5), top).y, 1e-5),
      );
    });

    test('jitter shifts clip space by a constant NDC offset', () {
      final projection = OrthographicProjection();
      final plain = projection.getProjectionMatrix(1.0);
      final jittered = projection.getProjectionMatrix(
        1.0,
        jitter: Vector2(0.01, -0.02),
      );
      final p = Vector3(1.3, -2.1, 7);
      final delta = _clip(jittered, p) - _clip(plain, p);
      expect(delta.x, closeTo(0.01, 1e-5));
      expect(delta.y, closeTo(-0.02, 1e-5));
      expect(delta.z, closeTo(0, 1e-5));
    });
  });

  group('ProjectionParams', () {
    test('reads a perspective projection', () {
      final params = ProjectionParams.of(
        PerspectiveProjection(fovRadiansY: math.pi / 2, near: 0.5, far: 80),
        const ui.Size(2, 1),
      );
      expect(params.orthographic, isFalse);
      expect(params.scaleY, closeTo(1, 1e-5));
      expect(params.scaleX, closeTo(2, 1e-5));
      expect(params.offsetX, 0);
      expect(params.near, closeTo(0.5, 1e-6));
      expect(params.far, closeTo(80, 1e-3));
    });

    test('reads an orthographic projection with a negative near', () {
      final params = ProjectionParams.of(
        OrthographicProjection(
          size: const OrthographicSize.height(6),
          offset: Vector2(1.5, 0),
          near: -20,
          far: 30,
        ),
        const ui.Size(2, 1),
      );
      expect(params.orthographic, isTrue);
      expect(params.scaleX, closeTo(6, 1e-5));
      expect(params.scaleY, closeTo(3, 1e-5));
      expect(params.near, closeTo(-20, 1e-5));
      expect(params.far, closeTo(30, 1e-5));
      // The shader reconstruction: xy = (ndc - offset) * scale.
      final ndc = _clip(
        OrthographicProjection(
          size: const OrthographicSize.height(6),
          offset: Vector2(1.5, 0),
          near: -20,
          far: 30,
        ).getProjectionMatrix(2.0),
        Vector3(4, -1, 3),
      );
      expect((ndc.x - params.offsetX) * params.scaleX, closeTo(4, 1e-5));
      expect((ndc.y - params.offsetY) * params.scaleY, closeTo(-1, 1e-5));
    });
  });

  group('OrthographicCamera', () {
    test('picking rays are parallel and start on the near plane', () {
      final camera = OrthographicCamera(
        position: Vector3(0, 0, 0),
        target: Vector3(0, 0, 1),
        projection: OrthographicProjection(
          size: const OrthographicSize.height(4),
          near: -10,
          far: 10,
        ),
      );
      const view = ui.Size(200, 100);
      final center = camera.screenPointToRay(const ui.Offset(100, 50), view);
      final corner = camera.screenPointToRay(const ui.Offset(0, 0), view);
      expect(center.direction.normalized().z, closeTo(1, 1e-5));
      expect(corner.direction.normalized().z, closeTo(1, 1e-5));
      expect(center.origin.z, closeTo(-10, 1e-5));
      // Screen right is up x forward, world +x for a camera looking down +z.
      expect(corner.origin.x, closeTo(-4, 1e-5));
      expect(corner.origin.y, closeTo(2, 1e-5));
    });

    test('worldToScreen projects points behind the eye', () {
      final camera = OrthographicCamera(
        position: Vector3.zero(),
        target: Vector3(0, 0, 1),
        projection: OrthographicProjection(near: -10),
      );
      final offset = camera.worldToScreen(
        Vector3(0, 0, -5),
        const ui.Size(100, 100),
      );
      expect(offset, isNotNull);
      expect(offset!.dx, closeTo(50, 1e-5));
    });

    test('framing contains the bounds inside the clip volume', () {
      final bounds = Aabb3.minMax(Vector3(-3, 0, 2), Vector3(5, 4, 9));
      final camera = OrthographicCamera.framing(
        bounds,
        direction: Vector3(1, 1, -1),
      );
      for (final aspect in [0.5, 1.0, 2.5]) {
        final m = camera.getViewTransform(ui.Size(100 * aspect, 100));
        for (var i = 0; i < 8; i++) {
          final corner = Vector3(
            (i & 1) == 0 ? bounds.min.x : bounds.max.x,
            (i & 2) == 0 ? bounds.min.y : bounds.max.y,
            (i & 4) == 0 ? bounds.min.z : bounds.max.z,
          );
          final c = _clip(m, corner);
          expect(c.x.abs(), lessThanOrEqualTo(1.0), reason: '$aspect $corner');
          expect(c.y.abs(), lessThanOrEqualTo(1.0), reason: '$aspect $corner');
          expect(c.z, inInclusiveRange(0.0, 1.0), reason: '$aspect $corner');
        }
      }
    });
  });

  group('pixelsPerUnit', () {
    test('shows the view size divided by the scale', () {
      final size = const OrthographicSize.pixelsPerUnit(
        32,
      ).visibleSize(const ui.Size(640, 320));
      expect(size.x, 20);
      expect(size.y, 10);
    });

    test('rendering resolves against the logical view size', () {
      final camera = OrthographicCamera(
        position: Vector3.zero(),
        target: Vector3(0, 0, 1),
        projection: OrthographicProjection(
          size: const OrthographicSize.pixelsPerUnit(20),
          near: -10,
        ),
      );
      const logical = ui.Size(400, 200);
      // A render target at 3x density and half render scale.
      const physical = ui.Size(600, 300);
      final bound = ViewportBoundCamera(camera, logical);
      final rendered = bound.getViewTransform(physical);
      final picked = camera.getViewTransform(logical);
      for (var i = 0; i < 16; i++) {
        expect(rendered.storage[i], closeTo(picked.storage[i], 1e-6));
      }
      // The pick through a view corner lands on the rendered corner.
      final ray = camera.screenPointToRay(const ui.Offset(400, 0), logical);
      final corner = _clip(rendered, ray.origin);
      expect(corner.x, closeTo(1, 1e-5));
      expect(corner.y, closeTo(1, 1e-5));

      final params = ProjectionParams.of(bound.projection, physical);
      expect(params.scaleX, closeTo(10, 1e-9));
      expect(params.scaleY, closeTo(5, 1e-9));
    });
  });

  group('orthographic cascades', () {
    test('split uniformly from the near plane and cover the view box', () {
      final camera = OrthographicCamera(
        position: Vector3(10, 10, -10),
        target: Vector3.zero(),
        projection: OrthographicProjection(
          size: const OrthographicSize.height(12),
          near: -30,
          far: 60,
        ),
      );
      final light = DirectionalLight(
        castsShadow: true,
        shadowCascadeCount: 3,
        shadowMaxDistance: 60,
      );
      const aspect = 16.0 / 9.0;
      final cascades = light.computeCascades(camera, aspect);
      expect(cascades, hasLength(3));
      expect(cascades[0].splitDistance, closeTo(0, 1e-5));
      expect(cascades[1].splitDistance, closeTo(30, 1e-5));
      expect(cascades[2].splitDistance, closeTo(60, 1e-5));

      // Every corner of each slice lies inside its cascade sphere.
      final forward = camera.forward;
      final right = camera.up.cross(forward)..normalize();
      final up = forward.cross(right)..normalize();
      final extent =
          camera.projection.visibleSize(const ui.Size(aspect, 1)) * 0.5;
      var sliceNear = -30.0;
      for (final cascade in cascades) {
        for (final depth in [sliceNear, cascade.splitDistance]) {
          for (final sx in [-1.0, 1.0]) {
            for (final sy in [-1.0, 1.0]) {
              final corner =
                  camera.position +
                  forward * depth +
                  right * (sx * extent.x) +
                  up * (sy * extent.y);
              expect(
                corner.distanceTo(cascade.center!),
                lessThanOrEqualTo(cascade.radius + 1e-4),
              );
            }
          }
        }
        sliceNear = cascade.splitDistance;
      }
    });
  });

  test('orthographic LOD size does not change with distance', () {
    expect(lodScreenSizeOrthographic(radius: 2, halfHeight: 8), 0.25);
  });

  group('orbit controller under an orthographic camera', () {
    test('dolly scales zoom and holds the eye distance', () {
      final node = Node();
      final projection = OrthographicProjection(zoom: 1.5);
      node.addComponent(CameraComponent(projection: projection));
      final controller = OrbitCameraController(distance: 10, smoothing: 0);
      node.addComponent(controller);
      controller.update(1 / 60);
      final eyeDistance = node.globalTransform.getTranslation().length;

      controller.dollyBy(1.0);
      controller.update(1 / 60);
      expect(controller.distance, lessThan(10));
      expect(projection.zoom, closeTo(1.5 * 10 / controller.distance, 1e-9));
      expect(
        node.globalTransform.getTranslation().length,
        closeTo(eyeDistance, 1e-9),
      );
    });

    test('keeps zoom set elsewhere and scales from it', () {
      final node = Node();
      final projection = OrthographicProjection();
      node.addComponent(CameraComponent(projection: projection));
      final controller = OrbitCameraController(distance: 8, smoothing: 0);
      node.addComponent(controller);
      controller.update(1 / 60);

      projection.zoom = 3.0;
      controller.update(1 / 60);
      expect(projection.zoom, 3.0);

      final before = controller.distance;
      controller.dollyBy(0.5);
      controller.update(1 / 60);
      expect(
        projection.zoom,
        closeTo(3.0 * before / controller.distance, 1e-9),
      );
    });

    test('a replaced projection keeps its own zoom', () {
      final node = Node();
      final component = CameraComponent(projection: OrthographicProjection());
      node.addComponent(component);
      final controller = OrbitCameraController(distance: 8, smoothing: 0);
      node.addComponent(controller);
      controller.dollyBy(1.0);
      controller.update(1 / 60);

      final replacement = OrthographicProjection(zoom: 0.5);
      component.projection = replacement;
      controller.update(1 / 60);
      expect(replacement.zoom, 0.5);
    });
  });

  test('an orthographic camera document realizes its projection', () {
    final doc = SceneDocument();
    final component =
        CameraCodec().realize(
              ComponentSpec(
                'camera',
                properties: {
                  'projection': const StringValue('orthographic'),
                  'orthographicSize': const StringValue('cover'),
                  'orthographicWidth': const DoubleValue(20),
                  'orthographicHeight': const DoubleValue(8),
                  'orthographicZoom': const DoubleValue(2),
                  'orthographicNear': const DoubleValue(-15),
                },
              ),
              RealizeContext(doc),
            )!
            as CameraComponent;
    final projection = component.projection as OrthographicProjection;
    final size = projection.size as OrthographicCover;
    expect(size.width, 20);
    expect(size.height, 8);
    expect(projection.zoom, 2);
    expect(projection.near, -15);
  });
  test('perspective clip distances stay positive in the schema', () {
    final schema = CameraCodec().propertySchema;
    ComponentPropertyDef def(String name) =>
        schema.firstWhere((d) => d.name == name);
    expect(def('near').hardMin, greaterThan(0));
    expect(def('far').hardMin, greaterThan(0));
    expect(def('orthographicNear').hardMin, isNull);
  });

  group('oblique planar capture of an orthographic camera', () {
    final source = OrthographicCamera(
      position: Vector3(6, 5, -6),
      target: Vector3.zero(),
      projection: OrthographicProjection(near: -20, far: 40),
    );
    final capture = PlanarReflectionCamera(
      source: source,
      plane: Plane.normalconstant(Vector3(0, 1, 0), 0),
    );
    const size = ui.Size(320, 200);

    test('recovers the reflected forward from the lateral rows', () {
      final viewProjection = capture.getViewTransform(size);
      expect(isOrthographicTransform(viewProjection), isTrue);
      final forward = orthographicForward(viewProjection);
      expect((forward - capture.forward.normalized()).length, lessThan(1e-5));
      // The depth row now follows the mirror, not the camera.
      final s = viewProjection.storage;
      final depthRow = Vector3(s[2], s[6], s[10])..normalize();
      expect(depthRow.dot(capture.forward.normalized()), lessThan(0.999));
    });

    test('reads the base projection terms', () {
      final params = ProjectionParams.of(capture.projection, size);
      expect(params.orthographic, isTrue);
      expect(params.near, -20);
      expect(params.far, 40);
    });
  });
}
