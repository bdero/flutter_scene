// Materialize showcase. The DamagedHelmet phases into existence from the
// bottom of the model to the top in three stages, each its own draw call over
// the same model:
//   1. A wireframe forms (view-facing ribbon quads over the mesh's unique
//      edges, unlit translucent .fmat with a glowing sweep front).
//   2. Glass triangles fly in and assemble over it (unwelded triangle soup
//      with flat outward normals; per-triangle centroid + seed attributes let
//      the vertex stage fly each shard in from a composable scattered pose,
//      a bias direction, a radial push from the model center, a push along
//      the face normal, and seeded jitter, fading in at a distance and
//      easing along an s-curve into a soft landing, then glowing on the
//      surface until the shell phases over it).
//   3. The real PBR surface reveals itself behind a hot emissive seam (the
//      original geometry with a .fmat that replicates standard PBR sampling,
//      re-binding the model's own textures, and discards above the front).
//
// A single eased progress value drives three staggered sweep fronts. All
// gating compares world-space height (the model only spins about the world
// up axis, so height is stable), wobbled by shared simplex noise so the
// boundaries read organic; the same noise inputs gate all three stages so
// their boundaries line up. Every mesh node and every primitive of the
// imported model is incorporated (wire/glass geometry per node, a shell
// material per primitive).
//
// Every look/timing input lives in MaterializeSettings (see
// materialize_settings.dart, which also holds the side panel and the
// playback bar); the panel's print button dumps the current values to the
// console.
//
// The wire and shard geometry is derived from the loaded model through the
// public readback and derivation APIs, Geometry.extractMeshData snapshots
// each primitive, MeshData.merge/unweld/extractEdges build the shard soup
// and the edge set (on a background isolate via compute), and
// LineSegmentsGeometry renders the edges as GPU-expanded thick ribbons.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart' show EnvironmentSelector, fetchResource;
import 'example_settings.dart';
import 'lighting_panel.dart';
import 'materialize_settings.dart';

const String _kHelmetUrl =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
    'main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb';
const int _kHelmetSizeBytes = 3773916;

// Sweep overshoot below/above the model so every fade band fully clears.
const double _kSweepPad = 0.15;

class ExampleMaterialize extends StatefulWidget {
  const ExampleMaterialize({super.key});

  @override
  State<ExampleMaterialize> createState() => _ExampleMaterializeState();
}

class _ExampleMaterializeState extends State<ExampleMaterialize> {
  final Scene scene = Scene();
  final MaterializeSettings _settings = MaterializeSettings();
  final EnvironmentSelector _environmentSelector = EnvironmentSelector();

  bool _ready = false;
  Object? _error;
  int _downloaded = 0;

  // One shell material per imported primitive (each carries that primitive's
  // textures), and one wire/glass pass per mesh node (each carries that
  // node's world transform).
  final List<PreprocessedMaterial> _shellMaterials = [];
  final List<(PreprocessedMaterial, LineSegmentsGeometry)> _wirePasses = [];
  final List<(Node, PreprocessedMaterial)> _glassPasses = [];

  final Node _spin = Node(name: 'materialize_spin');

  // World-space vertical extent of the whole model (all nodes, all
  // primitives), and its center, scanned at load with the spin at identity.
  double _minH = 0;
  double _maxH = 1;
  final vm.Vector3 _center = vm.Vector3.zero();
  double get _range => math.max(_maxH - _minH, 1e-3);

  vm.Vector3 _cameraPosition = vm.Vector3(0, 0, -3);
  vm.Vector3 _cameraTarget = vm.Vector3.zero();

  // Timeline. _t runs past [0, 1] a little so the effect holds briefly when
  // fully materialized and fully hidden.
  double _t = -0.05;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await fetchResource(
        _kHelmetUrl,
        expectedSize: _kHelmetSizeBytes,
        onChunk: (chunk) {
          if (!mounted) return;
          setState(() => _downloaded += chunk);
        },
      );
      final helmet = await Node.fromGlbBytes(bytes);
      if (!mounted) return;

