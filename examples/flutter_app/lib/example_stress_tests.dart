// Stress-test catalog: downloads Khronos glTF Sample Assets at runtime
// and renders them via the runtime GLB importer. Lets the renderer be
// exercised against PBR fidelity, animation/skinning, and correctness
// scenes without committing big binary blobs to the repo.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Animation;
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

import 'environment_menu.dart';
import 'example_action_hint.dart';
import 'example_overlay.dart';
import 'lighting_panel.dart';
import 'example_settings.dart';
import 'quake_camera.dart';

// The in-memory offline (ahead-of-time) glTF -> .fsceneb conversion, used by
// the per-test importer toggle below. Reaching into flutter_scene's internals
// is intentional here: this is a renderer stress test, not a typical consumer.
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/in_memory_import.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/realize/loader.dart';

// Toggle these on to inspect scenes as they load. Both are off by
// default; flip them locally when debugging a renderer regression in
// a specific stress test.
const bool _kDebugDumpScene = false;
const bool _kDebugTintMaterials = false;

/// Which importer path a stress test exercises. [runtime] uses the direct GLB
/// importer (`Node.fromGlbBytes` / `Node.fromGltfBytes`). [offline] runs the
/// ahead-of-time glTF -> .fsceneb conversion in memory and realizes the
/// result, the same conversion the `buildScenes` build hook performs. Offline
/// is `.glb` only (the offline importer has no multi-file `.gltf` path).
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

// Generates a procedural test environment: a low-resolution equirect
// colored by the dominant world axis of each direction (+X red, -X cyan,
// +Y green, -Y magenta, +Z blue, -Z yellow). Solid colors make the
// environment's orientation unambiguous in reflections and ambient light.
class ExampleStressTests extends StatefulWidget {
  const ExampleStressTests({super.key});

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
    return _StressScene(key: ValueKey(active.id), test: active, onBack: _back);
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
  const _StressScene({super.key, required this.test, required this.onBack});

  final _StressTest test;
  final VoidCallback onBack;

  @override
  State<_StressScene> createState() => _StressSceneState();
}

class _StressSceneState extends State<_StressScene> {
  final Scene _scene = Scene();
  final FocusNode _focusNode = FocusNode();

  // FPS-style free-look camera. Speed is scaled to the model size at load
  // time so the same controls feel right for a 10-cm bottle and a 100-m
  // architectural scene.
  final QuakeCamera _quake = QuakeCamera()..speed = 3.0;

  // Load state. `null` total means the server didn't send a Content-Length
  // — the screen still shows downloaded bytes so users see motion.
  bool _ready = false;
  int _downloaded = 0;
  int? _total;
  Object? _error;

  // Which importer to exercise. Switchable per test via the toggle; offline
  // is only offered for single-file .glb tests.
  _ImporterMode _importerMode = _ImporterMode.runtime;

  // Image-based-lighting environment (the shared selector caches loaded
  // HDRs; the renderer's built-in studio environment is the default).
  final EnvironmentSelector _environmentSelector = EnvironmentSelector();

