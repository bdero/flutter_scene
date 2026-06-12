import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_cuboid.dart' show SpinComponent;
import 'example_settings.dart';

/// Offscreen render targets displayed as HUD widgets.
///
/// Three scene-owned views render into [RenderTexture]s alongside the main
/// view, a top-down minimap on a 500 ms update interval, and a pair of
/// fixed-camera insets comparing anti-aliasing off against the scene's
/// mode. The comparison targets are deliberately low resolution and drawn
/// upscaled with nearest sampling, so the effect of the AA mode is visible
/// regardless of display density.
class ExampleRenderTarget extends StatefulWidget {
  const ExampleRenderTarget({super.key});

  @override
  ExampleRenderTargetState createState() => ExampleRenderTargetState();
}

class ExampleRenderTargetState extends State<ExampleRenderTarget> {
  Scene scene = Scene();

  final RenderTexture _minimap = RenderTexture(
    width: 320,
    height: 320,
    update: const RenderTextureUpdate.interval(Duration(milliseconds: 500)),
  );
  final RenderTexture _aaOff = RenderTexture(width: 240, height: 180);
  final RenderTexture _aaScene = RenderTexture(width: 240, height: 180);

  @override
  void initState() {
    final mesh = Mesh(
      CuboidGeometry(vm.Vector3(1, 1, 1), debugColors: true),
      UnlitMaterial(),
    );
    scene.add(Node(mesh: mesh)..addComponent(SpinComponent(-1.5)));

    final compareCamera = PerspectiveCamera(
      position: vm.Vector3(2.2, 1.2, 2.2),
      target: vm.Vector3(0, 0, 0),
    );
    scene.views.addAll([
      RenderView(
        camera: PerspectiveCamera(
          position: vm.Vector3(0, 4, 0.01),
          target: vm.Vector3(0, 0, 0),
        ),
        target: _minimap,
      ),
      RenderView(
        camera: compareCamera,
        target: _aaOff,
        antiAliasingMode: AntiAliasingMode.none,
      ),
      RenderView(camera: compareCamera, target: _aaScene),
    ]);

    super.initState();
  }

  Widget _inset(String label, RenderTexture target, {required double width}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: width,
          height: width * target.height / target.width,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white54),
            color: Colors.black26,
          ),
          // Nearest sampling keeps the upscale honest: each texture pixel
          // maps to a visible block, so the AA comparison reads clearly.
          child: RenderTextureView(
            target,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
          ),
        ),
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SceneView(
          scene,
          cameraBuilder: (elapsed) {
            final t = elapsed.inMicroseconds / 1e6;
            return PerspectiveCamera(
              position: vm.Vector3(sin(t * 0.4) * 5, 2, cos(t * 0.4) * 5),
              target: vm.Vector3(0, 0, 0),
            );
          },
          onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: _inset(
            'Top-down view (re-renders every 500 ms)',
            _minimap,
            width: 160,
          ),
        ),
        Positioned(
          bottom: 12,
          left: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _inset('Anti-aliasing off', _aaOff, width: 240),
              const SizedBox(width: 12),
              _inset('Scene anti-aliasing', _aaScene, width: 240),
            ],
          ),
        ),
      ],
    );
  }
}
