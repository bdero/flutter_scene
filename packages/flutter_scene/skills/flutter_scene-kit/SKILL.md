---
name: flutter_scene-kit
version: 3
description: Build interactive 3D gameplay, character controllers, camera rigs, dynamic day/night cycles, water surfaces, audio, pooling, and debug overlays in flutter_scene. Use when creating game mechanics, camera controls, NPC behaviors, atmospheric environments, or diagnostic HUDs.
---

# Gameplay, camera, and atmosphere kit in flutter_scene

Flutter Scene provides high-level gameplay components and ergonomic building blocks in `package:flutter_scene/kit.dart` so games and interactive experiences do not need to re-implement standard mechanics from scratch.

When choosing components, consider existing engine alternatives:
- For physics-driven character navigation with collider capsules, wall sliding, and autostep, use `KinematicCharacterController` from `package:flutter_scene/physics.dart`.
- For interactive mouse/touch orbit cameras with inertia, use `OrbitCameraController` or `FollowCameraController`.
- For framing a standalone `PerspectiveCamera`, use `PerspectiveCamera.framing`. Use `BoundsFraming` when computing a transform for a `NodeCamera` mounted in the scene graph.

## Imports

```dart
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/kit.dart';
import 'package:vector_math/vector_math.dart' as vm;
```

## Camera rigs and smoothing

### SpringArmComponent

`SpringArmComponent` attaches to a target character node and mounts a camera node at the arm's socket. It casts rays against the scene hierarchy to prevent geometry clipping, smoothly pulling the camera inward when colliding with walls.

Note on offsets: `targetOffset` is applied in world space from the character node's origin, and `socketOffset` acts in the camera socket's local plane along X (right) and Y (up).

```dart
final characterNode = Node();
final cameraNode = Node();
final cameraArm = SpringArmComponent(
  targetLength: 5.0,
  targetOffset: vm.Vector3(0, 1.6, 0), // Eye height
  socketOffset: vm.Vector3(0.5, 0, 0), // Over-the-shoulder
  enablePositionLag: true,
  positionLagSpeed: 8.0,
  cameraNode: cameraNode,
);

characterNode.addComponent(cameraArm);
scene.root.add(characterNode);
scene.root.add(cameraNode);
```

### CameraShake

`CameraShake` implements a trauma-decay model driven by deterministic simplex noise for organic multi-axis camera shake (explosions, footsteps, hits).

```dart
final shake = CameraShake(decayRate: 1.2, frequency: 25.0);

// Add trauma on hit
shake.addTrauma(0.6);

// Inside game loop
final offset = shake.update(deltaSeconds);
cameraNode.localTransform = baseTransform * offset.toMatrix4();
```

## Character movement and steering

### ThirdPersonControllerComponent

`ThirdPersonControllerComponent` handles kinematic movement, sprint multipliers, turn smoothing, ground snapping with raycasts, slope sliding, coyote time, and buffered jumps. Input expects `+Y` as forward in 3D.

```dart
final playerNode = Node();
final controller = ThirdPersonControllerComponent(
  walkSpeed: 4.5,
  runMultiplier: 1.8,
  jumpVelocity: 7.0,
  groundPlaneHeight: 0.0, // Optional fallback floor
);
playerNode.addComponent(controller);

// When using VirtualJoystick (where up is -Y in screen space), invert Y:
// controller.setMoveInput(vm.Vector2(joystickDir.x, -joystickDir.y), isRunning: isSprinting);
if (jumpPressed) controller.jump();
```

### Autonomous Steering Behaviors

`Steering` provides math helpers for NPC navigation, flocking, and crowd dynamics.

```dart
// Seek target
final seekForce = Steering.seek(npcPos, npcVel, targetPos, maxSpeed: 4.0);

// Arrive smoothly
final arriveForce = Steering.arrive(npcPos, npcVel, targetPos, slowingRadius: 3.0);

// Flocking separation
final sepForce = Steering.separation(npcPos, npcVel, neighborPositions, desiredDistance: 1.5);
```

## Dynamic environments and atmosphere

### DayNightCycleComponent

`DayNightCycleComponent` moves the sun along a realistic solar arc given latitude and time of day, evaluating sun colors, intensities, and ambient lighting transitions.

```dart
final sunLight = DirectionalLight();
final sunNode = Node()..addComponent(DirectionalLightComponent(sunLight));
scene.root.add(sunNode);

final skyCycle = DayNightCycleComponent(
  timeOfDay: 14.5, // 2:30 PM
  timeSpeed: 0.1,  // Progress 0.1 hours per second
  latitude: 34.0,
  sunLightNode: sunNode,
);
scene.root.addComponent(skyCycle);
```

### WaterSurfaceComponent

`WaterSurfaceComponent` evaluates multi-harmonic Gerstner trochoidal waves for water surfaces and floating buoyancy queries.

```dart
final water = WaterSurfaceComponent();
final surface = water.evaluateAt(vm.Vector2(playerPos.x, playerPos.z));
final waterHeight = surface.displacement.y;
final waterNormal = surface.normal;
```

## Immediate-mode debug visualization

`DebugDraw` provides static immediate-mode line, ray, box, sphere, and axis drawing utilities for physics debugging and AI visualizers.

```dart
DebugDraw.line(startPos, endPos, color: vm.Vector4(1, 0, 0, 1));
DebugDraw.box(aabb, color: vm.Vector4(0, 1, 0, 1));
DebugDraw.sphere(center, 1.0, color: vm.Vector4(0, 0, 1, 1));
DebugDraw.axes(node.globalTransform, size: 2.0);

// Render debug lines
final debugMesh = DebugDraw.flushMesh();
if (debugMesh != null) {
  debugNode.mesh = Mesh(debugMesh, UnlitMaterial());
}
```
