import 'package:flutter/widgets.dart';

import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';
import 'package:flutter_scene_input/src/pointer_lock/pointer_lock.dart';
import 'package:flutter_scene_input/src/sources/flutter_input.dart';

/// When an [InputListener] locks the pointer.
/// {@category Widgets}
enum PointerLockPolicy {
  /// Never. Mouse movement comes from pointer events.
  never,

  /// On the first press inside the listener, where supported.
  onPress,

  /// Only when the app calls `PointerLock.instance.lock()` itself.
  manual,
}

/// Feeds mouse input over [child] (usually the game view) into [system] and
/// provides [player] to descendants through [InputScope].
///
/// Widgets stacked above the listener keep their own clicks, since only
/// events that hit the listener reach the mouse source. The keyboard source
/// and text-entry guard are attached on first use.
///
/// ```dart
/// Stack(children: [
///   InputListener(
///     pointerLock: PointerLockPolicy.onPress,
///     child: SceneView(scene),
///   ),
///   const Hud(),
/// ])
/// ```
/// {@category Widgets}
class InputListener extends StatefulWidget {
  /// Feeds mouse input over [child] into [system] (default
  /// [InputSystem.instance]).
  const InputListener({
    super.key,
    this.system,
    this.player,
    this.pointerLock = PointerLockPolicy.never,
    required this.child,
  });

  /// The system fed, or null for [InputSystem.instance].
  final InputSystem? system;

  /// The player [InputScope] provides, or null for the system's default
  /// player.
  final PlayerInput? player;

  /// When to lock the pointer.
  final PointerLockPolicy pointerLock;

  /// The widget receiving input, usually a `SceneView`.
  final Widget child;

  @override
  State<InputListener> createState() => _InputListenerState();
}

class _InputListenerState extends State<InputListener> {
  late FlutterInputSources _sources;

  InputSystem get _system => widget.system ?? InputSystem.instance;

  @override
  void initState() {
    super.initState();
    _sources = FlutterInputSources.ensure(_system);
  }

  @override
  void didUpdateWidget(InputListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.system, widget.system)) {
      _sources.mouse.handleButtons(0);
      _sources = FlutterInputSources.ensure(_system);
    }
    if (oldWidget.pointerLock == PointerLockPolicy.onPress &&
        widget.pointerLock != PointerLockPolicy.onPress) {
      PointerLock.instance.unlock();
    }
  }

  @override
  void dispose() {
    _sources.mouse.handleButtons(0);
    if (widget.pointerLock == PointerLockPolicy.onPress) {
      PointerLock.instance.unlock();
    }
    super.dispose();
  }

  void _onEvent(PointerEvent event) {
    if (event is PointerDownEvent &&
        widget.pointerLock == PointerLockPolicy.onPress &&
        !PointerLock.instance.isLocked &&
        PointerLock.instance.isSupported) {
      // Requested inside the event handler, which the web requires.
      PointerLock.instance.lock();
    }
    _sources.mouse.handleEvent(event);
  }

  @override
  Widget build(BuildContext context) {
    return InputScope(
      player: widget.player ?? _system.defaultPlayer,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onEvent,
        onPointerUp: _onEvent,
        onPointerCancel: _onEvent,
        onPointerMove: _onEvent,
        onPointerHover: _onEvent,
        onPointerSignal: _onEvent,
        onPointerPanZoomUpdate: _onEvent,
        child: widget.child,
      ),
    );
  }
}

/// Provides a [PlayerInput] to descendant widgets, so HUD widgets read input
/// without threading it through constructors.
/// {@category Widgets}
class InputScope extends InheritedWidget {
  /// Provides [player] to [child].
  const InputScope({super.key, required this.player, required super.child});

  /// The player provided.
  final PlayerInput player;

  /// The nearest scope's player, or null.
  static PlayerInput? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InputScope>()?.player;

  /// The nearest scope's player. Throws when there is none.
  static PlayerInput of(BuildContext context) {
    final player = maybeOf(context);
    if (player == null) {
      throw FlutterError(
        'InputScope.of() found no InputScope. Wrap the game view in an '
        'InputListener or an InputScope.',
      );
    }
    return player;
  }

  @override
  bool updateShouldNotify(InputScope oldWidget) =>
      !identical(oldWidget.player, player);
}
