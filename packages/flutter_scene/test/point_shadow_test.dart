// Covers collectPointShadows (selection, cap, slots), the point row's no-slot
// default in the packed light parameters, and the lockstep between the CPU
// per-face view projection and the shader's analytic face reconstruction
// (dominant-axis selection, face-local uv, and the window-depth mapping).

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/point_shadow.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

PointLightComponent _point({required bool castsShadow, Vector3? at}) {
  final node = Node(localTransform: Matrix4.translation(at ?? Vector3.zero()));
  final component = PointLightComponent(
    PointLight(range: 10.0, castsShadow: castsShadow),
  );
  node.addComponent(component);
  return component;
}

// The shader's face selection and face-local frame (SamplePointShadow in
// material_shadow_sampling.glsl), mirrored so the test can assert the CPU
// matrices agree with it.
(int, Vector3) _shaderFaceLocal(Vector3 v) {
  final a = Vector3(v.x.abs(), v.y.abs(), v.z.abs());
  if (a.x >= a.y && a.x >= a.z) {
    return v.x >= 0
        ? (0, Vector3(-v.z, v.y, v.x))
        : (1, Vector3(v.z, v.y, -v.x));
  }
  if (a.y >= a.z) {
    return v.y >= 0
        ? (2, Vector3(-v.x, v.z, v.y))
        : (3, Vector3(v.x, v.z, -v.y));
  }
  return v.z >= 0 ? (4, Vector3(v.x, v.y, v.z)) : (5, Vector3(-v.x, v.y, -v.z));
}

void main() {
  test('no shadow casters yields null', () {
    final frame = collectPointShadows([
      _point(castsShadow: false),
      _point(castsShadow: false),
    ]);
    expect(frame, isNull);
  });

  test('selects only casters and reports slots', () {
    final a = _point(castsShadow: true, at: Vector3(0, 5, 0));
    final b = _point(castsShadow: false);
    final c = _point(castsShadow: true, at: Vector3(3, 5, 0));
    final frame = collectPointShadows([a, b, c])!;

    expect(frame.casters, [a, c]);
    expect(frame.slotOf(a), 0);
    expect(frame.slotOf(c), 1);
    expect(frame.slotOf(b), -1);
  });

  test('caps the number of shadow casters at kMaxPointShadows', () {
    final points = [
      for (var i = 0; i < kMaxPointShadows + 2; i++)
        _point(castsShadow: true, at: Vector3(i.toDouble(), 5, 0)),
    ];
    final frame = collectPointShadows(points)!;
    expect(frame.casters, hasLength(kMaxPointShadows));
    expect(frame.slotOf(points.last), -1);
  });

  test('the caster budget reports what it dropped', () {
    // The selection is first-in-list, so the lights past the cap are the tail;
    // what matters here is that the count of dropped casters is exposed rather
    // than the shortfall being silent.
    final points = [
      for (var i = 0; i < kMaxPointShadows + 3; i++)
        _point(castsShadow: true, at: Vector3(i.toDouble(), 5, 0)),
    ];
    final frame = collectPointShadows(points)!;
    final granted = frame.casters.length;
    final requested = points.where((p) => p.light.castsShadow).length;
    expect(granted, kMaxPointShadows);
    expect(requested - granted, 3);
    // Every light past the cap reports no slot, which is what the editor
    // marks in the viewport and the inspector.
    for (final point in points.skip(kMaxPointShadows)) {
      expect(frame.slotOf(point), -1);
    }
  });

  test('packLights leaves point rows with no shadow slot', () {
    final (floats, count) = PunctualLightBuffer.packLights(
      directionals: [],
      points: [_point(castsShadow: true, at: Vector3(1, 2, 3))],
      spots: [],
    );
    expect(count, 1);
    // Texel 3.y: -1 until build() stamps a caster's atlas tile.
    expect(floats[13], -1.0);
  });

  test('face matrices agree with the shader face reconstruction', () {
    final light = PointLight(range: 20.0, shadowNear: 0.25);
    final position = Vector3(2.0, -1.0, 4.0);
    final near = light.shadowNear;
    final far = light.shadowFar;
    final depthScale = far / (far - near);
    final depthOffset = far * near / (far - near);

    // Sample points around the light, at least one per dominant axis and
    // several off-axis, all inside the face frustums.
    final samples = [
      Vector3(6.0, 0.5, 1.0),
      Vector3(-5.0, 1.5, -1.0),
      Vector3(0.5, 8.0, 2.0),
      Vector3(1.0, -7.0, -2.5),
      Vector3(-1.5, 2.0, 9.0),
      Vector3(2.5, -0.5, -6.0),
    ];
    for (final offset in samples) {
      final world = position + offset;
      final (face, local) = _shaderFaceLocal(offset);
      final matrix = light.pointShadowFaceViewProjection(position, face);
      final clip = matrix.transform(Vector4(world.x, world.y, world.z, 1.0));
      final ndcX = clip.x / clip.w;
      final ndcY = clip.y / clip.w;
      final ndcZ = clip.z / clip.w;
      // The shader projects local.xy / local.z (a 90 degree square frustum)
      // and maps window depth as scale - offset / faceDepth.
      expect(ndcX, closeTo(local.x / local.z, 1e-5), reason: 'face $face x');
      expect(ndcY, closeTo(local.y / local.z, 1e-5), reason: 'face $face y');
      expect(
        ndcZ,
        closeTo(depthScale - depthOffset / local.z, 1e-5),
        reason: 'face $face z',
      );
    }
  });

  test('every direction lands inside its selected face frustum', () {
    final random = math.Random(7);
    for (var i = 0; i < 200; i++) {
      final v = Vector3(
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
        random.nextDouble() * 2 - 1,
      );
      if (v.length < 1e-3) continue;
      v.scale(8.0 / v.length);
      final (face, local) = _shaderFaceLocal(v);
      // The dominant axis bounds the other two, so the face uv stays in the
      // unit square.
      expect(local.z, greaterThan(0.0));
      expect((local.x / local.z).abs(), lessThanOrEqualTo(1.0 + 1e-6));
      expect((local.y / local.z).abs(), lessThanOrEqualTo(1.0 + 1e-6));
      expect(face, inInclusiveRange(0, 5));
    }
  });
}
