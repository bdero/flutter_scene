import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Scene content exposed to assistive technology: labeled 3D objects with
/// semantics actions (a tappable lamp, an adjustable pedestal), an occluded
/// gauge that opts into occlusion hiding, and a widget panel whose real
/// button semantics project onto its 3D surface. Run a screen reader (or
/// the Flutter semantics debugger) to explore; accessibility focus draws an
/// in-scene highlight through onDidGainAccessibilityFocus.
class ExampleAccessibility extends StatefulWidget {
  const ExampleAccessibility({super.key});

  @override
  ExampleAccessibilityState createState() => ExampleAccessibilityState();
}

class ExampleAccessibilityState extends State<ExampleAccessibility> {
  final Scene scene = Scene();

  late final Node _lamp;
  late final Node _pedestal;
  late final UnlitMaterial _lampMaterial;
  bool _lampOn = false;
  double _pedestalScale = 1.0;
  int _panelPresses = 0;

  static final vm.Vector4 _focusColor = vm.Vector4(1.0, 0.85, 0.2, 1.0);

  // The focus highlight rides on Node.highlightColor, set while assistive
  // technology focuses the object's semantics node.
  SemanticsProperties _focusable(
    Node node, {
    required String label,
    String? value,
    String? hint,
    bool button = false,
    VoidCallback? onTap,
    VoidCallback? onIncrease,
    VoidCallback? onDecrease,
    String? increasedValue,
    String? decreasedValue,
  }) => SemanticsProperties(
    label: label,
    value: value,
    increasedValue: increasedValue,
    decreasedValue: decreasedValue,
    hint: hint,
    button: button ? true : null,
    textDirection: TextDirection.ltr,
    onTap: onTap,
    onIncrease: onIncrease,
    onDecrease: onDecrease,
    onDidGainAccessibilityFocus: () =>
        setState(() => node.highlightColor = _focusColor),
    onDidLoseAccessibilityFocus: () =>
        setState(() => node.highlightColor = null),
  );

  void _toggleLamp() {
    setState(() {
      _lampOn = !_lampOn;
      _lampMaterial.baseColorFactor = _lampOn
          ? vm.Vector4(1.0, 0.9, 0.4, 1.0)
          : vm.Vector4(0.25, 0.25, 0.3, 1.0);
      _lampSemantics.value = _lampOn ? 'on' : 'off';
    });
  }

  late final SemanticsComponent _lampSemantics;

  void _scalePedestal(double delta) {
    setState(() {
      _pedestalScale = (_pedestalScale + delta).clamp(0.5, 2.0);
      _pedestal.localTransform = vm.Matrix4.translation(vm.Vector3(1.6, 0, 0))
        ..scaleByVector3(vm.Vector3.all(_pedestalScale));
      _pedestalSemantics.properties = _pedestalProperties();
    });
  }

  late final SemanticsComponent _pedestalSemantics;

  SemanticsProperties _pedestalProperties() => _focusable(
    _pedestal,
    label: 'Pedestal',
    value: '${(_pedestalScale * 100).round()} percent',
    increasedValue:
        '${((_pedestalScale + 0.25).clamp(0.5, 2.0) * 100).round()} percent',
    decreasedValue:
        '${((_pedestalScale - 0.25).clamp(0.5, 2.0) * 100).round()} percent',
    hint: 'Adjust to change its size',
    onIncrease: () => _scalePedestal(0.25),
    onDecrease: () => _scalePedestal(-0.25),
  );

  @override
  void initState() {
    super.initState();

    // A tappable lamp: activating it through the screen reader toggles its
    // color and reported value.
    _lampMaterial = UnlitMaterial()
      ..baseColorFactor = vm.Vector4(0.25, 0.25, 0.3, 1.0);
    _lamp = Node(
      name: 'lamp',
      localTransform: vm.Matrix4.translation(vm.Vector3(-1.6, 0, 0)),
      mesh: Mesh(SphereGeometry(radius: 0.6), _lampMaterial),
    );
    _lampSemantics = SemanticsComponent(
      properties: _focusable(
        _lamp,
        label: 'Lamp',
        value: 'off',
        hint: 'Activate to toggle',
        button: true,
        onTap: _toggleLamp,
      ),
    );
    _lamp.addComponent(_lampSemantics);
    scene.add(_lamp);

    // An adjustable pedestal: increase/decrease actions scale it.
    _pedestal = Node(
      name: 'pedestal',
      localTransform: vm.Matrix4.translation(vm.Vector3(1.6, 0, 0)),
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(0.9, 0.9, 0.9)),
        UnlitMaterial()..baseColorFactor = vm.Vector4(0.4, 0.6, 0.9, 1.0),
      ),
    );
    _pedestalSemantics = SemanticsComponent(properties: _pedestalProperties());
    _pedestal.addComponent(_pedestalSemantics);
    scene.add(_pedestal);

    // A gauge behind a wall, opted into occlusion hiding: it leaves the
    // semantics tree while the wall blocks the camera's line of sight.
    final gauge = Node(
      name: 'gauge',
      localTransform: vm.Matrix4.translation(vm.Vector3(0, 0.2, 3)),
      mesh: Mesh(
        SphereGeometry(radius: 0.35),
        UnlitMaterial()..baseColorFactor = vm.Vector4(0.9, 0.3, 0.3, 1.0),
      ),
    );
    gauge.addComponent(
      SemanticsComponent(
        label: 'Pressure gauge',
        value: 'nominal',
        textDirection: TextDirection.ltr,
        occlusionHiding: true,
      ),
    );
    scene.add(gauge);
    final wall = Node(
      name: 'wall',
      localTransform: vm.Matrix4.translation(vm.Vector3(0, 0.2, 1.8)),
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(1.4, 1.4, 0.1)),
        UnlitMaterial()..baseColorFactor = vm.Vector4(0.5, 0.5, 0.5, 1.0),
      ),
    );
    scene.add(wall);

    // A widget panel on a quad: the hosted buttons' own semantics project
    // onto the surface, so a screen reader traverses into them like any
    // other widgets.
    final panel = Node(
      name: 'panel',
      localTransform: vm.Matrix4.translation(vm.Vector3(0, 1.6, 0)),
    );
    panel.addComponent(
      WidgetComponent(
        size: const Size(360, 200),
        worldHeight: 1.2,
        child: _PanelContent(
          onPressed: () => setState(() => _panelPresses++),
          presses: () => _panelPresses,
        ),
      ),
    );
    scene.add(panel);
  }

  @override
  Widget build(BuildContext context) {
    return SceneView(
      scene,
      camera: PerspectiveCamera(
        position: vm.Vector3(0, 1.2, -5.5),
        target: vm.Vector3(0, 0.6, 0),
      ),
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}

class _PanelContent extends StatefulWidget {
  const _PanelContent({required this.onPressed, required this.presses});

  final VoidCallback onPressed;
  final int Function() presses;

  @override
  State<_PanelContent> createState() => _PanelContentState();
}

class _PanelContentState extends State<_PanelContent> {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F2430),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Control panel, pressed ${widget.presses()} times',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                widget.onPressed();
                setState(() {});
              },
              child: const Text('Press me'),
            ),
          ],
        ),
      ),
    );
  }
}
