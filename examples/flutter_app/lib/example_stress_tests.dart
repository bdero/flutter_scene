// Stress-test catalog: downloads Khronos glTF Sample Assets at runtime
// and renders them via the runtime GLB importer. Lets the renderer be
// exercised against PBR fidelity, animation/skinning, and correctness
// scenes without committing big binary blobs to the repo.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' hide Animation;
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math.dart' as vm;

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

  @override
  void initState() {
    super.initState();
    _scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(0.4, -1.0, 0.3),
      color: vm.Vector3(1.0, 0.97, 0.9),
      intensity: 2.5,
      castsShadow: true,
      shadowFrustumSize: 8.0,
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final bytes = await _fetchCachedGlb(
        widget.test,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloaded = received;
            _total = total ?? widget.test.sizeBytes;
          });
        },
      );

      final node = await Node.fromGlbBytes(bytes);
      node.name = widget.test.id;

      // Frame the camera around the model's AABB. Skinned scenes may
      // return null bounds (combinedLocalBounds bails on skinning); fall
      // back to a sensible default in that case.
      vm.Vector3 lookAt = vm.Vector3.zero();
      double distance = 5;
      double height = 2;
      double radius = 1;
      final bounds = node.combinedLocalBounds;
      if (bounds != null) {
        final center = bounds.center;
        final extent = bounds.max - bounds.min;
        radius = max(extent.length * 0.5, 0.1);
        lookAt = vm.Vector3.copy(center);
        // ~2.4× the bounding radius fills a 60-deg FOV without clipping.
        distance = max(radius * 2.4, 0.5);
        height = center.y + radius * 0.4;
      }
      // Initial camera: behind the +Z side of the model, looking back at
      // it. Yaw=0 / pitch tilted down so the model is centered.
      _camPos = vm.Vector3(lookAt.x, height, lookAt.z + distance);
      final dir = (lookAt - _camPos)..normalize();
      _yaw = 0;
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
        // Top-right: the main app's dropdown owns the top-left corner.
        Positioned(
          right: 8,
          top: 8,
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

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, {required this.position, required this.target});

  final Scene scene;
  final vm.Vector3 position;
  final vm.Vector3 target;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = PerspectiveCamera(position: position, target: target);
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Fetches `test.url`, streaming through to a cache file in the app's
// support directory so the second open is instant. Re-downloads on
// short reads in case a previous run was interrupted.
Future<Uint8List> _fetchCachedGlb(
  _StressTest test, {
  required void Function(int received, int? total) onProgress,
}) async {
  final dir = await getApplicationSupportDirectory();
  final cacheDir = Directory('${dir.path}/stress_tests');
  if (!await cacheDir.exists()) {
    await cacheDir.create(recursive: true);
  }
  final cached = File('${cacheDir.path}/${test.id}.glb');
  if (await cached.exists()) {
    final bytes = await cached.readAsBytes();
    if (bytes.lengthInBytes >= test.sizeBytes * 0.95) {
      onProgress(bytes.lengthInBytes, bytes.lengthInBytes);
      return bytes;
    }
    // Suspiciously short → re-download.
    await cached.delete();
  }

  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(test.url));
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('GET ${test.url} returned ${response.statusCode}');
    }
    final total = response.contentLength;
    final sink = cached.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
    } finally {
      await sink.close();
    }
    return cached.readAsBytes();
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
