import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ExampleClearcoat extends StatefulWidget {
  const ExampleClearcoat({super.key});

  @override
  State<ExampleClearcoat> createState() => _ExampleClearcoatState();
}

class _ExampleClearcoatState extends State<ExampleClearcoat> {
  final Scene _scene = Scene();
  final List<Node> _spheres = [];
  late final Node _particleLight;
  bool _loaded = false;
  Object? _error;
  double _azimuth = 0.0;
  double _elevation = 0.0;
  double _distance = 10.0;
  double _scaleStartDistance = 10.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      const normalSampling = TextureSampling(maxAnisotropy: 16);
      final loaded = await Future.wait([
        Texture2D.fromAsset('assets/clearcoat/carbon.png'),
        Texture2D.fromAsset(
          'assets/clearcoat/carbon_normal.png',
          content: TextureContent.normal,
          sampling: normalSampling,
        ),
        Texture2D.fromAsset(
          'assets/clearcoat/golf_ball_normal.jpg',
          content: TextureContent.normal,
          sampling: normalSampling,
        ),
        Texture2D.fromAsset(
          'assets/clearcoat/scratched_normal.png',
          content: TextureContent.normal,
          sampling: normalSampling,
        ),
        Texture2D.fromAsset(
          'assets/clearcoat/water_normal.jpg',
          content: TextureContent.normal,
          sampling: normalSampling,
        ),
        _createFlakesTexture(),
        EnvironmentMap.fromEquirectImageAsset(
          assetPath: 'assets/clearcoat/pisa.hdr',
        ),
      ]);
      final carbon = loaded[0] as Texture2D;
      final carbonNormal = loaded[1] as Texture2D;
      final golfNormal = loaded[2] as Texture2D;
      final scratchedNormal = loaded[3] as Texture2D;
      final waterNormal = loaded[4] as Texture2D;
      final flakesNormal = loaded[5] as Texture2D;
      final environment = loaded[6] as EnvironmentMap;
      final materials = await Future.wait([
        PhysicalMaterial.fromDescriptor(
          PhysicalMaterialDescriptor(
            name: 'Blue car paint',
            baseColor: vm.Vector4(0.0, 0.0, 1.0, 1.0),
            metallic: 0.9,
            roughness: 0.5,
            normalTexture: PhysicalTexture(
              source: flakesNormal,
              transform: TextureTransform(scale: vm.Vector2(10.0, 6.0)),
            ),
            normalScale: 0.15,
            clearcoat: 1.0,
            clearcoatRoughness: 0.1,
          ),
        ),
        PhysicalMaterial.fromDescriptor(
          PhysicalMaterialDescriptor(
            name: 'Carbon fiber',
            baseColorTexture: PhysicalTexture(
              source: carbon,
              transform: TextureTransform(scale: vm.Vector2.all(10.0)),
            ),
            metallic: 0.0,
            roughness: 0.5,
            normalTexture: PhysicalTexture(
              source: carbonNormal,
              transform: TextureTransform(scale: vm.Vector2.all(10.0)),
            ),
            clearcoat: 1.0,
            clearcoatRoughness: 0.1,
          ),
        ),
        PhysicalMaterial.fromDescriptor(
          PhysicalMaterialDescriptor(
            name: 'Golf ball',
            metallic: 0.0,
            roughness: 0.1,
            normalTexture: PhysicalTexture(source: golfNormal),
            clearcoat: 1.0,
            clearcoatNormalTexture: PhysicalTexture(source: scratchedNormal),
            clearcoatNormalScale: vm.Vector2(2.0, -2.0),
          ),
        ),
        PhysicalMaterial.fromDescriptor(
          PhysicalMaterialDescriptor(
            name: 'Red coated metal',
            baseColor: vm.Vector4(1.0, 0.0, 0.0, 1.0),
            metallic: 1.0,
            roughness: 1.0,
            normalTexture: PhysicalTexture(source: waterNormal),
            normalScale: 0.15,
            clearcoat: 1.0,
            clearcoatNormalTexture: PhysicalTexture(source: scratchedNormal),
            clearcoatNormalScale: vm.Vector2(2.0, -2.0),
          ),
        ),
      ]);
      if (!mounted) return;

      const positions = [(-1.0, 1.0), (1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)];
      for (var i = 0; i < materials.length; i++) {
        final position = positions[i];
        final node = Node(
          name: materials[i].name,
          mesh: Mesh(
            SphereGeometry(radius: 0.8, segments: 64, rings: 32),
            materials[i],
          ),
          localTransform: vm.Matrix4.translationValues(
            position.$1,
            position.$2,
            0.0,
          ),
        );
        _spheres.add(node);
        _scene.add(node);
      }

