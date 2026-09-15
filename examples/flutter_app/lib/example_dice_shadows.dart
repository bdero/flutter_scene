import 'dart:math' as math;

// flutter_scene's physics BoxShape and Material clash with Flutter's, so each
// conflicting name is hidden from the import that does not need it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter/services.dart';
import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';

/// Dice thrown over an ordinary Flutter screen. The scene clears to
/// transparent and an invisible [ShadowCatcherMaterial] plane stands in for
/// the screen surface, so the dice cast shadows onto the widgets underneath.
/// Drag anywhere to move the light, and switch between a directional, point,
/// and spot light in the panel.
class ExampleDiceShadows extends StatefulWidget {
  const ExampleDiceShadows({super.key});

  @override
  ExampleDiceShadowsState createState() => ExampleDiceShadowsState();
}

enum _LightKind { directional, point, spot }

enum _Surface { off, wood, glass }

class _Die {
  _Die(this.node, this.body);

  final Node node;
  final RigidBody body;
  vm.Vector3? lastVelocity;
  vm.Vector3? lastSpin;
  double lastHitTime = -1.0;
  double lastHitStrength = 0.0;
}

/// Runs [onUpdate] in the scene's component pass, right after the physics
/// step, so impacts are heard the frame they happen.
class _AfterPhysics extends Component {
  _AfterPhysics(this.onUpdate);

  final void Function(double deltaSeconds) onUpdate;

  @override
  void update(double deltaSeconds) => onUpdate(deltaSeconds);
}

class ExampleDiceShadowsState extends State<ExampleDiceShadows> {
  final Scene scene = Scene();
  late final PhysicsWorld world;

  // Logical pixels per world unit, so dice keep a steady on-screen size.
  static const double _pixelsPerUnit = 100.0;
  static const double _fovY = 35.0 * vm.degrees2Radians;
  static const double _dieHalf = 0.35;

  static const _faceValues = <int>[2, 5, 1, 6, 3, 4]; // +X -X +Y -Y +Z -Z

  final math.Random _random = math.Random();
  final GlobalKey _viewKey = GlobalKey();
  final GlobalKey _rollKey = GlobalKey();

  Size _viewSize = Size.zero;
  PerspectiveCamera _camera = PerspectiveCamera();
  double _ceilingY = 6.0;
  final List<Node> _bounds = [];

  late final MeshGeometry _dieGeometry;
  late final List<PhysicallyBasedMaterial> _dieMaterials;
  late final ShadowCatcherMaterial _catcher;
  final List<_Die> _dice = [];
  int _diceCount = 3;

  SoloudAudioEngine? _audio;
  AudioBus? _sfxBus;
  double _volume = 1.0;
  double _audioClock = 0.0;
  // When and how hard each sound set last played, to merge dice landing in
  // the same physics step.
  final Map<String, ({double time, double strength, AudioVoice voice})>
  _lastSetHit = {};
  // Impact one-shots by set (table, glass, wall, clack), found by their
  // `assets/sounds/dice_<set>_*.wav` names.
  final Map<String, List<AudioClip>> _impactClips = {};
  _Surface _surface = _Surface.wood;
  // Dice sit at about the same distance from the camera, so skip distance
  // falloff and keep only the left/right pan.
  static final AudioAttenuation _flat = AudioAttenuation(
    minDistance: 100,
    dopplerFactor: 0,
  );

  bool _rolling = false;
  double _rollTime = 0.0;
  double _stillTime = 0.0;
  final ValueNotifier<List<int>?> _lastRoll = ValueNotifier(null);
  final ValueNotifier<List<String>> _history = ValueNotifier([
    'Theo rolled 11',
    'Ava rolled 7',
    'Theo rolled 15',
  ]);

  _LightKind _kind = _LightKind.directional;
  // 0..1, mapped per light type (directional softness is an angle, punctual
  // softness a filter radius).
  double _softness = 0.35;

  late final DirectionalLight _sun;
  double _sunAzimuth = 2.4; // Radians in the world XZ plane.
  double _sunElevation = 55.0 * vm.degrees2Radians;

