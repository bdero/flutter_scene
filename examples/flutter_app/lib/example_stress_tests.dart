// Stress-test catalog: downloads Khronos glTF Sample Assets at runtime
// and renders them via the runtime GLB importer. Lets the renderer be
// exercised against PBR fidelity, animation/skinning, and correctness
// scenes without committing big binary blobs to the repo.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide Animation;
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

import 'hdr_image.dart';
import 'stress_cache.dart';
// The in-memory offline (ahead-of-time) glTF -> .model conversion, used by the
// per-test importer toggle below. Reaching into flutter_scene's internals is
// intentional here: this is a renderer stress test, not a typical consumer.
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';

// Toggle these on to inspect scenes as they load. Both are off by
// default; flip them locally when debugging a renderer regression in
// a specific stress test.
const bool _kDebugDumpScene = false;
const bool _kDebugTintMaterials = false;

/// Which importer path a stress test exercises. [runtime] uses the direct GLB
/// importer (`Node.fromGlbBytes` / `Node.fromGltfBytes`). [offline] runs the
/// ahead-of-time glTF -> .model conversion in memory and loads the result via
/// `Node.fromFlatbuffer`, the same conversion the `buildModels` build hook
/// performs. Offline is `.glb` only (the offline importer has no multi-file
/// `.gltf` path).
enum _ImporterMode { runtime, offline }

class _StressTest {
  const _StressTest({
    required this.id,
    required this.title,
    required this.description,
    required this.url,
    required this.sizeBytes,
    this.animationName,
  });

  final String id;
  final String title;
  final String description;
  final String url;
  final int sizeBytes;
  // If set, the first matching animation is played on a loop after load.
  final String? animationName;

  /// True when [url] points at a multi-file glTF (a `.gltf` JSON with
  /// external `.bin` and image files) rather than a single-file `.glb`.
  bool get isMultiFile => url.endsWith('.gltf');
}

const _catalog = <_StressTest>[
  _StressTest(
    id: 'ABeautifulGame',
    title: 'A Beautiful Game',
    description:
        'Chess set with rich PBR materials, many meshes, many textures. '
        'Stresses material variety and draw-call count.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/ABeautifulGame/glTF-Binary/ABeautifulGame.glb',
    sizeBytes: 42977928,
  ),
  _StressTest(
    id: 'AntiqueCamera',
    title: 'Antique Camera',
    description:
        'High-fidelity PBR with normal maps, occlusion, and emissive. A '
        'good "looks right by default" check.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AntiqueCamera/glTF-Binary/AntiqueCamera.glb',
    sizeBytes: 17540348,
  ),
  _StressTest(
    id: 'DamagedHelmet',
    title: 'Damaged Helmet',
    description:
        'The canonical glTF PBR test asset: one mesh with base color, '
        'normal, metallic-roughness, emissive, and occlusion maps. A quick '
        'all-in-one PBR fidelity check.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/DamagedHelmet/glTF-Binary/DamagedHelmet.glb',
    sizeBytes: 3773916,
  ),
  _StressTest(
    id: 'SciFiHelmet',
    title: 'Sci-Fi Helmet',
    description:
        'High-detail PBR helmet shipped as multi-file glTF: a .gltf plus '
        'a .bin buffer and four large textures. Exercises external '
        'resource resolution.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/SciFiHelmet/glTF/SciFiHelmet.gltf',
    sizeBytes: 30286979,
  ),
  _StressTest(
    id: 'FlightHelmet',
    title: 'Flight Helmet',
    description:
        'The Khronos high-fidelity reference: many separate meshes and '
        'textures. Multi-file glTF.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/FlightHelmet/glTF/FlightHelmet.gltf',
    sizeBytes: 48392569,
  ),
  _StressTest(
    id: 'Sponza',
    title: 'Sponza',
    description:
        'The classic architectural scene: large, many materials and '
        'textures, lots of draw calls. Multi-file glTF (71 files).',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/Sponza/glTF/Sponza.gltf',
    sizeBytes: 52686624,
  ),
  _StressTest(
    id: 'MetalRoughSpheres',
    title: 'Metal/Rough Spheres',
    description:
        'Grid of spheres varying metallic and roughness across the full '
        'range. Material-coverage sanity check.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/MetalRoughSpheres/glTF-Binary/MetalRoughSpheres.glb',
    sizeBytes: 11221356,
  ),
  _StressTest(
    id: 'Lantern',
    title: 'Lantern',
    description:
        'Emissive PBR test: the lantern glass should glow above the IBL '
        'while the metal frame stays grounded.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/Lantern/glTF-Binary/Lantern.glb',
    sizeBytes: 9564264,
  ),
  _StressTest(
    id: 'WaterBottle',
    title: 'Water Bottle',
    description:
        'Compact PBR; bottle label, cap, plastic. Without KHR_transmission '
        'support the bottle reads as opaque white plastic.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/WaterBottle/glTF-Binary/WaterBottle.glb',
    sizeBytes: 8966700,
  ),
  _StressTest(
    id: 'RecursiveSkeletons',
    title: 'Recursive Skeletons',
    description:
        'Deeply nested skinning hierarchy. Worst-case for the joint-matrix '
        'texture upload.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/RecursiveSkeletons/glTF-Binary/RecursiveSkeletons.glb',
    sizeBytes: 561620,
    animationName: 'Skeleton_Pose',
  ),
  _StressTest(
    id: 'BrainStem',
    title: 'Brain Stem',
    description:
        'The Khronos walking animation reference; common skinning baseline.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/BrainStem/glTF-Binary/BrainStem.glb',
    sizeBytes: 3194848,
    animationName: 'animation_0',
  ),
  _StressTest(
    id: 'Fox',
    title: 'Fox',
    description:
        'Quadruped skinning. Has Survey/Walk/Run clips; we play whichever '
        'lands first in the list.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/Fox/glTF-Binary/Fox.glb',
    sizeBytes: 162852,
    animationName: 'Run',
  ),
  _StressTest(
    id: 'AlphaBlendModeTest',
    title: 'Alpha Blend Mode Test',
    description:
        'Validation grid for OPAQUE / MASK / BLEND alpha modes. Surfaces '
        'sort-order and premultiplication regressions.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/AlphaBlendModeTest/glTF-Binary/AlphaBlendModeTest.glb',
    sizeBytes: 2978812,
  ),
  _StressTest(
    id: 'NormalTangentTest',
    title: 'Normal/Tangent Test',
    description:
        'Pairs of identical surfaces with and without tangents. Catches '
        'normal-map orientation and screen-space-derivative regressions.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/NormalTangentTest/glTF-Binary/NormalTangentTest.glb',
    sizeBytes: 1796996,
  ),
  _StressTest(
    id: 'OrientationTest',
    title: 'Orientation Test',
    description:
        'Axis-labelled cubes for catching coordinate-system and winding-flip '
        'bugs at a glance.',
    url:
        'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/'
        'main/Models/OrientationTest/glTF-Binary/OrientationTest.glb',
    sizeBytes: 38920,
  ),
];

