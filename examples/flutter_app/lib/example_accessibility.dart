import 'dart:math';

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// An accessible 3D scene: the car's doors, hood, and trunk are each a
/// pickable, labeled part. Hover (or accessibility-focus) draws a
/// see-through outline on the part through the built-in highlight system;
/// clicking (or activating its semantics) toggles it open or closed with an
/// animation. Every part is also a [SemanticsComponent], so a screen reader
/// navigates the same parts and performs the same toggles.
///
/// Toggle "Show semantics" to overlay Flutter's [SemanticsDebugger], which
/// draws every semantics rectangle and lets you tap one to fire its action,
/// a way to verify the accessibility tree without turning a screen reader
/// on.
class ExampleAccessibility extends StatefulWidget {
  const ExampleAccessibility({super.key});

  @override
  ExampleAccessibilityState createState() => ExampleAccessibilityState();
}

/// One openable car part: its node, rest pose, hinge axis, animation state,
/// and the semantics that expose it.
class _Part {
  _Part({
    required this.nodeName,
    required this.label,
    required this.axis,
    required this.sortOrder,
  });

  final String nodeName;
  final String label;
  final vm.Vector3 axis;
  final double sortOrder;

  late Node node;
  late vm.Matrix4 startTransform;
  late SemanticsComponent semantics;

  // Current open fraction (0 closed, 1 open) and the value it animates
  // toward.
  double amount = 0;
  double target = 0;
  bool get open => target > 0.5;
}

class ExampleAccessibilityState extends State<ExampleAccessibility> {
  final Scene scene = Scene();
  bool loaded = false;

  final EnvironmentSkySource _skySource = EnvironmentSkySource();

  // Hover outline (mouse) and focus outline (assistive technology). Linear
  // RGBA.
  static final vm.Vector4 _hoverColor = vm.Vector4(0.2, 0.9, 1.0, 1.0);
  static final vm.Vector4 _focusColor = vm.Vector4(1.0, 0.75, 0.1, 1.0);

  final List<_Part> _parts = [
    _Part(
      nodeName: 'DoorFront.L',
      label: 'Front left door',
      axis: vm.Vector3(0, -1, 0),
      sortOrder: 0,
    ),
    _Part(
      nodeName: 'DoorFront.R',
      label: 'Front right door',
      axis: vm.Vector3(0, -1, 0),
      sortOrder: 1,
    ),
    _Part(
      nodeName: 'DoorBack.L',
      label: 'Rear left door',
      axis: vm.Vector3(0, -1, 0),
      sortOrder: 2,
    ),
    _Part(
      nodeName: 'DoorBack.R',
      label: 'Rear right door',
      axis: vm.Vector3(0, -1, 0),
      sortOrder: 3,
    ),
    _Part(
      nodeName: 'Frunk',
      label: 'Front trunk',
      axis: vm.Vector3(0, 0, 1),
      sortOrder: 4,
    ),
    _Part(
      nodeName: 'Trunk',
      label: 'Trunk',
      axis: vm.Vector3(0, 0, -1),
      sortOrder: 5,
    ),
  ];

  final Map<Node, _Part> _partByNode = {};

  _Part? _hoveredPart;
  _Part? _focusedPart;

  // Camera orbit, paused while the pointer is over the scene so parts are
  // stationary (and easy to click) under the cursor.
  double _orbitPhase = 0;
  bool _pointerInside = false;
  Camera? _lastCamera;
  Size _viewSize = Size.zero;

  bool _showSemantics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final car = await loadScene('assets_src/fcar.glb');
    final environment = await EnvironmentMap.fromAssets(
      radianceImagePath: 'assets/little_paris_eiffel_tower.png',
    );
    if (!mounted) return;

    car.name = 'Car';
    scene.add(car);

    for (final part in _parts) {
      final node = car.getChildByNamePath([part.nodeName])!;
      part.node = node;
      part.startTransform = node.localTransform.clone();
      part.semantics = SemanticsComponent(
        label: part.label,
        value: 'closed',
        hint: 'Activate to open or close',
        button: true,
        sortOrder: part.sortOrder,
        onTap: () => _togglePart(part),
        onDidGainAccessibilityFocus: () => _setFocused(part),
        onDidLoseAccessibilityFocus: () => _clearFocused(part),
      );
      node.addComponent(part.semantics);
      _partByNode[node] = part;
    }

    scene.environment = environment;
    scene.exposure = 2.5;
    scene.skybox = Skybox(_skySource);
    scene.highlightStyle.thickness = 4.0;

