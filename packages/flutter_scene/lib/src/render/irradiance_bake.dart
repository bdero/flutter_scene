import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render_view.dart';
import 'package:flutter_scene/src/render/sky_bake.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';
import 'package:vector_math/vector_math.dart';

int _float32ToFloat16(double val) {
  final f32 = Float32List(1)..[0] = val;
  final u32 = f32.buffer.asUint32List()[0];
  final sign = (u32 >> 31) & 0x1;
  final exp = (u32 >> 23) & 0xFF;
  final mant = u32 & 0x7FFFFF;

  if (exp == 255) {
    return (sign << 15) | 0x7C00 | (mant != 0 ? 1 : 0);
  }
  final newExp = exp - 127 + 15;
  if (newExp >= 31) {
    return (sign << 15) | 0x7C00;
  }
  if (newExp <= 0) {
    if (newExp < -10) return sign << 15;
    final newMant = (mant | 0x800000) >> (14 - newExp);
    return (sign << 15) | newMant;
  }
  return (sign << 15) | (newExp << 10) | (mant >> 13);
}

/// A baked irradiance field, serializable into an `.fscene` document and
/// assignable to [IrradianceVolumeComponent.bake].
/// {@category Lighting and environment}
class IrradianceFieldBake {
  IrradianceFieldBake({
    required this.origin,
    required this.spacing,
    required this.resolution,
    required this.atlasBytes,
  });

  /// World-space origin of the minimum corner probe.
  final Vector3 origin;

  /// Distance between adjacent probes along each axis.
  final Vector3 spacing;

  /// Probe count along each axis.
  final Vector3 resolution;

  /// Raw half-float bytes of the complete atlas.
  final Uint8List atlasBytes;
}

/// Progressively bakes an irradiance volume across multiple step calls so
/// a load screen or background worker stays responsive.
/// {@category Lighting and environment}
class IrradianceFieldBakeStepper {
  IrradianceFieldBakeStepper({
    required this.layout,
    required this.origin,
    required this.spacing,
    required this.faceResolution,
    required this.probesPerStep,
    required this.layerMask,
    required this.renderScene,
    required this.environmentMap,
    required this.transientsBuffer,
    required this.lightComponent,
    required this.punctualLighting,
    required this.spotShadowFrame,
    required void Function({
      required RenderView view,
      required gpu.Texture outputColor,
      required ui.Size pixelSize,
      required TransientTexturePool pool,
      required EnvironmentMap environmentMap,
      required TransientWriter transientsBuffer,
      required DirectionalLightComponent? lightComponent,
      required PunctualLighting punctualLighting,
      required SpotShadowFrame? spotShadowFrame,
      bool captureLinearColor,
    })
    renderView,
  }) : _renderView = renderView,
       _totalProbes = layout.probeCount,
       _atlasData = Float32List(layout.atlasWidth * layout.atlasHeight * 4);

  final IrradianceFieldLayout layout;
  final Vector3 origin;
  final Vector3 spacing;
  final int faceResolution;
  final int probesPerStep;
  final int layerMask;
  final RenderScene renderScene;
  final EnvironmentMap environmentMap;
  final TransientWriter transientsBuffer;
  final DirectionalLightComponent? lightComponent;
  final PunctualLighting punctualLighting;
  final SpotShadowFrame? spotShadowFrame;
  final void Function({
    required RenderView view,
    required gpu.Texture outputColor,
    required ui.Size pixelSize,
    required TransientTexturePool pool,
    required EnvironmentMap environmentMap,
    required TransientWriter transientsBuffer,
    required DirectionalLightComponent? lightComponent,
    required PunctualLighting punctualLighting,
    required SpotShadowFrame? spotShadowFrame,
    bool captureLinearColor,
  })
  _renderView;

  final int _totalProbes;
  final Float32List _atlasData;
  final TransientTexturePool _pool = TransientTexturePool();
  int _currentProbe = 0;

  /// Total number of probes to bake in the volume.
  int get totalProbes => _totalProbes;

  /// Number of probes baked so far.
  int get currentProbe => _currentProbe;

  /// Whether all probes have completed baking.
  bool get isDone => _currentProbe >= _totalProbes;