// An image-based-lighting environment selectable from the scene's
// environment menu.
class _Environment {
  const _Environment({required this.id, required this.title, this.url});

  final String id;
  final String title;

  /// Radiance `.hdr` URL, or null for the renderer's built-in procedural
  /// studio environment.
  final String? url;
}

// Khronos sample-environment HDRs, downloaded at runtime. They are Git LFS
// blobs, so they are fetched through media.githubusercontent.com (the
// raw.githubusercontent.com path serves only the LFS pointer).
const _kEnvironmentBaseUrl =
    'https://media.githubusercontent.com/media/KhronosGroup/'
    'glTF-Sample-Environments/main';

const _environments = <_Environment>[
  _Environment(id: 'studio', title: 'Studio (built-in)'),
  _Environment(id: 'axis_test', title: 'Axis Test (solid colors)'),
  _Environment(
    id: 'neutral',
    title: 'Studio Neutral',
    url: '$_kEnvironmentBaseUrl/neutral.hdr',
  ),
  _Environment(
    id: 'footprint_court',
    title: 'Footprint Court',
    url: '$_kEnvironmentBaseUrl/footprint_court.hdr',
  ),
  _Environment(
    id: 'pisa',
    title: 'Pisa',
    url: '$_kEnvironmentBaseUrl/pisa.hdr',
  ),
  _Environment(
    id: 'doge2',
    title: "Doge's Palace",
    url: '$_kEnvironmentBaseUrl/doge2.hdr',
  ),
  _Environment(
    id: 'ennis',
    title: 'Ennis House',
    url: '$_kEnvironmentBaseUrl/ennis.hdr',
  ),
  _Environment(
    id: 'field',
    title: 'Field',
    url: '$_kEnvironmentBaseUrl/field.hdr',
  ),
  _Environment(
    id: 'helipad',
    title: 'Helipad',
    url: '$_kEnvironmentBaseUrl/helipad.hdr',
  ),
  _Environment(
    id: 'papermill',
    title: 'Papermill Ruins',
    url: '$_kEnvironmentBaseUrl/papermill.hdr',
  ),
  _Environment(
    id: 'directional',
    title: 'Directional (test)',
    url: '$_kEnvironmentBaseUrl/directional.hdr',
  ),
  _Environment(
    id: 'chromatic',
    title: 'Chromatic (test)',
    url: '$_kEnvironmentBaseUrl/chromatic.hdr',
  ),
];

