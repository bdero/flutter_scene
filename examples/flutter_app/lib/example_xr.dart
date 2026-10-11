import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_settings.dart';

/// A small lit room with an in-world widget panel, shown flat in a
/// [SceneView] and, where the browser offers WebXR, entered in VR or AR.
///
/// The same [Scene] renders both ways. Entering a session starts an
/// [XrSceneLoop] that draws it into the headset for every frame while the
/// flat view keeps the widget panel's subtree mounted; ending the session
/// tears the loop down.
class ExampleXr extends StatefulWidget {
  const ExampleXr({super.key});

  @override
  State<ExampleXr> createState() => _ExampleXrState();
}

class _ExampleXrState extends State<ExampleXr> {
  final Scene scene = Scene();
  final XrRig rig = XrRig();
  final PerspectiveCamera camera = PerspectiveCamera(
    position: vm.Vector3(0, 1.6, 2.5),
    target: vm.Vector3(0, 1.0, -1.0),
  );
  final ValueNotifier<int> _presses = ValueNotifier(0);

  bool _vrSupported = false;
  bool _arSupported = false;
  XrSession? _session;
  XrSceneLoop? _loop;
  XrInputSource? _input;
  String _status = XrRuntime.instance.isSupported
      ? 'Checking WebXR support...'
      : 'XR needs a WebXR browser; this platform has no runtime.';

  @override
  void initState() {
    super.initState();
    _buildRoom();
    scene.add(rig.origin);
    _checkSupport();
  }

  void _buildRoom() {
    // A floor grid of alternating tiles.
    for (var x = -3; x < 3; x++) {
      for (var z = -3; z < 3; z++) {
        final light = (x + z).isEven;
        scene.add(
          Node(
            localTransform: vm.Matrix4.translation(
              vm.Vector3(x + 0.5, 0, z + 0.5),
            ),
            mesh: Mesh(
              PlaneGeometry(width: 0.98, depth: 0.98),
              PhysicallyBasedMaterial()
                ..baseColorFactor = light
                    ? vm.Vector4(0.75, 0.75, 0.78, 1)
                    : vm.Vector4(0.25, 0.27, 0.32, 1)
                ..roughnessFactor = 0.7,
            ),
          ),
        );
      }
    }
    final shapes = [
      (vm.Vector3(-1.2, 0.4, -1.5), vm.Vector4(0.85, 0.3, 0.2, 1)),
      (vm.Vector3(1.2, 0.3, -1.8), vm.Vector4(0.2, 0.6, 0.9, 1)),
      (vm.Vector3(0.0, 0.25, -2.4), vm.Vector4(0.9, 0.8, 0.2, 1)),
    ];
    for (final (index, (position, color)) in shapes.indexed) {
      scene.add(
        Node(
          name: 'shape_$index',
          localTransform: vm.Matrix4.translation(position),
          mesh: Mesh(
            index.isEven
                ? CuboidGeometry(vm.Vector3.all(position.y * 2))
                : SphereGeometry(radius: position.y),
            PhysicallyBasedMaterial()
              ..baseColorFactor = color
              ..roughnessFactor = 0.4,
          ),
        ),
      );
    }
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.4, -1.0, -0.6),
      castsShadow: true,
    );

    // A widget panel at eye height; pointer rays from controllers reach it.
    final panel = Node(
      name: 'panel',
      localTransform: vm.Matrix4.translation(vm.Vector3(0, 1.4, -1.6)),
    );
    panel.addComponent(
      WidgetComponent(
        size: const Size(360, 200),
        worldHeight: 0.5,
        child: _Panel(presses: _presses),
      ),
    );
    scene.add(panel);
  }

  Future<void> _checkSupport() async {
    final runtime = XrRuntime.instance;
    if (!runtime.isSupported) return;
    final vr = await runtime.isSessionSupported(XrSessionMode.immersiveVr);
    final ar = await runtime.isSessionSupported(XrSessionMode.immersiveAr);
    if (!mounted) return;
    setState(() {
      _vrSupported = vr;
      _arSupported = ar;
      _status = vr || ar
          ? 'WebXR ready.'
          : 'WebXR is present but no immersive session is available.';
    });
  }

  Future<void> _enter(XrSessionMode mode) async {
    final ar = mode == XrSessionMode.immersiveAr;
    try {
      final session = await XrRuntime.instance.requestSession(
        XrSessionRequest(
          mode: mode,
          optionalFeatures: [
            XrFeatures.localFloor,
            XrFeatures.handTracking,
            if (ar) XrFeatures.hitTest,
            if (ar) XrFeatures.lightEstimation,
          ],
          domOverlayRoot: ar ? XrRuntime.instance.defaultDomOverlayRoot : null,
        ),
      );
      final input = XrInputSource(scene: scene, rig: rig);
      InputSystem.instance.addSource(input);
      final loop = XrSceneLoop(
        scene: scene,
        rig: rig,
        session: session,
        input: input,
        onTick: (frame, dt) => exampleSettings.applyTo(scene),
      )..start();
      setState(() {
        _session = session;
        _loop = loop;
        _input = input;
        _status = 'In ${mode.webName}, ${session.blendMode.name} blend.';
      });
      final reason = await session.ended;
      _teardown('Session ended (${reason.name}).');
    } catch (error) {
      _teardown('Could not start $mode: $error');
    }
  }

  void _teardown(String status) {
    _loop?.stop();
    final input = _input;
    if (input != null) InputSystem.instance.removeSource(input);
    if (!mounted) return;
    setState(() {
      _session = null;
      _loop = null;
      _input = null;
      _status = status;
    });
  }

  @override
  void dispose() {
    _loop?.stop();
    final input = _input;
    if (input != null) InputSystem.instance.removeSource(input);
    _session?.end();
    _presses.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inSession = _session != null;
    return Stack(
      children: [
        SceneView(
          scene,
          camera: camera,
          onTick: (elapsed, dt) {
            if (inSession) return;
            exampleSettings.applyTo(scene);
            final t = elapsed.inMicroseconds / 1e6;
            camera.position = vm.Vector3(
              math.sin(t * 0.3) * 2.5,
              1.6,
              math.cos(t * 0.3) * 2.5,
            );
          },
        ),
        ExampleOverlay.bottomCenter(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_status),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _vrSupported && !inSession
                            ? () => _enter(XrSessionMode.immersiveVr)
                            : null,
                        child: const Text('Enter VR'),
                      ),
                      FilledButton(
                        onPressed: _arSupported && !inSession
                            ? () => _enter(XrSessionMode.immersiveAr)
                            : null,
                        child: const Text('Enter AR'),
                      ),
                      OutlinedButton(
                        onPressed: inSession ? () => _session?.end() : null,
                        child: const Text('Exit'),
                      ),
                    ],
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

class _Panel extends StatelessWidget {
  const _Panel({required this.presses});

  final ValueNotifier<int> presses;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E2430),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'flutter_scene in XR',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: presses,
              builder: (context, count, _) => FilledButton(
                onPressed: () => presses.value = count + 1,
                child: Text('Pressed $count times'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