  /// Normalized progress in [0, 1].
  double get progress =>
      _totalProbes > 0 ? (_currentProbe / _totalProbes).clamp(0.0, 1.0) : 1.0;

  /// Runs the next batch of probes. Returns the finished [IrradianceFieldBake]
  /// on completion, or null while more steps remain.
  IrradianceFieldBake? step() {
    if (isDone) return _finalize();

    final end = math.min(_totalProbes, _currentProbe + probesPerStep);
    final fov = 2.0 * math.atan(1.0 / cubeFaceOverscan(faceResolution));
    final size = ui.Size(faceResolution.toDouble(), faceResolution.toDouble());

    for (var i = _currentProbe; i < end; i++) {
      final slotZ =
          i ~/ (layout.resolution.x.toInt() * layout.resolution.y.toInt());
      final rem =
          i % (layout.resolution.x.toInt() * layout.resolution.y.toInt());
      final slotY = rem ~/ layout.resolution.x.toInt();
      final slotX = rem % layout.resolution.x.toInt();

      final worldPos =
          origin +
          Vector3(slotX * spacing.x, slotY * spacing.y, slotZ * spacing.z);

      final faces = <gpu.Texture>[];
      for (final (forward, up) in cubeFaceBases) {
        final face = createHdrCaptureTarget(faceResolution);
        _pool.beginFrame();
        _renderView(
          view: RenderView(
            camera: PerspectiveCamera(
              fovRadiansY: fov,
              position: worldPos,
              target: worldPos + forward,
              up: up,
            ),
            layerMask: layerMask,
          ),
          outputColor: face,
          pixelSize: size,
          pool: _pool,
          environmentMap: environmentMap,
          transientsBuffer: transientsBuffer,
          lightComponent: lightComponent,
          punctualLighting: punctualLighting,
          spotShadowFrame: spotShadowFrame,
          captureLinearColor: true,
        );
        faces.add(face);
      }

      _convolveProbe(probeIndex: i, faces: faces);
    }

    _currentProbe = end;
    if (isDone) return _finalize();
    return null;
  }

  void _convolveProbe({
    required int probeIndex,
    required List<gpu.Texture> faces,
  }) {
    final col = layout.tileColumn(probeIndex);
    final row = layout.tileRow(probeIndex);

    final irrTileX = col * IrradianceFieldLayout.irradianceTile;
    final irrTileY =
        layout.irradianceOriginY + row * IrradianceFieldLayout.irradianceTile;

    final depthTileX = col * IrradianceFieldLayout.depthTile;
    final depthTileY =
        layout.depthOriginY + row * IrradianceFieldLayout.depthTile;

    for (var dy = 0; dy < IrradianceFieldLayout.irradianceTile; dy++) {
      for (var dx = 0; dx < IrradianceFieldLayout.irradianceTile; dx++) {
        final atlasX = irrTileX + dx;
        final atlasY = irrTileY + dy;
        final offset = (atlasY * layout.atlasWidth + atlasX) * 4;
        _atlasData[offset] = 0.05;
        _atlasData[offset + 1] = 0.05;
        _atlasData[offset + 2] = 0.05;
        _atlasData[offset + 3] = 0.0;
      }
    }

    for (var dy = 0; dy < IrradianceFieldLayout.depthTile; dy++) {
      for (var dx = 0; dx < IrradianceFieldLayout.depthTile; dx++) {
        final atlasX = depthTileX + dx;
        final atlasY = depthTileY + dy;
        final offset = (atlasY * layout.atlasWidth + atlasX) * 4;
        _atlasData[offset] = 1.0;
        _atlasData[offset + 1] = 1.0;
        _atlasData[offset + 2] = 0.0;
        _atlasData[offset + 3] = 1.0;
      }
    }
  }

  IrradianceFieldBake _finalize() {
    final byteData = ByteData(layout.atlasBytes);
    for (var i = 0; i < _atlasData.length; i++) {
      byteData.setUint16(
        i * 2,
        _float32ToFloat16(_atlasData[i]),
        Endian.little,
      );
    }
    return IrradianceFieldBake(
      origin: origin,
      spacing: spacing,
      resolution: layout.resolution,
      atlasBytes: byteData.buffer.asUint8List(),
    );
  }
}
