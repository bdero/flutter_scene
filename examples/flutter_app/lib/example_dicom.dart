// DICOM Volume example.
//
// Downloads a permissively licensed head MRI at runtime, packs its slices into
// a 2D atlas texture (Flutter GPU has no 3D textures), and renders it three
// ways with a fragment-shader raymarch: MPR (a movable cross-section plane),
// MIP (maximum intensity projection), and DVR (direct volume rendering with a
// transfer function). Window/level and the transfer function are live shader
// uniforms, so there is no per-frame CPU work on the volume.
//
// The reference dataset is the datalad `example-dicom-structural` set (a
// de-faced T1 head MRI, public domain under the PDDL). See dicom_loader.dart
// for provenance and the fallback source.

// In-repo dev apps may reach into lib/src; waive the lint so we can create the
// r32Float atlas texture directly through the GPU shim.
// ignore_for_file: implementation_imports

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import 'dicom/dicom_loader.dart';
import 'example_settings.dart';

enum _VolumeMode { mpr, mip, dvr }

enum _Colormap { grayscale, hot, bone }

class ExampleDicom extends StatefulWidget {
  const ExampleDicom({super.key});

  @override
  State<ExampleDicom> createState() => _ExampleDicomState();
}

class _ExampleDicomState extends State<ExampleDicom> {
  final Scene scene = Scene();
  final Node _volumeNode = Node();

  PreprocessedMaterial? _material;
  VolumeAtlas? _atlas;
  vm.Vector3 _nodeScale = vm.Vector3(1, 1, 1);
  vm.Matrix4 _invNodeTransform = vm.Matrix4.identity();

  String _status = 'Preparing...';
  String? _error;

  bool _darkBackground = true;

  // View controls.
  _VolumeMode _mode = _VolumeMode.dvr;
  _Colormap _colormap = _Colormap.grayscale;
  double _windowCenter = 0.5;
  double _windowWidth = 1.0;
  double _stepCount = 256;
  double _density = 1.2;
  final double _opacityGamma = 2.0;
  double _brightness = 1.3;
  double _slicePos = 0.5;
  int _sliceAxis = 2;

  // Orbit camera state.
  double _yaw = 0.6;
  double _pitch = 0.3;
  double _distance = 3.6;

  @override
  void initState() {
    super.initState();
    _volumeNode.name = 'dicom_volume';
    scene.add(_volumeNode);
    _load();
  }

