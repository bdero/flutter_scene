// DirectionalLight.shadowStrength fades the sun's shadow, and at 0 pauses its
// cascades without dropping the static cache or the shadowed shader variants.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/light.dart'
    show DirectionalShadowState, directionalShadowStateOf;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/shadow_atlas_layout.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/shadow_pass.dart'
    show shadowMapForShading;
// ignore: implementation_imports
import 'package:flutter_scene/src/scene.dart' show planShadowAtlas;
// ignore: implementation_imports
import 'package:flutter_scene/src/scene_encoder.dart' show pipelineCacheSize;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

class _ShadowProbe extends CustomRenderPass {
  bool sawShadowMap = false;
  bool sawShadowInfo = false;

  @override
  String get name => 'shadow_probe';

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

void _render(Scene scene) {
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

bool _renderedShadowPass(Scene scene) => scene.renderStats.latest!.views.any(
  (view) => view.passes.any((pass) => pass.name == 'ShadowPass'),
);

// Never paced, so every render encodes its frame.
Scene _boxScene(DirectionalLight sun, {bool staticCaster = false}) => Scene()
  ..maxGpuFramesInFlight = 0
  ..directionalLight = sun
  ..add(
    Node(mesh: Mesh(CuboidGeometry(Vector3.all(1)), PhysicallyBasedMaterial()))
      ..shadowStatic = staticCaster,
  );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  group('directionalShadowStateOf', () {
    test('keys on castsShadow and a positive strength, never intensity', () {
      expect(directionalShadowStateOf(null), DirectionalShadowState.none);
      expect(
        directionalShadowStateOf(DirectionalLight()),
        DirectionalShadowState.none,
      );
      expect(
        directionalShadowStateOf(DirectionalLight(castsShadow: true)),
        DirectionalShadowState.active,
      );
      expect(
        directionalShadowStateOf(
          DirectionalLight(castsShadow: true, intensity: 0.0),
        ),
        DirectionalShadowState.active,
      );
      expect(
        directionalShadowStateOf(
          DirectionalLight(castsShadow: true, shadowStrength: 0.01),
        ),
        DirectionalShadowState.active,
      );
      expect(
        directionalShadowStateOf(
          DirectionalLight(castsShadow: true, shadowStrength: 0.0),
        ),
        DirectionalShadowState.paused,
      );
      expect(
        directionalShadowStateOf(
          DirectionalLight(castsShadow: true, shadowStrength: -1.0),
        ),
        DirectionalShadowState.paused,
      );
      expect(
        directionalShadowStateOf(DirectionalLight(shadowStrength: 0.0)),
        DirectionalShadowState.none,
      );
    });

    test('defaults to full strength', () {
      expect(DirectionalLight().shadowStrength, 1.0);
    });
  });

  test('the atlas plan takes cascades only from an active sun', () {
    final sun = DirectionalLightComponent(
      DirectionalLight(castsShadow: true, shadowCascadeCount: 3),
    );
    final active = planShadowAtlas(
      sun,
      DirectionalShadowState.active,
      null,
      null,
    );
    expect(active!.cascadeTiles, hasLength(3));
    expect(
      planShadowAtlas(sun, DirectionalShadowState.paused, null, null),
      isNull,
    );
    expect(
      planShadowAtlas(sun, DirectionalShadowState.none, null, null),
      isNull,
    );
  });

  test('no atlas and no hold binds no shadow map', () {
    expect(shadowMapForShading(null, holdShadowVariant: false), isNull);
  });

  test(
    'strength 0 skips the cascades and hides them from custom passes',
    () async {
      await Scene.initializeStaticResources();
      final sun = DirectionalLight(castsShadow: true);
      final probe = _ShadowProbe();
      final scene = _boxScene(sun)..addRenderPass(probe);
      try {
        _render(scene);
        expect(_renderedShadowPass(scene), isTrue);
        expect(probe.sawShadowMap, isTrue);
        expect(probe.sawShadowInfo, isTrue);

        sun.shadowStrength = 0.0;
        _render(scene);
        expect(_renderedShadowPass(scene), isFalse);
        expect(probe.sawShadowMap, isFalse);
        expect(probe.sawShadowInfo, isFalse);

        // Intensity alone never pauses them.
        sun
          ..shadowStrength = 1.0
          ..intensity = 0.0;
        _render(scene);
        expect(_renderedShadowPass(scene), isTrue);
        expect(probe.sawShadowInfo, isTrue);
      } finally {
        scene.dispose();
      }
    },
    skip: noGpu,
  );

  test(
    'strength 0 keeps the shadowed variants, so no pipeline compiles',
    () async {
      await Scene.initializeStaticResources();
      final sun = DirectionalLight(castsShadow: true);
      final scene = _boxScene(sun);
      try {
        _render(scene);
        _render(scene);
        final before = pipelineCacheSize;
        sun.shadowStrength = 0.0;
        _render(scene);
        sun.shadowStrength = 0.5;
        _render(scene);
        expect(pipelineCacheSize, before);

        // Clearing castsShadow does switch to the no-shadow variants.
        sun.castsShadow = false;
        _render(scene);
        expect(pipelineCacheSize, greaterThan(before));
      } finally {
        scene.dispose();
      }
    },
    skip: noGpu,
  );

  test(
    'the static shadow cache survives a fade through 0 but not castsShadow',
    () async {
      await Scene.initializeStaticResources();
      final sun = DirectionalLight(castsShadow: true);
      final scene = _boxScene(sun, staticCaster: true);
      try {
        _render(scene);
        expect(scene.debugHeldHistoryTargets, contains('shadowCache'));

        sun.shadowStrength = 0.0;
        _render(scene);
        expect(scene.debugHeldHistoryTargets, contains('shadowCache'));

        sun.shadowStrength = 1.0;
        _render(scene);
        expect(scene.debugHeldHistoryTargets, contains('shadowCache'));

        sun.castsShadow = false;
        _render(scene);
        expect(scene.debugHeldHistoryTargets, isNot(contains('shadowCache')));
      } finally {
        scene.dispose();
      }
    },
    skip: noGpu,
  );

  test('probe captures plan the frame atlas while the sun is paused', () async {
    await Scene.initializeStaticResources();
    final scene =
        _boxScene(DirectionalLight(castsShadow: true, shadowStrength: 0.0))
          ..add(
            Node(localTransform: Matrix4.translation(Vector3(0, 4, 0)))
              ..addComponent(
                SpotLightComponent(
                  SpotLight(direction: Vector3(0, -1, 0), castsShadow: true),
                ),
              ),
          )
          ..add(
            Node()..addComponent(ReflectionProbeComponent(faceResolution: 8)),
          );
    scene.godRays.enabled = true;
    final layouts = <ShadowAtlasLayout?>[];
    scene.debugOnShadowAtlasPlanned = layouts.add;
    try {
      _render(scene);
      // At least the frame, six probe faces, and the screen view.
      expect(layouts.length, greaterThanOrEqualTo(8));
      final first = layouts.first!;
      expect(first.cascadeTiles, isEmpty);
      expect(first.spotTiles, hasLength(1));
      for (final layout in layouts) {
        expect(layout!.width, first.width);
        expect(layout.height, first.height);
        expect(layout.cascadeTiles, first.cascadeTiles);
        expect(layout.spotTiles, first.spotTiles);
        expect(layout.pointTiles, first.pointTiles);
      }
    } finally {
      scene.dispose();
    }
  }, skip: noGpu);
}
