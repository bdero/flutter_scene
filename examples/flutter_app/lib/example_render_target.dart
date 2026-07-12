import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_cuboid.dart' show SpinComponent;
import 'example_action_hint.dart';
import 'example_overlay.dart';
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

  static const double _previewWidth = 240;
  static const double _stripHeight = 328;

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
        Expanded(
          child: ExampleDropdown<T>(
            value: value,
            triggerColor: Colors.white12,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            isDense: true,
            iconSize: 18,
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
        ),
      ],
    );
  }

  Widget _minimapPanel() => Card(
    color: Colors.black54,
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 180,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Text(
              'Top-down view',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
          AspectRatio(aspectRatio: 1, child: RenderTextureView(_minimap)),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Text(
              'Refreshes every 500 ms',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _comparePanel(_ComparePanel panel, {required String title}) {
    return Card(
      color: Colors.black54,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: _previewWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            SizedBox(
              height: _previewWidth / _aspect,
              child: RenderTextureView(
                panel.target,
                fit: BoxFit.fill,
                filterQuality: panel.filter,
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dropdownRow<int>(
                    label: 'Size',
                    value: panel.height,
                    items: _heights,
                    name: (h) => '${_widthFor(h)}x$h',
                    onChanged: (h) {
                      panel.height = h;
                      panel.target.resize(_widthFor(h), h);
                    },
                  ),
                  const SizedBox(height: 4),
                  _dropdownRow<FilterQuality>(
                    label: 'Filter',
                    value: panel.filter,
                    items: FilterQuality.values,
                    name: (f) => f.name,
                    onChanged: (f) => panel.filter = f,
                  ),
                  const SizedBox(height: 4),
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
        ),
      ),
    );
  }

  Widget _renderTargetStrip() {
    final items = <Widget>[
      _minimapPanel(),
      _comparePanel(_panels[0], title: 'No anti-aliasing'),
      _comparePanel(_panels[1], title: 'Automatic anti-aliasing'),
    ];

    return SizedBox(
      height: _stripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => items[index],
      ),
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
        ExampleOverlay.bottomCenter(child: _renderTargetStrip()),
      ],
    );
  }
}
