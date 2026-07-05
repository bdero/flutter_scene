// Materialize showcase. The DamagedHelmet phases into existence from the
// bottom of the model to the top in three stages, each its own draw call over
// the same model:
//   1. A wireframe forms (view-facing ribbon quads over the mesh's unique
//      edges, unlit translucent .fmat with a glowing sweep front).
//   2. Glass triangles fly in and assemble over it (unwelded triangle soup
//      with flat outward normals; per-triangle centroid + seed attributes let
//      the vertex stage fly each shard in from a settable world direction,
//      fading in at a distance and easing along an s-curve into a soft
//      landing, then glowing on the surface until the shell phases over it).
//   3. The real PBR surface reveals itself behind a hot emissive seam (the
//      original geometry with a .fmat that replicates standard PBR sampling,
//      re-binding the model's own textures, and discards above the front).
//
// A single eased progress value drives three staggered sweep fronts. All
// gating compares dot(position, sweep_dir) in object space, where sweep_dir
// is the model's up axis mapped into mesh space at load, so the reveal
// travels bottom-to-top regardless of how the source asset is oriented.
//
// Every look/timing input lives in _MaterializeSettings, editable from the
// side panel; the print button dumps the current values to the console.
//
// The example reads the imported primitive's retained CPU vertex data back
// through the internal cpuMeshData accessor to derive the wire and soup
// geometry; in-repo example apps may reach into internals, so the lints are
// waived for the whole file (same waiver as example_shapes.dart).
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart' show EnvironmentSelector, fetchResource;
import 'example_settings.dart';
import 'lighting_panel.dart';

const String _kHelmetUrl =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
    'main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb';
const int _kHelmetSizeBytes = 3773916;

// Sweep overshoot below/above the model so every fade band fully clears.
const double _kSweepPad = 0.15;

/// Every tunable of the effect. Lengths are fractions of the model's height
/// along the sweep axis; the print button dumps the current values.
class _MaterializeSettings {
  // Wireframe.
  double wireThickness = 0.006;
  vm.Vector3 wireColor = vm.Vector3(0.25, 0.85, 1.0);
  double wireAlpha = 0.85;
  double wireGlow = 8.0;

  // Glass.
  vm.Vector3 glassTint = vm.Vector3(0.5, 0.85, 1.0);
  double glassAlpha = 0.69;
  vm.Vector3 glassGlowColor = vm.Vector3(1.0, 1.0, 0.6);
  double glassGlowStrength = 22.0;
  vm.Vector3 flyDir = vm.Vector3(0.0, -1.0, 0.0);
  double flyDistance = 1.4;
  double fadePortion = 0.64;
  double coolSpan = 0.33;
  double tumble = 2.3;
  double glassBand = 0.5;

  // Shell reveal.
  double seamWidth = 0.23;
  vm.Vector3 seamColor = vm.Vector3(0.3, 0.9, 1.0);
  double seamStrength = 28.6;

  // Timing.
  double duration = 7.0;
  double lagWireToGlass = 0.0;
  double lagGlassToSolid = 1.05;

  String dump() {
    String v3(vm.Vector3 v) =>
        '${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, '
        '${v.z.toStringAsFixed(3)}';
    String f(double v) => v.toStringAsFixed(3);
    return '''
=== Materialize settings ===
wireThickness: ${f(wireThickness)}
wireColor: ${v3(wireColor)}
wireAlpha: ${f(wireAlpha)}
wireGlow: ${f(wireGlow)}
glassTint: ${v3(glassTint)}
glassAlpha: ${f(glassAlpha)}
glassGlowColor: ${v3(glassGlowColor)}
glassGlowStrength: ${f(glassGlowStrength)}
flyDir: ${v3(flyDir)}
flyDistance: ${f(flyDistance)}
fadePortion: ${f(fadePortion)}
coolSpan: ${f(coolSpan)}
tumble: ${f(tumble)}
glassBand: ${f(glassBand)}
seamWidth: ${f(seamWidth)}
seamColor: ${v3(seamColor)}
seamStrength: ${f(seamStrength)}
duration: ${f(duration)}
lagWireToGlass: ${f(lagWireToGlass)}
lagGlassToSolid: ${f(lagGlassToSolid)}
============================''';
  }
}

