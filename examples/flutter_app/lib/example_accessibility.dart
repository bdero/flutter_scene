import 'dart:math';

import 'package:flutter/gestures.dart'
    show PointerDownEvent, PointerHoverEvent, PointerUpEvent;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// An accessible 3D scene. The car's doors, hood, and trunk are each a
/// pickable, labeled part: hovering (or landing accessibility focus on)
/// one draws a see-through outline through the built-in highlight system,
/// and clicking (or activating its semantics) toggles it open or closed
/// with an animation.
///
/// A control panel floats beside the car as a widget surface (a live
/// Flutter subtree rendered to a texture). Its two sliders drive the wheel
/// speed and steering, and their real semantics project onto the 3D panel,
/// so a screen reader navigates and drags them like ordinary widgets. The
/// panel sits to one side, so it is visible from that side and occluded by
/// the car body from the other; while occluded, its semantics leave the
/// tree (`WidgetComponent.occlusionHiding`).
///
/// "Show semantics" overlays Flutter's [SemanticsDebugger], which draws
/// every semantics rectangle and lets you tap one to fire its action, a
/// way to verify the accessibility tree without a screen reader.
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

  // Wheel nodes and their rest poses, spun and steered by the panel.
  final Map<String, Node> _wheels = {};
  final Map<String, vm.Matrix4> _wheelRest = {};
  double _speed = 0;
  double _steer = 0;
  double _wheelRotation = 0;

  // The control panel node, so pointer picks over it defer to the scene's
  // widget-input forwarding instead of toggling a car part.
  Node? _panelNode;

  _Part? _hoveredPart;
  _Part? _focusedPart;

  // Car-part press tracking (a tap toggles; a drag does not).
  _Part? _pressedPart;
  Offset? _pressPosition;

  // Camera orbit, paused while the pointer is over the scene so parts hold
  // still under the cursor (and the panel stays put to drag its sliders).
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

    for (final name in const [
      'WheelFront.L',
      'WheelFront.R',
      'WheelBack.L',
      'WheelBack.R',
    ]) {
      final node = car.getChildByNamePath([name])!;
      _wheels[name] = node;
      _wheelRest[name] = node.localTransform.clone();
    }

    // A widget surface beside the car (+X side): visible from that side,
    // occluded by the body from the other. The quad faces +Z locally, so a
    // quarter turn about Y points it outward along +X.
    final panel = Node(
      name: 'ControlPanel',
      localTransform: vm.Matrix4.translation(vm.Vector3(2.6, 1.1, 0))
        ..rotate(vm.Vector3(0, 1, 0), pi / 2),
    );
    panel.addComponent(
      WidgetComponent(
        size: const Size(320, 200),
        worldHeight: 1.25,
        occlusionHiding: true,
        child: _ControlPanel(
          onSpeed: (v) => _speed = v,
          onSteer: (v) => _steer = v,
        ),
      ),
    );
    scene.add(panel);
    _panelNode = panel;

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

  bool _isInPanel(Node node) {
    final panel = _panelNode;
    if (panel == null) return false;
    for (Node? current = node; current != null; current = current.parent) {
      if (identical(current, panel)) return true;
    }
    return false;
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
    _animateParts(deltaSeconds);
    _updateWheels(deltaSeconds);
    exampleSettings.applyTo(scene);
  }

  void _animateParts(double deltaSeconds) {
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
  }

  void _updateWheels(double deltaSeconds) {
    _wheelRotation += _speed * deltaSeconds * 6;
    for (final name in const ['WheelBack.L', 'WheelBack.R']) {
      _wheels[name]?.localTransform = _wheelRest[name]!.clone()
        ..rotate(vm.Vector3(0, 0, -1), _wheelRotation);
    }
    for (final name in const ['WheelFront.L', 'WheelFront.R']) {
      _wheels[name]?.localTransform =
          _wheelRest[name]!.clone() *
          vm.Matrix4.rotationY(-_steer / 2) *
          vm.Matrix4.rotationZ(-_wheelRotation);
    }
  }

  SceneRaycastHit? _rawPick(Offset localPosition) {
    final camera = _lastCamera;
    if (camera == null || _viewSize.isEmpty) return null;
    return scene.raycast(camera.screenPointToRay(localPosition, _viewSize));
  }

  void _onHover(PointerHoverEvent event) {
    final hit = _rawPick(event.localPosition);
    final part = hit == null ? null : _partForNode(hit.node);
    if (part == _hoveredPart) return;
    setState(() {
      _hoveredPart = part;
      _refreshHighlights();
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    final hit = _rawPick(event.localPosition);
    // A press on the panel drives its sliders through the scene's widget
    // input forwarding; do not also arm a car-part toggle.
    if (hit == null || _isInPanel(hit.node)) {
      _pressedPart = null;
      return;
    }
    _pressedPart = _partForNode(hit.node);
    _pressPosition = event.localPosition;
  }

  void _onPointerUp(PointerUpEvent event) {
    final part = _pressedPart;
    _pressedPart = null;
    if (part == null) return;
    // A drag is not a tap.
    if (_pressPosition != null &&
        (event.localPosition - _pressPosition!).distance > 8) {
      return;
    }
    final hit = _rawPick(event.localPosition);
    if (hit != null && _partForNode(hit.node) == part) {
      _togglePart(part);
    }
  }

  void _onExit() {
    _pointerInside = false;
    if (_hoveredPart != null) {
      setState(() {
        _hoveredPart = null;
        _refreshHighlights();
      });
    }
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
          onEnter: (_) => _pointerInside = true,
          onExit: (_) => _onExit(),
          onHover: _onHover,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
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

/// The widget surface floating beside the car: two sliders driving the
/// wheel speed and steering. A live Flutter subtree captured to a texture;
/// its slider semantics project onto the 3D panel.
class _ControlPanel extends StatefulWidget {
  const _ControlPanel({required this.onSpeed, required this.onSteer});

  final ValueChanged<double> onSpeed;
  final ValueChanged<double> onSteer;

  @override
  State<_ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<_ControlPanel> {
  double _speed = 0;
  double _steer = 0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B2431),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Car controls',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Wheel speed', style: TextStyle(color: Colors.white70)),
            Slider(
              value: _speed,
              label: '${(_speed * 100).round()}%',
              divisions: 20,
              onChanged: (v) {
                setState(() => _speed = v);
                widget.onSpeed(v);
              },
            ),
            const Text('Steering', style: TextStyle(color: Colors.white70)),
            Slider(
              value: _steer,
              min: -1,
              max: 1,
              divisions: 20,
              label: _steer == 0 ? 'Center' : (_steer < 0 ? 'Left' : 'Right'),
              onChanged: (v) {
                setState(() => _steer = v);
                widget.onSteer(v);
              },
            ),
          ],
        ),
      ),
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
          'Hover a door, hood, or trunk to outline it; click to open or '
          'close it.\n'
          'Drag the panel sliders (visible from one side) to drive the '
          'wheels.\n'
          'Turn on a screen reader, or "Show semantics", to navigate and '
          'operate the same parts and sliders.',
          textAlign: TextAlign.center,
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
