import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';
import 'quake_camera.dart';

/// A live widget subtree streamed onto scene geometry via [WidgetComponent]:
/// the component owns the panel quad, captures the widget whenever it
/// repaints, and binds the texture to the material. SceneView hosts the
/// widget invisibly; it never appears in the 2D UI. Taps and drags raycast
/// through `scene.raycast` and forward into the widgets at the hit UV.
class ExampleWidgetTexture extends StatefulWidget {
  const ExampleWidgetTexture({super.key});

  @override
  State<ExampleWidgetTexture> createState() => _ExampleWidgetTextureState();
}

class _ExampleWidgetTextureState extends State<ExampleWidgetTexture> {
  final Scene scene = Scene();
  // The material is provided (tier 3 implicit binding) so the recursive
  // toggle can also swap its texture by hand.
  final UnlitMaterial _material = UnlitMaterial()..alphaMode = AlphaMode.blend;
  late final WidgetComponent _component;
  Node? _panel;
  // Free-look camera (WASD + space/shift, drag to look). A drag that starts
  // on the widget panel forwards to the widgets instead.
  final QuakeCamera _quakeCamera = QuakeCamera(
    position: vm.Vector3(0, 1.2, 4.5),
    pitch: -0.15,
  )..speed = 6.0;
  PerspectiveCamera? _camera;
  bool _dragging = false;
  bool _recursive = false;

  @override
  void initState() {
    super.initState();
    scene.add(
      Node(
        name: 'floor',
        localTransform: vm.Matrix4.translation(vm.Vector3(0, -1.2, 0)),
        mesh: Mesh(
          PlaneGeometry(width: 8, depth: 8),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.25, 0.3, 0.4, 1.0)
            ..roughnessFactor = 0.7,
        ),
      ),
    );
    _component = WidgetComponent(
      child: const _PanelContent(),
      size: const Size(480, 300),
      pixelRatio: 2.0,
      worldHeight: 2.0,
      material: _material,
    );
    final panel = Node(name: 'panel')..addComponent(_component);
    // A solid backing box, slightly extruded, so the panel reads as an
    // object with depth and stays visible from behind (the widget quad
    // itself is front-facing only).
    panel.add(
      Node(
        name: 'panelBacking',
        localTransform: vm.Matrix4.translation(vm.Vector3(0, 0, -0.07)),
        mesh: Mesh(
          CuboidGeometry(vm.Vector3(3.4, 2.2, 0.12)),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.12, 0.13, 0.17, 1.0)
            ..roughnessFactor = 0.4,
        ),
      ),
    );
    _panel = panel;
    scene.add(panel);
  }

  /// Maps a tap inside the view to texture UV on the panel, or null when the
  /// ray misses or other geometry is in front. The tap is unprojected
  /// through the camera into a world ray; `scene.raycast` returns the
  /// nearest render-geometry hit with the surface UV interpolated from the
  /// vertex data, so any panel shape works and the floor occludes correctly.
  Offset? _panelUv(Offset position, Size viewSize) {
    final camera = _camera;
    if (camera == null || viewSize.isEmpty) return null;

    final viewProjection =
        camera.projection.getProjectionMatrix(
          viewSize.width / viewSize.height,
        ) *
        camera.getViewMatrix();
    final inverse = vm.Matrix4.inverted(viewProjection as vm.Matrix4);
    final ndc = vm.Vector2(
      position.dx / viewSize.width * 2 - 1,
      1 - position.dy / viewSize.height * 2,
    );
    vm.Vector3 unproject(double z) {
      final v = inverse * vm.Vector4(ndc.x, ndc.y, z, 1) as vm.Vector4;
      return v.xyz / v.w;
    }

    final near = unproject(0.0);
    final hit = scene.raycast(
      vm.Ray.originDirection(near, unproject(1.0) - near),
    );
    if (hit == null || hit.node != _panel) return null;
    final uv = hit.uv!;
    return Offset(uv.x, uv.y);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _quakeCamera.onKeyEvent,
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (details) {
                final uv = _panelUv(details.localPosition, constraints.biggest);
                if (uv != null) {
                  _dragging = true;
                  _component.controller.pointerDown(uv);
                }
              },
              onPanUpdate: (details) {
                if (_dragging) {
                  final uv = _panelUv(
                    details.localPosition,
                    constraints.biggest,
                  );
                  if (uv != null) _component.controller.pointerMove(uv);
                } else {
                  _quakeCamera.look(details.delta);
                }
              },
              onPanEnd: (details) {
                if (!_dragging) return;
                _dragging = false;
                final uv = _panelUv(details.localPosition, constraints.biggest);
                if (uv != null) {
                  _component.controller.pointerUp(uv);
                } else {
                  _component.controller.pointerCancel();
                }
              },
              onPanCancel: () {
                if (_dragging) {
                  _dragging = false;
                  _component.controller.pointerCancel();
                }
              },
              child: SceneView(
                scene,
                cameraBuilder: (elapsed) {
                  _quakeCamera.move(elapsed.inMicroseconds / 1e6);
                  return _camera = _quakeCamera.camera;
                },
                onTick: (elapsed, deltaSeconds) {
                  exampleSettings.applyTo(scene);
                  _panel?.localTransform = vm.Matrix4.rotationY(
                    elapsed.inMicroseconds / 4e6,
                  );
                  // Recursive mode samples the scene's own previous frame, a
                  // one-frame feedback loop (an infinite mirror as the camera
                  // orbits). Otherwise the panel shows the live widget capture.
                  final feedback = _recursive
                      ? scene.surface.lastSwapchainColorTexture()
                      : null;
                  _material.baseColorTexture =
                      feedback ??
                      _component.controller.texture ??
                      _material.baseColorTexture;
                },
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'recursive',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Switch(
                  value: _recursive,
                  onChanged: (value) => setState(() => _recursive = value),
                ),
              ],
            ),
          ),
          // Capture diagnostics.
          Positioned(
            left: 8,
            bottom: 8,
            child: ListenableBuilder(
              listenable: _component.controller,
              builder: (context, _) => Text(
                'captures: ${_component.controller.captureCount}  '
                'last: ${_component.controller.lastCaptureDuration.inMilliseconds}ms',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ordinary animated Flutter UI; everything here runs live while textured
/// onto the cube.
class _PanelContent extends StatefulWidget {
  const _PanelContent();

  @override
  State<_PanelContent> createState() => _PanelContentState();
}

class _PanelContentState extends State<_PanelContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  int _presses = 0;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B2433),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Hello from the widget tree',
            style: TextStyle(color: Colors.white, fontSize: 28),
          ),
          const SizedBox(height: 16),
          RotationTransition(turns: _spin, child: const FlutterLogo(size: 96)),
          const SizedBox(height: 16),
          const SizedBox(
            width: 220,
            child: LinearProgressIndicator(minHeight: 6),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => setState(() => _presses++),
            child: Text('Pressed $_presses times'),
          ),
        ],
      ),
    );
  }
}
