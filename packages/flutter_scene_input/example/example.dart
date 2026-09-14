import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:vector_math/vector_math.dart';

const fly = VectorAction('fly');
const look = DeltaAction('look');
const boost = ButtonAction('boost');

final flying = ActionSet('flying', {
  fly: {
    'keyboard': DpadBinding(
      up: PhysicalKeyboardKey.keyW.control,
      down: PhysicalKeyboardKey.keyS.control,
      left: PhysicalKeyboardKey.keyA.control,
      right: PhysicalKeyboardKey.keyD.control,
    ),
    'gamepad': const StickBinding(
      GamepadControl.leftStick,
      processors: [Deadzone(0.15)],
    ),
  },
  look: {
    'mouse': const DeltaBinding(MouseControl.delta),
    'gamepad': const StickBinding(
      GamepadControl.rightStick,
      processors: [Deadzone(0.15), PerSecond(600)],
    ),
  },
  boost: {
    'keyboard': ButtonBinding(PhysicalKeyboardKey.shiftLeft.control),
    'gamepad': const ButtonBinding(GamepadControl.leftStickPress),
  },
});

void main() => runApp(const MaterialApp(home: FlyDemo()));

/// A fly camera over a cube: WASD or the left stick to move, click to lock the
/// cursor and look with the mouse or the right stick, Shift to boost.
class FlyDemo extends StatefulWidget {
  const FlyDemo({super.key});

  @override
  State<FlyDemo> createState() => _FlyDemoState();
}

class _FlyDemoState extends State<FlyDemo> {
  final Scene scene = Scene();
  final Node camera = Node();

  @override
  void initState() {
    super.initState();
    InputSystem.instance.defaultPlayer.contexts.push(flying);
    scene.attachInput();
    scene.add(
      Node()..mesh = Mesh(CuboidGeometry(Vector3.all(1)), UnlitMaterial()),
    );
    camera
      ..addComponent(CameraComponent(activateOnMount: true))
      ..addComponent(FlyCameraInputDriver(move: fly, look: look, boost: boost))
      ..addComponent(FlyCameraController(position: Vector3(0, 1, 4)));
    scene.add(camera);
  }

  @override
  Widget build(BuildContext context) {
    return InputListener(
      pointerLock: PointerLockPolicy.onPress,
      child: SceneView(scene),
    );
  }
}