// Generates a procedural test environment: a low-resolution equirect
// colored by the dominant world axis of each direction (+X red, -X cyan,
// +Y green, -Y magenta, +Z blue, -Z yellow). Solid colors make the
// environment's orientation unambiguous in reflections and ambient light.
({Float32List pixels, int width, int height}) _buildAxisTestEquirect() {
  const width = 256;
  const height = 128;
  final pixels = Float32List(width * height * 4);
  for (var py = 0; py < height; py++) {
    // Row 0 is the down pole, matching EnvironmentMap.studio's convention.
    final v = (py + 0.5) / height;
    final latitude = (v - 0.5) * pi;
    final cosLat = cos(latitude);
    final dirY = sin(latitude);
    for (var px = 0; px < width; px++) {
      final u = (px + 0.5) / width;
      final longitude = (u - 0.5) * 2.0 * pi;
      final dirX = cosLat * cos(longitude);
      final dirZ = cosLat * sin(longitude);
      double r, g, b;
      if (dirX.abs() >= dirY.abs() && dirX.abs() >= dirZ.abs()) {
        r = dirX >= 0 ? 1.0 : 0.0; // +X red, -X cyan
        g = dirX >= 0 ? 0.0 : 1.0;
        b = dirX >= 0 ? 0.0 : 1.0;
      } else if (dirY.abs() >= dirZ.abs()) {
        r = dirY >= 0 ? 0.0 : 1.0; // +Y green, -Y magenta
        g = dirY >= 0 ? 1.0 : 0.0;
        b = dirY >= 0 ? 0.0 : 1.0;
      } else {
        r = dirZ >= 0 ? 0.0 : 1.0; // +Z blue, -Z yellow
        g = dirZ >= 0 ? 0.0 : 1.0;
        b = dirZ >= 0 ? 1.0 : 0.0;
      }
      final o = (py * width + px) * 4;
      pixels[o] = r;
      pixels[o + 1] = g;
      pixels[o + 2] = b;
      pixels[o + 3] = 1.0;
    }
  }
  return (pixels: pixels, width: width, height: height);
}

class ExampleStressTests extends StatefulWidget {
  const ExampleStressTests({super.key, this.elapsedSeconds = 0});
  final double elapsedSeconds;

  @override
  State<ExampleStressTests> createState() => _ExampleStressTestsState();
}

class _ExampleStressTestsState extends State<ExampleStressTests> {
  _StressTest? _active;

  void _open(_StressTest test) {
    setState(() => _active = test);
  }

  void _back() {
    setState(() => _active = null);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    if (active == null) {
      return _CatalogList(onOpen: _open);
    }
    return _StressScene(
      key: ValueKey(active.id),
      test: active,
      elapsedSeconds: widget.elapsedSeconds,
      onBack: _back,
    );
  }
}

