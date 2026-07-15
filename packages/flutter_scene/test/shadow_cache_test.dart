import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/light.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/shadow_cache.dart';
import 'package:vector_math/vector_math.dart';

ShadowCascade cascade(Vector3 center, double radius, double split) =>
    ShadowCascade(
      lightSpaceMatrix: Matrix4.identity(),
      splitDistance: split,
      boxSize: radius * 2.0,
      center: center,
      radius: radius,
    );

List<ShadowCascade> idealCascades({Vector3? offset}) {
  final o = offset ?? Vector3.zero();
  return [
    cascade(Vector3(0, 0, 5) + o, 6.0, 10.0),
    cascade(Vector3(0, 0, 20) + o, 25.0, 45.0),
  ];
}

void main() {
  late DirectionalLight light;
  late DirectionalShadowCache cache;

  setUp(() {
    light = DirectionalLight()
      ..direction = Vector3(0.3, -1.0, 0.2).normalized()
      ..shadowMapResolution = 512;
    cache = DirectionalShadowCache();
  });

  ShadowCachePlan plan(List<ShadowCascade> ideal, {int signature = 1}) =>
      cache.plan(
        light: light,
        lightDirection: light.direction,
        idealCascades: ideal,
        staticSignature: signature,
      );

  test('first frame refreshes every cascade', () {
    final p = plan(idealCascades());
    expect(p.refreshes.length, 2);
    expect(p.cascades.length, 2);
    // Effective boxes carry the slack.
    expect(
      p.cascades[0].boxSize,
      closeTo(6.0 * DirectionalShadowCache.slackFactor * 2.0, 1e-9),
    );
  });

  test('a stable view refreshes nothing and keeps the same matrices', () {
    plan(idealCascades());
    final p = plan(idealCascades());
    expect(p.refreshes, isEmpty);
    final q = plan(idealCascades());
    expect(q.cascades[1].lightSpaceMatrix, p.cascades[1].lightSpaceMatrix);
  });

  test('drift within the slack keeps the cached tiles', () {
    plan(idealCascades());
    // 10% of the small cascade's radius, under the 15% slack.
    final p = plan(idealCascades(offset: Vector3(0.6, 0, 0)));
    expect(p.refreshes, isEmpty);
  });

  test('drift past the slack re-renders the cascade that no longer fits', () {
    plan(idealCascades());
    // 20% of the near cascade's radius (over the slack), but only 4.8% of
    // the far cascade's.
    final p = plan(idealCascades(offset: Vector3(1.2, 0, 0)));
    expect(p.refreshes.length, 1);
    expect(p.refreshes.single.cascadeIndex, 0);
  });

  test('content changes refresh amortized, nearest cascade first', () {
    plan(idealCascades());
    final p1 = plan(idealCascades(), signature: 2);
    expect(p1.refreshes.length, DirectionalShadowCache.maxAmortizedRefreshes);
    expect(p1.refreshes.first.cascadeIndex, 0);
    final p2 = plan(idealCascades(), signature: 2);
    expect(p2.refreshes.length, 1);
    expect(p2.refreshes.first.cascadeIndex, 1);
    final p3 = plan(idealCascades(), signature: 2);
    expect(p3.refreshes, isEmpty);
  });

  test('a light direction change rebuilds everything', () {
    plan(idealCascades());
    light.direction = Vector3(-0.5, -1.0, 0.1).normalized();
    final p = plan(idealCascades());
    expect(p.refreshes.length, 2);
  });

  test('a resolution change rebuilds everything', () {
    plan(idealCascades());
    light.shadowMapResolution = 1024;
    final p = plan(idealCascades());
    expect(p.refreshes.length, 2);
  });
}
