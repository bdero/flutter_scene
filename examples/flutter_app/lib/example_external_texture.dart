import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide CameraController, Material;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_settings.dart';

/// Which live source feeds the scene.
enum _SourceKind {
  video('Video file'),
  camera('Camera');

  const _SourceKind(this.label);
  final String label;
}

/// Spins the owning node about its Y axis.
class _SpinComponent extends Component {
  _SpinComponent(this.radiansPerSecond);

  final double radiansPerSecond;

  @override
  void update(double deltaSeconds) {
    node.localTransform =
        node.localTransform *
        vm.Matrix4.rotationY(radiansPerSecond * deltaSeconds);
  }
}

/// A video file or the device camera sampled directly by scene materials.
///
/// [ExternalTexture] captures a plugin's platform texture by id, so the same
/// frames the `Texture` widget would show become an ordinary material texture.
/// The feed lands on a flat screen and on a spinning cube, and the material
/// controls act on it like any other texture, so the surface can be made
/// glossy, rough, or self-lit.
///
/// The camera feed arrives in sensor orientation. The `camera` plugin's own
/// preview widget rotates it for the display, and that rotation is not part of
/// the texture, so a portrait phone shows a sideways feed here.
class ExampleExternalTexture extends StatefulWidget {
  const ExampleExternalTexture({super.key});

  @override
  State<ExampleExternalTexture> createState() => _ExampleExternalTextureState();
}

class _ExampleExternalTextureState extends State<ExampleExternalTexture> {
  final Scene scene = Scene();

  ExternalTexture? _source;
  VideoPlayerController? _video;
  CameraController? _camera;
  _SourceKind _kind = _SourceKind.video;
  String? _error;
  bool _switching = false;

  late final PhysicallyBasedMaterial _screenMaterial;
  late final PhysicallyBasedMaterial _cubeMaterial;

  double _roughness = 0.35;
  double _metallic = 0.0;
  double _emissive = 0.8;
  bool _invertColors = false;
  bool _swapRb = false;

  ui.ColorFilter? _currentColorFilter() {
    if (!_invertColors && !_swapRb) return null;
    if (_invertColors && _swapRb) {
      return const ui.ColorFilter.matrix(<double>[
        0.0,
        0.0,
        -1.0,
        0.0,
        255.0,
        0.0,
        -1.0,
        0.0,
        0.0,
        255.0,
        -1.0,
        0.0,
        0.0,
        0.0,
        255.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ]);
    } else if (_invertColors) {
      return const ui.ColorFilter.matrix(<double>[
        -1.0,
        0.0,
        0.0,
        0.0,
        255.0,
        0.0,
        -1.0,
        0.0,
        0.0,
        255.0,
        0.0,
        0.0,
        -1.0,
        0.0,
        255.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ]);
    } else {
      return const ui.ColorFilter.matrix(<double>[
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
      ]);
    }
  }

  void _updateFilter() {
    _source?.colorFilter = _currentColorFilter();
    _source?.requestCapture();
  }

