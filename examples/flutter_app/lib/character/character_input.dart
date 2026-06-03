import 'package:vector_math/vector_math.dart';

/// Per-frame movement intent for a character, written by an input source
/// (keyboard, touch joystick, gamepad) and read by [CharacterController].
///
/// Keeping intent in a plain value here decouples the controller from any
/// particular input device or widget tree: a demo wires whatever controls
/// it likes to the same fields.
class CharacterInput {
  /// Desired move direction in the camera's horizontal plane, with `y`
  /// forward (away from the camera) and `x` right. Each component is in
  /// `[-1, 1]`; the magnitude scales speed up to the controller's maximum,
  /// so a half-pushed joystick walks and a full push runs.
  Vector2 move = Vector2.zero();

  /// Whether the jump control is currently held. The controller
  /// edge-triggers on the press, so holding it does not auto-bounce.
  bool jump = false;

  /// Held camera-orbit rate from keys (arrow keys), each in `[-1, 1]`:
  /// `x` orbits left/right, `y` tilts. Applied per frame, scaled by a
  /// rate, by whoever drives the camera.
  Vector2 lookRate = Vector2.zero();

  /// Accumulated camera-orbit delta from a drag, in logical pixels. The
  /// camera driver applies and then zeroes it each frame.
  Vector2 lookDelta = Vector2.zero();
}
