import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/raycast.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A camera boom component that maintains distance to a target while preventing
/// geometry occlusion by raycasting against the environment.
///
/// For a full-featured orbit camera controller with mouse/touch drag and inertial damping,
/// see `FollowCameraController` and `OrbitCameraController`.
///
/// Note on raycasting: [raycastNode] performs a hierarchical bounding-box early-out followed
/// by per-triangle intersection tests on static render meshes at rest pose.
/// {@category Gameplay kit}
class SpringArmComponent extends Component {
  /// Desired length of the boom arm when unoccluded.
  double targetLength;

  /// Current actual length of the boom after occlusion and smoothing.
  double currentLength;

  /// Radius of the sphere probe used to test for obstacles (0.0 for a thin ray).
  double probeRadius;

  /// Local offset applied along world axes from the owning node's origin to the boom's pivot.
  vm.Vector3 targetOffset;

  /// Local offset applied at the camera socket end along socket right (X) and up (Y).
  vm.Vector3 socketOffset;

  /// Whether the boom position smoothly lags behind the target.
  bool enablePositionLag;

  /// Speed at which the lagged position catches up to the target (higher = faster).
  double positionLagSpeed;

  /// Minimum distance the arm can compress to when obstructed.
  double minLength;

  /// Bitmask of layers to test for occlusion (defaults to all layers).
  int layerMask;

  /// Whether to inherit yaw rotation from the owning node.
  bool inheritYaw;

  /// Whether to inherit pitch rotation from the owning node.
  bool inheritPitch;

  /// Boom yaw angle in radians (used when [inheritYaw] is false).
  double yaw;

  /// Boom pitch angle in radians (used when [inheritPitch] is false).
  double pitch;

  /// An optional child camera node driven directly by this spring arm.
  Node? cameraNode;

  vm.Vector3 _smoothedPivotWorld = vm.Vector3.zero();
  vm.Matrix4 _cachedSocketTransform = vm.Matrix4.identity();
  bool _initialized = false;

  SpringArmComponent({
    double targetLength = 4.0,
    this.probeRadius = 0.2,
    vm.Vector3? targetOffset,
    vm.Vector3? socketOffset,
    this.enablePositionLag = false,
    this.positionLagSpeed = 10.0,
    this.minLength = 0.5,
    this.layerMask = 0xFFFFFFFF,
    this.cameraNode,
    this.inheritYaw = true,
    this.inheritPitch = true,
    this.yaw = 0.0,
    this.pitch = 0.0,
  }) : targetLength = math.max(minLength, targetLength),
       currentLength = math.max(minLength, targetLength),
       targetOffset = targetOffset?.clone() ?? vm.Vector3(0, 1.5, 0),
       socketOffset = socketOffset?.clone() ?? vm.Vector3.zero();

  /// Gets the world-space socket transform computed for this frame.
  vm.Matrix4 get socketTransform => _cachedSocketTransform;

  /// Effective yaw angle of the boom.
  double get effectiveYaw {
    if (!inheritYaw || !isAttached) return yaw;
    final ownerRot = vm.Quaternion.identity();
    node.globalTransform.decompose(
      vm.Vector3.zero(),
      ownerRot,
      vm.Vector3.zero(),
    );
    final qx = ownerRot.x;
    final qy = ownerRot.y;
    final qz = ownerRot.z;
    final qw = ownerRot.w;
    final ownerYaw = math.atan2(
      2 * (qw * qy + qz * qx),
      1 - 2 * (qy * qy + qz * qz),
    );
    return ownerYaw + yaw;
  }

  /// Effective pitch angle of the boom.
  double get effectivePitch {
    if (!inheritPitch || !isAttached) return pitch;
    final ownerRot = vm.Quaternion.identity();
    node.globalTransform.decompose(
      vm.Vector3.zero(),
      ownerRot,
      vm.Vector3.zero(),
    );
    final qx = ownerRot.x;
    final qy = ownerRot.y;
    final qz = ownerRot.z;
    final qw = ownerRot.w;
    final sinp = (2 * (qw * qx - qy * qz)).clamp(-1.0, 1.0);
    final ownerPitch = math.asin(sinp);
    return (ownerPitch + pitch).clamp(-1.4, 1.4);
  }

  vm.Vector3 get _currentRawPivotWorld {
    if (!isAttached) return targetOffset.clone();
    final parentPos = vm.Vector3.zero();
    node.globalTransform.decompose(
      parentPos,
      vm.Quaternion.identity(),
      vm.Vector3.zero(),
    );
    return parentPos + targetOffset;
  }

