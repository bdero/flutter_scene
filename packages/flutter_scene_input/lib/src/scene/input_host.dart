import 'package:flutter_scene/scene.dart';

import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';
import 'package:flutter_scene_input/src/sources/flutter_input.dart';

/// Advances an [InputSystem]'s read windows on a scene's clock, ahead of every
/// component: the frame window at the start of each tick and the fixed window
/// before each fixed step.
///
/// Install it with [SceneInput.attachInput], which also lets components find
/// their player through [NodeInput.playerInput].
/// {@category Scene integration}
final class InputHost extends SceneTickListener {
  /// A host advancing [system].
  InputHost(this.system);

  /// The system advanced.
  final InputSystem system;

  @override
  void beforeTick(double deltaSeconds) => system.advanceFrame(deltaSeconds);

  @override
  void beforeFixedStep(double fixedDt) => system.advanceFixedStep(fixedDt);
}

/// Connects a [Scene] to input.
/// {@category Scene integration}
extension SceneInput on Scene {
  /// Advances [system] (default [InputSystem.instance]) with this scene's
  /// ticks, wires the Flutter keyboard and mouse sources, and makes the
  /// system's default player the one [NodeInput.playerInput] finds.
  ///
  /// Returns the installed host; pass it to [Scene.removeTickListener] to
  /// detach.
  InputHost attachInput([InputSystem? system]) {
    final resolved = system ?? InputSystem.instance;
    FlutterInputSources.ensure(resolved);
    final host = InputHost(resolved);
    addTickListener(host);
    final previous = root.getComponent<InputRoot>();
    if (previous != null) root.removeComponent(previous);
    root.addComponent(InputRoot(resolved));
    return host;
  }
}

/// Marks a scene root with the [InputSystem] its components read. Added by
/// [SceneInput.attachInput].
/// {@category Scene integration}
final class InputRoot extends Component {
  /// A root reading [system].
  InputRoot(this.system);

  /// The system components under this root read.
  final InputSystem system;
}

/// Assigns [player] to this node's subtree, for split screen or any scene
/// where different nodes answer to different players.
/// {@category Scene integration}
final class PlayerBinding extends Component {
  /// Binds this node and its descendants to [player].
  PlayerBinding(this.player);

  /// The player this subtree reads.
  final PlayerInput player;
}

/// Finds the player a node answers to.
/// {@category Scene integration}
extension NodeInput on Node {
  /// The nearest ancestor-or-self [PlayerBinding]'s player, else the default
  /// player of the scene's [InputRoot], else null when the scene has no input
  /// attached.
  PlayerInput? get playerInput {
    for (Node? node = this; node != null; node = node.parent) {
      final binding = node.getComponent<PlayerBinding>();
      if (binding != null) return binding.player;
      final root = node.getComponent<InputRoot>();
      if (root != null) return root.system.defaultPlayer;
    }
    return null;
  }
}
