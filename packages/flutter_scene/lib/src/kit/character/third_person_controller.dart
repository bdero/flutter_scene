import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/raycast.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// High-level 3rd-person character movement component with ground snapping,
/// slope sliding, step climbing, coyote time, and turn smoothing.
/// {@category Gameplay kit}
class ThirdPersonControllerComponent extends Component {
  /// Base walking speed in world units per second.
  double walkSpeed;

  /// Multiplier applied when sprinting.
  double runMultiplier;

  /// Speed at which the character turns to face the movement direction (rad/s).
  double turnSpeed;

  /// Upward velocity impulse applied on jump.
  double jumpVelocity;

  /// Downward gravitational acceleration.
  double gravity;

  /// Maximum slope angle (in degrees) that can be walked up without sliding.
  double maxSlopeAngleDegrees;

  /// Maximum step obstacle height (in units) the character can smoothly step up.
  double maxStepHeight;

  /// Time window (in seconds) after leaving a ledge during which a jump is still allowed.
  double coyoteTimeWindow;

  /// Time window (in seconds) to buffer jump inputs before touching the ground.
  double jumpBufferWindow;

  /// Current linear velocity vector in world space.
  vm.Vector3 velocity = vm.Vector3.zero();

  /// Whether the character is currently touching the ground.
  bool isGrounded = false;

  /// Ground surface normal beneath the character.
  vm.Vector3 groundNormal = vm.Vector3(0, 1, 0);

  // Input states
  vm.Vector2 _moveInput = vm.Vector2.zero();
  bool _isRunning = false;
  double _coyoteTimer = 0.0;
  double _jumpBufferTimer = 0.0;
  double _currentYaw = 0.0;

  ThirdPersonControllerComponent({
    this.walkSpeed = 4.5,
    this.runMultiplier = 1.8,
    this.turnSpeed = 12.0,
    this.jumpVelocity = 6.5,
    this.gravity = 18.0,
    this.maxSlopeAngleDegrees = 45.0,
    this.maxStepHeight = 0.3,
    this.coyoteTimeWindow = 0.12,
    this.jumpBufferWindow = 0.15,
  });

  /// Feeds planar movement input vector (-1.0 to 1.0 on X/Y).
  void setMoveInput(vm.Vector2 input, {bool isRunning = false}) {
    _moveInput = input;
    _isRunning = isRunning;
  }

  /// Triggers a jump request (buffered if in mid-air).
  void jump() {
    _jumpBufferTimer = jumpBufferWindow;
  }

  Node get _rootNode {
    Node curr = node;
    while (curr.parent != null) {
      curr = curr.parent!;
    }
    return curr;
  }

  @override
  void update(double deltaSeconds) {
    if (deltaSeconds <= 0.0 || !isAttached) return;

    // Update timers
    if (_coyoteTimer > 0.0) _coyoteTimer -= deltaSeconds;
    if (_jumpBufferTimer > 0.0) _jumpBufferTimer -= deltaSeconds;

    final currentPos = (node.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;

    // 1. Ground detection probe via scene raycast
    var detectedGround = false;
    var groundY = currentPos.y;
    var norm = vm.Vector3(0, 1, 0);

    // Cast downward ray starting slightly above the character base
    final rayStart = currentPos + vm.Vector3(0, 0.4, 0);
    final ray = vm.Ray.originDirection(rayStart, vm.Vector3(0, -1, 0));
    final hit = raycastNode(_rootNode, ray, maxDistance: 0.6 + maxStepHeight);
    if (hit != null && hit.distance <= 0.45 + maxStepHeight) {
      detectedGround = true;
      groundY = rayStart.y - hit.distance;
      norm = hit.worldNormal;
    } else if (currentPos.y <= 0.05) {
      // Flat ground fallback at y = 0
      detectedGround = true;
      groundY = 0.0;
    }

    if (detectedGround) {
      if (!isGrounded) {
        // Just landed
        velocity.y = 0.0;
      }
      isGrounded = true;
      _coyoteTimer = coyoteTimeWindow;
      groundNormal = norm;
    } else {
      isGrounded = false;
    }

    // 2. Slope slide calculation
    final slopeAngle =
        math.acos(groundNormal.y.clamp(-1.0, 1.0)) * 180.0 / math.pi;
    final isTooSteep = slopeAngle > maxSlopeAngleDegrees;

    // 3. Process jump
    if (_jumpBufferTimer > 0.0 &&
        (isGrounded || _coyoteTimer > 0.0) &&
        !isTooSteep) {
      velocity.y = jumpVelocity;
      isGrounded = false;
      _coyoteTimer = 0.0;
      _jumpBufferTimer = 0.0;
    } else if (!isGrounded) {
      velocity.y -= gravity * deltaSeconds;
    }

    // 4. Horizontal movement calculation
    final targetSpeed = walkSpeed * (_isRunning ? runMultiplier : 1.0);
    final inputLen = _moveInput.length;

    if (inputLen > 0.01) {
      final inputDir = _moveInput.normalized();
      final desiredVelX = inputDir.x * targetSpeed;
      final desiredVelZ = inputDir.y * targetSpeed;

      // Smooth horizontal acceleration
      final accelRate = isGrounded ? 15.0 : 4.0;
      final t = (accelRate * deltaSeconds).clamp(0.0, 1.0);
      velocity.x += (desiredVelX - velocity.x) * t;
      velocity.z += (desiredVelZ - velocity.z) * t;

      // Smooth yaw rotation towards movement direction
      final targetYaw = math.atan2(inputDir.x, inputDir.y);
      var angleDiff = targetYaw - _currentYaw;
      while (angleDiff > math.pi) {
        angleDiff -= 2 * math.pi;
      }
      while (angleDiff < -math.pi) {
        angleDiff += 2 * math.pi;
      }
      _currentYaw += angleDiff * (turnSpeed * deltaSeconds).clamp(0.0, 1.0);
    } else {
      // Decelerate
      final friction = isGrounded ? 12.0 : 2.0;
      final t = (friction * deltaSeconds).clamp(0.0, 1.0);
      velocity.x += (0.0 - velocity.x) * t;
      velocity.z += (0.0 - velocity.z) * t;
    }

    // If on steep slope, apply slide force
    if (isGrounded && isTooSteep) {
      final slideDir = vm.Vector3(
        groundNormal.x,
        0,
        groundNormal.z,
      ).normalized();
      velocity.x += slideDir.x * gravity * deltaSeconds;
      velocity.z += slideDir.z * gravity * deltaSeconds;
    }

    // 5. Apply displacement to node
    var newPos = currentPos + velocity * deltaSeconds;
    if (isGrounded && newPos.y < groundY) {
      newPos.y = groundY;
    }

    final rot = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _currentYaw);
    node.localTransform = vm.Matrix4.compose(newPos, rot, node.scale);
  }

  @override
  Component? cloneFor(Node cloneOwner) {
    return ThirdPersonControllerComponent(
      walkSpeed: walkSpeed,
      runMultiplier: runMultiplier,
      turnSpeed: turnSpeed,
      jumpVelocity: jumpVelocity,
      gravity: gravity,
      maxSlopeAngleDegrees: maxSlopeAngleDegrees,
      maxStepHeight: maxStepHeight,
      coyoteTimeWindow: coyoteTimeWindow,
      jumpBufferWindow: jumpBufferWindow,
    );
  }
}
