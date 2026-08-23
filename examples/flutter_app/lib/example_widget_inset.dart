import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

/// Widget-surface input with the scene view away from the window origin.
///
/// A side rail pushes the [SceneView] to the right, so the view (and the
/// invisible widget-texture hosts inside it) sit at a non-zero global
/// offset. Forwarded pointer input must survive that: widgets that convert
/// a gesture's `globalPosition` back through render-object transforms, like
/// [Slider], only work when synthesized event positions agree with the
/// render tree about the coordinate space. This example exercises exactly
/// that path, dragging the slider on the 3D panel to drive the cube spin,
/// while the button and switch cover the tap path.
///
/// (Regression exercise: with texture-space positions dispatched as
/// `globalPosition`, the slider here jumps to a wrong value and drags in the
/// wrong place, while the button still works. None of the fullscreen
/// examples can show it, because there the two spaces coincide.)
class ExampleWidgetInset extends StatefulWidget {
  const ExampleWidgetInset({super.key});

  @override
  State<ExampleWidgetInset> createState() => ExampleWidgetInsetState();
}

class ExampleWidgetInsetState extends State<ExampleWidgetInset> {
  final Scene scene = Scene();
  bool loaded = false;

  Node? _cube;
  double _angle = 0;

  // Written by the widgets living on the in-scene panel. The panel owns its
  // own state (it is hosted once, so a rebuild of this widget does not
  // rebuild it); these are just the values read back out per tick.
  double _spin = 0.5;
  bool _lit = true;

  // Mirrors the panel's slider into the rail, so the value coming off the
  // surface is readable next to the surface itself.
  final ValueNotifier<double> _spinReadout = ValueNotifier<double>(0.5);

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      if (!mounted) return;
      _buildScene();
      setState(() => loaded = true);
    });
  }

  @override
  void dispose() {
    _spinReadout.dispose();
    super.dispose();
  }

  void _buildScene() {
    scene.add(
      Node(
        name: 'floor',
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.0, 0)),
        mesh: Mesh(
          PlaneGeometry(width: 10, depth: 10),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.30, 0.33, 0.40, 1)
            ..metallicFactor = 0.0
            ..roughnessFactor = 0.7,
        ),
      ),
    );

    _cube = Node(
      name: 'cube',
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(1.2, 1.2, 1.2)),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.35, 0.65, 0.90, 1)
          ..roughnessFactor = 0.35,
      ),
    )..position = vm.Vector3(1.9, 0.1, -0.2);
    scene.add(_cube!);

    // The zero-config widget surface: an aspect-correct quad hosting a live
    // subtree, with pointer input forwarded onto it automatically. The child
    // is hosted once and keeps its own state, so it is a StatefulWidget that
    // reports values out (the pattern for every widget surface).
    scene.add(
      Node(name: 'panel')
        ..position = vm.Vector3(0.15, 0.15, 0.6)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -0.25)
        ..addComponent(
          WidgetComponent(
            child: _PanelCard(
              onSpin: (v) {
                _spin = v;
                _spinReadout.value = v;
              },
              onLit: (v) => _lit = v,
            ),
            size: const Size(260, 200),
            pixelRatio: 2.0,
            worldHeight: 1.6,
          ),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The rail exists to move the SceneView off the window origin.
        Container(
          width: 230,
          color: const Color(0xFF14161B),
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inset view',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This rail offsets the SceneView from the window origin, so '
                'forwarded widget-surface input cannot take the texture-space '
                'shortcut.\n\n'
                'Drag the slider on the 3D panel: the thumb should follow the '
                'pointer and the cube spin track it. The button and switch '
                'cover the tap path.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: _spinReadout,
                builder: (context, value, _) => Text(
                  'spin off the surface: '
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                    color: Color(0xFF7FD1A0),
                    fontSize: 12.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: !loaded
              ? const Center(child: CircularProgressIndicator())
              : SceneView(
                  scene,
                  camera: PerspectiveCamera(
                    position: vm.Vector3(0, 1.2, 6.2),
                    target: vm.Vector3(0, 0.2, 0),
                  ),
                  onTick: (elapsed, deltaSeconds) {
                    _angle += deltaSeconds * _spin * 2.0;
                    _cube
                      ?..rotation = vm.Quaternion.axisAngle(
                        vm.Vector3(0, 1, 0),
                        _angle,
                      )
                      ..visible = _lit;
                  },
                ),
        ),
      ],
    );
  }
}

/// The live subtree on the panel: the slider is the probe for forwarded
/// position math, the button and switch for the tap path. It owns its state
/// and reports values out, the way every hosted subtree should. `SceneView`
/// mounts it once, so values pushed in from an enclosing `setState` would
/// never reach it.
class _PanelCard extends StatefulWidget {
  const _PanelCard({required this.onSpin, required this.onLit});

  final ValueChanged<double> onSpin;
  final ValueChanged<bool> onLit;

  @override
  State<_PanelCard> createState() => _PanelCardState();
}

class _PanelCardState extends State<_PanelCard> {
  double _spin = 0.5;
  bool _lit = true;
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cube',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: _lit,
                  onChanged: (v) {
                    setState(() => _lit = v);
                    widget.onLit(v);
                  },
                ),
              ],
            ),
            Text(
              'Spin ${(_spin * 100).round()}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Slider(
              value: _spin,
              onChanged: (v) {
                setState(() => _spin = v);
                widget.onSpin(v);
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => setState(() => _taps++),
                child: Text('Taps: $_taps'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
