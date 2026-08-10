import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene_editor/src/viewport/orbit_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('OrbitCamera.frame', () {
    final bounds = Aabb3.minMax(Vector3(-1, -2, -3), Vector3(3, 2, 1));

    test('centers the view without changing its angles', () {
      final camera = OrbitCamera(azimuth: 0.7, elevation: -0.3, radius: 4);

      camera.frame(bounds, aspectRatio: 16 / 9, margin: 1);

      expect(camera.target, bounds.center);
      expect(camera.azimuth, 0.7);
      expect(camera.elevation, -0.3);
      final boundsRadius = (bounds.max - bounds.min).length * 0.5;
      expect(camera.radius, closeTo(boundsRadius / sin(pi / 8), 1e-9));
    });

    test('pulls farther back for a portrait viewport', () {
      final landscape = OrbitCamera()..frame(bounds, aspectRatio: 2);
      final portrait = OrbitCamera()..frame(bounds, aspectRatio: 0.5);

      expect(portrait.radius, greaterThan(landscape.radius));
    });

    test('fits orthographic bounds through the narrower axis', () {
      final camera = OrbitCamera(orthographic: true);

      camera.frame(bounds, aspectRatio: 0.5, margin: 1);

      final boundsRadius = (bounds.max - bounds.min).length * 0.5;
      expect(camera.radius, closeTo(boundsRadius / (tan(pi / 8) * 0.5), 1e-9));
    });
  });

  group('OrbitCameraController scrolling', () {
    Future<void> pumpController(WidgetTester tester, OrbitCamera camera) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: OrbitCameraController(
            camera: camera,
            onChanged: () {},
            child: const SizedBox(width: 400, height: 300),
          ),
        ),
      );
    }

    testWidgets('mouse wheel zooms without orbiting', (tester) async {
      final camera = OrbitCamera(azimuth: 0.4, elevation: 0.3, radius: 10);
      await pumpController(tester, camera);

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(100, 100),
          scrollDelta: Offset(0, 20),
        ),
      );

      expect(camera.radius, greaterThan(10));
      expect(camera.azimuth, 0.4);
      expect(camera.elevation, 0.3);
    });

    testWidgets('trackpad scroll orbits without zooming', (tester) async {
      final camera = OrbitCamera(azimuth: 0.4, elevation: 0.3, radius: 10);
      await pumpController(tester, camera);

      await tester.sendEventToBinding(
        const PointerScrollEvent(
          kind: PointerDeviceKind.trackpad,
          position: Offset(100, 100),
          scrollDelta: Offset(20, 10),
        ),
      );

      expect(camera.radius, 10);
      expect(camera.azimuth, lessThan(0.4));
      expect(camera.elevation, lessThan(0.3));
    });
  });

  testWidgets('primary drag waits for the movement threshold', (tester) async {
    final camera = OrbitCamera(azimuth: 0.4, elevation: 0.3, radius: 10);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: OrbitCameraController(
          camera: camera,
          dragThreshold: 4,
          onChanged: () {},
          child: const SizedBox(width: 400, height: 300),
        ),
      ),
    );
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(const Offset(100, 100));

    await gesture.moveBy(const Offset(3, 0));
    expect(camera.azimuth, 0.4);

    await gesture.moveBy(const Offset(3, 0));
    expect(camera.azimuth, greaterThan(0.4));
    await gesture.up();
  });
}
