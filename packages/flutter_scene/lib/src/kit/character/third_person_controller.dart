import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/raycast.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// High-level 3rd-person character movement component with ground raycast snapping,
/// slope sliding, coyote time, and turn smoothing.
///
/// For physical character navigation against 3D colliders and capsules with autostep,
/// see `KinematicCharacterController` in `package:flutter_scene_rapier/physics.dart`.
///
/// Note on raycasting: [raycastNode] performs a hierarchical bounding-box early-out followed
/// by per-triangle intersection tests on static render meshes at rest pose.
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

  /// Time window (in seconds) after leaving a ledge during which a jump is still allowed.
  double coyoteTimeWindow;

  /// Time window (in seconds) to buffer jump inputs before touching the ground.
  double jumpBufferWindow;

  /// Bitmask of layers to test for ground (defaults to all layers).
  int groundLayerMask;

  /// Optional fixed ground plane height. When set, snaps the character if falling below this Y value.
  double? groundPlaneHeight;

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
    this.coyoteTimeWindow = 0.12,
    this.jumpBufferWindow = 0.15,
    this.groundLayerMask = 0xFFFFFFFF,
    this.groundPlaneHeight,
  });

  /// Feeds planar movement input vector (-1.0 to 1.0 on X/Y, where +Y is forward).
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

  bool _isExcluded(Node hitNode) {
    if (hitNode == node) return true;
    Node? p = hitNode.parent;
    while (p != null) {
      if (p == node) return true;
      p = p.parent;
    }
    return false;
  }

  @override
  void fixedUpdate(double fixedDt) {
    if (fixedDt <= 0.0 || !isAttached) return;

    // Update timers
    if (_coyoteTimer > 0.0) _coyoteTimer -= fixedDt;
    if (_jumpBufferTimer > 0.0) _jumpBufferTimer -= fixedDt;

    final currentPos = (node.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;

    // 1. Ground detection probe via scene raycast
    var detectedGround = false;
    var groundY = currentPos.y;
    var norm = vm.Vector3(0, 1, 0);

    // Cast downward ray starting 0.4m above the character base
    final rayStart = currentPos + vm.Vector3(0, 0.4, 0);
    final ray = vm.Ray.originDirection(rayStart, vm.Vector3(0, -1, 0));
    final hit = raycastNode(
      _rootNode,
      ray,
      maxDistance: 0.8,
      layerMask: groundLayerMask,
      where: (n) => !_isExcluded(n),
    );

    if (hit != null && hit.distance <= 0.7) {
      detectedGround = true;
      groundY = rayStart.y - hit.distance;
      norm = hit.worldNormal;
    } else if (groundPlaneHeight != null &&
        currentPos.y <= groundPlaneHeight! + 0.05) {
      detectedGround = true;
      groundY = groundPlaneHeight!;
    }

    if (detectedGround &&
        (isGrounded || currentPos.y <= groundY + 0.1 || velocity.y <= 0.0)) {
      if (!isGrounded) {
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
      velocity.y -= gravity * fixedDt;
    }

    // 4. Horizontal movement calculation (exponential smoothing)
    final targetSpeed = walkSpeed * (_isRunning ? runMultiplier : 1.0);
    final inputLen = _moveInput.length;

    if (inputLen > 0.01) {
      final inputDir = _moveInput.normalized();
      final desiredVelX = inputDir.x * targetSpeed;
      final desiredVelZ = inputDir.y * targetSpeed;

      final accelRate = isGrounded ? 15.0 : 4.0;
      final t = 1.0 - math.exp(-accelRate * fixedDt);
      velocity.x += (desiredVelX - velocity.x) * t;
      velocity.z += (desiredVelZ - velocity.z) * t;

      final targetYaw = math.atan2(inputDir.x, inputDir.y);
      var angleDiff = targetYaw - _currentYaw;
      while (angleDiff > math.pi) {
        angleDiff -= 2 * math.pi;
      }
      while (angleDiff < -math.pi) {
        angleDiff += 2 * math.pi;
      }
      final rotT = 1.0 - math.exp(-turnSpeed * fixedDt);
      _currentYaw += angleDiff * rotT;
    } else {
      final friction = isGrounded ? 12.0 : 2.0;
      final t = 1.0 - math.exp(-friction * fixedDt);
      velocity.x += (0.0 - velocity.x) * t;
      velocity.z += (0.0 - velocity.z) * t;
    }

    // Slope sliding
    if (isGrounded && isTooSteep) {
      final slideDir = vm.Vector3(
        groundNormal.x,
        0,
        groundNormal.z,
      ).normalized();
      velocity.x += slideDir.x * gravity * fixedDt;
      velocity.z += slideDir.z * gravity * fixedDt;
    }

    // 5. Apply displacement converting world position back to parent local space
    var newWorldPos = currentPos + velocity * fixedDt;
    if (isGrounded) {
      newWorldPos.y = groundY;
    }

    // TODO(kit): implement forward-probe step climbing against kinematic obstacles.

    final newWorldRot = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      _currentYaw,
    );
    final worldMat = vm.Matrix4.compose(newWorldPos, newWorldRot, node.scale);

    final parent = node.parent;
    if (parent != null) {
      final invParent = parent.globalTransform.clone()..invert();
      node.localTransform = invParent * worldMat;
    } else {
      node.localTransform = worldMat;
    }
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
      coyoteTimeWindow: coyoteTimeWindow,
      jumpBufferWindow: jumpBufferWindow,
      groundLayerMask: groundLayerMask,
      groundPlaneHeight: groundPlaneHeight,
    );
  }
}
