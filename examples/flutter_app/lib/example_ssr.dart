import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';
import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'lighting_panel.dart';
import 'quake_camera.dart';

/// Demonstrates screen-space reflections: a dark floor reflects a ring of
/// lit objects standing on it. A tuning panel exposes the SSR settings, and
/// the camera can be detached into a free first-person fly mode to inspect
/// trouble spots.
class ExampleSsr extends StatefulWidget {
  const ExampleSsr({super.key});

  @override
  ExampleSsrState createState() => ExampleSsrState();
}

class ExampleSsrState extends State<ExampleSsr> {
  final Scene scene = Scene();

  // Drives the image-based-lighting environment / skybox menu (the same one
  // the stress-tests example uses). The environment is what a reflection
  // falls back to on a miss, so it is worth exploring against SSR.
  final EnvironmentSelector _environmentSelector = EnvironmentSelector();

  // The free "inspection" camera and whether it is active. While inactive it
  // is kept synced to the orbiting camera so toggling on does not jump.
  bool _freeCamera = false;
  final QuakeCamera _freeCam = QuakeCamera(position: vm.Vector3(0, 2.2, 9))
    ..speed = 8.0
    ..enabled = false;

  double _elapsed = 0;
  Camera _camera = PerspectiveCamera(
    position: vm.Vector3(0, 2.2, 9),
    target: vm.Vector3(0, 1, 0),
  );

  @override
  void initState() {
    super.initState();

    scene.root.addComponent(
      DirectionalLightComponent(
        DirectionalLight(
          direction: vm.Vector3(-0.5, -1.0, -0.4),
          intensity: 3.0,
          castsShadow: true,
          shadowMaxDistance: 30.0,
        ),
      ),
    );

    // The environment and skybox are configured live through the lighting
    // panel below. The skybox samples the selected environment, so the floor
    // reflects (via SSR and the miss fallback) the same backdrop it shows.

    // A large, dark, smooth floor at y = 0.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 40, depth: 40),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.02, 0.02, 0.025, 1.0)
            ..roughnessFactor = 0.1
            ..metallicFactor = 0.0,
        ),
      ),
    );

    // A ring of brightly colored objects sitting on the floor.
    final palette = <vm.Vector4>[
      vm.Vector4(0.90, 0.25, 0.25, 1.0),
      vm.Vector4(0.95, 0.65, 0.20, 1.0),
      vm.Vector4(0.25, 0.80, 0.40, 1.0),
      vm.Vector4(0.25, 0.55, 0.95, 1.0),
      vm.Vector4(0.70, 0.35, 0.90, 1.0),
      vm.Vector4(0.95, 0.85, 0.30, 1.0),
    ];
    const count = 6;
    const ringRadius = 4.0;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi;
      final geometry = i.isEven
          ? SphereGeometry(radius: 0.9)
          : CuboidGeometry(vm.Vector3(1.4, 1.6, 1.4));
      final height = i.isEven ? 0.9 : 0.8;
      final node =
          Node(
              mesh: Mesh(
                geometry,
                PhysicallyBasedMaterial()
                  ..baseColorFactor = palette[i]
                  ..roughnessFactor = 0.4
                  ..metallicFactor = 0.0,
              ),
            )
            ..localTransform = vm.Matrix4.translation(
              vm.Vector3(
                cos(angle) * ringRadius,
                height,
                sin(angle) * ringRadius,
              ),
            );
      scene.add(node);
    }

    scene.screenSpaceReflections.enabled = true;
  }

  void _toggleFreeCamera() {
    setState(() {
      _freeCamera = !_freeCamera;
      _freeCam
        ..enabled = _freeCamera
        ..releaseKeys()
        ..move(_elapsed);
    });
  }

  PerspectiveCamera _orbitCamera() {
    return PerspectiveCamera(
      position: vm.Vector3(
        sin(_elapsed * 0.3) * 9,
        2.2,
        cos(_elapsed * 0.3) * 9,
      ),
      target: vm.Vector3(0, 1.0, 0),
    );
  }

  @override
  void dispose() {
    _environmentSelector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _freeCam.onKeyEvent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: _freeCamera
                  ? (details) => setState(() => _freeCam.look(details.delta))
                  : null,
              child: SceneView(
                scene,
                cameraBuilder: (elapsed) => _camera,
                onTick: (elapsed, deltaSeconds) {
                  _elapsed = elapsed.inMicroseconds / 1e6;
                  if (_freeCamera) {
                    _freeCam.move(_elapsed);
                    _camera = _freeCam.camera;
                  } else {
                    final orbit = _orbitCamera();
                    _freeCam.syncTo(orbit);
                    _camera = orbit;
                  }
                  exampleSettings.applyTo(scene);
                },
              ),
            ),
          ),
          ExampleOverlay.bottomRightPanel(
            paired: true,
            child: _SsrPanel(
              settings: scene.screenSpaceReflections,
              onChanged: () => setState(() {}),
            ),
          ),
          ExampleOverlay.bottomLeftPanel(
            paired: true,
            child: LightingPanel(scene: scene, selector: _environmentSelector),
          ),
          ExampleOverlay.bottomCenter(
            child: _CameraToggle(
              freeCamera: _freeCamera,
              onToggle: _toggleFreeCamera,
            ),
          ),
        ],
      ),
    );
  }
}

