// Materialize showcase. The DamagedHelmet phases into existence bottom-to-top
// in three stages, each its own draw call over the same model:
//   1. A wireframe forms (line-list geometry over the mesh's unique edges,
//      unlit translucent .fmat with a glowing sweep front).
//   2. Glass triangles fly in and assemble over it (unwelded triangle soup
//      with flat outward normals; a per-triangle centroid + seed attribute
//      lets the vertex stage scatter each shard along its face normal with a
//      seeded tumble and pull it into place).
//   3. The real PBR surface reveals itself behind a hot emissive seam (the
//      original geometry with a .fmat that replicates standard PBR sampling,
//      re-binding the model's own textures, and discards above the front).
//
// A single eased progress value drives three object-space front heights
// (wire leads, glass lags, solid trails), written into the materials each
// tick, so all gating is a per-fragment compare against vertex.position.y.
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

import 'environment_menu.dart' show fetchResource;
import 'example_settings.dart';

const String _kHelmetUrl =
    'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
    'main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb';
const int _kHelmetSizeBytes = 3773916;

// How far (in normalized model height) each stage trails the one before it.
const double _kStageLag = 0.35;
// Sweep overshoot below/above the model so every fade band fully clears.
const double _kSweepPad = 0.15;

class ExampleMaterialize extends StatefulWidget {
  const ExampleMaterialize({super.key});

  @override
  State<ExampleMaterialize> createState() => _ExampleMaterializeState();
}

class _ExampleMaterializeState extends State<ExampleMaterialize> {
  final Scene scene = Scene();

  bool _ready = false;
  Object? _error;
  int _downloaded = 0;

  PreprocessedMaterial? _wireMaterial;
  PreprocessedMaterial? _glassMaterial;
  PreprocessedMaterial? _shellMaterial;

  final Node _spin = Node(name: 'materialize_spin');
  Node? _glassNode;

  // Object-space vertical extent of the helmet, from the shell geometry's
  // local bounds. Every sweep front is derived from these.
  double _minY = 0;
  double _maxY = 1;

  vm.Vector3 _cameraPosition = vm.Vector3(0, 0, -3);
  vm.Vector3 _cameraTarget = vm.Vector3.zero();

  // Timeline. _t runs past [0, 1] a little so the effect holds briefly when
  // fully materialized and fully hidden.
  double _t = -0.05;
  bool _playing = true;
  double _duration = 8.0;

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

      final bounds = primitive.geometry.localBounds;
      if (bounds == null) {
        throw StateError('Imported geometry has no local bounds.');
      }
      _minY = bounds.min.y;
      _maxY = bounds.max.y;
      final height = math.max(_maxY - _minY, 1e-3);

      // Stage 3: the original geometry, shading like the imported PBR
      // material but clipped to the reveal front with an emissive seam.
      _bindShellInputs(shell, primitive.material);
      shell.parameters.setFloat('seam_width', height * 0.05);
      primitive.material = shell;

      // Stage 1: the unique triangle edges as a line list. Source positions
      // and normals are reused so the lines can inflate off the surface.
      final wireNode = Node(
        name: 'materialize_wire',
        mesh: Mesh(_buildWireGeometry(source), wire),
      );
      meshNode.add(wireNode);
      wire.parameters
        ..setFloat('band', height * 0.06)
        ..setFloat('inflate', height * 0.004);

      // Stage 2: the unwelded shard soup with flat normals and per-triangle
      // centroid/seed attributes.
      final glassNode = Node(
        name: 'materialize_glass',
        mesh: Mesh(_buildGlassGeometry(source), glass),
      );
      meshNode.add(glassNode);
      glass.parameters
        ..setFloat('band', height * 0.30)
        ..setFloat('scatter', height * 0.8);

      _spin.add(helmet);
      scene.add(_spin);

      // Frame the camera. After the importer's scene-root Z flip glTF
      // models face -Z, so the camera sits on the -Z side.
      final center = vm.Vector3.copy(bounds.center);
      final radius = math.max((bounds.max - bounds.min).length * 0.5, 0.1);
      _cameraTarget = center;
      _cameraPosition = vm.Vector3(
        center.x + radius * 0.4,
        center.y + radius * 0.5,
        center.z - radius * 2.6,
      );

      _wireMaterial = wire;
      _glassMaterial = glass;
      _shellMaterial = shell;
      _glassNode = glassNode;
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

  /// A line list over the mesh's unique undirected edges. Shared edges are
  /// deduplicated so the translucent lines do not double-blend.
  MeshGeometry _buildWireGeometry(_TriangleMesh source) {
    final seen = <int>{};
    final edges = <int>[];
    void addEdge(int a, int b) {
      final lo = math.min(a, b);
      final hi = math.max(a, b);
      if (seen.add(lo * 0x100000 + hi)) {
        edges
          ..add(lo)
          ..add(hi);
      }
    }

    final indices = source.indices;
    for (var t = 0; t + 2 < indices.length; t += 3) {
      addEdge(indices[t], indices[t + 1]);
      addEdge(indices[t + 1], indices[t + 2]);
      addEdge(indices[t + 2], indices[t]);
    }
    return MeshGeometry.fromArrays(
      positions: source.positions,
      normals: source.normals,
      indices: edges,
      primitiveType: gpu.PrimitiveType.line,
    );
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

  /// Maps eased progress to the three object-space sweep fronts and writes
  /// them (plus the animated inputs) into the materials.
  void _applyProgress(double elapsedSeconds) {
    final wire = _wireMaterial;
    final glass = _glassMaterial;
    final shell = _shellMaterial;
    final glassNode = _glassNode;
    if (wire == null || glass == null || shell == null || glassNode == null) {
      return;
    }
    final p = _t.clamp(0.0, 1.0);
    final eased = p * p * (3 - 2 * p);
    final height = _maxY - _minY;

    const start = -_kSweepPad;
    const end = 1.0 + 2 * _kStageLag + _kSweepPad;
    final wireN = start + eased * (end - start);
    double frontY(double n) => _minY + n * height;

    final wireY = frontY(wireN);
    final glassY = frontY(wireN - _kStageLag);
    final solidY = frontY(wireN - 2 * _kStageLag);

    wire.parameters
      ..setFloat('wire_y', wireY)
      ..setFloat('solid_y', solidY);
    glass.parameters
      ..setFloat('glass_y', glassY)
      ..setFloat('solid_y', solidY)
      ..setFloat('time', elapsedSeconds);
    shell.parameters.setFloat('solid_y', solidY);

    // The glass vertex stage does its shard math in object space and needs
    // the node's world transform to write world outputs itself.
    glass.parameters.setMat4('model_matrix', glassNode.globalTransform);
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
                _t += deltaSeconds / _duration;
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
          left: 16,
          right: 16,
          bottom: 16,
          child: Card(
            color: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
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
                  const Text('Progress', style: TextStyle(color: Colors.white)),
                  Expanded(
                    child: Slider(
                      value: _t.clamp(0.0, 1.0).toDouble(),
                      onChangeStart: (_) => setState(() => _playing = false),
                      onChanged: (value) => setState(() => _t = value),
                    ),
                  ),
                  Text(
                    'Cycle ${_duration.toStringAsFixed(0)}s',
                    style: const TextStyle(color: Colors.white),
                  ),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: _duration,
                      min: 3,
                      max: 16,
                      onChanged: (value) => setState(() => _duration = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
