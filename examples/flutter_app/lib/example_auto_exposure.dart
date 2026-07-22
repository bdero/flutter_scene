import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

/// Demonstrates auto exposure (eye adaptation): the camera walks out of a
/// dim room into bright sunlight and back, and the metered exposure factor
/// eases the image toward a consistent brightness in both. A tuning panel
/// exposes the settings; toggle it off mid-walk to see the raw range the
/// meter is covering.
class ExampleAutoExposure extends StatefulWidget {
  const ExampleAutoExposure({super.key});

  @override
  ExampleAutoExposureState createState() => ExampleAutoExposureState();
}

class ExampleAutoExposureState extends State<ExampleAutoExposure> {
  final Scene scene = Scene();

  // The walk path: camera z from deep inside the room to well outside.
  static const double _insideZ = -3.2;
  static const double _outsideZ = 11.0;

  bool _autoWalk = true;
  double _walk = 0.0; // 0 inside, 1 outside.
  Camera _camera = PerspectiveCamera(
    position: vm.Vector3(0, 1.7, _insideZ),
    target: vm.Vector3(0, 1.5, _insideZ + 6),
  );

  @override
  void initState() {
    super.initState();

    // A dim image-based-lighting bed so the room interior reads dark; the
    // sunlight (the shared directional light, boosted for this example) and
    // the bright gradient sky carry the outdoors.
    scene.environmentIntensity = 0.25;
    scene.skybox = Skybox(
      GradientSkySource(
        // Matches the shared light's default azimuth/elevation, so the sky
        // reads as the source of the sunlight (the disk sits behind the
        // camera on this path).
        sunDirection: vm.Vector3(-0.47, 0.82, -0.33),
      ),
    );

    scene.autoExposure.enabled = true;

    _buildWorld();
  }

  void _buildWorld() {
    Node box(
      vm.Vector3 center,
      vm.Vector3 size,
      vm.Vector4 color, {
      double roughness = 0.85,
    }) {
      return Node(
        mesh: Mesh(
          CuboidGeometry(size),
          PhysicallyBasedMaterial()
            ..baseColorFactor = color
            ..roughnessFactor = roughness
            ..metallicFactor = 0.0,
        ),
      )..localTransform = vm.Matrix4.translation(center);
    }

    // Sunlit ground.
    scene.add(
      Node(
        mesh: Mesh(
          PlaneGeometry(width: 60, depth: 60),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.45, 0.42, 0.35, 1.0)
            ..roughnessFactor = 0.9
            ..metallicFactor = 0.0,
        ),
      ),
    );

    // The room: an 8x8 shell with a doorway in the +z wall. The walls block
    // the sun, so the interior is lit only by the dim environment.
    final wallColor = vm.Vector4(0.62, 0.60, 0.57, 1.0);
    scene.add(box(vm.Vector3(0, 2, -4), vm.Vector3(8, 4, 0.3), wallColor));
    scene.add(box(vm.Vector3(-4, 2, 0), vm.Vector3(0.3, 4, 8), wallColor));
    scene.add(box(vm.Vector3(4, 2, 0), vm.Vector3(0.3, 4, 8), wallColor));
    scene.add(
      box(vm.Vector3(0, 4.15, 0), vm.Vector3(8.6, 0.3, 8.6), wallColor),
    );
    // The doorway wall: two segments beside a 2-wide opening and a lintel
    // above it.
    scene.add(box(vm.Vector3(-2.5, 2, 4), vm.Vector3(3, 4, 0.3), wallColor));
    scene.add(box(vm.Vector3(2.5, 2, 4), vm.Vector3(3, 4, 0.3), wallColor));
    scene.add(box(vm.Vector3(0, 3.4, 4), vm.Vector3(2, 1.2, 0.3), wallColor));

    // Furniture inside, so the dark half of the walk has a subject to
    // recover detail on.
    scene.add(
      Node(
        mesh: Mesh(
          SphereGeometry(radius: 0.7),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.75, 0.72, 0.68, 1.0)
            ..roughnessFactor = 0.5
            ..metallicFactor = 0.0,
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(-1.6, 0.7, -1.6)),
    );
    scene.add(
      box(
        vm.Vector3(1.7, 0.6, -2.2),
        vm.Vector3(1.2, 1.2, 1.2),
        vm.Vector4(0.30, 0.45, 0.70, 1.0),
        roughness: 0.4,
      ),
    );

