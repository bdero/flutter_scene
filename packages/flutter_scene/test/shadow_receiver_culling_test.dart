// Covers shadowReceiverCullingPlanes: the planes must never reject a caster
// that can shadow a receiver its cascade tile serves, and should reject
// casters that cannot.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/render/shadow_receiver_culling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const _size = ui.Size(1280, 720);

bool _pointInside(List<Plane> planes, Vector3 p, {double tolerance = 1e-6}) {
  for (final plane in planes) {
    final scale = max(1.0, p.length);
    if (plane.normal.dot(p) + plane.constant < -tolerance * scale) return false;
  }
  return true;
}

Vector3 _randomUnit(Random random) {
  while (true) {
    final v = Vector3(
      random.nextDouble() * 2 - 1,
      random.nextDouble() * 2 - 1,
      random.nextDouble() * 2 - 1,
    );
    final length2 = v.length2;
    if (length2 > 1e-4 && length2 <= 1.0) return v.normalized();
  }
}

/// Light travel direction for a cascade matrix (row 2 of the orthographic
/// projection).
Vector3 _travel(Matrix4 m) =>
    Vector3(m.storage[2], m.storage[6], m.storage[10]).normalized();

bool _inPrism(Matrix4 lightSpace, Vector3 p) {
  final clip = lightSpace.transformed3(p.clone());
  return clip.x.abs() <= 1.0 && clip.y.abs() <= 1.0;
}

