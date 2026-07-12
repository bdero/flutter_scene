import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_action_hint.dart';
import 'example_overlay.dart';

/// A single shadow-casting spot light orbiting above a few occluders on a
/// floor, with a live settings panel (bottom-left) for the shadow parameters
/// and the spotlight, so the shadow quality can be tuned interactively.
class ExampleSpotShadow extends StatefulWidget {
  const ExampleSpotShadow({super.key});

  @override
  ExampleSpotShadowState createState() => ExampleSpotShadowState();
}

/// Orbits the owning node around a horizontal circle above the scene, aiming a
/// spot light straight down, so its cone (and the occluders' shadows) sweep.
class _OrbitAimDownComponent extends Component {
  _OrbitAimDownComponent(this.radius, this.height, this.speed);

  final double radius;
  final double height;
  final double speed;
  double _elapsed = 0.0;

  @override
  void update(double deltaSeconds) {
    _elapsed += deltaSeconds;
    final a = _elapsed * speed;
    node.localTransform = vm.Matrix4.translation(
      vm.Vector3(cos(a) * radius, height, sin(a) * radius),
    );
  }
}

class ExampleSpotShadowState extends State<ExampleSpotShadow> {
  Scene scene = Scene();
  bool _controlsOpen = true;

  // The live spot light, mutated by the settings panel. The renderer reads its
  // fields fresh each frame, so edits take effect immediately.
  late final SpotLight spot;

  @override
  void initState() {
    // A dim ambient so shadowed areas are dark but not pitch black; no sun.
    scene.environmentIntensity = 0.12;
    scene.directionalLight = null;
    // Reflect the scene off the floor, so the occluders' reflections reveal
    // exactly where they meet (or float above) it.
    scene.screenSpaceReflections.enabled = true;

    // A dark, near-polished floor.
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(30, 0.4, 30)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.08, 0.08, 0.1, 1)
            ..roughnessFactor = 0.08
            ..metallicFactor = 0.0,
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.2, 0)),
      ),
    );

    // A ring of occluders for the spot to cast shadows from, seated on the
    // floor (its top surface is at y = -1.0).
    final palette = <vm.Vector4>[
      vm.Vector4(0.9, 0.4, 0.35, 1),
      vm.Vector4(0.4, 0.8, 0.5, 1),
      vm.Vector4(0.45, 0.55, 0.95, 1),
      vm.Vector4(0.9, 0.8, 0.4, 1),
      vm.Vector4(0.8, 0.5, 0.9, 1),
    ];
    for (var i = 0; i < palette.length; i++) {
      final a = i / palette.length * 2 * pi;
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = palette[i]
        ..roughnessFactor = 0.6
        ..metallicFactor = 0.0;
      // Seat each shape so its base sits on the floor top (y = -1.0).
      final Geometry geometry;
      final double centerY;
      if (i.isEven) {
        geometry = CuboidGeometry(vm.Vector3(1.4, 2.4, 1.4));
        centerY = -1.0 + 1.2; // half-height above the floor top
      } else {
        geometry = SphereGeometry(radius: 1.0);
        centerY = -1.0 + 1.0;
      }
      scene.add(
        Node(
          mesh: Mesh(geometry, material),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(cos(a) * 4.5, centerY, sin(a) * 4.5),
          ),
        ),
      );
    }

    // The shadow-casting spot: high overhead, aimed straight down, orbiting so
    // the occluders' shadows sweep across the floor.
    spot = SpotLight(
      color: vm.Vector3(1.0, 0.97, 0.9),
      intensity: 199.0,
      range: 60.0,
      direction: vm.Vector3(0, -1, 0),
      innerConeAngle: 0.6,
      outerConeAngle: 0.81,
      castsShadow: true,
      shadowMapResolution: 1024,
      shadowNear: 0.02,
    );
    scene.add(
      Node()
        ..addComponent(SpotLightComponent(spot))
        ..addComponent(_OrbitAimDownComponent(3.5, 12.0, 0.5)),
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SceneView(
          scene,
          cameraBuilder: (elapsed) {
            final t = elapsed.inMicroseconds / 1e6 * 0.2;
            return PerspectiveCamera(
              position: vm.Vector3(sin(t) * 16, 11, cos(t) * 16),
              target: vm.Vector3(0, -0.5, 0),
            );
          },
        ),
        ExampleOverlay.bottomLeftPanel(
          child: _SettingsPanel(
            open: _controlsOpen,
            onToggle: () => setState(() => _controlsOpen = !_controlsOpen),
            spot: spot,
            onChanged: () => setState(() {}),
          ),
        ),
      ],
    );
  }
}

