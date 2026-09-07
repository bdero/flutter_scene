import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/input/input_manager.dart';
import 'package:flutter_scene/src/input/input_source.dart';

/// Wires Flutter's keyboard and pointer events into an [InputManager] and
/// exposes it to the subtree.
///
/// Wrap the game's `SceneView` in one of these and the bundled sources are
/// attached and torn down with the widget:
///
/// ```dart
/// InputScope(
///   manager: input,
///   child: SceneView(scene: scene, camera: camera),
/// )
/// ```
///
/// Keyboard events arrive through a [Focus], so a focused text field takes
/// them instead of the game. Set [autofocus] false when something else should
/// hold focus first. Reach the manager from a descendant with
/// `InputScope.of(context)`.
/// {@category Picking and input}
class InputScope extends StatefulWidget {
  const InputScope({
    super.key,
    required this.manager,
    required this.child,
    this.autofocus = true,
    this.focusNode,
  });

  /// The manager fed by this scope. The caller owns its lifetime; this widget
  /// attaches sources to it but does not dispose it.
  final InputManager manager;

  final Widget child;

  /// Whether to take focus on mount, so keyboard input works without a click.
  final bool autofocus;

  /// An externally owned focus node, when the caller needs to move focus
  /// itself (opening a menu, focusing a chat box).
  final FocusNode? focusNode;

  /// The nearest enclosing scope's manager, or null when there is none.
  static InputManager? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InputScopeMarker>()?.manager;

  /// The nearest enclosing scope's manager. Throws when there is no
  /// [InputScope] above [context].
  static InputManager of(BuildContext context) {
    final manager = maybeOf(context);
    if (manager == null) {
      throw FlutterError(
        'InputScope.of() found no InputScope above this context.\n'
        'Wrap the widget that reads input in an InputScope.',
      );
    }
    return manager;
  }

  @override
  State<InputScope> createState() => _InputScopeState();
}

class _InputScopeState extends State<InputScope> {
  late final KeyboardInputSource _keyboard;
  late final PointerInputSource _pointer;
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'InputScope'));

  @override
  void initState() {
    super.initState();
    // The keyboard source routes through this scope's Focus rather than
    // listening globally, so focus decides who receives keys.
    _keyboard = KeyboardInputSource();
    _pointer = PointerInputSource();
    _attachTo(widget.manager);
  }

  void _attachTo(InputManager manager) {
    manager
      ..attach(_keyboard)
      ..attach(_pointer);
  }

  void _detachFrom(InputManager manager) {
    manager
      ..detach(_keyboard)
      ..detach(_pointer);
  }

  @override
  void didUpdateWidget(InputScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.manager, widget.manager)) {
      _detachFrom(oldWidget.manager);
      _attachTo(widget.manager);
    }
  }

  @override
  void dispose() {
    _detachFrom(widget.manager);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    _keyboard.handleKeyEvent(event);
    // Ignored rather than handled: the game reads state on its own tick, and
    // claiming the event would break shortcuts and text entry elsewhere.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return _InputScopeMarker(
      manager: widget.manager,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _onKey,
        child: Listener(
          // Opaque so the scope receives pointer events even when the
          // subtree has nothing hit-testable under the cursor. Without
          // this, mouse look silently does nothing over empty regions.
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _pointer.handleButtons(event.buttons),
          onPointerUp: (event) => _pointer.handleButtons(event.buttons),
          onPointerCancel: (_) => _pointer.handleButtons(0),
          onPointerMove: (event) {
            _pointer
              ..handleButtons(event.buttons)
              ..handleMove(event.delta.dx, event.delta.dy);
          },
          onPointerHover: (event) =>
              _pointer.handleMove(event.delta.dx, event.delta.dy),
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _pointer.handleScroll(event.scrollDelta.dy);
            }
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _InputScopeMarker extends InheritedWidget {
  const _InputScopeMarker({required this.manager, required super.child});

  final InputManager manager;

  @override
  bool updateShouldNotify(_InputScopeMarker oldWidget) =>
      !identical(oldWidget.manager, manager);
}