  static vm.Vector3 _computeEyePosition(
    vm.Vector3 pivot,
    double yAngle,
    double pAngle,
    double dist,
  ) {
    final horizontal = math.cos(pAngle) * dist;
    return pivot +
        vm.Vector3(-math.sin(yAngle), 0.0, -math.cos(yAngle)) * horizontal +
        vm.Vector3(0.0, math.sin(pAngle) * dist, 0.0);
  }

  Node get _rootNode {
    Node curr = node;
    while (curr.parent != null) {
      curr = curr.parent!;
    }
    return curr;
  }

  bool _isExcluded(Node hitNode) {
    if (hitNode == node || hitNode == cameraNode) return true;
    Node? p = hitNode.parent;
    while (p != null) {
      if (p == node || p == cameraNode) return true;
      p = p.parent;
    }
    return false;
  }

  @override
  void onMount() {
    _smoothedPivotWorld = _currentRawPivotWorld;
    currentLength = targetLength;
    _updateSocketTransform();
    _initialized = true;
  }

  void _updateSocketTransform() {
    final currentYaw = effectiveYaw;
    final currentPitch = effectivePitch.clamp(-1.4, 1.4);
    final eye = _computeEyePosition(
      _smoothedPivotWorld,
      currentYaw,
      currentPitch,
      currentLength,
    );
    final lookDir = (_smoothedPivotWorld - eye).normalized();
    final right = vm.Vector3(0, 1, 0).cross(lookDir).normalized();
    final offsetEye =
        eye + right * socketOffset.x + vm.Vector3(0, 1, 0) * socketOffset.y;
    final offsetTarget =
        _smoothedPivotWorld +
        right * socketOffset.x +
        vm.Vector3(0, 1, 0) * socketOffset.y;

    _cachedSocketTransform = Node.lookAtTransform(
      offsetEye,
      offsetTarget,
      up: vm.Vector3(0, 1, 0),
    );
  }

  @override
  void update(double deltaSeconds) {
    if (!_initialized) onMount();
    if (deltaSeconds <= 0.0) return;

    final rawPivot = _currentRawPivotWorld;

    // 1. Position lag smoothing (exponential)
    if (enablePositionLag && positionLagSpeed > 0.0) {
      final t = 1.0 - math.exp(-positionLagSpeed * deltaSeconds);
      _smoothedPivotWorld =
          _smoothedPivotWorld + (rawPivot - _smoothedPivotWorld) * t;
    } else {
      _smoothedPivotWorld = rawPivot;
    }

    final currentYaw = effectiveYaw;
    final currentPitch = effectivePitch.clamp(-1.4, 1.4);

    // 2. Occlusion query from pivot along boom direction toward desired eye
    final unoccludedEye = _computeEyePosition(
      _smoothedPivotWorld,
      currentYaw,
      currentPitch,
      targetLength,
    );
    final rayDir = (unoccludedEye - _smoothedPivotWorld).normalized();
    final ray = vm.Ray.originDirection(_smoothedPivotWorld, rayDir);

    var desiredLength = targetLength;
    final hit = raycastNode(
      _rootNode,
      ray,
      maxDistance: targetLength,
      layerMask: layerMask,
      where: (n) => !_isExcluded(n),
    );
    if (hit != null && hit.distance < targetLength) {
      desiredLength = math.max(minLength, hit.distance - probeRadius);
    }

    // Smoothly compress or expand current length
    if (desiredLength < currentLength) {
      currentLength = desiredLength;
    } else {
      final t = (1.0 - math.exp(-12.0 * deltaSeconds)).clamp(0.0, 1.0);
      currentLength = currentLength + (desiredLength - currentLength) * t;
    }

    // 3. Compute final camera socket transform
    _updateSocketTransform();

    // 4. Update child camera node converting world socket to local space
    if (cameraNode != null) {
      final camParent = cameraNode!.parent;
      if (camParent != null) {
        final invParent = camParent.globalTransform.clone()..invert();
        cameraNode!.localTransform = invParent * _cachedSocketTransform;
      } else {
        cameraNode!.localTransform = _cachedSocketTransform;
      }
    }
  }

  @override
  Component? cloneFor(Node cloneOwner) {
    if (cameraNode != null) {
      // Caller-driven rebinding needed when referencing external nodes.
      return null;
    }
    return SpringArmComponent(
      targetLength: targetLength,
      probeRadius: probeRadius,
      targetOffset: targetOffset.clone(),
      socketOffset: socketOffset.clone(),
      enablePositionLag: enablePositionLag,
      positionLagSpeed: positionLagSpeed,
      minLength: minLength,
      layerMask: layerMask,
      inheritYaw: inheritYaw,
      inheritPitch: inheritPitch,
      yaw: yaw,
      pitch: pitch,
    );
  }
}
