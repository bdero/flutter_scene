import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_cuboid.dart' show SpinComponent;
import 'example_settings.dart';

/// Offscreen render targets displayed as HUD widgets.
///
/// A top-down minimap re-renders on a 500 ms interval, and two
/// configurable panels render the same fixed camera side by side. Each
/// panel has its own render resolution (the texture resizes while the
/// on-screen area stays fixed, so low resolutions pixelate), display
/// filtering, and per-view anti-aliasing mode, making the AA modes easy
/// to compare regardless of display density.
class ExampleRenderTarget extends StatefulWidget {
  const ExampleRenderTarget({super.key});

  @override
  ExampleRenderTargetState createState() => ExampleRenderTargetState();
}

/// One comparison panel's render target, view, and display settings.
class _ComparePanel {
  _ComparePanel({
    required this.target,
    required this.view,
    required this.height,
    required this.filter,
  });

  final RenderTexture target;
  final RenderView view;
  int height;
  FilterQuality filter;
}

class ExampleRenderTargetState extends State<ExampleRenderTarget> {
  static const double _aspect = 4 / 3;
  static const List<int> _heights = [1080, 720, 540, 360, 240, 180, 120, 90];

  Scene scene = Scene();

  final RenderTexture _minimap = RenderTexture(
    width: 320,
    height: 320,
    update: const RenderTextureUpdate.interval(Duration(milliseconds: 500)),
  );

  late final List<_ComparePanel> _panels;

  static int _widthFor(int height) => (height * _aspect).round();

  @override
  void initState() {
    final mesh = Mesh(
      CuboidGeometry(vm.Vector3(1, 1, 1), debugColors: true),
      UnlitMaterial(),
    );
    scene.add(Node(mesh: mesh)..addComponent(SpinComponent(-1.5)));

    // An in-scene monitor showing the minimap capture live: assigning the
    // RenderTexture to a material slot samples its latest completed
    // frame. The top-down camera sees this monitor too, so the capture
    // contains itself, one frame stale (no feedback loop).
    final monitorMaterial = UnlitMaterial();
    monitorMaterial.baseColorTexture = _minimap;
    final monitor = Node(
      mesh: Mesh(PlaneGeometry(width: 2.4, depth: 1.8), monitorMaterial),
    );
    monitor.localTransform =
        vm.Matrix4.translation(vm.Vector3(0, 0.4, -2.4)) *
        vm.Matrix4.rotationX(pi / 2);
    scene.add(monitor);

    final compareCamera = PerspectiveCamera(
      position: vm.Vector3(2.2, 1.2, 2.2),
      target: vm.Vector3(0, 0, 0),
    );
    _ComparePanel makePanel(AntiAliasingMode mode) {
      const height = 180;
      final target = RenderTexture(width: _widthFor(height), height: height);
      final view = RenderView(
        camera: compareCamera,
        target: target,
        antiAliasingMode: mode,
      );
      return _ComparePanel(
        target: target,
        view: view,
        height: height,
        filter: FilterQuality.none,
      );
    }

    _panels = [
      makePanel(AntiAliasingMode.none),
      makePanel(AntiAliasingMode.auto),
    ];

    scene.views.addAll([
      RenderView(
        camera: PerspectiveCamera(
          position: vm.Vector3(0, 4, 0.01),
          target: vm.Vector3(0, 0, 0),
        ),
        target: _minimap,
      ),
      for (final panel in _panels) panel.view,
    ]);

    super.initState();
  }

  Widget _label(String text) => Container(
    color: Colors.black54,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );

  Widget _dropdownRow<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) name,
    required void Function(T) onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: Colors.black87,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(name(item))),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => onChanged(value));
            }
          },
        ),
      ],
    );
  }

  Widget _comparePanel(_ComparePanel panel) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 240,
          height: 240 / _aspect,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white54),
            color: Colors.black26,
          ),
          child: RenderTextureView(
            panel.target,
            fit: BoxFit.fill,
            filterQuality: panel.filter,
          ),
        ),
        Container(
          color: Colors.black54,
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dropdownRow<int>(
                label: 'Height',
                value: panel.height,
                items: _heights,
                name: (h) => '${_widthFor(h)}x$h',
                onChanged: (h) {
                  panel.height = h;
                  panel.target.resize(_widthFor(h), h);
                },
              ),
              _dropdownRow<FilterQuality>(
                label: 'Filter',
                value: panel.filter,
                items: FilterQuality.values,
                name: (f) => f.name,
                onChanged: (f) => panel.filter = f,
              ),
              _dropdownRow<AntiAliasingMode>(
                label: 'AA',
                value: panel.view.antiAliasingMode!,
                items: AntiAliasingMode.values,
                name: (m) => m.name,
                onChanged: (m) => panel.view.antiAliasingMode = m,
              ),
            ],
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
        // Scrolls horizontally so the panels fit a narrow (phone) screen
        // instead of overflowing.
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white54),
                        color: Colors.black26,
                      ),
                      child: RenderTextureView(_minimap),
                    ),
                    _label('Top-down view (re-renders every 500 ms)'),
                  ],
                ),
                const SizedBox(width: 12),
                _comparePanel(_panels[0]),
                const SizedBox(width: 12),
                _comparePanel(_panels[1]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