    setState(() => loaded = true);
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  // Walks up from a hit node to the openable part it belongs to, or null.
  _Part? _partForNode(Node node) {
    for (Node? current = node; current != null; current = current.parent) {
      final part = _partByNode[current];
      if (part != null) return part;
    }
    return null;
  }

  void _togglePart(_Part part) {
    setState(() {
      part.target = part.open ? 0.0 : 1.0;
      part.semantics.value = part.open ? 'open' : 'closed';
    });
  }

  void _setFocused(_Part part) {
    setState(() {
      _focusedPart = part;
      _refreshHighlights();
    });
  }

  void _clearFocused(_Part part) {
    if (_focusedPart != part) return;
    setState(() {
      _focusedPart = null;
      _refreshHighlights();
    });
  }

  // Sets each part's outline color: amber where accessibility focus sits,
  // cyan where the mouse hovers, none otherwise. highlightColor does not
  // inherit, so it is set on the part node and all of its descendants.
  void _refreshHighlights() {
    for (final part in _parts) {
      final color = part == _focusedPart
          ? _focusColor
          : (part == _hoveredPart ? _hoverColor : null);
      _applyHighlight(part.node, color);
    }
  }

  void _applyHighlight(Node node, vm.Vector4? color) {
    node.highlightColor = color;
    for (final child in node.children) {
      _applyHighlight(child, color);
    }
  }

  Camera _buildCamera() {
    const radius = 10.0;
    return PerspectiveCamera(
      position: vm.Vector3(
        sin(_orbitPhase) * radius,
        4,
        cos(_orbitPhase) * radius,
      ),
      target: vm.Vector3(0, 0.5, 0),
    );
  }

  void _onTick(double deltaSeconds) {
    if (!_pointerInside) {
      _orbitPhase += deltaSeconds * 0.2;
    }
    // Animate each part toward its open/closed target.
    const speed = 3.0; // reaches the target in ~1/3 second
    for (final part in _parts) {
      if (part.amount == part.target) continue;
      final step = speed * deltaSeconds;
      if ((part.target - part.amount).abs() <= step) {
        part.amount = part.target;
      } else {
        part.amount += part.target > part.amount ? step : -step;
      }
      part.node.localTransform = part.startTransform.clone()
        ..rotate(part.axis, part.amount * pi / 2);
    }
    exampleSettings.applyTo(scene);
  }

  void _onEnter() => _pointerInside = true;

  void _onExit() {
    _pointerInside = false;
    if (_hoveredPart != null) {
      setState(() {
        _hoveredPart = null;
        _refreshHighlights();
      });
    }
  }

  _Part? _pick(Offset localPosition) {
    final camera = _lastCamera;
    if (camera == null || _viewSize.isEmpty) return null;
    final hit = scene.raycast(
      camera.screenPointToRay(localPosition, _viewSize),
    );
    return hit == null ? null : _partForNode(hit.node);
  }

  void _onHover(PointerHoverEvent event) {
    final part = _pick(event.localPosition);
    if (part == _hoveredPart) return;
    setState(() {
      _hoveredPart = part;
      _refreshHighlights();
    });
  }

  void _onTapUp(TapUpDetails details) {
    final part = _pick(details.localPosition);
    if (part != null) _togglePart(part);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final scene3d = LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = constraints.biggest;
        return MouseRegion(
          onEnter: (_) => _onEnter(),
          onExit: (_) => _onExit(),
          onHover: _onHover,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _onTapUp,
            child: SceneView(
              scene,
              cameraBuilder: (elapsed) => _lastCamera = _buildCamera(),
              onTick: (elapsed, deltaSeconds) => _onTick(deltaSeconds),
            ),
          ),
        );
      },
    );

    // The debugger absorbs pointers to report semantics taps, so the toggle
    // button rides above it (a later Stack child) to stay interactive.
    return Stack(
      children: [
        Positioned.fill(
          child: _showSemantics ? SemanticsDebugger(child: scene3d) : scene3d,
        ),
        const Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Align(alignment: Alignment.topCenter, child: _Instructions()),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: FilledButton.icon(
            onPressed: () => setState(() => _showSemantics = !_showSemantics),
            icon: Icon(
              _showSemantics ? Icons.visibility_off : Icons.accessibility_new,
            ),
            label: Text(_showSemantics ? 'Hide semantics' : 'Show semantics'),
          ),
        ),
      ],
    );
  }
}

class _Instructions extends StatelessWidget {
  const _Instructions();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xAA000000),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Hover a door, hood, or trunk to outline it.\n'
          'Click it to open or close it.\n'
          'Turn on a screen reader, or "Show semantics",\n'
          'to navigate and toggle the same parts.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            height: 1.4,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