    // Landmarks outside along the path.
    final palette = <vm.Vector4>[
      vm.Vector4(0.90, 0.30, 0.25, 1.0),
      vm.Vector4(0.95, 0.70, 0.20, 1.0),
      vm.Vector4(0.30, 0.75, 0.40, 1.0),
      vm.Vector4(0.65, 0.35, 0.85, 1.0),
    ];
    for (var i = 0; i < palette.length; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final z = 7.0 + i * 2.5;
      scene.add(
        Node(
            mesh: Mesh(
              i.isEven
                  ? SphereGeometry(radius: 0.8)
                  : CuboidGeometry(vm.Vector3(1.3, 1.5, 1.3)),
              PhysicallyBasedMaterial()
                ..baseColorFactor = palette[i]
                ..roughnessFactor = 0.45
                ..metallicFactor = 0.0,
            ),
          )
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(side * (2.5 + i * 0.6), i.isEven ? 0.8 : 0.75, z),
          ),
      );
    }
  }

  void _updateCamera() {
    final z = _insideZ + (_outsideZ - _insideZ) * _walk;
    _camera = PerspectiveCamera(
      position: vm.Vector3(0, 1.7, z),
      target: vm.Vector3(0, 1.5, z + 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) => _camera,
            onTick: (elapsed, deltaSeconds) {
              if (_autoWalk) {
                final t = elapsed.inMicroseconds / 1e6;
                // Ease-in-out ping-pong with a hold at each end, so the
                // adaptation is visible both mid-walk and at rest.
                _walk = 0.5 - 0.5 * cos(t * 0.45);
              }
              _updateCamera();
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        ExampleOverlay.bottomRightPanel(
          paired: true,
          child: _AutoExposurePanel(
            settings: scene.autoExposure,
            onChanged: () => setState(() {}),
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          paired: true,
          child: _WalkPanel(
            autoWalk: _autoWalk,
            walk: _walk,
            onAutoWalkChanged: (v) => setState(() => _autoWalk = v),
            onWalkChanged: (v) => setState(() {
              _autoWalk = false;
              _walk = v;
            }),
          ),
        ),
      ],
    );
  }
}

// The auto exposure tuning panel: sliders that mutate the scene's
// AutoExposureSettings live, plus a snap button exercising reset().
class _AutoExposurePanel extends StatelessWidget {
  const _AutoExposurePanel({required this.settings, required this.onChanged});

  final AutoExposureSettings settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ExamplePanelCard(
      icon: Icons.exposure,
      title: 'Auto exposure',
      width: 340,
      maxBodyHeight: 520,
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
            label: 'Strength',
            value: settings.strength,
            min: 0,
            max: 1,
            onChanged: (v) {
              settings.strength = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Compensation',
            value: settings.compensation,
            min: -3,
            max: 3,
            onChanged: (v) {
              settings.compensation = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Min EV',
            value: settings.minEv,
            min: -4,
            max: 0,
            onChanged: (v) {
              settings.minEv = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Max EV',
            value: settings.maxEv,
            min: 0,
            max: 4,
            onChanged: (v) {
              settings.maxEv = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Speed up',
            value: settings.speedUp,
            min: 0.1,
            max: 8,
            onChanged: (v) {
              settings.speedUp = v;
              onChanged();
            },
          ),
          _SliderRow(
            label: 'Speed down',
            value: settings.speedDown,
            min: 0.1,
            max: 8,
            onChanged: (v) {
              settings.speedDown = v;
              onChanged();
            },
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                settings.reset();
                onChanged();
              },
              icon: const Icon(Icons.center_focus_strong, size: 18),
              label: const Text('Snap adaptation'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// Walk controls: an automatic in-and-out stroll, or a manual scrub between
// the room and the daylight.
class _WalkPanel extends StatelessWidget {
  const _WalkPanel({
    required this.autoWalk,
    required this.walk,
    required this.onAutoWalkChanged,
    required this.onWalkChanged,
  });

  final bool autoWalk;
  final double walk;
  final ValueChanged<bool> onAutoWalkChanged;
  final ValueChanged<double> onWalkChanged;

  @override
  Widget build(BuildContext context) {
    return ExamplePanelCard(
      icon: Icons.directions_walk,
      title: 'Camera walk',
      width: 300,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Auto walk', style: TextStyle(color: Colors.white)),
              ),
              Switch(value: autoWalk, onChanged: onAutoWalkChanged),
            ],
          ),
          _SliderRow(
            label: 'Position',
            value: walk,
            min: 0,
            max: 1,
            onChanged: onWalkChanged,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Left is inside the room, right is out in the sun.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
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
          width: 120,
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