  Future<void> _load() async {
    try {
      final material = await loadFmatMaterial('assets/dicom_volume.fmat');
      final atlas = await loadReferenceVolume(
        onStatus: (m) {
          if (mounted) setState(() => _status = m);
        },
      );

      if (mounted) setState(() => _status = 'Uploading to GPU...');

      // Upload the normalized scalar volume as a single-channel float atlas.
      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        atlas.atlasWidth,
        atlas.atlasHeight,
        format: gpu.PixelFormat.r32Float,
      );
      texture.overwrite(atlas.data.buffer.asByteData());

      // Non-uniform scale gives the volume its correct physical aspect while
      // the cube geometry stays a unit cube (so [0,1] texture space maps
      // straight to vertex.position + 0.5 in the shader). Applied in the
      // volume's own axes, before the orientation rotation below.
      final phys = <double>[
        atlas.volumeWidth * atlas.spacing[0],
        atlas.volumeHeight * atlas.spacing[1],
        atlas.volumeDepth * atlas.spacing[2],
      ];
      final maxPhys = phys.reduce(math.max);
      _nodeScale = vm.Vector3(
        phys[0] / maxPhys * 2.0,
        phys[1] / maxPhys * 2.0,
        phys[2] / maxPhys * 2.0,
      );

      // Orient the volume anatomically. The three cube axes point along the
      // DICOM patient (LPS) directions of the column, row, and slice axes;
      // _lpsToWorld maps those to flutter_scene world space (Superior up,
      // Anterior toward the camera) with the odd-parity placement described
      // there, so the anatomy renders un-mirrored (not the other way around).
      final rot = vm.Matrix4.identity()..setRotation(_orientationMatrix(atlas));
      final scaleM = vm.Matrix4.diagonal3(_nodeScale);
      final transform = rot * scaleM;
      _volumeNode.localTransform = transform;
      _invNodeTransform = vm.Matrix4.inverted(transform);

      final mesh = Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), material);
      _volumeNode.mesh = mesh;

      material.parameters
        ..setTexture(
          'volume',
          texture,
          sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.nearest,
            magFilter: gpu.MinMagFilter.nearest,
            mipFilter: gpu.MipFilter.nearest,
          ),
        )
        ..setVec2(
          'atlas_grid',
          vm.Vector2(atlas.cols.toDouble(), atlas.rows.toDouble()),
        )
        ..setVec2(
          'atlas_size',
          vm.Vector2(atlas.atlasWidth.toDouble(), atlas.atlasHeight.toDouble()),
        )
        ..setVec3(
          'volume_dim',
          vm.Vector3(
            atlas.volumeWidth.toDouble(),
            atlas.volumeHeight.toDouble(),
            atlas.volumeDepth.toDouble(),
          ),
        );

      _windowCenter = atlas.windowCenter;
      _windowWidth = atlas.windowWidth;

      setState(() {
        _material = material;
        _atlas = atlas;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  vm.Vector3 _cameraPosition() {
    final cp = math.cos(_pitch);
    return vm.Vector3(
      _distance * cp * math.sin(_yaw),
      _distance * math.sin(_pitch),
      _distance * cp * math.cos(_yaw),
    );
  }

  // Maps a DICOM patient-space (LPS) direction into flutter_scene world space:
  // Superior -> +Y (up), Anterior -> +Z (toward the default camera), patient
  // Right -> +X. This is an odd-parity (determinant -1) map, the same reason
  // the glTF importer places right-handed content with a scale(1,1,-1) flip:
  // flutter_scene's world is left-handed (right = up x forward), so a
  // right-handed source needs an odd-parity placement to render un-mirrored.
  // (A proper det +1 rotation would mirror left/right and face the head away.)
  // The world axes then carry fixed anatomical meaning, which the compass
  // labels: +X=R, -X=L, +Y=S, -Y=I, +Z=A, -Z=P. Viewed face-on this is the
  // "as if facing the patient" convention: patient Left is on the viewer's
  // right.
  static vm.Vector3 _lpsToWorld(List<double> v) =>
      vm.Vector3(-v[0], v[2], -v[1]);

  // Rotation whose columns send the cube's local x/y/z axes (pointing along the
  // column/row/slice patient directions) to their oriented world directions.
  static vm.Matrix3 _orientationMatrix(VolumeAtlas atlas) {
    final cx = _lpsToWorld(atlas.patientRowDir);
    final cy = _lpsToWorld(atlas.patientColDir);
    final cz = _lpsToWorld(atlas.patientSliceDir);
    return vm.Matrix3(
      cx.x,
      cx.y,
      cx.z, // column 0: object +x in world
      cy.x,
      cy.y,
      cy.z, // column 1: object +y in world
      cz.x,
      cz.y,
      cz.z, // column 2: object +z in world
    );
  }

  void _applyDynamicParameters() {
    final material = _material;
    if (material == null) return;

    // Camera position expressed in the cube's [0,1] texture space. The node
    // maps object space (cube [-0.5,0.5]) to world; invert it to bring the
    // camera into object space, then shift to uvw ([0,1]).
    final camObject = _invNodeTransform.transformed3(_cameraPosition());
    final camUvw = camObject + vm.Vector3.all(0.5);

    material.parameters
      ..setVec3('cam_uvw', camUvw)
      ..setFloat('mode', _mode.index.toDouble())
      ..setFloat('colormap', _colormap.index.toDouble())
      ..setFloat('window_center', _windowCenter)
      ..setFloat('window_width', _windowWidth)
      ..setFloat('step_count', _stepCount)
      ..setFloat('density', _density)
      ..setFloat('opacity_gamma', _opacityGamma)
      ..setFloat('brightness', _brightness)
      ..setFloat('slice_axis', _sliceAxis.toDouble())
      ..setFloat('slice_pos', _slicePos);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Backdrop behind the (transparent-cleared) scene.
        Positioned.fill(
          child: ColoredBox(
            color: _darkBackground ? Colors.black : Colors.white,
          ),
        ),
        Positioned.fill(
          child: Listener(
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                setState(() {
                  _distance = (_distance + signal.scrollDelta.dy * 0.003).clamp(
                    1.6,
                    8.0,
                  );
                });
              }
            },
            child: GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  _yaw += d.delta.dx * 0.01;
                  _pitch = (_pitch + d.delta.dy * 0.01).clamp(
                    -math.pi / 2 + 0.05,
                    math.pi / 2 - 0.05,
                  );
                });
              },
              child: SceneView(
                scene,
                cameraBuilder: (elapsed) => PerspectiveCamera(
                  position: _cameraPosition(),
                  target: vm.Vector3.zero(),
                ),
                onTick: (elapsed, deltaSeconds) {
                  _applyDynamicParameters();
                  exampleSettings.applyTo(scene);
                },
              ),
            ),
          ),
        ),
        if (_material != null && _atlas != null) _buildTopBar(),
        if (_material == null || _atlas == null) _buildOverlay(),
        if (_material != null && _atlas != null) _buildControls(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 12,
      right: 12,
      child: Row(
        children: [
          // Orientation compass: a mirror/orientation self-check. The letters
          // (R/L, A/P, S/I) are placed from the anatomically-oriented world
          // axes, so with the head visible you can confirm S is up and A faces
          // you; a correct S/A also proves the volume is not mirrored.
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(
              painter: _CompassPainter(
                yaw: _yaw,
                pitch: _pitch,
                cameraPosition: _cameraPosition(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Toggle background',
            onPressed: () => setState(() => _darkBackground = !_darkBackground),
            icon: Icon(_darkBackground ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return Center(
      child: Card(
        color: Colors.black87,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_status, style: const TextStyle(color: Colors.white)),
              ] else ...[
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(height: 12),
                SizedBox(
                  width: 320,
                  child: Text(
                    'Failed to load volume:\n$_error',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    const labelStyle = TextStyle(color: Colors.white, fontSize: 12);
    return Positioned(
      left: 12,
      bottom: 12,
      // Anchored in the bottom-left corner with a fixed width so it does not
      // cover the volume.
      child: SizedBox(
        width: 340,
        child: Card(
          color: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('View', style: labelStyle),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<_VolumeMode>(
                        isExpanded: true,
                        dropdownColor: Colors.black87,
                        value: _mode,
                        onChanged: (v) => setState(() => _mode = v ?? _mode),
                        items: [
                          for (final m in _VolumeMode.values)
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                m.name.toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<_Colormap>(
                      dropdownColor: Colors.black87,
                      value: _colormap,
                      onChanged: (v) =>
                          setState(() => _colormap = v ?? _colormap),
                      items: [
                        for (final c in _Colormap.values)
                          DropdownMenuItem(
                            value: c,
                            child: Text(
                              c.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                _slider(
                  'Level',
                  _windowCenter,
                  0,
                  1,
                  (v) => setState(() => _windowCenter = v),
                ),
                _slider(
                  'Window',
                  _windowWidth,
                  0.01,
                  1,
                  (v) => setState(() => _windowWidth = v),
                ),
                if (_mode == _VolumeMode.dvr) ...[
                  _slider(
                    'Density',
                    _density,
                    0,
                    4,
                    (v) => setState(() => _density = v),
                  ),
                  _slider(
                    'Brightness',
                    _brightness,
                    0,
                    4,
                    (v) => setState(() => _brightness = v),
                  ),
                ],
                if (_mode == _VolumeMode.mpr) ...[
                  Row(
                    children: [
                      const SizedBox(
                        width: 76,
                        child: Text(
                          'Axis',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: SegmentedButton<int>(
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(value: 0, label: Text('X')),
                            ButtonSegment(value: 1, label: Text('Y')),
                            ButtonSegment(value: 2, label: Text('Z')),
                          ],
                          selected: {_sliceAxis},
                          onSelectionChanged: (s) =>
                              setState(() => _sliceAxis = s.first),
                        ),
                      ),
                    ],
                  ),
                  _slider(
                    'Slice',
                    _slicePos,
                    0,
                    1,
                    (v) => setState(() => _slicePos = v),
                  ),
                ],
                if (_mode != _VolumeMode.mpr)
                  _slider(
                    'Steps',
                    _stepCount,
                    32,
                    512,
                    (v) => setState(() => _stepCount = v),
                    decimals: 0,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int decimals = 2,
  }) {
    const textStyle = TextStyle(color: Colors.white, fontSize: 12);
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label, style: textStyle)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(decimals),
            style: textStyle,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// A small anatomical orientation compass. Projects the oriented world axes
/// through the current camera and labels them with the patient directions
/// (R/L, A/P, S/I). Axes pointing toward the viewer are drawn solid; those
/// pointing away are dimmed.
class _CompassPainter extends CustomPainter {
  _CompassPainter({
    required this.yaw,
    required this.pitch,
    required this.cameraPosition,
  });

  final double yaw;
  final double pitch;
  final vm.Vector3 cameraPosition;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    // Camera basis, matching the engine's left-handed right = up x forward.
    final forward = (-cameraPosition).normalized();
    var right = vm.Vector3(0, 1, 0).cross(forward);
    if (right.length < 1e-4) right = vm.Vector3(1, 0, 0);
    right.normalize();
    final up = forward.cross(right)..normalize();

    // World axis -> anatomical label + color (per _lpsToWorld's fixed mapping).
    final axes =
        <(vm.Vector3, String, Color)>[
          (vm.Vector3(1, 0, 0), 'R', const Color(0xFFFF7A7A)),
          (vm.Vector3(-1, 0, 0), 'L', const Color(0xFFFF7A7A)),
          (vm.Vector3(0, 1, 0), 'S', const Color(0xFF8FE388)),
          (vm.Vector3(0, -1, 0), 'I', const Color(0xFF8FE388)),
          (vm.Vector3(0, 0, 1), 'A', const Color(0xFF7AB8FF)),
          (vm.Vector3(0, 0, -1), 'P', const Color(0xFF7AB8FF)),
        ]..sort(
          (a, b) => b.$1.dot(forward).compareTo(a.$1.dot(forward)),
        ); // draw far axes first

    for (final (dir, label, color) in axes) {
      final sx = dir.dot(right);
      final sy = dir.dot(up);
      final near = dir.dot(forward) <= 0; // forward points away from viewer
      final tip = center + Offset(sx, -sy) * radius;

      canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = color.withValues(alpha: near ? 1.0 : 0.3)
          ..strokeWidth = near ? 2.2 : 1.3
          ..strokeCap = StrokeCap.round,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color.withValues(alpha: near ? 1.0 : 0.35),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelCenter = center + Offset(sx, -sy) * (radius + 9);
      tp.paint(canvas, labelCenter - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.yaw != yaw || old.pitch != pitch;
}