      final lightMaterial = UnlitMaterial()
        ..baseColorFactor = vm.Vector4.all(1.0)
        ..vertexColorWeight = 0.0;
      _particleLight = Node(
        name: 'Moving point light',
        mesh: Mesh(
          SphereGeometry(radius: 0.05, segments: 16, rings: 8),
          lightMaterial,
        ),
      )..addComponent(PointLightComponent(PointLight(intensity: 30.0)));
      _scene.add(_particleLight);
      _scene
        ..environment = environment
        ..skybox = Skybox(EnvironmentSkySource())
        ..exposure = 1.25
        ..toneMapping = ToneMappingMode.aces;
      setState(() => _loaded = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<Texture2D> _createFlakesTexture() async {
    const size = 512;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0.0, 0.0, 512.0, 512.0),
      ui.Paint()..color = const ui.Color.fromARGB(255, 127, 127, 255),
    );
    final random = math.Random(7);
    final paint = ui.Paint();
    for (var i = 0; i < 4000; i++) {
      var nx = random.nextDouble() * 2.0 - 1.0;
      var ny = random.nextDouble() * 2.0 - 1.0;
      var nz = 1.5;
      final inverseLength = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz);
      nx *= inverseLength;
      ny *= inverseLength;
      nz *= inverseLength;
      paint.color = ui.Color.fromARGB(
        255,
        (nx * 127.0 + 127.0).round().clamp(0, 255),
        (ny * 127.0 + 127.0).round().clamp(0, 255),
        (nz * 255.0).round().clamp(0, 255),
      );
      canvas.drawCircle(
        ui.Offset(random.nextDouble() * size, random.nextDouble() * size),
        random.nextDouble() * 3.0 + 3.0,
        paint,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    try {
      return await Texture2D.fromImage(
        image,
        content: TextureContent.normal,
        sampling: const TextureSampling(maxAnisotropy: 16),
      );
    } finally {
      image.dispose();
    }
  }

  PerspectiveCamera _camera() {
    final horizontal = math.cos(_elevation) * _distance;
    return PerspectiveCamera(
      position: vm.Vector3(
        math.sin(_azimuth) * horizontal,
        math.sin(_elevation) * _distance,
        math.cos(_azimuth) * horizontal,
      ),
      target: vm.Vector3.zero(),
      fovRadiansY: 27.0 * math.pi / 180.0,
      fovNear: 0.25,
      fovFar: 50.0,
    );
  }

  void _tick(Duration elapsed, double deltaSeconds) {
    final timer = elapsed.inMicroseconds / 1000000.0 * 0.25;
    final rotation = elapsed.inMicroseconds / 1000000.0 * 0.3;
    for (var i = 0; i < _spheres.length; i++) {
      final x = i.isEven ? -1.0 : 1.0;
      final y = i < 2 ? 1.0 : -1.0;
      _spheres[i].localTransform = vm.Matrix4.translationValues(x, y, 0.0)
        ..rotateY(rotation);
    }
    _particleLight.localTransform = vm.Matrix4.translationValues(
      math.sin(timer * 7.0) * 3.0,
      math.cos(timer * 5.0) * 4.0,
      math.cos(timer * 3.0) * 3.0,
    );
  }

  @override
  void dispose() {
    _scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final error?) {
      return Center(
        child: Text(
          'Could not load clearcoat example\n'
          'Run tool/fetch_clearcoat_assets.sh, then restart the app.\n$error',
        ),
      );
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          setState(() {
            _distance = (_distance * math.exp(event.scrollDelta.dy * 0.001))
                .clamp(4.0, 25.0);
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _scaleStartDistance = _distance,
        onScaleUpdate: (details) {
          setState(() {
            if (details.pointerCount == 1) {
              _azimuth += details.focalPointDelta.dx * 0.005;
              _elevation = (_elevation + details.focalPointDelta.dy * 0.005)
                  .clamp(-1.45, 1.45);
            } else {
              _distance = (_scaleStartDistance / details.scale).clamp(
                4.0,
                25.0,
              );
            }
          });
        },
        child: SceneView(
          _scene,
          cameraBuilder: (_) => _camera(),
          onTick: _tick,
        ),
      ),
    );
  }
}
