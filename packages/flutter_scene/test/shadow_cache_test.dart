import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/shadow_cache.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/scene.dart'
    show shouldRenderDirectionalShadows;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

class _ShadowMapProbe extends CustomRenderPass {
  bool sawShadowMap = false;
  bool sawShadowInfo = false;

  @override
  String get name => 'shadow_map_probe';

  @override
  RenderStage get stage => RenderStage.afterScene;

  @override
  Set<RenderInput> get inputs => const {RenderInput.shadowMap};

  @override
  void execute(RenderPassContext context) {
    sawShadowMap = context.shadowMap != null;
    sawShadowInfo = context.shadowInfo != null;
  }
}

void _renderScene(Scene scene) {
  final recorder = ui.PictureRecorder();
  try {
    scene.render(
      PerspectiveCamera(position: Vector3(0, 2, 5)),
      ui.Canvas(recorder),
      viewport: const ui.Rect.fromLTWH(0, 0, 32, 32),
      pixelRatio: 1.0,
    );
  } finally {
    recorder.endRecording().dispose();
  }
}

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
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';
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

  test('a small light turn refreshes amortized, nearest cascade first', () {
    plan(idealCascades());
    // A 2 degree step, inside the lag tolerance.
    light.direction = Quaternion.axisAngle(
      Vector3(0, 0, 1),
      2.0 * degrees2Radians,
    ).rotated(light.direction);
    final p1 = plan(idealCascades());
    expect(p1.refreshes.length, DirectionalShadowCache.maxAmortizedRefreshes);
    expect(p1.refreshes.single.cascadeIndex, 0);
    // The far cascade still samples through its old matrix.
    final oldFar = Matrix4.copy(p1.cascades[1].lightSpaceMatrix);
    final p2 = plan(idealCascades());
    expect(p2.refreshes.single.cascadeIndex, 1);
    expect(p2.cascades[1].lightSpaceMatrix, isNot(oldFar));
    expect(plan(idealCascades()).refreshes, isEmpty);
  });

  test('a large light turn re-renders everything', () {
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

  test('a shadow-caster channel change rebuilds everything', () {
    plan(idealCascades());
    expect(plan(idealCascades()).refreshes, isEmpty);
    light.shadowCasterChannelMask = 0x0F;
    expect(plan(idealCascades()).refreshes.length, 2);
  });

  group('shouldRenderDirectionalShadows', () {
    test(
      'skips zero-intensity directional light when no shadow reader is active',
      () {
        final zeroSun = DirectionalLight(
          intensity: 0.0,
          castsShadow: true,
          shadowAmbientStrength: 0.0,
        );
        expect(
          shouldRenderDirectionalShadows(zeroSun, hasShadowCatcher: false),
          isFalse,
        );
        expect(
          shouldRenderDirectionalShadows(
            DirectionalLight(intensity: -0.5, castsShadow: true),
            hasShadowCatcher: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'renders zero-intensity shadows when catchers, ambient shadow, god rays, or custom shadow passes are active',
      () {
        final zeroSun = DirectionalLight(
          intensity: 0.0,
          castsShadow: true,
          shadowAmbientStrength: 0.0,
        );
        expect(
          shouldRenderDirectionalShadows(zeroSun, hasShadowCatcher: true),
          isTrue,
        );
        expect(
          shouldRenderDirectionalShadows(
            zeroSun,
            hasShadowCatcher: false,
            hasGodRays: true,
          ),
          isTrue,
        );
        expect(
          shouldRenderDirectionalShadows(
            zeroSun,
            hasShadowCatcher: false,
            hasCustomShadowMapPass: true,
          ),
          isTrue,
        );
        expect(
          shouldRenderDirectionalShadows(
            DirectionalLight(
              intensity: 0.0,
              castsShadow: true,
              shadowAmbientStrength: 0.25,
            ),
            hasShadowCatcher: false,
          ),
          isTrue,
        );
      },
    );

    test('honors castsShadow and any positive intensity', () {
      expect(
        shouldRenderDirectionalShadows(null, hasShadowCatcher: true),
        isFalse,
      );
      expect(
        shouldRenderDirectionalShadows(
          DirectionalLight(intensity: 1.0, castsShadow: false),
          hasShadowCatcher: true,
        ),
        isFalse,
      );
      expect(
        shouldRenderDirectionalShadows(
          DirectionalLight(intensity: 1e-7, castsShadow: true),
          hasShadowCatcher: false,
        ),
        isTrue,
      );
    });
  });

  test(
    'zero-intensity directional light keeps shadowCache alive while clearing castsShadow drops it',
    () async {
      await Scene.initializeStaticResources();
      final sun = DirectionalLight(intensity: 1.0, castsShadow: true);
      final scene = Scene()
        ..directionalLight = sun
        ..add(
          Node(
            mesh: Mesh(
              CuboidGeometry(Vector3.all(1)),
              PhysicallyBasedMaterial(),
            ),
          )..shadowStatic = true,
        );
      try {
        _renderScene(scene);
        expect(scene.debugHeldHistoryTargets, contains('shadowCache'));

        sun.intensity = 0.0;
        _renderScene(scene);
        expect(scene.debugHeldHistoryTargets, contains('shadowCache'));

        sun.castsShadow = false;
        _renderScene(scene);
        expect(scene.debugHeldHistoryTargets, isNot(contains('shadowCache')));
      } finally {
        scene.dispose();
      }
    },
    skip: noGpu,
  );

  test(
    'zero-intensity directional light still feeds shadowMap to a custom RenderInput.shadowMap pass',
    () async {
      await Scene.initializeStaticResources();
      final probe = _ShadowMapProbe();
      final scene = Scene()
        ..directionalLight = DirectionalLight(intensity: 0.0, castsShadow: true)
        ..add(
          Node(
            mesh: Mesh(
              CuboidGeometry(Vector3.all(1)),
              PhysicallyBasedMaterial(),
            ),
          ),
        )
        ..addRenderPass(probe);
      try {
        _renderScene(scene);
        expect(probe.sawShadowMap, isTrue);
        expect(probe.sawShadowInfo, isTrue);
      } finally {
        scene.dispose();
      }
    },
    skip: noGpu,
  );
}