/// A compact panel of sliders and dropdowns bound to [spot]. [onChanged] is
/// called after every edit so the host rebuilds (the slider positions update;
/// the scene picks up the new values on its next frame).
class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.open,
    required this.onToggle,
    required this.spot,
    required this.onChanged,
  });

  final bool open;
  final VoidCallback onToggle;
  final SpotLight spot;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bodyHeight = constraints.hasBoundedHeight
              ? min(420.0, max(0.0, constraints.maxHeight - 57.0))
              : 420.0;

          return Card(
            color: Colors.black54,
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white, fontSize: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.highlight,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Spot shadow controls',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(
                            open ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (open) ...[
                    const Divider(height: 1, color: Colors.white24),
                    SizedBox(
                      height: bodyHeight,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _header('Shadow'),
                            _dropdown<ShadowCasterFaces>(
                              context,
                              'Caster faces',
                              spot.shadowCasterFaces,
                              ShadowCasterFaces.values,
                              (v) => v.name,
                              (v) {
                                spot.shadowCasterFaces = v;
                                onChanged();
                              },
                            ),
                            _dropdown<int>(
                              context,
                              'Resolution',
                              spot.shadowMapResolution,
                              const [256, 512, 1024, 2048],
                              (v) => '$v',
                              (v) {
                                spot.shadowMapResolution = v;
                                onChanged();
                              },
                            ),
                            _slider(
                              'Depth bias',
                              spot.shadowDepthBias,
                              0.0,
                              0.02,
                              4,
                              (v) {
                                spot.shadowDepthBias = v;
                                onChanged();
                              },
                            ),
                            _slider(
                              'Normal bias',
                              spot.shadowNormalBias,
                              0.0,
                              0.2,
                              3,
                              (v) {
                                spot.shadowNormalBias = v;
                                onChanged();
                              },
                            ),
                            _slider('Near', spot.shadowNear, 0.02, 3.0, 2, (v) {
                              spot.shadowNear = v;
                              onChanged();
                            }),
                            _slider(
                              'Softness',
                              spot.shadowSoftness,
                              0.0,
                              4.0,
                              2,
                              (v) {
                                spot.shadowSoftness = v;
                                onChanged();
                              },
                            ),
                            const SizedBox(height: 8),
                            _header('Spot light'),
                            _slider(
                              'Intensity',
                              spot.intensity,
                              0.0,
                              300.0,
                              0,
                              (v) {
                                spot.intensity = v;
                                onChanged();
                              },
                            ),
                            _slider('Range', spot.range, 5.0, 60.0, 1, (v) {
                              spot.range = v;
                              onChanged();
                            }),
                            _slider(
                              'Inner cone',
                              spot.innerConeAngle,
                              0.0,
                              1.4,
                              2,
                              (v) {
                                spot.innerConeAngle = min(
                                  v,
                                  spot.outerConeAngle - 0.01,
                                );
                                onChanged();
                              },
                            ),
                            _slider(
                              'Outer cone',
                              spot.outerConeAngle,
                              0.1,
                              1.5,
                              2,
                              (v) {
                                spot.outerConeAngle = max(
                                  v,
                                  spot.innerConeAngle + 0.01,
                                );
                                onChanged();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    int digits,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(digits),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>(
    BuildContext context,
    String label,
    T value,
    List<T> options,
    String Function(T) name,
    ValueChanged<T> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label)),
          Expanded(
            child: ExampleDropdown<T>(
              value: value,
              triggerColor: Colors.white12,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              isDense: true,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: [
                for (final option in options)
                  DropdownMenuItem<T>(value: option, child: Text(name(option))),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