class ExampleMaterialize extends StatefulWidget {
  const ExampleMaterialize({super.key});

  @override
  State<ExampleMaterialize> createState() => _ExampleMaterializeState();
}

class _ExampleMaterializeState extends State<ExampleMaterialize> {
  final Scene scene = Scene();
  final _MaterializeSettings _settings = _MaterializeSettings();
  final EnvironmentSelector _environmentSelector = EnvironmentSelector();

  bool _ready = false;
  Object? _error;
  int _downloaded = 0;

  PreprocessedMaterial? _wireMaterial;
  PreprocessedMaterial? _glassMaterial;
  PreprocessedMaterial? _shellMaterial;

  final Node _spin = Node(name: 'materialize_spin');
  Node? _wireNode;
  Node? _glassNode;

  // The model's up axis in mesh-object space, and the vertex extent along it.
  vm.Vector3 _sweepDir = vm.Vector3(0, 1, 0);
  double _sweepMin = 0;
  double _sweepMax = 1;
  double get _sweepRange => math.max(_sweepMax - _sweepMin, 1e-3);

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
      final wire = await loadFmatMaterial('assets/materialize_wireframe.fmat');
      final glass = await loadFmatMaterial('assets/materialize_glass.fmat');
      final shell = await loadFmatMaterial('assets/materialize_shell.fmat');

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

      final meshNode = _findMeshNode(helmet);
      if (meshNode == null) {
        throw StateError('No mesh found in the downloaded model.');
      }
      final primitive = meshNode.mesh!.primitives.first;
      final source = _extractTriangleMesh(primitive.geometry);

      // The source asset's mesh space is not necessarily y-up (the glTF node
      // hierarchy carries a rotation), so map the model's world up axis into
      // mesh space and sweep along that.
      final inverse = vm.Matrix4.copy(meshNode.globalTransform)..invert();
      _sweepDir = inverse.getRotation().transform(vm.Vector3(0, 1, 0))
        ..normalize();
      _sweepMin = double.infinity;
      _sweepMax = double.negativeInfinity;
      for (var v = 0; v < source.positions.length; v += 3) {
        final s =
            source.positions[v] * _sweepDir.x +
            source.positions[v + 1] * _sweepDir.y +
            source.positions[v + 2] * _sweepDir.z;
        if (s < _sweepMin) _sweepMin = s;
        if (s > _sweepMax) _sweepMax = s;
      }

      // Stage 3: the original geometry, shading like the imported PBR
      // material but clipped to the reveal front with an emissive seam.
      _bindShellInputs(shell, primitive.material);
      primitive.material = shell;

      // Stage 1: view-facing ribbon quads over the mesh's unique edges.
      final wireNode = Node(
        name: 'materialize_wire',
        mesh: Mesh(_buildWireGeometry(source), wire),
      );
      meshNode.add(wireNode);

      // Stage 2: the unwelded shard soup with flat normals and per-triangle
      // centroid/seed attributes.
      final glassNode = Node(
        name: 'materialize_glass',
        mesh: Mesh(_buildGlassGeometry(source), glass),
      );
      meshNode.add(glassNode);

      _spin.add(helmet);
      scene.add(_spin);

      // Frame the camera. After the importer's scene-root Z flip glTF
      // models face -Z, so the camera sits on the -Z side.
      final bounds = primitive.geometry.localBounds;
      final center = bounds == null
          ? vm.Vector3.zero()
          : vm.Vector3.copy(bounds.center);
      final radius = bounds == null
          ? 1.0
          : math.max((bounds.max - bounds.min).length * 0.5, 0.1);
      _cameraTarget = center;
      _cameraPosition = vm.Vector3(
        center.x + radius * 0.4,
        center.y + radius * 0.5,
        center.z - radius * 2.6,
      );