class _CatalogList extends StatelessWidget {
  const _CatalogList({required this.onOpen});
  final ValueChanged<_StressTest> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
      itemCount: _catalog.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final test = _catalog[i];
        return Card(
          child: ListTile(
            title: Text(test.title),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(test.description),
                  const SizedBox(height: 4),
                  Text(
                    _formatBytes(test.sizeBytes),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpen(test),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

class _StressScene extends StatefulWidget {
  const _StressScene({
    super.key,
    required this.test,
    required this.elapsedSeconds,
    required this.onBack,
  });

  final _StressTest test;
  final double elapsedSeconds;
  final VoidCallback onBack;

  @override
  State<_StressScene> createState() => _StressSceneState();
}

class _StressSceneState extends State<_StressScene> {
  final Scene _scene = Scene();
  final FocusNode _focusNode = FocusNode();

  // FPS-style camera state. `_yaw` rotates about world +Y; `_pitch`
  // rotates the look direction up/down. At yaw=0, pitch=0 forward
  // points down -Z.
  vm.Vector3 _camPos = vm.Vector3(0, 2, 5);
  double _yaw = 0;
  double _pitch = 0;
  static const _pitchLimit = 1.5; // ~86 deg

  // Movement speed (units/sec) scaled to the model size so the same
  // controls feel right for a 10-cm bottle and a 100-m architectural
  // scene. Set at load-time from the model's AABB radius.
  double _moveSpeed = 3.0;

  // Currently-held movement keys (read each frame). Mouse delta is
  // applied immediately on drag.
  final Set<LogicalKeyboardKey> _pressed = {};
  double _lastUpdateSeconds = 0;

  // Load state. `null` total means the server didn't send a Content-Length
  // — the screen still shows downloaded bytes so users see motion.
  bool _ready = false;
  int _downloaded = 0;
  int? _total;
  Object? _error;

  // Which importer to exercise. Switchable per test via the toggle; offline
  // is only offered for single-file .glb tests.
  _ImporterMode _importerMode = _ImporterMode.runtime;

  // Image-based-lighting environment. `_activeEnvironment` tracks the menu
  // choice; the renderer's built-in studio environment is the default.
  // Loaded HDR environments are cached so re-selecting one is instant.
  _Environment _activeEnvironment = _environments.first;
  bool _environmentLoading = false;
  final Map<String, EnvironmentMap> _environmentCache = {};

  // Tone-mapping exposure and image-based-lighting intensity, tunable
  // from the lighting panel. Both default to the renderer's neutral 1.0.
  double _exposure = 1.0;
  double _environmentIntensity = 1.0;

  // Environment rotation in degrees about each world axis.
  double _envRotationX = 0.0;
  double _envRotationY = 0.0;
  double _envRotationZ = 0.0;

  @override
  void initState() {
    super.initState();
    // No analytic light: these scenes are lit purely by the image-based
    // environment, so the environment menu is what's being evaluated.
    unawaited(_load());
  }

  // Accumulates downloaded bytes (across every file of a multi-file
  // model) into the progress display.
  void _reportChunk(int bytes) {
    if (!mounted) return;
    setState(() {
      _downloaded += bytes;
      _total = widget.test.sizeBytes;
    });
  }

  Future<void> _load() async {
    try {
      final node = await _importTest(widget.test, _importerMode, _reportChunk);
      node.name = widget.test.id;

      if (_kDebugDumpScene) {
        _debugDumpScene(node);
      }
      if (_kDebugTintMaterials) {
        _debugTintMaterials(node);
      }

      // Frame the camera around the model. combinedLocalBounds returns
      // null when the subtree contains skinned content (bind-pose AABB
      // under-covers once joints animate, so the engine conservatively
      // refuses to commit to a number). When that happens fall back to
      // a translation hull of every node in the subtree — a rough but
      // robust scale estimate that gets Fox/BrainStem/RecursiveSkeletons
      // into frame instead of "model is way bigger than the camera
      // expected" territory.
      vm.Vector3 lookAt = vm.Vector3.zero();
      double radius = 1;
      final bounds = node.combinedLocalBounds ?? _nodeTranslationHull(node);
      if (bounds != null) {
        lookAt = vm.Vector3.copy(bounds.center);
        final extent = bounds.max - bounds.min;
        radius = max(extent.length * 0.5, 0.1);
      }
      // ~2.4× the bounding radius fills a 60-deg FOV without clipping.
      final double distance = max(radius * 2.4, 0.5);
      final double height = lookAt.y + radius * 0.4;
      // Initial camera: on the -Z side looking toward +Z. After the
      // importer's scene-root Z-flip, glTF models face -Z, so this puts
      // the camera in front of the model rather than behind it. Yaw=pi
      // turns the camera around to look back at the model; pitch tilts
      // down so it stays centered.
      _camPos = vm.Vector3(lookAt.x, height, lookAt.z - distance);
      final dir = (lookAt - _camPos)..normalize();
      _yaw = pi;
      _pitch = asin(dir.y).clamp(-_pitchLimit, _pitchLimit);
      _moveSpeed = max(radius * 0.5, 0.5);

      // Kick off the first matching animation if requested.
      final wantedAnim = widget.test.animationName;
      if (wantedAnim != null) {
        final anim = _findAnimation(node, wantedAnim) ?? _firstAnimation(node);
        if (anim != null) {
          node.createAnimationClip(anim)
            ..loop = true
            ..play();
        }
      }

      _scene.add(node);
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  // Switches the importer path and reloads the model. The download is cached,
  // so this just re-imports the same bytes via the chosen path.
  void _setImporterMode(_ImporterMode mode) {
    if (mode == _importerMode) return;
    _scene.removeAll();
    setState(() {
      _importerMode = mode;
      _ready = false;
      _downloaded = 0;
      _error = null;
    });
    unawaited(_load());
  }

  // Switches the scene's image-based-lighting environment. Downloads and
  // decodes the HDR on first use (cached afterward); the built-in studio
  // environment needs no download.
  Future<void> _selectEnvironment(_Environment environment) async {
    if (environment.id == _activeEnvironment.id && !_environmentLoading) {
      return;
    }
    setState(() {
      _activeEnvironment = environment;
      _environmentLoading = true;
    });
    try {
      final map = await _resolveEnvironment(environment);
      if (!mounted) return;
      setState(() {
        _scene.environment = map;
        _environmentLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _environmentLoading = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to load ${environment.title}: $e')),
      );
    }
  }

  // Returns the [EnvironmentMap] for [environment], or null for the
  // renderer's built-in studio default. HDR environments are downloaded,
  // decoded off the UI isolate, prefiltered, and cached; the axis-test
  // environment is generated procedurally.
  Future<EnvironmentMap?> _resolveEnvironment(_Environment environment) async {
    if (environment.id == 'studio') return null; // renderer's built-in

    final cached = _environmentCache[environment.id];
    if (cached != null) return cached;

    final EnvironmentMap map;
    if (environment.id == 'axis_test') {
      final test = _buildAxisTestEquirect();
      map = await EnvironmentMap.fromEquirectHdr(
        linearPixels: test.pixels,
        width: test.width,
        height: test.height,
      );
    } else {
      final bytes = await _fetchResource(environment.url!, onChunk: (_) {});
      final hdr = await compute(loadHdrEnvironment, bytes);
      map = await EnvironmentMap.fromEquirectHdr(
        linearPixels: hdr.pixels,
        width: hdr.width,
        height: hdr.height,
      );
    }
    _environmentCache[environment.id] = map;
    return map;
  }

  // Rebuilds the scene's environment rotation from the three Euler angles.
  void _applyEnvironmentRotation() {
    const degToRad = pi / 180.0;
    _scene.environmentTransform =
        vm.Matrix3.rotationY(_envRotationY * degToRad) *
        vm.Matrix3.rotationX(_envRotationX * degToRad) *
        vm.Matrix3.rotationZ(_envRotationZ * degToRad);
  }

  Animation? _findAnimation(Node root, String name) {
    final hit = root.findAnimationByName(name);
    if (hit != null) return hit;
    for (final child in root.children) {
      final inChild = _findAnimation(child, name);
      if (inChild != null) return inChild;
    }
    return null;
  }

  Animation? _firstAnimation(Node root) {
    final anims = _collectAnimations(root);
    return anims.isEmpty ? null : anims.first;
  }

  List<Animation> _collectAnimations(Node node) {
    final list = <Animation>[];
    list.addAll(node.parsedAnimations);
    for (final child in node.children) {
      list.addAll(_collectAnimations(child));
    }
    return list;
  }

  // One-shot diagnostic dump for stress-test loads: combinedLocalBounds
  // status, animation list, mesh count, and per-mesh material/texture
  // bindings. Helps sanity-check what the runtime importer produced
  // versus what the source glTF claims.
  void _debugDumpScene(Node root) {
    final bounds = root.combinedLocalBounds;
    final hull = _nodeTranslationHull(root);
    final anims = _collectAnimations(root);
    debugPrint(
      '[stress] ${widget.test.id}: '
      'combinedLocalBounds=${bounds == null ? "null" : "${bounds.min} .. ${bounds.max}"}, '
      'translationHull=${hull == null ? "null" : "${hull.min} .. ${hull.max}"}, '
      'animations.length=${anims.length} '
      '${anims.map((a) => "\"${a.name}\"").join(", ")}',
    );
    var meshIdx = 0;
    void visit(Node n) {
      final mesh = n.mesh;
      if (mesh != null) {
        for (final p in mesh.primitives) {
          final m = p.material;
          var summary = m.runtimeType.toString();
          if (m is PhysicallyBasedMaterial) {
            summary +=
                ' base=${m.baseColorFactor.storage.map((v) => v.toStringAsFixed(2)).toList()}'
                ' tex=${m.baseColorTexture == null ? "<missing>" : "<bound>"}'
                ' metRoughTex=${m.metallicRoughnessTexture == null ? "<missing>" : "<bound>"}'
                ' emissive=${m.emissiveFactor.storage.map((v) => v.toStringAsFixed(2)).toList()}';
          }
          debugPrint('[stress]   mesh#${meshIdx++} node="${n.name}": $summary');
        }
      }
      for (final c in n.children) {
        visit(c);
      }
    }

    visit(root);
  }

  // DEBUG: walk the subtree and set every PhysicallyBasedMaterial's
  // baseColorFactor to bright red. Diagnostic only; remove once we
  // know whether color flows.
  void _debugTintMaterials(Node root) {
    void visit(Node n) {
      final mesh = n.mesh;
      if (mesh != null) {
        for (final p in mesh.primitives) {
          final m = p.material;
          if (m is PhysicallyBasedMaterial) {
            m.baseColorFactor = vm.Vector4(1.0, 0.0, 0.0, 1.0);
          }
        }
      }
      for (final c in n.children) {
        visit(c);
      }
    }

    visit(root);
  }

  // Best-effort scale estimator for subtrees with skinned content (where
  // `combinedLocalBounds` bails). Walks every descendant and unions
  // their global translation. Doesn't account for mesh extent at each
  // node, so the radius can under-cover the actual geometry — but
  // padding the framing distance compensates. Returns null only when
  // the subtree is empty.
  vm.Aabb3? _nodeTranslationHull(Node root) {
    vm.Aabb3? hull;
    void visit(Node n) {
      final pos = n.globalTransform.getTranslation();
      if (hull == null) {
        hull = vm.Aabb3.minMax(vm.Vector3.copy(pos), vm.Vector3.copy(pos));
      } else {
        hull!.hullPoint(pos);
      }
      for (final c in n.children) {
        visit(c);
      }
    }

    visit(root);
    return hull;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scene.removeAll();
    super.dispose();
  }

  // Forward unit vector from yaw/pitch. Yaw=0/pitch=0 → (0, 0, -1).
  vm.Vector3 _forward() {
    final cp = cos(_pitch);
    return vm.Vector3(-sin(_yaw) * cp, sin(_pitch), -cos(_yaw) * cp);
  }

  // Strafe-right unit vector (yaw only — strafing ignores pitch so we
  // don't drift into/out of the floor when looking down).
  vm.Vector3 _right() => vm.Vector3(cos(_yaw), 0, -sin(_yaw));

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    final tracked = _isMovementKey(key);
    if (!tracked) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _pressed.add(key);
    } else if (event is KeyUpEvent) {
      _pressed.remove(key);
    }
    return KeyEventResult.handled;
  }

  bool _isMovementKey(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.keyW ||
      k == LogicalKeyboardKey.keyA ||
      k == LogicalKeyboardKey.keyS ||
      k == LogicalKeyboardKey.keyD ||
      k == LogicalKeyboardKey.keyQ ||
      k == LogicalKeyboardKey.keyE ||
      k == LogicalKeyboardKey.shiftLeft ||
      k == LogicalKeyboardKey.shiftRight;

  void _onPanUpdate(DragUpdateDetails d) {
    const sensitivity = 0.005;
    setState(() {
      // Horizontal: drag-the-world (drag right turns camera left).
      // Vertical: FPS convention (drag down looks down).
      _yaw += d.delta.dx * sensitivity;
      _pitch -= d.delta.dy * sensitivity;
      _pitch = _pitch.clamp(-_pitchLimit, _pitchLimit);
    });
  }

  // Integrates camera position from currently-held keys. Called from
  // build() so the parent ticker drives it; dt is clamped to keep a
  // dropped frame or focus pause from teleporting the camera.
  void _updateCamera() {
    final dt = (widget.elapsedSeconds - _lastUpdateSeconds).clamp(0.0, 0.1);
    _lastUpdateSeconds = widget.elapsedSeconds;
    if (_pressed.isEmpty) return;
    var velocity = vm.Vector3.zero();
    if (_pressed.contains(LogicalKeyboardKey.keyW)) velocity += _forward();
    if (_pressed.contains(LogicalKeyboardKey.keyS)) velocity -= _forward();
    // D moves the camera to its own right (toward what's on the right
    // side of the screen). A moves left.
    if (_pressed.contains(LogicalKeyboardKey.keyD)) velocity -= _right();
    if (_pressed.contains(LogicalKeyboardKey.keyA)) velocity += _right();
    if (_pressed.contains(LogicalKeyboardKey.keyE)) {
      velocity += vm.Vector3(0, 1, 0);
    }
    if (_pressed.contains(LogicalKeyboardKey.keyQ)) {
      velocity -= vm.Vector3(0, 1, 0);
    }
    if (velocity.length2 == 0) return;
    velocity.normalize();
    final boosted =
        _pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        _pressed.contains(LogicalKeyboardKey.shiftRight);
    final speed = _moveSpeed * (boosted ? 4.0 : 1.0);
    _camPos += velocity * (speed * dt);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) _updateCamera();
    return Stack(
      children: [
        if (_ready)
          Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (_) => _focusNode.requestFocus(),
                onPanUpdate: _onPanUpdate,
                child: SizedBox.expand(
                  child: CustomPaint(
                    painter: _ScenePainter(
                      _scene,
                      position: _camPos,
                      target: _camPos + _forward(),
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Failed to load ${widget.test.title}:\n$_error',
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          _LoadingOverlay(
            title: widget.test.title,
            downloaded: _downloaded,
            total: _total,
          ),
        // Below the example picker: the settings sidebar owns the
        // top-right corner, and the app dropdown owns the top-left.
        Positioned(
          left: 8,
          top: 56,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            shape: const CircleBorder(),
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.onBack,
              tooltip: 'Back to stress tests',
            ),
          ),
        ),
        // Importer toggle (single-file .glb only; offline has no multi-file
        // path). Lets the offline ahead-of-time importer be compared against
        // the runtime importer on the same model.
        if (_ready && !widget.test.isMultiFile)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text('Importer'),
                      ),
                      SegmentedButton<_ImporterMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _ImporterMode.runtime,
                            label: Text('Runtime'),
                          ),
                          ButtonSegment(
                            value: _ImporterMode.offline,
                            label: Text('Offline'),
                          ),
                        ],
                        selected: {_importerMode},
                        onSelectionChanged: (selection) =>
                            _setImporterMode(selection.first),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_ready)
          Positioned(
            left: 8,
            bottom: 8,
            child: _LightingPanel(
              activeEnvironment: _activeEnvironment,
              environmentLoading: _environmentLoading,
              onEnvironmentSelected: _selectEnvironment,
              exposure: _exposure,
              environmentIntensity: _environmentIntensity,
              envRotationX: _envRotationX,
              envRotationY: _envRotationY,
              envRotationZ: _envRotationZ,
              onExposureChanged: (value) {
                setState(() {
                  _exposure = value;
                  _scene.exposure = value;
                });
              },
              onEnvironmentIntensityChanged: (value) {
                setState(() {
                  _environmentIntensity = value;
                  _scene.environmentIntensity = value;
                });
              },
              onEnvRotationXChanged: (value) {
                setState(() {
                  _envRotationX = value;
                  _applyEnvironmentRotation();
                });
              },
              onEnvRotationYChanged: (value) {
                setState(() {
                  _envRotationY = value;
                  _applyEnvironmentRotation();
                });
              },
              onEnvRotationZChanged: (value) {
                setState(() {
                  _envRotationZ = value;
                  _applyEnvironmentRotation();
                });
              },
            ),
          ),
        if (_ready)
          Positioned(
            right: 8,
            bottom: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'WASD move · QE up/down · drag to look · shift to boost',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({
    required this.title,
    required this.downloaded,
    required this.total,
  });

  final String title;
  final int downloaded;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    final progress = (total != null && total > 0) ? downloaded / total : null;
    return Center(
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Downloading $title',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              total == null
                  ? _formatBytes(downloaded)
                  : '${_formatBytes(downloaded)} / ${_formatBytes(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// The "Active Environment" menu: a compact dark pill that opens the list
// of selectable image-based-lighting environments. Shows a spinner while
// the chosen environment downloads and prefilters.
class _EnvironmentMenu extends StatelessWidget {
  const _EnvironmentMenu({
    required this.active,
    required this.loading,
    required this.onSelected,
  });

  final _Environment active;
  final bool loading;
  final ValueChanged<_Environment> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(4),
      child: PopupMenuButton<_Environment>(
        tooltip: 'Select environment',
        position: PopupMenuPosition.over,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final environment in _environments)
            PopupMenuItem<_Environment>(
              value: environment,
              child: Text(environment.title),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.light_mode, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                active.title,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 6),
              loading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white,
                      size: 18,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bottom-left lighting panel: the environment menu plus exposure and
// image-based-lighting intensity sliders.
class _LightingPanel extends StatelessWidget {
  const _LightingPanel({
    required this.activeEnvironment,
    required this.environmentLoading,
    required this.onEnvironmentSelected,
    required this.exposure,
    required this.environmentIntensity,
    required this.envRotationX,
    required this.envRotationY,
    required this.envRotationZ,
    required this.onExposureChanged,
    required this.onEnvironmentIntensityChanged,
    required this.onEnvRotationXChanged,
    required this.onEnvRotationYChanged,
    required this.onEnvRotationZChanged,
  });

  final _Environment activeEnvironment;
  final bool environmentLoading;
  final ValueChanged<_Environment> onEnvironmentSelected;
  final double exposure;
  final double environmentIntensity;
  final double envRotationX;
  final double envRotationY;
  final double envRotationZ;
  final ValueChanged<double> onExposureChanged;
  final ValueChanged<double> onEnvironmentIntensityChanged;
  final ValueChanged<double> onEnvRotationXChanged;
  final ValueChanged<double> onEnvRotationYChanged;
  final ValueChanged<double> onEnvRotationZChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      constraints: const BoxConstraints(maxHeight: 440),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EnvironmentMenu(
              active: activeEnvironment,
              loading: environmentLoading,
              onSelected: onEnvironmentSelected,
            ),
            const SizedBox(height: 4),
            _LabeledSlider(
              label: 'Exposure',
              value: exposure,
              min: 0.1,
              max: 8.0,
              onChanged: onExposureChanged,
            ),
            _LabeledSlider(
              label: 'IBL intensity',
              value: environmentIntensity,
              min: 0.0,
              max: 4.0,
              onChanged: onEnvironmentIntensityChanged,
            ),
            _LabeledSlider(
              label: 'Env rotation X',
              value: envRotationX,
              min: -180.0,
              max: 180.0,
              onChanged: onEnvRotationXChanged,
            ),
            _LabeledSlider(
              label: 'Env rotation Y',
              value: envRotationY,
              min: -180.0,
              max: 180.0,
              onChanged: onEnvRotationYChanged,
            ),
            _LabeledSlider(
              label: 'Env rotation Z',
              value: envRotationZ,
              min: -180.0,
              max: 180.0,
              onChanged: onEnvRotationZChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// A compact labeled slider for the lighting panel: label and current
// value on one row, the slider below.
class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, {required this.position, required this.target});

  final Scene scene;
  final vm.Vector3 position;
  final vm.Vector3 target;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = PerspectiveCamera(position: position, target: target);
    exampleSettings.applyTo(scene);
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Downloads (and caches) the model for `test` and imports it.
//
// Single-file `.glb` models go through Node.fromGlbBytes. Multi-file
// `.gltf` models download the `.gltf` and resolve its `.bin` / image
// siblings on demand through Node.fromGltfBytes; every sibling is
// fetched relative to the `.gltf`'s own URL and cached beside it.
Future<Node> _importTest(
  _StressTest test,
  _ImporterMode mode,
  void Function(int) onChunk,
) async {
  if (!test.isMultiFile) {
    final bytes = await _fetchResource(
      test.url,
      onChunk: onChunk,
      expectedSize: test.sizeBytes,
    );
    if (mode == _ImporterMode.offline) {
      // Exercise the offline (ahead-of-time) importer: run the same
      // glTF -> .model conversion the build hook performs, in memory, then
      // load the result. This is the path issue #134 lives in.
      final modelBytes = importGlbToModelBytes(bytes);
      return Node.fromFlatbuffer(ByteData.sublistView(modelBytes));
    }
    return Node.fromGlbBytes(bytes);
  }

  // Multi-file glTF: the offline importer is .glb-only, so this is always the
  // runtime path. The `.gltf` and its `.bin` / image siblings are each fetched
  // (and cached) by their own absolute URL, resolved relative to the `.gltf`'s
  // URL.
  final baseUri = Uri.parse(test.url);
  final gltfBytes = await _fetchResource(test.url, onChunk: onChunk);
  return Node.fromGltfBytes(
    gltfBytes,
    resolveUri: (uri) =>
        _fetchResource(baseUri.resolve(uri).toString(), onChunk: onChunk),
  );
}

// Fetches `url` and returns its bytes. Serves from the platform cache
// (on-disk on native, in-memory on web) when a usable copy is present;
// otherwise streams the download via http, caches it, and returns it.
// `onChunk` is fed each streamed chunk's length -- and the whole length on a
// cache hit -- so callers can show cumulative progress.
Future<Uint8List> _fetchResource(
  String url, {
  required void Function(int bytes) onChunk,
  int? expectedSize,
}) async {
  final cached = await loadCachedResource(url);
  if (cached != null) {
    // With a known size, reject a suspiciously short (interrupted) cache
    // entry; otherwise just require it to be non-empty.
    final usable = expectedSize == null
        ? cached.isNotEmpty
        : cached.lengthInBytes >= expectedSize * 0.95;
    if (usable) {
      onChunk(cached.lengthInBytes);
      return cached;
    }
  }

  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) {
      throw Exception('GET $url returned ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      onChunk(chunk.length);
    }
    final bytes = builder.takeBytes();
    await storeCachedResource(url, bytes);
    return bytes;
  } finally {
    client.close();
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