void main() {
  test('never rejects a caster that shadows a served receiver', () {
    final random = Random(1234);
    var checkedCasters = 0;
    for (var trial = 0; trial < 300; trial++) {
      final forward = _randomUnit(random);
      // Mix random suns with the degenerate cases: along the view axis,
      // against it, straight down, and grazing.
      final lightDirection = switch (trial % 6) {
        0 => forward.clone(),
        1 => -forward,
        2 => Vector3(0, -1, 0),
        3 => Vector3(1, -0.02, 0.3).normalized(),
        _ => _randomUnit(random),
      };
      final position = Vector3(
        random.nextDouble() * 200 - 100,
        random.nextDouble() * 50,
        random.nextDouble() * 200 - 100,
      );
      final camera = PerspectiveCamera(
        position: position,
        target: position + forward,
        up: forward.y.abs() > 0.99 ? Vector3(0, 0, 1) : Vector3(0, 1, 0),
        fovRadiansY: (20 + random.nextDouble() * 90) * degrees2Radians,
        fovNear: 0.05 + random.nextDouble(),
        fovFar: 50 + random.nextDouble() * 2000,
      );
      final light = DirectionalLight(
        castsShadow: true,
        direction: lightDirection,
        shadowCascadeCount: 1 + trial % 4,
        shadowMaxDistance: 20 + random.nextDouble() * 400,
        cascadeOverlap: random.nextDouble() < 0.5 ? 0.0 : random.nextDouble(),
      );
      final aspect = _size.width / _size.height;
      final cascades = light.computeCascades(camera, aspect, lightDirection);
      final viewProjection = camera.getViewTransform(_size);
      final frustum = Frustum.matrix(viewProjection);
      final receiverFrustum = shadowReceiverFrustum(viewProjection, _size);

      final cameraForward = camera.forward;
      final right = camera.up.cross(cameraForward).normalized();
      final up = cameraForward.cross(right).normalized();
      final tanV = tan(camera.fovRadiansY / 2);
      final tanH = tanV * aspect;

      for (final cascade in cascades) {
        final planes = shadowReceiverCullingPlanes(
          receiverFrustum: receiverFrustum,
          lightSpaceMatrix: cascade.lightSpaceMatrix,
          margin: 0.0,
        );
        final travel = _travel(cascade.lightSpaceMatrix);
        var receivers = 0;
        for (var s = 0; s < 4000 && receivers < 200; s++) {
          // Bias depth samples toward the cascade so the tile's own
          // receivers dominate, while still reaching the far plane.
          final depth = random.nextDouble() < 0.8
              ? camera.fovNear +
                    random.nextDouble() *
                        (cascade.radius * 3 + cascade.splitDistance)
              : camera.fovNear +
                    random.nextDouble() * (camera.fovFar - camera.fovNear);
          final receiver =
              camera.position +
              cameraForward * depth +
              right * ((random.nextDouble() * 2 - 1) * depth * tanH) +
              up * ((random.nextDouble() * 2 - 1) * depth * tanV);
          if (!frustum.containsVector3(receiver)) continue;
          if (!_inPrism(cascade.lightSpaceMatrix, receiver)) continue;
          receivers++;
          // No planes means no receiver volume was found, which is only
          // allowed when the tile serves no receivers (a cascade reaching
          // past the camera's far plane).
          expect(planes, isNotNull, reason: 'trial $trial found no volume');
          for (var c = 0; c < 8; c++) {
            final t = c == 0 ? 0.0 : random.nextDouble() * cascade.radius * 14;
            final caster = receiver - travel * t;
            checkedCasters++;
            expect(
              _pointInside(planes!, caster),
              isTrue,
              reason:
                  'trial $trial rejected caster $caster shadowing $receiver',
            );
          }
        }
      }
    }
    expect(checkedCasters, greaterThan(100000));
  });

  group('culls casters that cannot shadow the view', () {
    // Sun straight down, camera at head height looking level along -z.
    final camera = PerspectiveCamera(
      position: Vector3(0, 2, 0),
      target: Vector3(0, 2, -1),
      fovRadiansY: 60 * degrees2Radians,
    );
    final sun = Vector3(0, -1, 0);
    final light = DirectionalLight(
      castsShadow: true,
      direction: sun,
      shadowCascadeCount: 4,
      shadowMaxDistance: 100,
    );
    final cascades = light.computeCascades(
      camera,
      _size.width / _size.height,
      sun,
    );
    final viewProjection = camera.getViewTransform(_size);
    final receiverFrustum = shadowReceiverFrustum(viewProjection, _size);
    List<Plane> planesFor(int cascade) => shadowReceiverCullingPlanes(
      receiverFrustum: receiverFrustum,
      lightSpaceMatrix: cascades[cascade].lightSpaceMatrix,
      margin: 0.0,
    )!;
    bool inLightBox(int cascade, Vector3 p) {
      final clip = cascades[cascade].lightSpaceMatrix.transformed3(p.clone());
      return clip.x.abs() <= 1 &&
          clip.y.abs() <= 1 &&
          clip.z >= 0 &&
          clip.z <= 1;
    }

    test('a caster behind the camera', () {
      final behind = Vector3(0, 4, 3);
      expect(inLightBox(1, behind), isTrue);
      expect(_pointInside(planesFor(1), behind), isFalse);
    });

    test('a caster below the view, underground', () {
      final below = Vector3(0, -40, -10);
      expect(inLightBox(1, below), isTrue);
      expect(_pointInside(planesFor(1), below), isFalse);
    });

    test('keeps a caster above visible ground', () {
      final above = Vector3(0, 30, -10);
      expect(inLightBox(1, above), isTrue);
      expect(_pointInside(planesFor(1), above), isTrue);
    });
  });

  test('the margin widens every plane', () {
    final camera = PerspectiveCamera(
      position: Vector3(0, 2, 0),
      target: Vector3(0, 2, -1),
    );
    final light = DirectionalLight(castsShadow: true);
    final cascade = light.computeCascades(camera, 16 / 9).first;
    final receiverFrustum = shadowReceiverFrustum(
      camera.getViewTransform(_size),
      _size,
    );
    final tight = shadowReceiverCullingPlanes(
      receiverFrustum: receiverFrustum,
      lightSpaceMatrix: cascade.lightSpaceMatrix,
      margin: 0.0,
    )!;
    final loose = shadowReceiverCullingPlanes(
      receiverFrustum: receiverFrustum,
      lightSpaceMatrix: cascade.lightSpaceMatrix,
      margin: 0.5,
    )!;
    expect(loose, hasLength(tight.length));
    for (var i = 0; i < tight.length; i++) {
      expect(loose[i].constant - tight[i].constant, closeTo(0.5, 1e-9));
    }
  });

  test('margin covers normal bias, filter, and blocker search', () {
    final light = DirectionalLight(
      castsShadow: true,
      shadowNormalBias: 0.02,
      shadowMapResolution: 1024,
      angularRadius: 0.01,
    );
    const box = 20.0;
    final texel = box / 1024;
    final base = shadowReceiverMargin(light, box, 0.1);
    expect(base, closeTo(0.02 + 0.8 + 0.1 + 2 * texel, 1e-9));
    light.shadowFilter = DirectionalShadowFilter.pcss;
    expect(
      shadowReceiverMargin(light, box, 0.1) - base,
      closeTo(tan(0.01) * 7 * box + texel, 1e-9),
    );
  });
}
