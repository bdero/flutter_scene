import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const MaterialApp(home: XrDemo()));

/// A cube shown flat in a [SceneView], with an Enter VR button where the
/// browser offers WebXR. The same scene renders in both.
class XrDemo extends StatefulWidget {
  const XrDemo({super.key});

  @override
  State<XrDemo> createState() => _XrDemoState();
}

class _XrDemoState extends State<XrDemo> {
  final Scene scene = Scene();
  final XrRig rig = XrRig();
  bool _vrSupported = false;
  XrSession? _session;

  @override
  void initState() {
    super.initState();
    scene.add(
      Node(
        mesh: Mesh(
          CuboidGeometry(vm.Vector3.all(0.4)),
          PhysicallyBasedMaterial(),
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(0, 1.4, -1)),
      ),
    );
    scene.add(rig.origin);
    if (XrRuntime.instance.isSupported) {
      XrRuntime.instance.isSessionSupported(XrSessionMode.immersiveVr).then((
        supported,
      ) {
        if (mounted) setState(() => _vrSupported = supported);
      });
    }
  }

  Future<void> _enterVr() async {
    final session = await XrRuntime.instance.requestSession(
      XrSessionRequest(
        mode: XrSessionMode.immersiveVr,
        optionalFeatures: [XrFeatures.localFloor],
      ),
    );
    final input = XrInputSource(scene: scene, rig: rig);
    InputSystem.instance.addSource(input);
    final loop = XrSceneLoop(
      scene: scene,
      rig: rig,
      session: session,
      input: input,
    )..start();
    setState(() => _session = session);
    await session.ended;
    loop.stop();
    InputSystem.instance.removeSource(input);
    if (mounted) setState(() => _session = null);
  }

  @override
  void dispose() {
    _session?.end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SceneView(
          scene,
          camera: PerspectiveCamera(
            position: vm.Vector3(0, 1.6, 1.5),
            target: vm.Vector3(0, 1.4, -1),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: FilledButton(
              onPressed: _vrSupported && _session == null ? _enterVr : null,
              child: const Text('Enter VR'),
            ),
          ),
        ),
      ],
    );
  }
}