      final meshNodes = <Node>[];
      _collectMeshNodes(helmet, meshNodes);
      if (meshNodes.isEmpty) {
        throw StateError('No mesh found in the downloaded model.');
      }

      // World-space AABB across every node and primitive, for the sweep
      // extent and the camera framing.
      var minX = double.infinity, minY = double.infinity;
      var minZ = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      var maxZ = double.negativeInfinity;
      var primitiveCount = 0;
      var triangleCount = 0;
      final scratch = vm.Vector3.zero();

      for (final meshNode in meshNodes) {
        final world = meshNode.globalTransform;
        final parts = <MeshData>[];
        for (final primitive in meshNode.mesh!.primitives) {
          final source = primitive.geometry.extractMeshData();
          parts.add(source);
          primitiveCount++;
          triangleCount += source.triangleCount;
          for (var v = 0; v < source.positions.length; v += 3) {
            scratch.setValues(
              source.positions[v],
              source.positions[v + 1],
              source.positions[v + 2],
            );
            world.transform3(scratch);
            if (scratch.x < minX) minX = scratch.x;
            if (scratch.y < minY) minY = scratch.y;
            if (scratch.z < minZ) minZ = scratch.z;
            if (scratch.x > maxX) maxX = scratch.x;
            if (scratch.y > maxY) maxY = scratch.y;
            if (scratch.z > maxZ) maxZ = scratch.z;
          }

          // Stage 3: this primitive keeps its geometry but shades through the
          // reveal material, mirroring its own imported textures/factors.
          final shell = await loadFmatMaterial('assets/materialize_shell.fmat');
          _bindShellInputs(shell, primitive.material);
          primitive.material = shell;
          _shellMaterials.add(shell);
        }

        // Derive the shard soup and the edge set on a background isolate;
        // both are pure MeshData transforms.
        final derived = await compute(
          _deriveMaterializeGeometry,
          MeshData.merge(parts),
        );
        if (!mounted) return;

        // Stage 1: the unique edges as GPU-expanded thick ribbons, offset
        // off the surface so they do not z-fight the shell.
        final wire = await loadFmatMaterial(
          'assets/materialize_wireframe.fmat',
        );
        final wireGeometry = LineSegmentsGeometry(
          derived.edges,
          normalOffset: 0.002,
        );
        meshNode.add(
          Node(name: 'materialize_wire', mesh: Mesh(wireGeometry, wire)),
        );
        _wirePasses.add((wire, wireGeometry));

        // Stage 2: the unwelded shard soup, carrying the canned
        // triangle_centroid/triangle_seed attributes the glass material's
        // vertex stage reads.
        final glass = await loadFmatMaterial('assets/materialize_glass.fmat');
        final glassNode = Node(
          name: 'materialize_glass',
          mesh: Mesh(MeshGeometry.fromMeshData(derived.shards), glass),
        );
        meshNode.add(glassNode);
        _glassPasses.add((glassNode, glass));
      }
      debugPrint(
        'Materialize: ${meshNodes.length} mesh node(s), '
        '$primitiveCount primitive(s), $triangleCount triangles',
      );

      _minH = minY;
      _maxH = maxY;
      _center.setValues(
        (minX + maxX) / 2,
        (minY + maxY) / 2,
        (minZ + maxZ) / 2,
      );
      final radius = math.max(
        vm.Vector3(maxX - minX, maxY - minY, maxZ - minZ).length * 0.5,
        0.1,
      );

      _spin.add(helmet);
      scene.add(_spin);

      // Frame the camera. After the importer's scene-root Z flip glTF
      // models face -Z, so the camera sits on the -Z side.
      _cameraTarget = vm.Vector3.copy(_center);
      _cameraPosition = vm.Vector3(
        _center.x + radius * 0.4,
        _center.y + radius * 0.5,
        _center.z - radius * 2.6,
      );