// The SSR tuning panel: a collapsible card of sliders and a debug-view
// dropdown that mutate the scene's ScreenSpaceReflectionsSettings live.
class _SsrPanel extends StatelessWidget {
  const _SsrPanel({required this.settings, required this.onChanged});

  final ScreenSpaceReflectionsSettings settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ExamplePanelCard(
      icon: Icons.tune,
      title: 'SSR settings',
      width: 340,
      maxBodyHeight: 560,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Enabled', style: TextStyle(color: Colors.white)),
              ),
              Switch(
                value: settings.enabled,
                onChanged: (v) {
                  settings.enabled = v;
                  onChanged();
                },
              ),
            ],
          ),
          _SliderRow(
            label: 'Intensity',
            value: settings.intensity,
            min: 0,
            max: 2,
            onChanged: (v) {
              settings.intensity = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Max dist',
            value: settings.maxDistance,
            min: 1,
            max: 60,
            onChanged: (v) {
              settings.maxDistance = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Thickness',
            value: settings.thickness,
            min: 0.01,
            max: 3,
            onChanged: (v) {
              settings.thickness = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Stride',
            value: settings.stride,
            min: 1,
            max: 12,
            onChanged: (v) {
              settings.stride = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Max steps',
            value: settings.maxSteps.toDouble(),
            min: 16,
            max: 256,
            onChanged: (v) {
              settings.maxSteps = v.round();
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Blur',
            value: settings.blur,
            min: 0,
            max: 1,
            onChanged: (v) {
              settings.blur = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Fade start',
            value: settings.distanceFadeStart,
            min: 0,
            max: 1,
            onChanged: (v) {
              settings.distanceFadeStart = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Resolution',
            value: settings.resolutionScale,
            min: 0.25,
            max: 1,
            onChanged: (v) {
              settings.resolutionScale = v;
              onChanged();
            },
          ),
          Row(
            children: [
              const SizedBox(
                width: 110,
                child: Text('Debug', style: TextStyle(color: Colors.white)),
              ),
              Expanded(
                child: ExampleDropdown<SsrDebugView>(
                  value: settings.debugView,
                  onChanged: (v) {
                    if (v != null) {
                      settings.debugView = v;
                      onChanged();
                    }
                  },
                  items: [
                    for (final view in SsrDebugView.values)
                      DropdownMenuItem(value: view, child: Text(view.name)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

// A toggle for the free "inspection" camera, with a usage hint while active.
class _CameraToggle extends StatelessWidget {
  const _CameraToggle({required this.freeCamera, required this.onToggle});

  final bool freeCamera;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (freeCamera)
          Card(
            color: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'WASD to move, Q and E for down and up, Shift to boost, drag to look',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ),
          ),
        Card(
          color: Colors.black54,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    freeCamera ? Icons.videocam : Icons.videocam_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    freeCamera ? 'Free camera' : 'Orbit camera',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