  @override
  void initState() {
    super.initState();

    _screenMaterial = PhysicallyBasedMaterial()
      ..metallicFactor = _metallic
      ..roughnessFactor = _roughness;
    _cubeMaterial = PhysicallyBasedMaterial()
      ..metallicFactor = _metallic
      ..roughnessFactor = _roughness;
    _applyEmissive();

    scene.add(
      Node(
        name: 'floor',
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.5, 0)),
        mesh: Mesh(
          PlaneGeometry(width: 12, depth: 12),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.16, 0.18, 0.22, 1.0)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.25,
        ),
      ),
    );

    scene.add(
      Node(
        name: 'screen',
        localTransform:
            vm.Matrix4.translation(vm.Vector3(-1.5, 0.1, 0)) *
            vm.Matrix4.rotationY(0.35),
        mesh: Mesh(CuboidGeometry(vm.Vector3(2.4, 2.4, 0.12)), _screenMaterial),
      ),
    );

    scene.add(
      Node(
        name: 'cube',
        localTransform: vm.Matrix4.translation(vm.Vector3(1.9, 0.1, 0)),
        mesh: Mesh(CuboidGeometry(vm.Vector3(1.5, 1.5, 1.5)), _cubeMaterial),
      )..addComponent(_SpinComponent(0.7)),
    );

    _select(_SourceKind.video);
  }

  void _applyEmissive() {
    final factor = vm.Vector4(_emissive, _emissive, _emissive, 1.0);
    _screenMaterial.emissiveFactor = factor;
    _cubeMaterial.emissiveFactor = factor;
  }

  /// Points both materials at [source], or at nothing when it is null.
  void _bind(ExternalTexture? source) {
    _screenMaterial
      ..baseColorTexture = source
      ..emissiveTexture = source;
    _cubeMaterial
      ..baseColorTexture = source
      ..emissiveTexture = source;
  }

  Future<void> _select(_SourceKind kind) async {
    if (_switching) return;
    _switching = true;
    setState(() {
      _kind = kind;
      _error = null;
    });
    await _teardown();
    try {
      switch (kind) {
        case _SourceKind.video:
          await _startVideo();
        case _SourceKind.camera:
          await _startCamera();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _switching = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startVideo() async {
    final controller = VideoPlayerController.asset('assets/testsrc.mp4');
    _video = controller;
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(0);
    await controller.play();
    if (!mounted) return;

    // video_player exposes a player id, not a texture id, so the texture id
    // comes off the platform view it builds. A platform-view player has no
    // texture id at all; capture a WidgetTexture around the preview widget in
    // that case.
    // ignore: invalid_use_of_visible_for_testing_member
    final playerId = controller.playerId;
    final view = VideoPlayerPlatform.instance.buildViewWithOptions(
      VideoViewOptions(playerId: playerId),
    );
    if (view is! Texture) {
      throw StateError(
        'This platform builds video previews as a platform view, which has no '
        'texture id to capture.',
      );
    }
    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      throw StateError('Video has invalid or zero dimensions.');
    }
    _attach(view.textureId, size.width.round(), size.height.round());
  }

  Future<void> _startCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No cameras available.');
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _camera = controller;
    await controller.initialize();
    if (!mounted) return;
    final size = controller.value.previewSize!;
    // cameraId is the texture id the plugin's own preview samples.
    _attach(controller.cameraId, size.width.round(), size.height.round());
  }

  void _attach(int textureId, int width, int height) {
    final source = ExternalTexture(
      textureId: textureId,
      width: width,
      height: height,
      colorFilter: _currentColorFilter(),
    );
    _source = source;
    _bind(source);
  }

  Future<void> _teardown() async {
    _bind(null);
    _source?.dispose();
    _source = null;
    final video = _video;
    _video = null;
    await video?.dispose();
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) => Row(
    children: [
      SizedBox(
        width: 76,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      Expanded(
        child: Slider(
          value: value,
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      ),
      SizedBox(
        width: 32,
        child: Text(
          value.toStringAsFixed(2),
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ),
    ],
  );

  Widget _panel() {
    final source = _source;
    return Card(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 76,
                  child: Text(
                    'Source',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: ExampleDropdown<_SourceKind>(
                    value: _kind,
                    triggerColor: Colors.white12,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    isDense: true,
                    iconSize: 18,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    items: [
                      for (final kind in _SourceKind.values)
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                    ],
                    onChanged: (kind) {
                      if (kind != null) _select(kind);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _slider(
              label: 'Roughness',
              value: _roughness,
              onChanged: (v) {
                _roughness = v;
                _screenMaterial.roughnessFactor = v;
                _cubeMaterial.roughnessFactor = v;
              },
            ),
            _slider(
              label: 'Metallic',
              value: _metallic,
              onChanged: (v) {
                _metallic = v;
                _screenMaterial.metallicFactor = v;
                _cubeMaterial.metallicFactor = v;
              },
            ),
            _slider(
              label: 'Emissive',
              value: _emissive,
              onChanged: (v) {
                _emissive = v;
                _applyEmissive();
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Invert colors',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                Switch(
                  value: _invertColors,
                  onChanged: (v) {
                    setState(() => _invertColors = v);
                    _updateFilter();
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Swap R/B (BGR)',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                Switch(
                  value: _swapRb,
                  onChanged: (v) {
                    setState(() => _swapRb = v);
                    _updateFilter();
                  },
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  source == null
                      ? 'Starting...'
                      : '${source.width}x${source.height}, '
                            '${source.captureCount} captures, '
                            'last ${source.lastCaptureDuration.inMilliseconds} ms',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SceneView(
          scene,
          cameraBuilder: (elapsed) {
            final t = elapsed.inMicroseconds / 1e6;
            return PerspectiveCamera(
              position: vm.Vector3(sin(t * 0.15) * 5.5, 1.6, 5.5),
              target: vm.Vector3(0, 0, 0),
            );
          },
          onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
        ),
        ExampleOverlay.bottomCenter(
          child: SizedBox(width: 360, child: _panel()),
        ),
      ],
    );
  }
}