      _applySettings();
      _applyProgress(0);
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _collectMeshNodes(Node node, List<Node> out) {
    final mesh = node.mesh;
    if (mesh != null && mesh.primitives.isNotEmpty) {
      out.add(node);
    }
    for (final child in node.children) {
      _collectMeshNodes(child, out);
    }
  }

  /// Copies the imported material's textures and factors into the shell
  /// material's mirrored PBR parameters.
  void _bindShellInputs(PreprocessedMaterial shell, Material imported) {
    if (imported is! PhysicallyBasedMaterial) return;
    void bind(String name, TextureSource? source) {
      final texture = source?.sampledTexture;
      if (texture == null) return;
      shell.parameters.setTexture(
        name,
        texture,
        sampler: source!.sampledSampler,
      );
    }

    bind('base_color_texture', imported.baseColorTexture);
    bind('metallic_roughness_texture', imported.metallicRoughnessTexture);
    bind('normal_texture', imported.normalTexture);
    bind('occlusion_texture', imported.occlusionTexture);
    bind('emissive_texture', imported.emissiveTexture);
    shell.parameters
      ..setVec4('base_color_factor', imported.baseColorFactor)
      ..setFloat('metallic_factor', imported.metallicFactor)
      ..setFloat('roughness_factor', imported.roughnessFactor)
      ..setVec3('emissive_factor', imported.emissiveFactor.rgb)
      ..setFloat('normal_scale', imported.normalScale)
      ..setFloat('occlusion_strength', imported.occlusionStrength);
  }

  /// Writes every look setting into the materials (scaled to the model's
  /// world height where the setting is a fraction).
  void _applySettings() {
    if (_shellMaterials.isEmpty) return;
    final s = _settings;
    final range = _range;
    final noiseScale = s.noiseScale / range;
    final noiseAmp = s.noiseAmp * range;

    for (final (wire, wireGeometry) in _wirePasses) {
      wireGeometry.width = range * s.wireThickness;
      wire.parameters
        ..setFloat('band', range * 0.06)
        ..setVec4(
          'wire_color',
          vm.Vector4(s.wireColor.x, s.wireColor.y, s.wireColor.z, s.wireAlpha),
        )
        ..setFloat('glow_strength', s.wireGlow)
        ..setVec3('noise_scale', noiseScale)
        ..setFloat('noise_amp', noiseAmp);
    }

    for (final (_, glass) in _glassPasses) {
      glass.parameters
        ..setFloat('band', range * s.glassBand)
        ..setVec3('fly_dir', s.flyDir)
        ..setFloat('fly_distance', range * s.flyDistance)
        ..setFloat('center_distance', range * s.centerDistance)
        ..setFloat('normal_distance', range * s.normalDistance)
        ..setFloat('jitter', range * s.jitter)
        ..setFloat('fade_portion', s.fadePortion)
        ..setFloat('cool_span', s.coolSpan)
        ..setFloat('tumble', s.tumble)
        ..setVec4(
          'glass_color',
          vm.Vector4(s.glassTint.x, s.glassTint.y, s.glassTint.z, s.glassAlpha),
        )
        ..setVec3('glow_color', s.glassGlowColor)
        ..setFloat('glow_strength', s.glassGlowStrength)
        ..setVec3('noise_scale', noiseScale)
        ..setFloat('noise_amp', noiseAmp);
    }

    for (final shell in _shellMaterials) {
      shell.parameters
        ..setFloat('seam_width', range * s.seamWidth)
        ..setVec4(
          'seam_color',
          vm.Vector4(s.seamColor.x, s.seamColor.y, s.seamColor.z, 1.0),
        )
        ..setFloat('seam_strength', s.seamStrength)
        ..setVec3('noise_scale', noiseScale)
        ..setFloat('noise_amp', noiseAmp);
    }
  }

