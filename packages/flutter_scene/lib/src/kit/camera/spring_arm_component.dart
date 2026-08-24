import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/raycast.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A camera boom component that maintains distance to a target while preventing
/// geometry occlusion by raycasting or sphere-probing against the environment.
/// {@category Gameplay kit}
class SpringArmComponent extends Component {
  /// Desired length of the boom arm when unoccluded.
  double targetLength;

  /// Current actual length of the boom after occlusion and smoothing.
  double currentLength;

  /// Radius of the sphere probe used to test for obstacles (0.0 for a thin ray).
  double probeRadius;

  /// Local offset from the owning node's origin to the boom's pivot.
  vm.Vector3 targetOffset;

  /// Local offset applied at the camera socket end (e.g. over-the-shoulder offset).
  vm.Vector3 socketOffset;

  /// Whether the boom position smoothly lags behind the target.
  bool enablePositionLag;

  /// Speed at which the lagged position catches up to the target (higher = faster).
  double positionLagSpeed;

  /// Whether the boom rotation smoothly lags behind the target rotation.
  bool enableRotationLag;

  /// Speed at which the lagged rotation catches up (higher = faster).
  double rotationLagSpeed;

  /// Minimum distance the arm can compress to when obstructed.
  double minLength;

  /// An optional child camera node driven directly by this spring arm.
  Node? cameraNode;

  vm.Vector3 _smoothedPivotWorld = vm.Vector3.zero();
  vm.Quaternion _smoothedRotation = vm.Quaternion.identity();
  bool _initialized = false;

  SpringArmComponent({
    double targetLength = 4.0,
    this.probeRadius = 0.2,
    vm.Vector3? targetOffset,
    vm.Vector3? socketOffset,
    this.enablePositionLag = false,
    this.positionLagSpeed = 10.0,
    this.enableRotationLag = false,
    this.rotationLagSpeed = 10.0,
    this.minLength = 0.5,
    this.cameraNode,
  }) : targetLength = math.max(minLength, targetLength),
       currentLength = math.max(minLength, targetLength),
       targetOffset = targetOffset ?? vm.Vector3(0, 1.5, 0),
       socketOffset = socketOffset ?? vm.Vector3.zero();

  /// Gets the world-space socket transform computed for this frame.
  vm.Matrix4 get socketTransform {
    final pivot = _initialized ? _smoothedPivotWorld : _currentRawPivotWorld;
    final rot = _initialized ? _smoothedRotation : _currentRawRotation;

    // Arm direction is back (-Z in model space) rotated by the boom rotation.
    final backDir = rot.rotate(vm.Vector3(0, 0, 1));
    final socketPos = pivot + backDir * currentLength;
    final finalPos = socketPos + rot.rotate(socketOffset);

    return vm.Matrix4.compose(finalPos, rot, vm.Vector3.all(1.0));
  }

  vm.Vector3 get _currentRawPivotWorld {
    if (!isAttached) return targetOffset;
    final parentWorld = node.globalTransform;
    return (parentWorld *
            vm.Vector4(targetOffset.x, targetOffset.y, targetOffset.z, 1.0))
        .xyz;
  }

  vm.Quaternion get _currentRawRotation {
    if (!isAttached) return vm.Quaternion.identity();
    final rot = vm.Quaternion.identity();
    node.globalTransform.decompose(vm.Vector3.zero(), rot, vm.Vector3.zero());
    return rot;
  }

  Node get _rootNode {
    Node curr = node;
    while (curr.parent != null) {
      curr = curr.parent!;
    }
    return curr;
  }

  @override
  void onMount() {
    _smoothedPivotWorld = _currentRawPivotWorld;
    _smoothedRotation = _currentRawRotation;
    currentLength = targetLength;
    _initialized = true;
  }

  @override
  void update(double deltaSeconds) {
    if (!_initialized) onMount();
    if (deltaSeconds <= 0.0) return;

    final rawPivot = _currentRawPivotWorld;
    final rawRot = _currentRawRotation;

    // 1. Position lag smoothing
    if (enablePositionLag && positionLagSpeed > 0.0) {
      final t = 1.0 - math.exp(-positionLagSpeed * deltaSeconds);
      _smoothedPivotWorld =
          _smoothedPivotWorld + (rawPivot - _smoothedPivotWorld) * t;
    } else {
      _smoothedPivotWorld = rawPivot;
    }

    // 2. Rotation lag smoothing
    if (enableRotationLag && rotationLagSpeed > 0.0) {
      final t = (1.0 - math.exp(-rotationLagSpeed * deltaSeconds)).clamp(
        0.0,
        1.0,
      );
      _smoothedRotation = _smoothedRotation.slerp(rawRot, t);
    } else {
      _smoothedRotation = rawRot;
    }

    // 3. Occlusion query
    var desiredLength = targetLength;
    final rayStart = _smoothedPivotWorld;
    final rayDir = _smoothedRotation.rotate(vm.Vector3(0, 0, 1)).normalized();

    // Query scene raycast if in tree
    final ray = vm.Ray.originDirection(rayStart, rayDir);
    final hit = raycastNode(_rootNode, ray, maxDistance: targetLength);
    if (hit != null && hit.distance < targetLength) {
      desiredLength = math.max(minLength, hit.distance - probeRadius);
    }

    // Smoothly compress or expand current length
    if (desiredLength < currentLength) {
      // Compress instantly to avoid wall clipping
      currentLength = desiredLength;
    } else {
      // Expand smoothly
      final t = (1.0 - math.exp(-12.0 * deltaSeconds)).clamp(0.0, 1.0);
      currentLength = currentLength + (desiredLength - currentLength) * t;
    }

    // 4. Update child camera node if bound
    if (cameraNode != null) {
      cameraNode!.localTransform = socketTransform;
    }
  }

  @override
  Component? cloneFor(Node cloneOwner) {
    return SpringArmComponent(
      targetLength: targetLength,
      probeRadius: probeRadius,
      targetOffset: targetOffset.clone(),
      socketOffset: socketOffset.clone(),
      enablePositionLag: enablePositionLag,
      positionLagSpeed: positionLagSpeed,
      enableRotationLag: enableRotationLag,
      rotationLagSpeed: rotationLagSpeed,
      minLength: minLength,
    );
  }
}
