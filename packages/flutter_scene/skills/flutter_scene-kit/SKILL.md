---
name: flutter_scene-kit
version: 1
description: Build interactive 3D gameplay, character controllers, camera rigs, dynamic day/night cycles, water surfaces, audio, pooling, and debug overlays in flutter_scene. Use when creating game mechanics, camera controls, NPC behaviors, atmospheric environments, or diagnostic HUDs.
---

# Gameplay, camera, and atmosphere kit in flutter_scene

Flutter Scene provides high-level gameplay components and ergonomic building blocks in `package:flutter_scene/kit.dart` so games and interactive experiences do not need to re-implement standard mechanics from scratch.

## Imports

```dart
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/kit.dart';
import 'package:vector_math/vector_math.dart' as vm;
```

## Camera rigs and smoothing

### SpringArmComponent

`SpringArmComponent` attaches to a target character node and mounts a camera node at the arm's socket. It casts rays against the scene hierarchy to prevent geometry clipping, smoothly pulling the camera inward when colliding with walls.

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

`ThirdPersonControllerComponent` handles planar movement, sprint multipliers, turn smoothing, ground snapping with raycasts, slope sliding, step climbing, coyote time, and buffered jumps.

```dart
final playerNode = Node();
final controller = ThirdPersonControllerComponent(
  walkSpeed: 4.5,
  runMultiplier: 1.8,
  jumpVelocity: 7.0,
);
playerNode.addComponent(controller);

// Feed joystick or keyboard input
controller.setMoveInput(vm.Vector2(inputX, inputY), isRunning: isSprinting);
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
final sepForce = Steering.separation(npcPos, neighborPositions, desiredDistance: 1.5);
```

## Dynamic environments and atmosphere

### DayNightCycleComponent

`DayNightCycleComponent` moves the sun along a realistic solar arc given latitude and time of day, evaluating sun colors, intensities, and ambient lighting transitions.

```dart
final sunNode = Node()..addComponent(DirectionalLightComponent());
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
  debugNode.mesh = Mesh(debugMesh, material: UnlitMaterial());
}
```
