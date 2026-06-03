import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import 'character_input.dart';

/// Wraps a scene with character controls and writes them into a shared
/// [CharacterInput]: keyboard (WASD / arrow keys to move, space to jump)
/// plus an on-screen joystick and jump button, so the same demo is
/// playable with a keyboard on the web or by touch on a phone.
///
/// The joystick takes over the move vector while it is being dragged;
/// otherwise the keyboard drives it. Jump is the union of the space key
/// and the on-screen button.
class CharacterControls extends StatefulWidget {
  const CharacterControls({
    super.key,
    required this.input,
    required this.child,
  });

  final CharacterInput input;
  final Widget child;

  @override
  State<CharacterControls> createState() => _CharacterControlsState();
}

class _CharacterControlsState extends State<CharacterControls> {
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressed = {};

  // Joystick drag state, in [-1, 1] (y up); null when not dragging.
  Vector2? _stickValue;
  bool _buttonJump = false;

  static const double _stickRadius = 56.0;

  @override
  void initState() {
    super.initState();
    // Grab focus after the first frame so keyboard input works immediately
    // on the web without a click.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double _axis(LogicalKeyboardKey positive, LogicalKeyboardKey negative) =>
      (_held(positive) ? 1.0 : 0.0) - (_held(negative) ? 1.0 : 0.0);

  void _sync() {
    // Movement: the joystick when dragging, otherwise WASD.
    widget.input.move =
        _stickValue?.clone() ??
        Vector2(
          _axis(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyA),
          _axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS),
        );
    // Arrow keys orbit the camera.
    widget.input.lookRate = Vector2(
      _axis(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft),
      _axis(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown),
    );
    widget.input.jump =
        _buttonJump || _pressed.contains(LogicalKeyboardKey.space);
  }

  bool _held(LogicalKeyboardKey key) => _pressed.contains(key);

  static final Set<LogicalKeyboardKey> _handledKeys = {
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.space,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      _pressed.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _pressed.remove(event.logicalKey);
    }
    _sync();
    return _handledKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _onStick(Offset local, Size baseSize) {
    final center = Offset(baseSize.width / 2, baseSize.height / 2);
    var dx = (local.dx - center.dx) / _stickRadius;
    var dy = (local.dy - center.dy) / _stickRadius;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length > 1.0) {
      dx /= length;
      dy /= length;
    }
    // Screen y is down, so negate for "forward".
    setState(() => _stickValue = Vector2(dx, -dy));
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // Dragging anywhere on the scene (outside the controls below)
          // orbits the camera.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) =>
                  widget.input.lookDelta.add(Vector2(d.delta.dx, d.delta.dy)),
              child: widget.child,
            ),
          ),
          Positioned(left: 24, bottom: 24, child: _joystick()),
          Positioned(right: 24, bottom: 24, child: _jumpButton()),
        ],
      ),
    );
  }

  Widget _joystick() {
    const size = _stickRadius * 2;
    final stick = _stickValue ?? Vector2.zero();
    return GestureDetector(
      onPanStart: (d) => _onStick(d.localPosition, const Size(size, size)),
      onPanUpdate: (d) => _onStick(d.localPosition, const Size(size, size)),
      onPanEnd: (_) {
        setState(() => _stickValue = null);
        _sync();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Transform.translate(
            offset: Offset(stick.x * _stickRadius, -stick.y * _stickRadius),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _jumpButton() {
    return GestureDetector(
      onTapDown: (_) {
        _buttonJump = true;
        _sync();
      },
      onTapUp: (_) {
        _buttonJump = false;
        _sync();
      },
      onTapCancel: () {
        _buttonJump = false;
        _sync();
      },
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        ),
        child: const Icon(Icons.arrow_upward, color: Colors.white, size: 32),
      ),
    );
  }
}