  @override
  void initState() {
    super.initState();
    // Keep an actual scene visible while a remote stress asset is downloading.
    _scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.06, 0.08, 0.12),
        horizonColor: vm.Vector3(0.18, 0.22, 0.29),
        groundColor: vm.Vector3(0.035, 0.045, 0.065),
      ),
    );
    // Lighting (the directional key light and shadows) is driven by the
    // shared settings panel via ExampleSettings.applyTo.
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
      _quake.position = vm.Vector3(lookAt.x, height, lookAt.z - distance);
      final dir = (lookAt - _quake.position)..normalize();
      _quake.yaw = pi;
      _quake.pitch = asin(
        dir.y,
      ).clamp(-QuakeCamera.pitchLimit, QuakeCamera.pitchLimit);
      _quake.speed = max(radius * 0.5, 0.5);

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
    _environmentSelector.dispose();
    _scene.removeAll();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _quake.look(d.delta));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Focus(
          focusNode: _focusNode,
          autofocus: _ready,
          onKeyEvent: _quake.onKeyEvent,
          child: IgnorePointer(
            ignoring: !_ready,
            child: MouseRegion(
              cursor: _ready
                  ? SystemMouseCursors.move
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (_) => _focusNode.requestFocus(),
                onPanUpdate: _onPanUpdate,
                child: SceneView(
                  _scene,
                  cameraBuilder: (elapsed) {
                    _quake.move(elapsed.inMicroseconds / 1e6);
                    return _quake.camera;
                  },
                  onTick: (elapsed, deltaSeconds) {
                    exampleSettings.applyTo(_scene);
                  },
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          _LoadFailure(title: widget.test.title, detail: '$_error')
        else if (!_ready)
          _LoadingOverlay(
            title: widget.test.title,
            downloaded: _downloaded,
            total: _total,
          ),
        if (_ready && !widget.test.isMultiFile)
          ExampleOverlay.topCenterAction(
            maxWidth: 400,
            leadingReservation: 160,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExampleActionButton(
                      tooltip: 'Back to stress tests',
                      icon: Icons.arrow_back,
                      onPressed: widget.onBack,
                    ),
                    const SizedBox(width: 12),
                    _ImporterModeControl(
                      selected: _importerMode,
                      onChanged: _setImporterMode,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const ExampleActionHint(
                  message:
                      'WASD move  ·  QE up/down  ·  Drag: look  ·  Shift: boost',
                ),
              ],
            ),
          ),
        if (!_ready || widget.test.isMultiFile)
          ExampleOverlay.topLeadingAction(
            child: ExampleActionButton(
              tooltip: 'Back to stress tests',
              icon: Icons.arrow_back,
              onPressed: widget.onBack,
            ),
          ),
        if (_ready)
          ExampleOverlay.bottomLeftPanel(
            child: LightingPanel(scene: _scene, selector: _environmentSelector),
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
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: SizedBox(
          width: 280,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Downloading $title',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  color: Colors.deepPurpleAccent,
                  backgroundColor: Colors.white24,
                ),
                const SizedBox(height: 8),
                Text(
                  total == null
                      ? _formatBytes(downloaded)
                      : '${_formatBytes(downloaded)} / ${_formatBytes(total)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Failed to load $title:\n$detail',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

class _ImporterModeControl extends StatelessWidget {
  const _ImporterModeControl({required this.selected, required this.onChanged});

  final _ImporterMode selected;
  final ValueChanged<_ImporterMode> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black54,
    borderRadius: BorderRadius.circular(8),
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, right: 8),
            child: Text('Importer', style: TextStyle(color: Colors.white)),
          ),
          SegmentedButton<_ImporterMode>(
            showSelectedIcon: false,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white24
                    : Colors.transparent,
              ),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              side: const WidgetStatePropertyAll(
                BorderSide(color: Colors.white38),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              visualDensity: VisualDensity.compact,
            ),
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
            selected: {selected},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    ),
  );
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
    final bytes = await fetchResource(
      test.url,
      onChunk: onChunk,
      expectedSize: test.sizeBytes,
    );
    if (mode == _ImporterMode.offline) {
      // Exercise the offline (ahead-of-time) importer: run the same
      // glTF -> .fsceneb conversion the build hook performs, in memory, then
      // realize the result. This is the path issue #134 lives in.
      final scenebBytes = importGlbToFscenebBytes(bytes);
      return loadFscenebBytesAsync(scenebBytes);
    }
    return Node.fromGlbBytes(bytes);
  }

  // Multi-file glTF: the offline importer is .glb-only, so this is always the
  // runtime path. The `.gltf` and its `.bin` / image siblings are each fetched
  // (and cached) by their own absolute URL, resolved relative to the `.gltf`'s
  // URL.
  final baseUri = Uri.parse(test.url);
  final gltfBytes = await fetchResource(test.url, onChunk: onChunk);
  return Node.fromGltfBytes(
    gltfBytes,
    resolveUri: (uri) =>
        fetchResource(baseUri.resolve(uri).toString(), onChunk: onChunk),
  );
}

// Fetches `url` and returns its bytes. Serves from the platform cache
// (on-disk on native, in-memory on web) when a usable copy is present;
// otherwise streams the download via http, caches it, and returns it.
// `onChunk` is fed each streamed chunk's length -- and the whole length on a
// cache hit -- so callers can show cumulative progress.

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