  late final PointLight _point;
  late final SpotLight _spot;
  late final Node _pointNode;
  late final Node _spotNode;
  vm.Vector3 _lampPosition = vm.Vector3(-1.0, 5.0, -2.0);

  @override
  void initState() {
    super.initState();
    scene.environmentIntensity = 0.7;

    world = PhysicsWorld(RapierWorld(gravity: vm.Vector3(0, -30.0, 0)));
    scene.root.addComponent(world);

    _catcher = ShadowCatcherMaterial(shadowIntensity: 0.55, aoStrength: 0.0);
    scene.add(Node(mesh: Mesh(PlaneGeometry(width: 80, depth: 80), _catcher)));

    _dieGeometry = _buildDieGeometry(half: _dieHalf, radius: 0.08);
    final pips = _buildPipAtlas();
    _dieMaterials = [
      for (final color in [
        vm.Vector4(0.95, 0.93, 0.88, 1),
        vm.Vector4(0.86, 0.22, 0.20, 1),
        vm.Vector4(0.20, 0.42, 0.86, 1),
        vm.Vector4(0.22, 0.66, 0.42, 1),
        vm.Vector4(0.95, 0.70, 0.20, 1),
        vm.Vector4(0.55, 0.32, 0.80, 1),
      ])
        PhysicallyBasedMaterial()
          ..baseColorTexture = pips
          ..baseColorFactor = color
          ..roughnessFactor = 0.32
          ..metallicFactor = 0.0,
    ];

    _sun = DirectionalLight(
      color: vm.Vector3(1.0, 0.97, 0.92),
      intensity: 3.0,
      castsShadow: true,
      cacheStaticShadows: false,
      shadowCascadeCount: 2,
    );
    _point = PointLight(
      color: vm.Vector3(1.0, 0.9, 0.75),
      castsShadow: true,
      shadowMapResolution: 1024,
    );
    _spot = SpotLight(
      color: vm.Vector3(1.0, 0.9, 0.75),
      innerConeAngle: 0.55,
      outerConeAngle: 0.95,
      castsShadow: true,
    );
    _pointNode = Node()
      ..addComponent(PointLightComponent(_point))
      ..add(_bulb());
    _spotNode = Node()
      ..addComponent(SpotLightComponent(_spot))
      ..add(_bulb());
    _applyLights();

    scene.root.addComponent(_AfterPhysics(_listenForImpacts));
    _startAudio();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _roll();
      });
    });
  }

  @override
  void dispose() {
    for (final clips in _impactClips.values) {
      for (final clip in clips) {
        clip.dispose();
      }
    }
    _lastRoll.dispose();
    _history.dispose();
    super.dispose();
  }

  Future<void> _startAudio() async {
    // A 512 frame buffer keeps each click within about 12 ms of its impact
    // (the default 2048 is about 46 ms).
    final audio = SoloudAudioEngine(bufferSize: 512);
    scene.root.addComponent(audio);
    _sfxBus = audio.createBus('sfx')..volume = _volume;
    _audio = audio;

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final path in manifest.listAssets()) {
      final match = RegExp(r'assets/sounds/dice_(\w+?)_').firstMatch(path);
      if (match == null) continue;
      final clip = await audio.loadClip(path);
      if (!mounted) {
        clip.dispose();
        return;
      }
      _impactClips.putIfAbsent(match.group(1)!, () => []).add(clip);
    }
  }

  // --- Scene setup ----------------------------------------------------------

  Node _bulb() {
    final material = UnlitMaterial()
      ..baseColorFactor = vm.Vector4(1.0, 0.92, 0.7, 1);
    return Node(mesh: Mesh(SphereGeometry(radius: 0.12), material))
      ..shadowCastingMode = ShadowCastingMode.off;
  }

  /// Fits the camera to [size] and rebuilds the walls along the frustum, so
  /// dice bounce off the visible screen edges at every height.
  void _configureView(Size size) {
    if (size == _viewSize || size.isEmpty) return;
    _viewSize = size;

    final halfHeight = size.height / _pixelsPerUnit / 2;
    final distance = halfHeight / math.tan(_fovY / 2);
    _camera = PerspectiveCamera(
      position: vm.Vector3(0, distance, 0),
      target: vm.Vector3.zero(),
      up: vm.Vector3(0, 0, -1),
      fovRadiansY: _fovY,
      fovNear: 0.5,
      fovFar: distance * 2,
    );
    _ceilingY = math.min(distance * 0.55, 7.0);
    _sun.shadowMaxDistance = distance + 8.0;

    for (final node in _bounds) {
      scene.remove(node);
    }
    _bounds.clear();

    final reach = math.max(size.width, size.height) / _pixelsPerUnit + 20;
    _addBound(vm.Vector3(0, -0.5, 0), vm.Vector3(reach, 0.5, reach));
    _addBound(vm.Vector3(0, _ceilingY + 0.5, 0), vm.Vector3(reach, 0.5, reach));

    final eye = _camera.position;
    final center = _floorHit(size.center(Offset.zero));
    final up = vm.Vector3(0, 1, 0);
    for (final edge in [
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
    ]) {
      // The wall's inner face lies in the frustum side plane through the eye
      // and this screen edge's floor line.
      final e = _floorHit(edge);
      final along = up.cross(e - center)..normalize();
      final inward = along.cross(eye - e)..normalize();
      if (inward.dot(center + up - e) < 0) inward.negate();
      final slant = (eye - e)..normalize();
      final wallLength = _ceilingY / slant.y;
      final basis = vm.Matrix3.columns(inward, along.cross(inward), along);
      _addBound(
        e + slant * (wallLength / 2) - inward * 0.5,
        vm.Vector3(0.5, wallLength / 2 + 0.5, reach),
        rotation: vm.Quaternion.fromRotation(basis),
      );
    }
  }

  void _addBound(
    vm.Vector3 position,
    vm.Vector3 halfExtents, {
    vm.Quaternion? rotation,
  }) {
    final node = Node(
      localTransform: vm.Matrix4.compose(
        position,
        rotation ?? vm.Quaternion.identity(),
        vm.Vector3.all(1.0),
      ),
    );
    node.addComponent(RigidBody(type: BodyType.fixed));
    node.addComponent(
      Collider(
        shape: BoxShape(halfExtents: halfExtents),
        material: const PhysicsMaterial(friction: 0.4, restitution: 0.45),
      ),
    );
    scene.add(node);
    _bounds.add(node);
  }

  vm.Vector3 _planeHit(Offset screen, double height) {
    final ray = _camera.screenPointToRay(screen, _viewSize);
    final t = (height - ray.origin.y) / ray.direction.y;
    return ray.origin + ray.direction * t;
  }

  vm.Vector3 _floorHit(Offset screen) => _planeHit(screen, 0.0);

  // --- Lights ---------------------------------------------------------------

  void _applyLights() {
    scene.directionalLight = _kind == _LightKind.directional ? _sun : null;
    _setAttached(_pointNode, _kind == _LightKind.point);
    _setAttached(_spotNode, _kind == _LightKind.spot);

    final toLight = vm.Vector3(
      math.cos(_sunAzimuth) * math.cos(_sunElevation),
      math.sin(_sunElevation),
      math.sin(_sunAzimuth) * math.cos(_sunElevation),
    );
    _sun.direction = -toLight;
    _sun.shadowSoftness = _softness * 0.3;

    // Scale intensity with height squared so the dice stay evenly exposed as
    // the lamp rises and falls.
    final height = _lampPosition.y;
    final lampIntensity = 3.5 * height * height;
    final transform = vm.Matrix4.translation(_lampPosition);
    _point
      ..intensity = lampIntensity
      ..shadowSoftness = _softness * 4.0;
    _pointNode.localTransform = transform;
    // The spot leans toward the middle of the screen.
    final aim = vm.Vector3(_lampPosition.x * 0.4, 0, _lampPosition.z * 0.4);
    _spot
      ..intensity = lampIntensity
      ..shadowSoftness = _softness * 4.0
      ..direction = (aim - _lampPosition).normalized();
    _spotNode.localTransform = transform;
  }

  void _setAttached(Node node, bool attached) {
    if (attached && node.parent == null) scene.add(node);
    if (!attached && node.parent != null) scene.remove(node);
  }

  /// Puts the light where the finger is. The lamps sit under the finger at
  /// their height; the sun comes from the finger's direction off the screen
  /// center, lower toward the edges.
  void _dragLight(Offset position) {
    if (_viewSize.isEmpty) return;
    if (_kind == _LightKind.directional) {
      final offset =
          _floorHit(position) - _floorHit(_viewSize.center(Offset.zero));
      final halfExtent =
          math.min(_viewSize.width, _viewSize.height) / _pixelsPerUnit / 2;
      final reach = (offset.length / halfExtent).clamp(0.0, 1.0);
      if (offset.length > 1e-3) _sunAzimuth = math.atan2(offset.z, offset.x);
      _sunElevation = (90.0 - reach * 70.0) * vm.degrees2Radians;
    } else {
      final height = _lampPosition.y;
      _lampPosition = _planeHit(position, height)..y = height;
    }
    setState(_applyLights);
  }

  /// Where the sun marker sits on screen, the inverse of [_dragLight].
  Offset? _sunMarkerPosition() {
    if (_viewSize.isEmpty) return null;
    final halfExtent =
        math.min(_viewSize.width, _viewSize.height) / _pixelsPerUnit / 2;
    final reach = (90.0 - _sunElevation * vm.radians2Degrees) / 70.0;
    final center = _floorHit(_viewSize.center(Offset.zero));
    final point =
        center +
        vm.Vector3(math.cos(_sunAzimuth), 0, math.sin(_sunAzimuth)) *
            (reach * halfExtent);
    return _camera.worldToScreen(point, _viewSize);
  }

  // --- Dice -----------------------------------------------------------------

  void _roll() {
    if (_viewSize.isEmpty) return;
    for (final die in _dice) {
      scene.remove(die.node);
    }
    _dice.clear();

    // Launch from the roll button toward the middle of the screen.
    var origin = _viewSize.bottomRight(const Offset(-80, -80));
    final button = _rollKey.currentContext?.findRenderObject() as RenderBox?;
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (button != null && view != null) {
      origin = view.globalToLocal(
        button.localToGlobal(button.size.center(Offset.zero)),
      );
    }
    // Rows of up to three dice across the throw. Walls lean inward with
    // height, so clamp to the view at each die's height.
    final halfW = _viewSize.width / _pixelsPerUnit / 2;
    final halfH = _viewSize.height / _pixelsPerUnit / 2;
    vm.Vector3 clampToView(vm.Vector3 p, double margin) {
      final shrink = 1 - p.y / _camera.position.y;
      final maxX = math.max(0.0, halfW * shrink - margin);
      final maxZ = math.max(0.0, halfH * shrink - margin);
      return p
        ..x = p.x.clamp(-maxX, maxX)
        ..z = p.z.clamp(-maxZ, maxZ);
    }

    final rows = (_diceCount + 2) ~/ 3;
    final topY = 1.0 + (rows - 1) * 1.2;
    final start = clampToView(_floorHit(origin)..y = topY, 1.8)..y = 0;
    final toward = (vm.Vector3.zero() - start)..y = 0;
    if (toward.length2 < 1e-4) toward.setValues(0, 0, -1);
    toward.normalize();
    final side = vm.Vector3(-toward.z, 0, toward.x);

    for (var i = 0; i < _diceCount; i++) {
      final row = i ~/ 3;
      final inRow = math.min(3, _diceCount - row * 3);
      final position = clampToView(
        start + side * ((i % 3 - (inRow - 1) / 2) * 1.0)
          ..y = 1.0 + row * 1.2,
        0.7,
      );
      final velocity =
          toward * (5.0 + _random.nextDouble() * 4.0) +
          vm.Vector3(
            _jitter(1.5),
            4.0 + _random.nextDouble() * 4.0,
            _jitter(1.5),
          );
      final spin = vm.Vector3(_jitter(25), _jitter(25), _jitter(25));
      final rotation = vm.Quaternion.euler(
        _random.nextDouble() * math.pi * 2,
        _random.nextDouble() * math.pi * 2,
        _random.nextDouble() * math.pi * 2,
      );
      final node = Node(
        mesh: Mesh(_dieGeometry, _dieMaterials[i % _dieMaterials.length]),
        localTransform: vm.Matrix4.compose(
          position,
          rotation,
          vm.Vector3.all(1.0),
        ),
      );
      final body = RigidBody(
        linearVelocity: velocity,
        angularVelocity: spin,
        angularDamping: 0.3,
        ccdEnabled: true,
      );
      node.addComponent(body);
      node.addComponent(
        Collider(
          shape: BoxShape(halfExtents: vm.Vector3.all(_dieHalf)),
          material: const PhysicsMaterial(friction: 0.5, restitution: 0.35),
        ),
      );
      scene.add(node);
      _dice.add(_Die(node, body));
    }
    _rolling = true;
    _rollTime = 0.0;
    _stillTime = 0.0;
  }

  double _jitter(double amount) => (_random.nextDouble() * 2 - 1) * amount;

  void _onTick(Duration elapsed, double deltaSeconds) {
    if (!_rolling) return;
    _rollTime += deltaSeconds;
    final still = _dice.every(
      (d) =>
          d.body.linearVelocity.length < 0.05 &&
          d.body.angularVelocity.length < 0.1,
    );
    _stillTime = still ? _stillTime + deltaSeconds : 0.0;
    // A die propped on a wall may never fully settle, so time out too.
    if ((_rollTime > 0.6 && _stillTime > 0.3) || _rollTime > 8.0) {
      _rolling = false;
      final faces = [for (final d in _dice) _topFace(d.node)];
      _lastRoll.value = faces;
      final total = faces.fold(0, (a, b) => a + b);
      _history.value = ['You rolled $total', ..._history.value.take(5)];
    }
  }

  /// Plays a hit for any die whose velocity jumped more than gravity explains
  /// since the last physics step. Tumbling edge strikes register too, since
  /// they change the spin.
  void _listenForImpacts(double deltaSeconds) {
    _audioClock += deltaSeconds;
    final audio = _audio;
    if (audio == null || _surface == _Surface.off || deltaSeconds <= 0) {
      return;
    }
    final now = _audioClock;
    final gravityStep = vm.Vector3(0, -30.0 * deltaSeconds, 0);
    final eyeHeight = _camera.position.y;
    final halfW = _viewSize.width / _pixelsPerUnit / 2;
    final halfH = _viewSize.height / _pixelsPerUnit / 2;
    for (final die in _dice) {
      final velocity = die.body.linearVelocity;
      final spin = die.body.angularVelocity;
      final lastVelocity = die.lastVelocity;
      final lastSpin = die.lastSpin;
      die.lastVelocity = velocity;
      die.lastSpin = spin;
      if (lastVelocity == null || lastSpin == null) continue;

      final change = velocity - lastVelocity - gravityStep;
      final strength =
          change.length + (spin - lastSpin).length * _dieHalf * 0.5;
      if (strength < _minImpact) continue;
      // The contact keeps resolving for a few steps after a hit. A follow-up
      // plays only if it beats that echo, whose bar halves every 40 ms, so
      // fresh hard hits in quick succession still sound.
      final sinceHit = now - die.lastHitTime;
      // Never twice in back-to-back physics steps.
      if (sinceHit < 0.025) continue;
      final echo = die.lastHitStrength * math.pow(0.5, sinceHit / 0.04);
      if (strength <= echo) continue;

      final position = die.node.globalTransform.getTranslation();
      final shrink = 1 - position.y / eyeHeight;
      final nearWall =
          halfW * shrink - position.x.abs() < 0.6 ||
          halfH * shrink - position.z.abs() < 0.6;
      _Die? neighbor;
      var neighborDistance = _dieHalf * 3.2;
      for (final other in _dice) {
        if (other == die) continue;
        final d = other.node.globalTransform.getTranslation().distanceTo(
          position,
        );
        if (d < neighborDistance) {
          neighbor = other;
          neighborDistance = d;
        }
      }
      final horizontal = vm.Vector2(change.x, change.z).length;
      // An upward kick low down is the surface, even beside another die.
      final floorKick = position.y < _dieHalf * 1.8 && change.y > horizontal;
      final String set;
      if (!floorKick && neighbor != null) {
        set = 'clack';
      } else if (!floorKick && nearWall && horizontal > change.y.abs()) {
        set = 'wall';
      } else {
        set = _surface == _Surface.glass ? 'glass' : 'table';
      }
      final clips = _impactClips[set];
      if (clips == null || clips.isEmpty) continue;

      // Dice landing within a step of each other would flam, so keep only the
      // loudest; its click masks the cut tail of the one it replaces.
      final last = _lastSetHit[set];
      if (last != null && now - last.time < 0.02) {
        if (strength <= last.strength) continue;
        last.voice.stop();
      }
      die.lastHitTime = now;
      die.lastHitStrength = strength;
      // Both dice feel a die-on-die hit; one click covers the pair.
      if (set == 'clack') {
        neighbor!
          ..lastHitTime = now
          ..lastHitStrength = math.max(neighbor.lastHitStrength, strength);
      }

      // Decibels across the strength range, so a tap is far quieter than a
      // slam.
      final t = (math.log(strength / _minImpact) / math.log(30 / _minImpact))
          .clamp(0.0, 1.0);
      final voice = audio.playOneShot(
        clips[_random.nextInt(clips.length)],
        position: position,
        volume: math.pow(10, (-32 + 32 * t) / 20).toDouble(),
        // Softer hits ring a little lower.
        pitch: 0.92 + 0.08 * t + _jitter(0.05),
        bus: _sfxBus,
        attenuation: _flat,
      );
      _lastSetHit[set] = (time: now, strength: strength, voice: voice);
    }
  }

  static const double _minImpact = 1.2;

  /// The value on the face pointing most upward.
  int _topFace(Node node) {
    final m = node.globalTransform;
    var best = 0;
    var bestUp = -double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      final up = m.entry(1, axis);
      if (up.abs() > bestUp) {
        bestUp = up.abs();
        best = axis * 2 + (up >= 0 ? 0 : 1);
      }
    }
    return _faceValues[best];
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _configureView(constraints.biggest);
        final sunMarker = _kind == _LightKind.directional
            ? _sunMarkerPosition()
            : null;
        return Stack(
          key: _viewKey,
          children: [
            Positioned.fill(
              child: _GameScreen(
                rollKey: _rollKey,
                onRoll: _roll,
                lastRoll: _lastRoll,
                history: _history,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: SceneView(
                  scene,
                  cameraBuilder: (_) => _camera,
                  onTick: _onTick,
                  warmUp: true,
                ),
              ),
            ),
            // Pan only, so taps still reach the widgets underneath.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (d) => _dragLight(d.localPosition),
                onPanUpdate: (d) => _dragLight(d.localPosition),
              ),
            ),
            if (sunMarker != null)
              Positioned(
                left: sunMarker.dx - 18,
                top: sunMarker.dy - 18,
                child: const IgnorePointer(
                  child: Icon(Icons.wb_sunny, size: 36, color: Colors.amber),
                ),
              ),
            ExampleOverlay.bottomLeftPanel(child: _buildPanel()),
          ],
        );
      },
    );
  }

  Widget _buildPanel() {
    final directional = _kind == _LightKind.directional;
    return ExamplePanelCard(
      icon: Icons.light_mode,
      title: 'Dice shadows',
      width: 340,
      body: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Drag anywhere to move the light.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_LightKind>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                foregroundColor: Colors.white70,
                selectedForegroundColor: Colors.black,
                selectedBackgroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                for (final (kind, label) in const [
                  (_LightKind.directional, 'Directional'),
                  (_LightKind.point, 'Point'),
                  (_LightKind.spot, 'Spot'),
                ])
                  ButtonSegment(
                    value: kind,
                    // Scale down rather than wrap when the segment is narrow.
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1, softWrap: false),
                    ),
                  ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) {
                setState(() {
                  _kind = selection.first;
                  _applyLights();
                });
              },
            ),
            const SizedBox(height: 6),
            if (directional)
              _slider(
                'Elevation',
                _sunElevation * vm.radians2Degrees,
                20,
                90,
                (v) => _sunElevation = v * vm.degrees2Radians,
              )
            else
              _slider(
                'Height',
                _lampPosition.y,
                1.5,
                math.max(1.6, _ceilingY + 3.0),
                (v) => _lampPosition.y = v,
              ),
            _slider('Softness', _softness, 0, 1, (v) => _softness = v),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 64, child: Text('Sound')),
                Expanded(
                  child: SegmentedButton<_Surface>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      selectedForegroundColor: Colors.black,
                      selectedBackgroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: _Surface.off, label: Text('Off')),
                      ButtonSegment(value: _Surface.wood, label: Text('Wood')),
                      ButtonSegment(
                        value: _Surface.glass,
                        label: Text('Glass'),
                      ),
                    ],
                    selected: {_surface},
                    onSelectionChanged: (selection) =>
                        setState(() => _surface = selection.first),
                  ),
                ),
              ],
            ),
            _slider('Volume', _volume, 0, 1, (v) {
              _volume = v;
              _sfxBus?.volume = v;
            }),
            _slider(
              'Darkness',
              _catcher.shadowIntensity,
              0,
              1,
              (v) => _catcher.shadowIntensity = v,
            ),
            _slider(
              'Dice',
              _diceCount.toDouble(),
              1,
              6,
              (v) => _diceCount = v.round(),
              divisions: 5,
            ),
          ],
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
    int? divisions,
  }) {
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) => setState(() {
              onChanged(v);
              _applyLights();
            }),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            divisions != null ? '${value.round()}' : value.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// The ordinary app screen the dice roll over.
