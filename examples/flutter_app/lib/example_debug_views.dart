// Surface debug views: every material's resolved surface shown one channel at
// a time, split against the lit image, with a wireframe overlay and a
// per-node exclusion. The engine's own materials and a `.fmat` participate
// with no changes; the raw ShaderMaterial in the corner did not opt in, so
// it draws through the fallback (geometry channels work, the rest stripes).

import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

class ExampleDebugViews extends StatefulWidget {
  const ExampleDebugViews({super.key});

  @override
  State<ExampleDebugViews> createState() => _ExampleDebugViewsState();
}

class _ExampleDebugViewsState extends State<ExampleDebugViews> {
  final Scene scene = Scene();
  final Node ground = Node();
  bool loaded = false;

  DebugViewEntry _entry = DebugViewRegistry.byId('roughness')!;
  bool _split = true;
  double _splitAt = 0.5;
  double _gain = 1.0;
  bool _wireframe = false;
  bool _excludeGround = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.5, -1.0, -0.4),
      castsShadow: true,
    );

    // A ground plane, excludable to show a node override.
    ground.mesh = Mesh(
      PlaneGeometry(width: 12, depth: 12),
      PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.55, 0.57, 0.6, 1)
        ..roughnessFactor = 0.85
        ..metallicFactor = 0.0,
    );
    scene.add(ground);

    // A metallic-roughness sweep, so the surface channels read as ramps.
    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      scene.add(
        Node(
            mesh: Mesh(
              SphereGeometry(radius: 0.55),
              PhysicallyBasedMaterial()
                ..baseColorFactor = vm.Vector4(0.9, 0.35 + 0.5 * t, 0.2, 1)
                ..roughnessFactor = 0.1 + 0.8 * t
                ..metallicFactor = i.isEven ? 1.0 : 0.0,
            ),
          )
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(-4 + 2.0 * i, 0.6, -1.5),
          ),
      );
    }

    // A deliberately wrong material: metallic 0.5 and a near-black albedo,
    // which the validation view flags.
    scene.add(
      Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(1.2, 1.2, 1.2)),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.01, 0.01, 0.012, 1)
              ..roughnessFactor = 0.4
              ..metallicFactor = 0.5,
          ),
        )
        ..localTransform =
            vm.Matrix4.translation(vm.Vector3(-3, 0.6, 1.5)) *
            vm.Matrix4.rotationY(0.4),
    );

    // An unlit material takes part too; its color is its base color.
    scene.add(
      Node(
        mesh: Mesh(
          TorusGeometry(radius: 0.8, tubeRadius: 0.25),
          UnlitMaterial(),
        ),
      )..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.6, 1.5)),
    );

    // A raw ShaderMaterial that never opted in: the fallback shader draws it.
    final library = await gpu.loadShaderLibraryAsync(
      await gpu.resolveShaderBundleKey('example'),
    );
    final vertexShader = library?['RippleVertex'];
    final fragmentShader = library?['RippleFragment'];
    if (vertexShader != null && fragmentShader != null) {
      final raw = ShaderMaterial(
        vertexShader: vertexShader,
        fragmentShader: fragmentShader,
      );
      raw.setUniformBlockFromFloats('TintInfo', [
        0.45, 0.85, 1.0, 1.0, //
        0.04, 0.16, 0.42, 1.0, //
      ]);
      raw.setUniformBlock(
        'RippleInfo',
        ByteData.sublistView(Float32List.fromList([0, 0.15, 1.4, 0])),
        stage: ShaderStage.vertex,
      );
      scene.add(
        Node(mesh: Mesh(PlaneGeometry(width: 2.4, depth: 2.4), raw))
          ..localTransform = vm.Matrix4.translation(vm.Vector3(3, 0.6, 1.5)),
      );
    }
    _apply();
    if (mounted) setState(() => loaded = true);
  }

  void _apply() {
    scene.debug.view = _entry.view.copyWith(gain: _gain);
    scene.debug.split = _split ? _splitAt : null;
    scene.debug.overlays
      ..clear()
      ..addAll({if (_wireframe) DebugOverlay.wireframe});
    ground.debugView = _excludeGround ? DebugView.none : null;
  }

  @override
  void dispose() {
    // A scene's debug state lives on the scene; the node override is global
    // bookkeeping, so clear it with the node.
    ground.debugView = null;
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = DebugViewRegistry.entries
        .where((entry) => entry.group != SurfaceDebugGroup.none)
        .toList();
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            camera: PerspectiveCamera(
              position: vm.Vector3(0, 5.0, 9.0),
              target: vm.Vector3(0, 0.4, 0),
            ),
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
          ),
        ),
        ExampleOverlay.bottomLeftPanel(
          child: ExamplePanelCard(
            icon: Icons.bug_report,
            title: 'Debug views',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButton<DebugViewEntry>(
                  value: _entry,
                  isExpanded: true,
                  dropdownColor: Colors.grey.shade900,
                  style: const TextStyle(color: Colors.white),
                  items: [
                    for (final entry in entries)
                      DropdownMenuItem(
                        value: entry,
                        child: Text(
                          '${_groupLabel(entry.group)}  ${entry.label}',
                        ),
                      ),
                  ],
                  onChanged: (entry) {
                    if (entry == null) return;
                    setState(() {
                      _entry = entry;
                      _apply();
                    });
                  },
                ),
                _SliderRow(
                  label: 'Gain',
                  value: _gain,
                  min: 0.1,
                  max: 8,
                  onChanged: (v) => setState(() {
                    _gain = v;
                    _apply();
                  }),
                ),
                _CheckRow(
                  label: 'Split against lit',
                  value: _split,
                  onChanged: (v) => setState(() {
                    _split = v;
                    _apply();
                  }),
                ),
                if (_split)
                  _SliderRow(
                    label: 'Split at',
                    value: _splitAt,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() {
                      _splitAt = v;
                      _apply();
                    }),
                  ),
                _CheckRow(
                  label: 'Wireframe overlay',
                  value: _wireframe,
                  onChanged: (v) => setState(() {
                    _wireframe = v;
                    _apply();
                  }),
                ),
                _CheckRow(
                  label: 'Exclude the ground (Node.debugView)',
                  value: _excludeGround,
                  onChanged: (v) => setState(() {
                    _excludeGround = v;
                    _apply();
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _groupLabel(SurfaceDebugGroup group) => switch (group) {
    SurfaceDebugGroup.none => '',
    SurfaceDebugGroup.geometry => 'Geometry',
    SurfaceDebugGroup.surface => 'Surface',
    SurfaceDebugGroup.physical => 'Physical',
    SurfaceDebugGroup.identity => 'Identity',
    SurfaceDebugGroup.validation => 'Validation',
    SurfaceDebugGroup.custom => 'Custom',
  };
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