  /// Maps eased progress to the three staggered sweep fronts and writes them
  /// (plus the animated inputs) into the materials.
  void _applyProgress(double elapsedSeconds) {
    if (_shellMaterials.isEmpty) return;
    final s = _settings;
    final p = _t.clamp(0.0, 1.0);
    final eased = p * p * (3 - 2 * p);

    // Pad past the noise amplitude so the wobbled boundaries fully clear.
    final pad = _kSweepPad + s.noiseAmp;
    final start = -pad;
    final end = 1.0 + s.lagWireToGlass + s.lagGlassToSolid + pad;
    final wireN = start + eased * (end - start);
    double front(double n) => _minH + n * _range;

    final wireFront = front(wireN);
    final glassFront = front(wireN - s.lagWireToGlass);
    final solidFront = front(wireN - s.lagWireToGlass - s.lagGlassToSolid);

    // The model center, spun along with the model, for the radial scatter.
    final center = vm.Vector3.copy(_center);
    _spin.globalTransform.transform3(center);

    for (final (wire, _) in _wirePasses) {
      wire.parameters
        ..setFloat('wire_front', wireFront)
        ..setFloat('solid_front', solidFront);
    }
    for (final (node, glass) in _glassPasses) {
      glass.parameters
        ..setFloat('glass_front', glassFront)
        ..setFloat('solid_front', solidFront)
        ..setFloat('time', elapsedSeconds)
        ..setVec3('model_center', center)
        ..setMat4('model_matrix', node.globalTransform);
    }
    for (final shell in _shellMaterials) {
      shell.parameters.setFloat('solid_front', solidFront);
    }
  }

  @override
  void dispose() {
    scene.removeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          'Failed to load the model.\n$_error',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!_ready) {
      final fraction = (_downloaded / _kHelmetSizeBytes)
          .clamp(0.0, 1.0)
          .toDouble();
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              child: LinearProgressIndicator(value: fraction),
            ),
            const SizedBox(height: 12),
            Text(
              'Downloading DamagedHelmet '
              '(${(_downloaded / (1024 * 1024)).toStringAsFixed(1)} MB)',
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF06080C))),
        Positioned.fill(
          child: SceneView(
            scene,
            camera: PerspectiveCamera(
              position: _cameraPosition,
              target: _cameraTarget,
            ),
            onTick: (elapsed, deltaSeconds) {
              final seconds = elapsed.inMicroseconds / 1e6;
              if (_playing) {
                _t += deltaSeconds / _settings.duration;
                // Hold briefly at both ends, then loop.
                if (_t > 1.3) _t = -0.08;
              }
              _spin.localTransform = vm.Matrix4.rotationY(seconds * 0.25);
              _applyProgress(seconds);
              exampleSettings.applyTo(scene);
            },
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: LightingPanel(
            scene: scene,
            selector: _environmentSelector,
            initialEnvironmentId: 'helipad',
            initialSkyBlur: 0.33,
            initialExposure: 2.03,
            initialIblIntensity: 1.36,
            initialRotationDegrees: vm.Vector3(0.0, -80.7, 0.0),
          ),
        ),
        // The panel starts below the debug banner and the global settings
        // buttons in the top-right corner.
        Positioned(
          top: 72,
          right: 8,
          bottom: 8,
          child: MaterializeSettingsPanel(
            settings: _settings,
            onChanged: _applySettings,
          ),
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: MaterializePlaybackBar(
              playing: _playing,
              progress: _t.clamp(0.0, 1.0).toDouble(),
              onPlayingChanged: (playing) => setState(() => _playing = playing),
              onRestart: () => setState(() {
                _t = -0.05;
                _playing = true;
              }),
              onScrub: (value) => setState(() => _t = value),
            ),
          ),
        ),
      ],
    );
  }
}

/// Derives the Materialize passes' geometry from one node's merged source
/// mesh. Pure CPU work; runs on a background isolate via `compute`.
({MeshData shards, LineSegmentData edges}) _deriveMaterializeGeometry(
  MeshData source,
) {
  return (
    shards: source.unweld(
      attributes: {UnweldAttribute.centroid, UnweldAttribute.seed},
    ),
    edges: source.extractEdges(),
  );
}