class _GameScreen extends StatelessWidget {
  const _GameScreen({
    required this.rollKey,
    required this.onRoll,
    required this.lastRoll,
    required this.history,
  });

  final GlobalKey rollKey;
  final VoidCallback onRoll;
  final ValueListenable<List<int>?> lastRoll;
  final ValueListenable<List<String>> history;

  @override
  Widget build(BuildContext context) {
    final insets = ExampleOverlay.safeInsetsOf(context);
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE76F51)),
      useMaterial3: true,
    );
    return Theme(
      data: theme,
      child: ColoredBox(
        color: const Color(0xFFF4EFE6),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, insets.top + 72, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Game night',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Round 3, your turn',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Expanded(
                        child: _PlayerCard(
                          name: 'Ava',
                          score: 42,
                          color: Color(0xFFE76F51),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _PlayerCard(
                          name: 'Theo',
                          score: 37,
                          color: Color(0xFF2A9D8F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ValueListenableBuilder<List<int>?>(
                        valueListenable: lastRoll,
                        builder: (context, faces, _) {
                          final total = faces?.fold(0, (a, b) => a + b);
                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Last roll',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    Text(
                                      faces == null
                                          ? 'Rolling...'
                                          : faces.join(' + '),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                total == null ? '-' : '$total',
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: const Color(0xFFE9C46A),
                    elevation: 0,
                    child: ValueListenableBuilder<List<String>>(
                      valueListenable: history,
                      builder: (context, entries, _) => Column(
                        children: [
                          for (final entry in entries)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.casino_outlined),
                              title: Text(entry),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 20,
              bottom: insets.bottom + 20,
              child: FloatingActionButton.extended(
                key: rollKey,
                onPressed: onRoll,
                icon: const Icon(Icons.casino),
                label: const Text('Roll'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.name,
    required this.score,
    required this.color,
  });

  final String name;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: color,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: text.titleMedium?.copyWith(color: Colors.white)),
            Text(
              '$score',
              style: text.headlineLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded cube whose faces map into a 6x1 pip atlas, one cell per value.
/// Each face is a grid dense across the bevels, pushed out to the rounded
/// surface around an inner box.
MeshGeometry _buildDieGeometry({
  required double half,
  required double radius,
  int bevelSteps = 4,
}) {
  final inner = half - radius;
  final samples = <double>[
    for (var i = 0; i <= bevelSteps; i++) -half + radius * i / bevelSteps,
    for (var i = 0; i <= bevelSteps; i++) inner + radius * i / bevelSteps,
  ];
  final n = samples.length;
  // (normal, u axis) per face, in the same order as the face values.
  final faces = <(vm.Vector3, vm.Vector3)>[
    (vm.Vector3(1, 0, 0), vm.Vector3(0, 0, -1)),
    (vm.Vector3(-1, 0, 0), vm.Vector3(0, 0, 1)),
    (vm.Vector3(0, 1, 0), vm.Vector3(1, 0, 0)),
    (vm.Vector3(0, -1, 0), vm.Vector3(1, 0, 0)),
    (vm.Vector3(0, 0, 1), vm.Vector3(1, 0, 0)),
    (vm.Vector3(0, 0, -1), vm.Vector3(-1, 0, 0)),
  ];
  const faceValues = ExampleDiceShadowsState._faceValues;

  final positions = Float32List(faces.length * n * n * 3);
  final normals = Float32List(faces.length * n * n * 3);
  final texCoords = Float32List(faces.length * n * n * 2);
  final indices = <int>[];
  var vertex = 0;
  for (var f = 0; f < faces.length; f++) {
    final (normal, u) = faces[f];
    // v = normal x u keeps each face counter-clockwise from outside.
    final v = normal.cross(u);
    final base = vertex;
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final p = normal * half + u * samples[i] + v * samples[j];
        final core = vm.Vector3(
          p.x.clamp(-inner, inner),
          p.y.clamp(-inner, inner),
          p.z.clamp(-inner, inner),
        );
        final outward = (p - core)..normalize();
        final surface = core + outward * radius;
        positions.setAll(vertex * 3, [surface.x, surface.y, surface.z]);
        normals.setAll(vertex * 3, [outward.x, outward.y, outward.z]);
        texCoords.setAll(vertex * 2, [
          (faceValues[f] - 1 + (samples[i] + half) / (2 * half)) / 6,
          1 - (samples[j] + half) / (2 * half),
        ]);
        vertex++;
      }
    }
    for (var j = 0; j < n - 1; j++) {
      for (var i = 0; i < n - 1; i++) {
        final k = base + j * n + i;
        indices.addAll([k, k + 1, k + n + 1, k, k + n + 1, k + n]);
      }
    }
  }
  return MeshGeometry.fromArrays(
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    indices: indices,
  );
}

/// White faces with dark pips, one 128px cell per value (1 through 6).
Texture2D _buildPipAtlas() {
  const cell = 128;
  const lo = 0.27, mid = 0.5, hi = 0.73;
  const layouts = <List<(double, double)>>[
    [(mid, mid)],
    [(lo, lo), (hi, hi)],
    [(lo, lo), (mid, mid), (hi, hi)],
    [(lo, lo), (hi, lo), (lo, hi), (hi, hi)],
    [(lo, lo), (hi, lo), (mid, mid), (lo, hi), (hi, hi)],
    [(lo, lo), (hi, lo), (lo, mid), (hi, mid), (lo, hi), (hi, hi)],
  ];
  const pipRadius = cell * 0.095;
  final pixels = Uint8List(cell * 6 * cell * 4);
  for (var y = 0; y < cell; y++) {
    for (var x = 0; x < cell * 6; x++) {
      final value = x ~/ cell;
      final cx = x - value * cell + 0.5;
      final cy = y + 0.5;
      var coverage = 0.0;
      for (final (px, py) in layouts[value]) {
        final dx = cx - px * cell, dy = cy - py * cell;
        final d = math.sqrt(dx * dx + dy * dy);
        coverage = math.max(coverage, (pipRadius - d + 0.5).clamp(0.0, 1.0));
      }
      final shade = (255 - coverage * 227).round();
      final o = (y * cell * 6 + x) * 4;
      pixels[o] = shade;
      pixels[o + 1] = shade;
      pixels[o + 2] = shade;
      pixels[o + 3] = 255;
    }
  }
  return Texture2D.fromPixels(pixels, cell * 6, cell);
}