      _wireMaterial = wire;
      _glassMaterial = glass;
      _shellMaterial = shell;
      _wireNode = wireNode;
      _glassNode = glassNode;
      _applySettings();
      _applyProgress(0);
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Node? _findMeshNode(Node node) {
    final mesh = node.mesh;
    if (mesh != null && mesh.primitives.isNotEmpty) {
      return node;
    }
    for (final child in node.children) {
      final found = _findMeshNode(child);
      if (found != null) return found;
    }
    return null;
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

  /// Reads positions, normals, and triangle indices back from the imported
  /// geometry's retained CPU copy (interleaved unskinned layout, 12 floats
  /// per vertex).
  _TriangleMesh _extractTriangleMesh(Geometry geometry) {
    final data = geometry.cpuMeshData;
    final vertices = data.vertices;
    final indexData = data.indices;
    if (vertices == null || indexData == null) {
      throw StateError('Imported geometry retained no CPU vertex data.');
    }
    const stride = 12; // floats per unskinned vertex
    final floats = Float32List.sublistView(vertices);
    final vertexCount = data.vertexCount;
    final positions = Float32List(vertexCount * 3);
    final normals = Float32List(vertexCount * 3);
    for (var v = 0; v < vertexCount; v++) {
      final base = v * stride;
      positions[v * 3] = floats[base];
      positions[v * 3 + 1] = floats[base + 1];
      positions[v * 3 + 2] = floats[base + 2];
      normals[v * 3] = floats[base + 3];
      normals[v * 3 + 1] = floats[base + 4];
      normals[v * 3 + 2] = floats[base + 5];
    }
    final List<int> indices = data.indexType == gpu.IndexType.int32
        ? Uint32List.sublistView(indexData, 0, data.indexCount)
        : Uint16List.sublistView(indexData, 0, data.indexCount);
    return _TriangleMesh(positions, normals, indices);
  }

  /// A view-facing ribbon quad per unique undirected edge. Each vertex
  /// carries the opposite endpoint and a side sign; the material's vertex
  /// stage expands the quad perpendicular to the edge and the view.
  MeshGeometry _buildWireGeometry(_TriangleMesh source) {
    final seen = <int>{};
    final edgeA = <int>[];
    final edgeB = <int>[];
    void addEdge(int a, int b) {
      final lo = math.min(a, b);
      final hi = math.max(a, b);
      if (seen.add(lo * 0x100000 + hi)) {
        edgeA.add(lo);
        edgeB.add(hi);
      }
    }

    final srcIndices = source.indices;
    for (var t = 0; t + 2 < srcIndices.length; t += 3) {
      addEdge(srcIndices[t], srcIndices[t + 1]);
      addEdge(srcIndices[t + 1], srcIndices[t + 2]);
      addEdge(srcIndices[t + 2], srcIndices[t]);
    }

    final edgeCount = edgeA.length;
    final positions = Float32List(edgeCount * 12);
    final normals = Float32List(edgeCount * 12);
    final others = Float32List(edgeCount * 12);
    final sides = Float32List(edgeCount * 4);
    final indices = List<int>.filled(edgeCount * 6, 0);
    void writeVec3(Float32List dst, int vertex, Float32List src, int index) {
      dst[vertex * 3] = src[index * 3];
      dst[vertex * 3 + 1] = src[index * 3 + 1];
      dst[vertex * 3 + 2] = src[index * 3 + 2];
    }

    for (var e = 0; e < edgeCount; e++) {
      final a = edgeA[e], b = edgeB[e];
      final base = e * 4;
      for (var corner = 0; corner < 4; corner++) {
        final v = base + corner;
        final atA = corner < 2;
        writeVec3(positions, v, source.positions, atA ? a : b);
        writeVec3(normals, v, source.normals, atA ? a : b);
        writeVec3(others, v, source.positions, atA ? b : a);
        sides[v] = corner.isEven ? 1.0 : -1.0;
      }
      final i = e * 6;
      indices[i] = base;
      indices[i + 1] = base + 1;
      indices[i + 2] = base + 2;
      indices[i + 3] = base;
      indices[i + 4] = base + 2;
      indices[i + 5] = base + 3;
    }
    return MeshGeometry.fromArrays(
        positions: positions,
        normals: normals,
        indices: indices,
      )
      ..setCustomAttribute('edge_other', others, components: 3)
      ..setCustomAttribute('edge_side', sides, components: 1);
  }

  /// The shard soup: every triangle unwelded to three unique vertices with a
  /// flat outward normal, plus the triangle centroid and a random seed as
  /// custom attributes for the glass material's vertex stage.
  MeshGeometry _buildGlassGeometry(_TriangleMesh source) {
    final indices = source.indices;
    final triangleCount = indices.length ~/ 3;
    final positions = Float32List(triangleCount * 9);
    final normals = Float32List(triangleCount * 9);
    final centroids = Float32List(triangleCount * 9);
    final seeds = Float32List(triangleCount * 3);

    final p0 = vm.Vector3.zero(),
        p1 = vm.Vector3.zero(),
        p2 = vm.Vector3.zero();
    final smooth = vm.Vector3.zero();
    var seedState = 0x9e3779b9;
    for (var t = 0; t < triangleCount; t++) {
      final i0 = indices[t * 3],
          i1 = indices[t * 3 + 1],
          i2 = indices[t * 3 + 2];
      p0.setValues(
        source.positions[i0 * 3],
        source.positions[i0 * 3 + 1],
        source.positions[i0 * 3 + 2],
      );
      p1.setValues(
        source.positions[i1 * 3],
        source.positions[i1 * 3 + 1],
        source.positions[i1 * 3 + 2],
      );
      p2.setValues(
        source.positions[i2 * 3],
        source.positions[i2 * 3 + 1],
        source.positions[i2 * 3 + 2],
      );

      // Flat face normal, sign-checked against the averaged vertex normals
      // so it always points outward.
      final flat = (p1 - p0).cross(p2 - p0);
      if (flat.length2 > 0) flat.normalize();
      smooth.setValues(
        source.normals[i0 * 3] +
            source.normals[i1 * 3] +
            source.normals[i2 * 3],
        source.normals[i0 * 3 + 1] +
            source.normals[i1 * 3 + 1] +
            source.normals[i2 * 3 + 1],
        source.normals[i0 * 3 + 2] +
            source.normals[i1 * 3 + 2] +
            source.normals[i2 * 3 + 2],
      );
      if (flat.dot(smooth) < 0) flat.negate();

      final cx = (p0.x + p1.x + p2.x) / 3;
      final cy = (p0.y + p1.y + p2.y) / 3;
      final cz = (p0.z + p1.z + p2.z) / 3;

      // Cheap deterministic per-triangle random in [0, 1).
      seedState = 0x1fffffff & (seedState * 1103515245 + 12345);
      final seed = (seedState & 0xffff) / 0x10000;

      for (var v = 0; v < 3; v++) {
        final src = v == 0 ? p0 : (v == 1 ? p1 : p2);
        final out = (t * 3 + v) * 3;
        positions[out] = src.x;
        positions[out + 1] = src.y;
        positions[out + 2] = src.z;
        normals[out] = flat.x;
        normals[out + 1] = flat.y;
        normals[out + 2] = flat.z;
        centroids[out] = cx;
        centroids[out + 1] = cy;
        centroids[out + 2] = cz;
        seeds[t * 3 + v] = seed;
      }
    }
    return MeshGeometry.fromArrays(positions: positions, normals: normals)
      ..setCustomAttribute('tri_centroid', centroids, components: 3)
      ..setCustomAttribute('tri_seed', seeds, components: 1);
  }

  /// Writes every look setting into the materials (scaled to the model's
  /// height along the sweep axis where the setting is a fraction).
  void _applySettings() {
    final wire = _wireMaterial;
    final glass = _glassMaterial;
    final shell = _shellMaterial;
    if (wire == null || glass == null || shell == null) return;
    final s = _settings;
    final range = _sweepRange;

    wire.parameters
      ..setVec3('sweep_dir', _sweepDir)
      ..setFloat('band', range * 0.06)
      ..setFloat('thickness', range * s.wireThickness)
      ..setFloat('inflate', range * 0.004)
      ..setVec4(
        'wire_color',
        vm.Vector4(s.wireColor.x, s.wireColor.y, s.wireColor.z, s.wireAlpha),
      )
      ..setFloat('glow_strength', s.wireGlow);

    glass.parameters
      ..setVec3('sweep_dir', _sweepDir)
      ..setFloat('band', range * s.glassBand)
      ..setVec3('fly_dir', s.flyDir)
      ..setFloat('fly_distance', range * s.flyDistance)
      ..setFloat('fade_portion', s.fadePortion)
      ..setFloat('cool_span', s.coolSpan)
      ..setFloat('tumble', s.tumble)
      ..setVec4(
        'glass_color',
        vm.Vector4(s.glassTint.x, s.glassTint.y, s.glassTint.z, s.glassAlpha),
      )
      ..setVec3('glow_color', s.glassGlowColor)
      ..setFloat('glow_strength', s.glassGlowStrength);

    shell.parameters
      ..setVec3('sweep_dir', _sweepDir)
      ..setFloat('seam_width', range * s.seamWidth)
      ..setVec4(
        'seam_color',
        vm.Vector4(s.seamColor.x, s.seamColor.y, s.seamColor.z, 1.0),
      )
      ..setFloat('seam_strength', s.seamStrength);
  }

  /// Maps eased progress to the three staggered sweep fronts and writes them
  /// (plus the animated inputs) into the materials.
  void _applyProgress(double elapsedSeconds) {
    final wire = _wireMaterial;
    final glass = _glassMaterial;
    final shell = _shellMaterial;
    final wireNode = _wireNode;
    final glassNode = _glassNode;
    if (wire == null ||
        glass == null ||
        shell == null ||
        wireNode == null ||
        glassNode == null) {
      return;
    }
    final s = _settings;
    final p = _t.clamp(0.0, 1.0);
    final eased = p * p * (3 - 2 * p);

    const start = -_kSweepPad;
    final end = 1.0 + s.lagWireToGlass + s.lagGlassToSolid + _kSweepPad;
    final wireN = start + eased * (end - start);
    double front(double n) => _sweepMin + n * _sweepRange;

    final wireFront = front(wireN);
    final glassFront = front(wireN - s.lagWireToGlass);
    final solidFront = front(wireN - s.lagWireToGlass - s.lagGlassToSolid);

    wire.parameters
      ..setFloat('wire_front', wireFront)
      ..setFloat('solid_front', solidFront)
      ..setMat4('model_matrix', wireNode.globalTransform);
    glass.parameters
      ..setFloat('glass_front', glassFront)
      ..setFloat('solid_front', solidFront)
      ..setFloat('time', elapsedSeconds)
      ..setMat4('model_matrix', glassNode.globalTransform);
    shell.parameters.setFloat('solid_front', solidFront);
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
            showSkybox: false,
          ),
        ),
        Positioned(top: 8, right: 8, bottom: 8, child: _settingsPanel()),
        Positioned(top: 8, left: 8, child: _playbackBar()),
      ],
    );
  }

  Widget _playbackBar() {
    return Card(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: () => setState(() => _playing = !_playing),
            ),
            IconButton(
              icon: const Icon(Icons.replay, color: Colors.white),
              onPressed: () => setState(() {
                _t = -0.05;
                _playing = true;
              }),
            ),
            SizedBox(
              width: 220,
              child: Slider(
                value: _t.clamp(0.0, 1.0).toDouble(),
                onChangeStart: (_) => setState(() => _playing = false),
                onChanged: (value) => setState(() => _t = value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsPanel() {
    return SizedBox(
      width: 290,
      child: Card(
        color: Colors.black54,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  const Text(
                    'Effect settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Print settings to console',
                    icon: const Icon(Icons.print, color: Colors.white),
                    onPressed: () => debugPrint(_settings.dump()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  _section('Wireframe', [
                    _slider(
                      'Thickness',
                      _settings.wireThickness,
                      0.001,
                      0.03,
                      (v) => _settings.wireThickness = v,
                    ),
                    _colorRow(
                      'Color',
                      _settings.wireColor,
                      (v) => _settings.wireColor = v,
                    ),
                    _slider(
                      'Opacity',
                      _settings.wireAlpha,
                      0.0,
                      1.0,
                      (v) => _settings.wireAlpha = v,
                    ),
                    _slider(
                      'Front glow',
                      _settings.wireGlow,
                      0.0,
                      30.0,
                      (v) => _settings.wireGlow = v,
                    ),
                  ]),
                  _section('Glass', [
                    _colorRow(
                      'Tint',
                      _settings.glassTint,
                      (v) => _settings.glassTint = v,
                    ),
                    _slider(
                      'Translucency',
                      _settings.glassAlpha,
                      0.0,
                      1.0,
                      (v) => _settings.glassAlpha = v,
                    ),
                    _colorRow(
                      'Glow color',
                      _settings.glassGlowColor,
                      (v) => _settings.glassGlowColor = v,
                    ),
                    _slider(
                      'Glow intensity',
                      _settings.glassGlowStrength,
                      0.0,
                      30.0,
                      (v) => _settings.glassGlowStrength = v,
                    ),
                    _slider(
                      'Fly-in X',
                      _settings.flyDir.x,
                      -1.0,
                      1.0,
                      (v) => _settings.flyDir.x = v,
                    ),
                    _slider(
                      'Fly-in Y',
                      _settings.flyDir.y,
                      -1.0,
                      1.0,
                      (v) => _settings.flyDir.y = v,
                    ),
                    _slider(
                      'Fly-in Z',
                      _settings.flyDir.z,
                      -1.0,
                      1.0,
                      (v) => _settings.flyDir.z = v,
                    ),
                    _slider(
                      'Fly distance',
                      _settings.flyDistance,
                      0.1,
                      4.0,
                      (v) => _settings.flyDistance = v,
                    ),
                    _slider(
                      'Fade portion',
                      _settings.fadePortion,
                      0.05,
                      1.0,
                      (v) => _settings.fadePortion = v,
                    ),
                    _slider(
                      'Glow cool span',
                      _settings.coolSpan,
                      0.05,
                      4.0,
                      (v) => _settings.coolSpan = v,
                    ),
                    _slider(
                      'Tumble',
                      _settings.tumble,
                      0.0,
                      3.0,
                      (v) => _settings.tumble = v,
                    ),
                    _slider(
                      'Assembly band',
                      _settings.glassBand,
                      0.05,
                      1.0,
                      (v) => _settings.glassBand = v,
                    ),
                  ]),
                  _section('Reveal', [
                    _slider(
                      'Seam thickness',
                      _settings.seamWidth,
                      0.005,
                      0.3,
                      (v) => _settings.seamWidth = v,
                    ),
                    _colorRow(
                      'Seam color',
                      _settings.seamColor,
                      (v) => _settings.seamColor = v,
                    ),
                    _slider(
                      'Seam brightness',
                      _settings.seamStrength,
                      0.0,
                      40.0,
                      (v) => _settings.seamStrength = v,
                    ),
                  ]),
                  _section('Timing', [
                    _slider(
                      'Cycle seconds',
                      _settings.duration,
                      3.0,
                      20.0,
                      (v) => _settings.duration = v,
                    ),
                    _slider(
                      'Wire to glass lag',
                      _settings.lagWireToGlass,
                      0.0,
                      1.0,
                      (v) => _settings.lagWireToGlass = v,
                    ),
                    _slider(
                      'Glass to solid lag',
                      _settings.lagGlassToSolid,
                      0.0,
                      1.5,
                      (v) => _settings.lagGlassToSolid = v,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    void Function(double) apply,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: (v) => setState(() {
                apply(v);
                _applySettings();
              }),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _colorRow(
    String label,
    vm.Vector3 color,
    void Function(vm.Vector3) apply,
  ) {
    Widget channel(String name, double value, void Function(double) set) {
      return Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0).toDouble(),
            onChanged: (v) => setState(() {
              set(v);
              apply(color);
              _applySettings();
            }),
          ),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: Color.fromARGB(
              255,
              (color.x * 255).round(),
              (color.y * 255).round(),
              (color.z * 255).round(),
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        channel('R', color.x, (v) => color.x = v),
        channel('G', color.y, (v) => color.y = v),
        channel('B', color.z, (v) => color.z = v),
      ],
    );
  }
}

class _TriangleMesh {
  _TriangleMesh(this.positions, this.normals, this.indices);

  final Float32List positions;
  final Float32List normals;
  final List<int> indices;
}
