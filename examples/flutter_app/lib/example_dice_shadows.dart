import 'dart:math' as math;
import 'dart:ui' as ui;

// flutter_scene's physics BoxShape and Material clash with Flutter's, so each
// conflicting name is hidden from the import that does not need it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide BoxShape;
import 'package:flutter/services.dart';
import 'package:flutter_scene/audio.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:flutter_scene_soloud/flutter_scene_soloud.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'dice/dice_breakage.dart';
import 'dice/dice_celebration.dart';
import 'dice/dice_clock.dart';
import 'dice/dice_contacts.dart';
import 'dice/dice_finishes.dart';
import 'dice/dice_vfx.dart';
import 'dice/pop_theme.dart';
import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

/// Dice thrown over an ordinary Flutter screen. The scene clears to
/// transparent and an invisible [ShadowCatcherMaterial] plane stands in for
/// the screen surface, so the dice cast shadows onto the widgets underneath.
/// Drag to aim an arrow and release to throw the dice in from off screen, and
/// drag the light's handle to move it. The panel switches between a
/// directional, point, and spot light, picks what the dice are made of, and
/// can copy the screen into the scene so glass dice refract it.
///
/// A settled roll counts itself up die by die, multiplies a matched set, and
/// slams the result into the running total with confetti.
class ExampleDiceShadows extends StatefulWidget {
  const ExampleDiceShadows({super.key});

  @override
  ExampleDiceShadowsState createState() => ExampleDiceShadowsState();
}

enum _LightKind { directional, point, spot }

enum _Surface { off, wood, glass }

/// A drawn aim arrow, live while dragging and again while it dissolves.
class _Aim {
  const _Aim(this.start, this.end);

  final Offset start;
  final Offset end;

  Offset get delta => end - start;

  /// 0 at rest, 1 once the drag is long enough to throw at full speed.
  double get strength => (delta.distance / _kFullPullPixels).clamp(0.0, 1.0);
}

/// Drag length that reaches the hardest throw.
const double _kFullPullPixels = 420.0;

/// One scored roll in the history list.
typedef RollRecord = ({List<int> faces, int multiplier, int scored});

/// A card's break in progress on the host side.
class _BreakRun {
  _BreakRun({required this.hit, required this.seed, required this.start});

  final Offset hit;
  final int seed;
  final double start;
  ui.Image? image;
  bool shattered = false;
  bool rebuilding = false;
}

class _Die {
  _Die(this.node, this.visual, this.body, this.trail, this.finish, this.color);

  /// The physics body. Its transform is the die's pose.
  final Node node;

  /// The child carrying the mesh (and the outline highlight).
  final Node visual;
  final RigidBody body;
  final TrailComponent trail;
  DiceFinish finish;
  final vm.Vector4 color;

  /// The pool of light under a glass die.
  Caustic? caustic;
  double lastSkidTime = -1.0;
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

class ExampleDiceShadowsState extends State<ExampleDiceShadows>
    with SingleTickerProviderStateMixin {
  final Scene scene = Scene();
  late final PhysicsWorld world;

  // Logical pixels per world unit, so dice keep a steady on-screen size.
  static const double _pixelsPerUnit = 100.0;
  static const double _fovY = 35.0 * vm.degrees2Radians;
  // Half the die's edge, set by the size slider.
  double _dieHalf = 0.35;

  static const _faceValues = <int>[2, 5, 1, 6, 3, 4]; // +X -X +Y -Y +Z -Z

  final math.Random _random = math.Random();
  final GlobalKey _viewKey = GlobalKey();
  final GlobalKey _rollKey = GlobalKey();

  Size _viewSize = Size.zero;
  PerspectiveCamera _camera = PerspectiveCamera();
  double _ceilingY = 6.0;
  // Shadow range with the sun overhead. A low sun stretches shadows far past
  // this, so [_applyLights] extends it.
  double _shadowBaseDistance = 20.0;
  final List<Node> _bounds = [];
  // The four frustum walls, by the world direction each one faces from the
  // middle of the view. Dice thrown in from off screen need one of them to
  // let go for a moment, since the walls trace the screen edges.
  final List<({vm.Vector3 outward, Collider collider})> _walls = [];
  final List<Collider> _openWalls = [];
  double _openWallTime = 0.0;

  // Where the light handle sits, so a drag that starts on it aims the light
  // instead of the dice.
  Rect _lightHandleRect = Rect.zero;
  // The arrow under the finger, then the one dissolving after the throw.
  final ValueNotifier<_Aim?> _aim = ValueNotifier(null);
  final ValueNotifier<_Aim?> _spentAim = ValueNotifier(null);
  late final AnimationController _aimDissolve;

  late MeshGeometry _dieGeometry;
  late final DieTextures _textures;
  late final ShadowCatcherMaterial _catcher;
  late final DiceVfx _vfx;
  final List<_Die> _dice = [];
  int _diceCount = const int.fromEnvironment(
    'DICE_COUNT',
    defaultValue: 3,
  ).clamp(1, 6);
  // `--dart-define=DICE_FINISH=<name>` and `DICE_EMBED_BACKDROP=true` pick
  // the starting look, for driving a launch from a script.
  DiceFinish _finish = DiceFinish.values.firstWhere(
    (f) => f.name == const String.fromEnvironment('DICE_FINISH'),
    orElse: () => DiceFinish.mixed,
  );

  // The screen copied into the scene as an opaque plane under the shadow
  // catcher, so glass dice have something to refract. Off, the scene stays
  // transparent and glass composites over the widgets with plain alpha.
  bool _embedBackdrop = const bool.fromEnvironment('DICE_EMBED_BACKDROP');

  // Pools of light under clear glass dice. Off unless asked for
  // (`--dart-define=DICE_CAUSTICS=true` starts them on).
  bool _caustics = const bool.fromEnvironment('DICE_CAUSTICS');
  final WidgetTextureController _capture = WidgetTextureController();
  late final UnlitMaterial _backdropMaterial;
  Node? _backdropNode;
  gpu.Texture? _boundCapture;

  // The roll being scored, and the frame the score widgets draw from.
  Celebration? _celebration;
  final ValueNotifier<CelebrationFrame> _frame = ValueNotifier(
    const CelebrationFrame(total: 1240),
  );
  int _total = 1240;
  // The score banner's centre in view coordinates, measured by the screen.
  Offset? _bannerCenter;
  // Where the counter flies, relative to the middle of the view. Measured
  // after layout, so the counter listens rather than reading it at build.
  final ValueNotifier<Offset> _flight = ValueNotifier(const Offset(0, -260));
  final math.Random _vfxRandom = math.Random();

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
  // Celebration one-shots by name (`assets/sounds/celebrate_<name>.wav`).
  final Map<String, AudioClip> _fxClips = {};
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
  final ValueNotifier<List<RollRecord>> _history = ValueNotifier([
    (faces: [3, 5, 3], multiplier: 2, scored: 22),
    (faces: [6, 2, 1], multiplier: 1, scored: 9),
    (faces: [4, 4, 4], multiplier: 3, scored: 36),
  ]);

  // Sun elevation at the middle of the view and out at the edge. Low enough
  // that a die at the rim throws a shadow most of the way across.
  static const double _sunElevationHigh = 90.0;
  static const double _sunElevationLow = 7.0;

  _LightKind _kind = _LightKind.directional;

  // The sun is the shared settings' directional light, so the settings
  // sidebar and this panel drive the same thing. Radians here.
  double get _sunAzimuth =>
      exampleSettings.lightAzimuthDegrees * vm.degrees2Radians;
  double get _sunElevation =>
      exampleSettings.lightElevationDegrees * vm.degrees2Radians;

  // 0..1 shadow softness; the sun's is an angle, the lamps' a filter radius.
  double get _softness =>
      (exampleSettings.shadowSoftness / 0.3).clamp(0.0, 1.0);
  set _softness(double value) => exampleSettings.shadowSoftness = value * 0.3;

  // Real seconds since the example opened, and the physics time scale the
  // slow-motion beat dips.
  double _realTime = 0.0;
  double _timeScale = 1.0;
  double _slowUntil = -1.0;
  bool _slowFired = false;

  // Where the dice touch the screen, for the widgets under them.
  final ValueNotifier<DiceContacts> _contacts = ValueNotifier(
    const DiceContacts(),
  );
  final List<DiceHit> _hits = [];

  // The screen's cards and button as measured, in view coordinates, and the
  // raised colliders standing in for them.
  List<Rect> _cardRects = const [];
  Rect? _buttonRect;
  final List<Node> _uiBounds = [];
  String _uiBoundsKey = '';

  // The Roll pill glows, and the TOTAL sticker flashes when a slam lands.
  late final PointLight _buttonLight;
  late final PointLight _stickerLight;
  late final Node _buttonLightNode;
  late final Node _stickerLightNode;
  double _stickerFlash = 0.0;

  // A drag that starts on a die shoves the dice instead of aiming.
  bool _sweeping = false;
  Offset? _sweepLast;
  double _sweepTime = 0.0;

  ScreenTheme _theme = ScreenTheme.pop;

  // Screen shake, applied to the whole view (widgets and scene together) so
  // nothing drifts out of alignment. Amplitude decays; the offset is noise.
  double _shake = 0.0;
  final ValueNotifier<(Offset, double)> _shakeOffset = ValueNotifier((
    Offset.zero,
    0.0,
  ));

  // Timed one-shots queued by the celebration (fireworks, hops, breaks).
  final List<({double at, void Function() run})> _cues = [];

  // Golden hour: the sun swings low and warm for a big match, then back.
  double _goldenStart = -1.0;
  double _goldenEnd = -1.0;
  ({
    double azimuth,
    double elevation,
    double intensity,
    vm.Vector3 color,
    double environment,
  })?
  _goldenRestore;

  // Cards a die has broken, and the shards on the table.
  final CardBreakController _breaks = CardBreakController();
  final Map<int, _BreakRun> _breakRuns = {};
  final List<
    ({PhysicallyBasedMaterial material, double fadeAt, List<Node> nodes})
  >
  _shardSets = [];
  final List<Node?> _cardColliders = [];

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

    _dieGeometry = _buildDieGeometry(half: _dieHalf, radius: _dieHalf * 0.23);
    _textures = DieTextures.bake();
    _backdropMaterial = UnlitMaterial();
    _capture.addListener(_bindCapture);

    _vfx = DiceVfx(scene)
      ..load()
      ..additive = _embedBackdrop;
    if (_embedBackdrop) exampleSettings.toneMapping = ToneMappingMode.linear;
    scene.highlightStyle.thickness = 6.5;

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
    _buttonLight = PointLight(intensity: 0.0, range: 5.0);
    _stickerLight = PointLight(intensity: 0.0, range: 7.0);
    _buttonLightNode = Node()..addComponent(PointLightComponent(_buttonLight));
    _stickerLightNode = Node()
      ..addComponent(PointLightComponent(_stickerLight));
    scene
      ..add(_buttonLightNode)
      ..add(_stickerLightNode);
    _applyLights();
    _buildEnvironment();

    scene.root.addComponent(_AfterPhysics(_listenForImpacts));
    _startAudio();

    _aimDissolve =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 420),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _spentAim.value = null;
        });

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
    for (final clip in _fxClips.values) {
      clip.dispose();
    }
    _vfx.dispose();
    _contacts.dispose();
    _flight.dispose();
    _breaks.dispose();
    _shakeOffset.dispose();
    _capture.removeListener(_bindCapture);
    _capture.dispose();
    _frame.dispose();
    _lastRoll.dispose();
    _history.dispose();
    _aim.dispose();
    _spentAim.dispose();
    _aimDissolve.dispose();
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
      // `dice_<set>_N` are the table's own sounds, `land_<set>_N` a die
      // finish's, `celebrate_<name>` the one-shots.
      final impact = RegExp(
        r'assets/sounds/(dice|land)_(\w+?)_',
      ).firstMatch(path);
      final fx = RegExp(r'assets/sounds/celebrate_(\w+)\.').firstMatch(path);
      if (impact == null && fx == null) continue;
      final clip = await audio.loadClip(path);
      if (!mounted) {
        clip.dispose();
        return;
      }
      if (impact != null) {
        final key = impact.group(1) == 'land'
            ? 'land_${impact.group(2)}'
            : impact.group(2)!;
        _impactClips.putIfAbsent(key, () => []).add(clip);
      } else {
        _fxClips[fx!.group(1)!] = clip;
      }
    }
  }

  /// Plays a celebration sound, positional when [position] is given.
  void _playFx(
    String name, {
    double volume = 1.0,
    double pitch = 1.0,
    vm.Vector3? position,
  }) {
    final audio = _audio;
    final clip = _fxClips[name];
    if (audio == null || clip == null || _surface == _Surface.off) return;
    audio.playOneShot(
      clip,
      position: position,
      volume: volume,
      pitch: pitch,
      bus: _sfxBus,
      attenuation: _flat,
    );
  }

  // --- Backdrop ---------------------------------------------------------------

  /// Copies the screen into the scene (or takes it back out). Glass dice are
  /// rebuilt so they refract the copy instead of alpha-blending.
  void _setEmbedBackdrop(bool value) {
    if (value == _embedBackdrop) return;
    _embedBackdrop = value;
    _vfx.additive = value;
    // The copy is unlit and its colors must survive the resolve, so the tone
    // curve comes off while it is in the scene. The dice clip a little.
    exampleSettings.toneMapping = value
        ? ToneMappingMode.linear
        : ToneMappingMode.pbrNeutral;
    if (!value) {
      final node = _backdropNode;
      if (node != null) scene.remove(node);
      _backdropNode = null;
      _boundCapture = null;
    }
    // The plane waits for the first capture (see _bindCapture), so it never
    // shows untextured.
    _respawnInPlace();
    setState(() {});
  }

  void _bindCapture() {
    final texture = _capture.texture;
    if (texture == null || identical(texture, _boundCapture)) return;
    final first = _boundCapture == null;
    _boundCapture = texture;
    _backdropMaterial.baseColorTexture = GpuTextureSource(
      texture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    if (first) _rebuildBackdropPlane();
  }

  /// Lays the screen copy over the floor rectangle the view sees at y = 0,
  /// just under the shadow catcher. The plane's texture axes are matched to
  /// the screen's from the camera itself, so the copy lines up with the live
  /// widgets whichever way the view's axes run.
  void _rebuildBackdropPlane() {
    if (!_embedBackdrop || _viewSize.isEmpty || _boundCapture == null) return;
    final node = _backdropNode;
    if (node != null) scene.remove(node);
    final width = _viewSize.width / _pixelsPerUnit;
    final depth = _viewSize.height / _pixelsPerUnit;
    final center = _viewSize.center(Offset.zero);
    // PlaneGeometry puts u = 0 at -x and v = 0 at -z. The capture has u = 0
    // at screen left and v = 0 at screen top.
    final minusX = _camera.worldToScreen(vm.Vector3(-1, 0, 0), _viewSize);
    final minusZ = _camera.worldToScreen(vm.Vector3(0, 0, -1), _viewSize);
    final mirrorU = minusX != null && minusX.dx > center.dx;
    final mirrorV = minusZ != null && minusZ.dy > center.dy;
    _backdropMaterial.baseColorTextureTransform = TextureTransform(
      scale: vm.Vector2(mirrorU ? -1 : 1, mirrorV ? -1 : 1),
      offset: vm.Vector2(mirrorU ? 1 : 0, mirrorV ? 1 : 0),
    );
    _backdropNode = Node(
      mesh: Mesh(PlaneGeometry(width: width, depth: depth), _backdropMaterial),
      localTransform: vm.Matrix4.translation(vm.Vector3(0, -0.01, 0)),
    )..shadowCastingMode = ShadowCastingMode.off;
    scene.add(_backdropNode!);
  }

  /// Each look brings its own handful when the picker says mix.
  static const Map<ScreenLook, List<DiceFinish>> _themeDice = {
    ScreenLook.pop: DiceFinish.concrete,
    ScreenLook.blueprint: [
      DiceFinish.steel,
      DiceFinish.glass,
      DiceFinish.frosted,
      DiceFinish.gold,
    ],
    ScreenLook.washi: [
      DiceFinish.wood,
      DiceFinish.marble,
      DiceFinish.gold,
      DiceFinish.classic,
    ],
  };

  DiceFinish _finishFor(int index) {
    if (_finish != DiceFinish.mixed) return _finish;
    final set = _themeDice[_theme.look]!;
    return set[index % set.length];
  }

  void _setTheme(ScreenTheme theme) {
    if (theme == _theme) return;
    setState(() => _theme = theme);
    _buildEnvironment();
    _respawnInPlace();
  }

  /// Lights the dice with the screen itself: the look's background is
  /// painted below the horizon of a small equirect and a soft sky above, so
  /// metal and glass reflect the pattern they sit on.
  Future<void> _buildEnvironment() async {
    final theme = _theme;
    const width = 512, height = 256;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const w = 512.0, h = 256.0;
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h / 2),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, h / 2), [
          const Color(0xFFFFFFFF),
          theme.cream,
        ]),
    );
    canvas.save();
    canvas.translate(0, height / 2);
    canvas.clipRect(const Rect.fromLTWH(0, 0, w, h / 2));
    theme.paintBackground(canvas, const Size(w, h / 2), 0.0);
    canvas.restore();
    final image = await recorder.endRecording().toImage(width, height);
    final environment = await EnvironmentMap.fromUIImages(radianceImage: image);
    if (!mounted || theme != _theme) return;
    scene.environment = environment;
  }

  PhysicallyBasedMaterial _materialFor(DiceFinish finish, int index) =>
      buildDieMaterial(
        finish,
        index,
        _textures,
        refractive: _embedBackdrop,
        thickness: _dieHalf * 2,
      );

  /// Resizes the dice. While the slider drags only the meshes follow, so it
  /// stays cheap; [commit] on release rebuilds the colliders too.
  void _setDieSize(double half, {required bool commit}) {
    if (half != _dieHalf) {
      _dieHalf = half;
      _dieGeometry = _buildDieGeometry(half: half, radius: half * 0.23);
      for (var i = 0; i < _dice.length; i++) {
        final die = _dice[i];
        die.visual.mesh = Mesh(_dieGeometry, _materialFor(die.finish, i));
        final proxy = buildShadowProxyMaterial(die.finish, _textures);
        for (final child in die.visual.children) {
          child.mesh = Mesh(_dieGeometry, proxy!);
        }
      }
    }
    if (commit) _respawnInPlace();
  }

  /// Rebuilds every die where it lies (new geometry, collider, material and
  /// shadow proxy) with its motion dropped, so a panel change shows at once.
  /// Not a roll: the score stands and nothing is counted again.
  void _respawnInPlace() {
    _endCelebration();
    final poses = [
      for (final die in _dice)
        (
          position: die.node.localTransform.getTranslation(),
          rotation: vm.Quaternion.fromRotation(
            die.node.localTransform.getRotation(),
          ),
        ),
    ];
    for (final die in _dice) {
      _removeDie(die);
    }
    _dice.clear();
    for (var i = 0; i < poses.length; i++) {
      final pose = poses[i];
      _spawnDie(
        pose.position,
        vm.Vector3.zero(),
        i,
        spin: vm.Vector3.zero(),
        rotation: pose.rotation,
      );
    }
  }

  void _setCaustics(bool value) {
    if (value == _caustics) return;
    setState(() => _caustics = value);
    for (final die in _dice) {
      final existing = die.caustic;
      if (!value && existing != null) {
        _vfx.removeCaustic(existing);
        die.caustic = null;
      } else if (value && existing == null && die.finish.castsCaustic) {
        die.caustic = _vfx.createCaustic(die.color);
      }
    }
  }

  void _setFinish(DiceFinish finish) {
    if (finish == _finish) return;
    setState(() => _finish = finish);
    // Re-skin the dice on the table so the pick shows without a throw.
    _respawnInPlace();
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
    _shadowBaseDistance = distance + 8.0;
    _rebuildBackdropPlane();

    for (final node in _bounds) {
      scene.remove(node);
    }
    _bounds.clear();
    _walls.clear();
    _openWalls.clear();

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
      final collider = _addBound(
        e + slant * (wallLength / 2) - inward * 0.5,
        vm.Vector3(0.5, wallLength / 2 + 0.5, reach),
        rotation: vm.Quaternion.fromRotation(basis),
      );
      _walls.add((outward: (-inward)..y = 0, collider: collider));
    }
  }

  Collider _addBound(
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
    final collider = Collider(
      shape: BoxShape(halfExtents: halfExtents),
      material: const PhysicsMaterial(friction: 0.4, restitution: 0.45),
    );
    node.addComponent(collider);
    scene.add(node);
    _bounds.add(node);
    return collider;
  }

  vm.Vector3 _planeHit(Offset screen, double height) {
    final ray = _camera.screenPointToRay(screen, _viewSize);
    final t = (height - ray.origin.y) / ray.direction.y;
    return ray.origin + ray.direction * t;
  }

  vm.Vector3 _floorHit(Offset screen) => _planeHit(screen, 0.0);

  // --- Lights ---------------------------------------------------------------

  /// Pushes the shared settings into the scene, then places this example's
  /// own lights. Runs every tick, like the other examples, so the settings
  /// sidebar always wins.
  void _applyLights() {
    exampleSettings.directionalLightEnabled = _kind == _LightKind.directional;
    exampleSettings.applyTo(scene);
    _setAttached(_pointNode, _kind == _LightKind.point);
    _setAttached(_spotNode, _kind == _LightKind.spot);

    final sun = scene.directionalLight;
    if (sun != null) {
      // A die throws a shadow of its height over the tangent of the
      // elevation, so the cascades have to reach much further when the sun
      // sits low.
      final tangent = math.max(math.tan(_sunElevation), 0.06);
      sun.shadowMaxDistance =
          _shadowBaseDistance + math.min(48.0, 4.0 / tangent);
    }

    // The Roll pill's glow and the sticker's flash.
    _buttonLight
      ..color = _linear(_theme.button)
      ..intensity = 9.0;
    _stickerLight
      ..color = _linear(_theme.score)
      ..intensity = 160.0 * _stickerFlash;

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
      if (offset.length > 1e-3) {
        exampleSettings.lightAzimuthDegrees =
            math.atan2(offset.z, offset.x) * vm.radians2Degrees;
      }
      exampleSettings.lightElevationDegrees =
          _sunElevationHigh - reach * (_sunElevationHigh - _sunElevationLow);
    } else {
      final height = _lampPosition.y;
      _lampPosition = _planeHit(position, height)..y = height;
    }
    setState(_applyLights);
  }

  /// Where the light's handle sits on screen. The lamps project from their
  /// world position; the sun has none, so it rides the direction it shines
  /// from (the inverse of [_dragLight]).
  Offset? _lightHandlePosition() {
    if (_viewSize.isEmpty) return null;
    if (_kind != _LightKind.directional) {
      return _camera.worldToScreen(_lampPosition, _viewSize);
    }
    return _sunMarkerPosition();
  }

  /// Where the sun marker sits on screen, the inverse of [_dragLight].
  Offset? _sunMarkerPosition() {
    if (_viewSize.isEmpty) return null;
    final halfExtent =
        math.min(_viewSize.width, _viewSize.height) / _pixelsPerUnit / 2;
    final reach =
        (_sunElevationHigh - _sunElevation * vm.radians2Degrees) /
        (_sunElevationHigh - _sunElevationLow);
    final center = _floorHit(_viewSize.center(Offset.zero));
    final point =
        center +
        vm.Vector3(math.cos(_sunAzimuth), 0, math.sin(_sunAzimuth)) *
            (reach * halfExtent);
    return _camera.worldToScreen(point, _viewSize);
  }

  // --- Dice -----------------------------------------------------------------

  void _roll({_Aim? aim}) {
    if (_viewSize.isEmpty) return;
    _endCelebration();
    _cues.clear();
    for (final die in _dice) {
      _removeDie(die);
    }
    _dice.clear();
    _slowFired = false;
    _lastRoll.value = null;
    _playFx('throw', volume: 0.7, pitch: 0.95 + _random.nextDouble() * 0.1);

    if (aim != null) {
      _throwAlong(aim);
      return;
    }

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
      _spawnDie(
        position,
        velocity,
        i,
        spin: vm.Vector3(_jitter(25), _jitter(25), _jitter(25)),
      );
    }
    _rolling = true;
    _rollTime = 0.0;
    _stillTime = 0.0;
  }

  /// Throws the dice in from off screen along the drawn arrow. The dice start
  /// outside the view, so the wall they cross stops blocking until they land
  /// inside (see [_closeEntryWalls]).
  void _throwAlong(_Aim aim) {
    final from = _floorHit(aim.start);
    final to = _floorHit(aim.end);
    final direction = (to - from)..y = 0;
    if (direction.length2 < 1e-4) return;
    final pull = direction.length; // World units dragged.
    direction.normalize();

    final side = vm.Vector3(-direction.z, 0, direction.x);
    // Room the loose handful needs, wider as dice are added.
    final cluster = 0.5 + 0.16 * _diceCount;
    // Back the throw up just past the edge of the view at the height the dice
    // fly at. The view narrows toward the floor, so that is a shorter run than
    // the floor rectangle would suggest.
    final spawnHeight = math.max(1.15, _dieHalf * 2 + 0.5);
    final runway =
        _exitDistance(from, -direction, height: spawnHeight) + 0.6 + cluster;
    final origin = from - direction * runway;

    // Speed follows the arrow and nothing else, so a flick stays a flick.
    var speed = (3.0 + pull * 3.0).clamp(3.0, 28.0);

    // The dice still have to cross the runway before gravity lands them, so a
    // slow throw buys its distance with a higher arc rather than more speed.
    const gravity = 30.0;
    final reach = runway + 0.6;
    var lift = 2.0 + speed * 0.12;
    final wantedAirTime = reach / speed;
    // Vertical launch speed that keeps a die up for exactly that long.
    final lofted =
        (0.5 * gravity * wantedAirTime * wantedAirTime - spawnHeight) /
        wantedAirTime;
    // Arcing into the ceiling looks worse than throwing a little harder.
    final headroom = math.max(_ceilingY - spawnHeight - 0.6, 0.5);
    final maxLift = math.sqrt(2 * gravity * headroom);
    lift = math.max(lift, math.min(lofted, maxLift));
    final airTime =
        (lift + math.sqrt(lift * lift + 2 * gravity * spawnHeight)) / gravity;
    speed = math.max(speed, reach / airTime);

    _openEntryWalls(direction);
    final placed = _scatterCluster(
      origin,
      direction,
      side,
      spawnHeight,
      cluster,
    );
    final tumble = direction.cross(vm.Vector3(0, 1, 0));
    for (var i = 0; i < placed.length; i++) {
      // Each die leaves the hand slightly differently, so the handful opens
      // up as it flies rather than travelling as a block.
      final velocity =
          direction * (speed * (1.0 + _jitter(0.10))) +
          side * _jitter(1.1) +
          vm.Vector3(0, lift * (1.0 + _jitter(0.18)), 0);
      final axis = vm.Vector3(_jitter(1.0), _jitter(1.0), _jitter(1.0));
      if (axis.length2 < 1e-6) axis.setValues(0, 1, 0);
      axis.normalize();
      _spawnDie(
        placed[i],
        velocity,
        i,
        // Mostly end over end along the throw, plus a random tumble.
        spin:
            tumble * (speed * (0.7 + _random.nextDouble() * 0.7)) +
            axis * (6.0 + _random.nextDouble() * 16.0),
      );
    }
    _rolling = true;
    _rollTime = 0.0;
    _stillTime = 0.0;
  }

  /// Random spots for a loose handful of dice, none of them touching. Dice
  /// spin freely, so centres stay a full diagonal apart.
  List<vm.Vector3> _scatterCluster(
    vm.Vector3 origin,
    vm.Vector3 direction,
    vm.Vector3 side,
    double height,
    double radius,
  ) {
    final minGap = _dieHalf * 2 * math.sqrt(3) + 0.06;
    final placed = <vm.Vector3>[];
    var reach = radius;
    for (var i = 0; i < _diceCount; i++) {
      vm.Vector3? spot;
      for (var attempt = 0; attempt < 80 && spot == null; attempt++) {
        // Flatter than it is wide, the way a handful leaves the fingers.
        final candidate =
            origin + side * _jitter(reach) + direction * _jitter(reach * 0.8);
        candidate.y = math.max(height + _jitter(reach * 0.55), _dieHalf + 0.15);
        if (placed.every((p) => p.distanceTo(candidate) >= minGap)) {
          spot = candidate;
        }
        // Loosen up if the handful is too tight to fit.
        if (attempt == 40) reach += minGap * 0.5;
      }
      // Fall back to a straight line if the sampling never found room.
      final fallback = origin + side * (i * minGap)
        ..y = height;
      placed.add(spot ?? fallback);
    }
    return placed;
  }

  void _spawnDie(
    vm.Vector3 position,
    vm.Vector3 velocity,
    int index, {
    required vm.Vector3 spin,
    vm.Quaternion? rotation,
  }) {
    rotation ??= vm.Quaternion.euler(
      _random.nextDouble() * math.pi * 2,
      _random.nextDouble() * math.pi * 2,
      _random.nextDouble() * math.pi * 2,
    );
    final finish = _finishFor(index);
    final color = dieColors[index % dieColors.length];
    final visual = Node(mesh: Mesh(_dieGeometry, _materialFor(finish, index)));
    // Glass is translucent, which the shadow pass skips, so a glass die
    // casts through an invisible dithered stand-in that reads as a lighter
    // shadow once the light's softness blurs the dots.
    if (finish == DiceFinish.clock) {
      // A live clock sealed inside the glass. The quad faces +z, so turn it
      // to face up, with its top toward the top of the screen.
      final clock = Node(localTransform: vm.Matrix4.rotationX(-math.pi / 2))
        ..shadowCastingMode = ShadowCastingMode.off;
      clock.addComponent(
        WidgetComponent(
          child: DieClockFace(theme: _theme),
          size: const Size(128, 128),
          worldHeight: _dieHalf * 1.3,
          update: const WidgetUpdatePolicy.interval(Duration(milliseconds: 40)),
          input: WidgetInput.manual,
          // Opaque, so the glass refracts it like any surface behind it.
          material: UnlitMaterial(),
        ),
      );
      visual.add(clock);
    }
    final proxyMaterial = buildShadowProxyMaterial(finish, _textures);
    if (proxyMaterial != null) {
      visual.add(
        Node(mesh: Mesh(_dieGeometry, proxyMaterial))
          ..shadowCastingMode = ShadowCastingMode.shadowsOnly,
      );
    }
    // A streak in the die's color while it flies. It rides the body node,
    // which carries no mesh of its own, so it never casts a shadow.
    final trail = TrailComponent(
      width: _dieHalf * 0.5,
      lifetime: 0.26,
      minVertexDistance: 0.03,
      widthOverTrail: ParticleCurve.linear(from: 1.0, to: 0.0),
      colorOverTrail: ColorGradient([
        ColorStop(
          0.0,
          vm.Vector4(color.x * 2.5, color.y * 2.5, color.z * 2.5, 0.55),
        ),
        ColorStop(1.0, vm.Vector4(color.x, color.y, color.z, 0.0)),
      ]),
    );
    final node =
        Node(
            localTransform: vm.Matrix4.compose(
              position,
              rotation,
              vm.Vector3.all(1.0),
            ),
          )
          ..shadowCastingMode = ShadowCastingMode.off
          ..add(visual)
          ..addComponent(trail);
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
    final die = _Die(node, visual, body, trail, finish, color);
    if (_caustics && finish.castsCaustic) {
      die.caustic = _vfx.createCaustic(color);
    }
    _dice.add(die);
  }

  /// Distance from [point] to the edge of the view along [direction], measured
  /// at [height] (the view narrows toward the floor).
  double _exitDistance(
    vm.Vector3 point,
    vm.Vector3 direction, {
    double height = 0.0,
  }) {
    final shrink = math.max(1 - height / _camera.position.y, 0.05);
    final halfW = _viewSize.width / _pixelsPerUnit / 2 * shrink;
    final halfH = _viewSize.height / _pixelsPerUnit / 2 * shrink;
    var distance = double.infinity;
    if (direction.x.abs() > 1e-6) {
      final edge = direction.x > 0 ? halfW : -halfW;
      distance = math.min(distance, (edge - point.x) / direction.x);
    }
    if (direction.z.abs() > 1e-6) {
      final edge = direction.z > 0 ? halfH : -halfH;
      distance = math.min(distance, (edge - point.z) / direction.z);
    }
    return distance.isFinite ? math.max(distance, 0.0) : 0.0;
  }

  /// Lets go of every wall the dice could cross on their way in. A throw
  /// across a corner passes two of them, so opening only the most opposed one
  /// leaves the dice bouncing off the other from outside.
  void _openEntryWalls(vm.Vector3 direction) {
    _closeEntryWalls();
    for (final wall in _walls) {
      if (wall.outward.dot(-direction) > 0.05) {
        wall.collider.isTrigger = true;
        _openWalls.add(wall.collider);
      }
    }
    _openWallTime = 0.0;
  }

  void _closeEntryWalls() {
    for (final collider in _openWalls) {
      collider.isTrigger = false;
    }
    _openWalls.clear();
  }

  double _jitter(double amount) => (_random.nextDouble() * 2 - 1) * amount;

  /// Whether a point sits inside the visible frustum at its own height. The
  /// view narrows toward the floor, so higher points have less room.
  bool _insideView(vm.Vector3 point, double margin) {
    final shrink = 1 - point.y / _camera.position.y;
    if (shrink <= 0) return false;
    final maxX = _viewSize.width / _pixelsPerUnit / 2 * shrink - margin;
    final maxZ = _viewSize.height / _pixelsPerUnit / 2 * shrink - margin;
    return point.x.abs() < maxX && point.z.abs() < maxZ;
  }

  // --- Aiming ---------------------------------------------------------------

  void _aimStart(Offset position) {
    // The light handle owns its own drag.
    if (_lightHandleRect.contains(position)) return;
    // A drag that starts on a die shoves the dice around instead. That
    // counts as a fresh roll once they settle.
    if (_dieUnder(position) != null) {
      _sweeping = true;
      _sweepLast = position;
      _sweepTime = _realTime;
      _endCelebration();
      _slowFired = false;
      _rolling = true;
      _rollTime = 0.0;
      _stillTime = 0.0;
      return;
    }
    _aimDissolve.stop();
    _spentAim.value = null;
    _aim.value = _Aim(position, position);
  }

  void _aimUpdate(Offset position) {
    if (_sweeping) {
      _sweep(position);
      return;
    }
    final aim = _aim.value;
    if (aim == null) return;
    _aim.value = _Aim(aim.start, position);
  }

  /// The die whose footprint the finger is on, if any.
  _Die? _dieUnder(Offset position) {
    final reach = _dieHalf * _pixelsPerUnit * 1.6;
    for (final die in _dice) {
      if ((_screenPositionOf(die) - position).distance < reach) return die;
    }
    return null;
  }

  /// Pushes the dice near the finger along with it.
  void _sweep(Offset position) {
    final last = _sweepLast;
    final dt = math.max(_realTime - _sweepTime, 1 / 120);
    _sweepLast = position;
    _sweepTime = _realTime;
    if (last == null) return;
    final here = _floorHit(position);
    final push = (here - _floorHit(last)) / dt;
    final reach = _dieHalf * 2.4;
    for (final die in _dice) {
      final at = die.node.localTransform.getTranslation();
      final gap = vm.Vector2(at.x - here.x, at.z - here.z).length;
      if (gap > reach || at.y > _dieHalf * 2.5) continue;
      // Carried by the hand, with a little lift so it tumbles.
      die.body.linearVelocity =
          push * 0.8 +
          vm.Vector3(_jitter(0.6), 1.6 + _random.nextDouble(), _jitter(0.6));
      die.body.angularVelocity = vm.Vector3(
        _jitter(9.0),
        _jitter(9.0),
        _jitter(9.0),
      );
    }
  }

  void _aimRelease() {
    if (_sweeping) {
      _sweeping = false;
      _sweepLast = null;
      _aim.value = null;
      return;
    }
    final aim = _aim.value;
    _aim.value = null;
    if (aim == null) return;
    // Ignore a stray tap.
    if (aim.delta.distance < 24) return;
    _spentAim.value = aim;
    _aimDissolve.forward(from: 0);
    _roll(aim: aim);
  }

  void _onTick(Duration elapsed, double realDelta) {
    _realTime += realDelta;
    _runCues();
    _advanceGolden();
    _advanceShake(realDelta);
    _advanceBreaks();
    _applyLights();
    _stickerFlash *= math.exp(-realDelta * 4.0);

    // Slow motion dips the scene clock, not the wall clock: the scene is
    // ticked here with the scaled delta, so the view skips its own tick.
    final slow = _slowUntil > _realTime ? (_slowUntil - _realTime) / 0.9 : 0.0;
    _timeScale = slow <= 0 ? 1.0 : 0.18 + 0.82 * math.pow(1 - slow, 3);
    final deltaSeconds = realDelta * _timeScale;
    if (slow > 0) {
      scene.postProcess.chromaticAberration
        ..enabled = true
        ..intensity = 1.4 * slow;
    }
    // Everything that changes nodes (highlights, effects) runs before the
    // scene ticks, so the render items are in sync by the time they draw.
    _vfx.update(deltaSeconds);
    _advanceCelebration(realDelta);
    scene.update(deltaSeconds);

    _publishContacts(realDelta);
    for (final die in _dice) {
      // Streak only while flying; a rolling die drags no light behind it.
      die.trail.emitting = die.body.linearVelocity.length > 5.0;
      _placeCaustic(die);
      _skid(die);
    }
    _watchForMatch();
    if (_openWalls.isNotEmpty) {
      _openWallTime += deltaSeconds;
      final allInside = _dice.every(
        (d) => _insideView(d.node.localTransform.getTranslation(), 0.2),
      );
      // Time out too, in case a die never makes it in.
      if ((allInside && _openWallTime > 0.1) || _openWallTime > 2.5) {
        _closeEntryWalls();
      }
    }
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
      var faces = [for (final d in _dice) _topFace(d.node)];
      // `--dart-define=DICE_DEBUG_MATCH=<n>` scores every roll as an n-of-a-
      // kind, to drive the jackpot tiers from a script. Debug only.
      const forced = int.fromEnvironment('DICE_DEBUG_MATCH');
      if (kDebugMode && forced >= 2 && faces.length >= forced) {
        faces = [for (var i = 0; i < faces.length; i++) i < forced ? 6 : i + 1];
      }
      _lastRoll.value = faces;
      _startCelebration(faces);
    }
  }

  void _runCues() {
    if (_cues.isEmpty) return;
    final due = _cues.where((cue) => cue.at <= _realTime).toList();
    _cues.removeWhere((cue) => cue.at <= _realTime);
    for (final cue in due) {
      cue.run();
    }
  }

  void _cue(double delay, void Function() run) =>
      _cues.add((at: _realTime + delay, run: run));

  // --- Screen shake -------------------------------------------------------

  /// Kicks the shake up to at least [amount] (0..1).
  void _kickShake(double amount) => _shake = math.max(_shake, amount);

  static double _smooth(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  void _advanceShake(double dt) {
    if (_shake <= 0.002) {
      if (_shakeOffset.value.$1 != Offset.zero) {
        _shakeOffset.value = (Offset.zero, 0.0);
      }
      _shake = 0.0;
      return;
    }
    _shake *= math.exp(-dt * 5.5);
    final t = _realTime;
    // Two incommensurate frequencies per axis read as a rattle, not a wobble.
    final offset = Offset(
      math.sin(t * 61.0) * 0.6 + math.sin(t * 37.3) * 0.4,
      math.cos(t * 53.0) * 0.6 + math.sin(t * 43.7) * 0.4,
    );
    final reach = 16.0 * _shake * _shake + 4.0 * _shake;
    _shakeOffset.value = (offset * reach, math.sin(t * 47.0) * 0.014 * _shake);
  }

  // --- Golden hour --------------------------------------------------------

  /// Swings the sun low and warm from the sticker's side so every shadow
  /// stretches across the screen, for [seconds], then eases back.
  void _startGolden(double seconds) {
    _goldenRestore ??= (
      azimuth: exampleSettings.lightAzimuthDegrees,
      elevation: exampleSettings.lightElevationDegrees,
      intensity: exampleSettings.lightIntensity,
      color: exampleSettings.lightColor.clone(),
      environment: exampleSettings.environmentIntensity,
    );
    _goldenStart = _realTime;
    _goldenEnd = _realTime + seconds;
  }

  void _advanceGolden() {
    final restore = _goldenRestore;
    if (restore == null) return;
    const ramp = 0.9;
    final t = _realTime;
    final double amount;
    if (t < _goldenStart + ramp) {
      amount = (t - _goldenStart) / ramp;
    } else if (t < _goldenEnd) {
      amount = 1.0;
    } else if (t < _goldenEnd + 1.3) {
      amount = 1.0 - (t - _goldenEnd) / 1.3;
    } else {
      exampleSettings
        ..lightAzimuthDegrees = restore.azimuth
        ..lightElevationDegrees = restore.elevation
        ..lightIntensity = restore.intensity
        ..environmentIntensity = restore.environment
        ..lightColor.setFrom(restore.color);
      _goldenRestore = null;
      return;
    }
    final a = _smooth(amount);
    final banner = _bannerCenter;
    final sticker = banner == null ? vm.Vector3(1, 0, -1) : _floorHit(banner);
    final azimuth = math.atan2(sticker.z, sticker.x) * vm.radians2Degrees;
    exampleSettings
      ..lightAzimuthDegrees = _lerpAngle(restore.azimuth, azimuth, a)
      ..lightElevationDegrees =
          restore.elevation + (9.0 - restore.elevation) * a
      ..lightIntensity = restore.intensity + (4.6 - restore.intensity) * a
      ..environmentIntensity =
          restore.environment + (0.3 - restore.environment) * a;
    exampleSettings.lightColor.setValues(
      restore.color.x + (1.0 - restore.color.x) * a,
      restore.color.y + (0.66 - restore.color.y) * a,
      restore.color.z + (0.38 - restore.color.z) * a,
    );
  }

  static double _lerpAngle(double from, double to, double t) {
    var delta = (to - from) % 360.0;
    if (delta > 180) delta -= 360;
    return from + delta * t;
  }

  // --- Jackpot escalation -------------------------------------------------

  /// What a match of [multiplier] earns beyond the confetti, queued from
  /// the moment the slam lands.
  void _escalate(int multiplier, List<int> matched) {
    if (multiplier < 3) return;
    final banner = _bannerCenter;
    final sticker = banner == null
        ? vm.Vector3.zero()
        : (_floorHit(banner)..y = 0.2);
    final rockets = 3 + (multiplier - 3) * 2;
    for (var i = 0; i < rockets; i++) {
      _cue(0.35 + i * 0.28, () {
        final from =
            i == 0
                  ? sticker
                  : _floorHit(
                      Offset(
                        _viewSize.width * (0.15 + _random.nextDouble() * 0.7),
                        _viewSize.height * (0.2 + _random.nextDouble() * 0.6),
                      ),
                    )
              ..y = 0.2;
        final color = _linearColor(
          _theme.confetti[_random.nextInt(_theme.confetti.length)],
        );
        _playFx('firework_launch', volume: 0.5, position: from);
        _vfx.firework(
          from,
          color,
          height: math.max(3.5, _camera.position.y * 0.55),
          onBurst: (apex) {
            _stickerFlash = math.max(_stickerFlash, 0.8);
            _kickShake(0.3);
            _playFx('firework_burst', volume: 0.8, position: apex);
            _vfx.shockwave(
              _screenUv(_camera.worldToScreen(apex, _viewSize) ?? Offset.zero),
              strength: 0.012,
            );
          },
        );
      });
    }
    if (multiplier >= 4) {
      _startGolden(2.2 + (multiplier - 4) * 1.4);
    }
    if (multiplier >= 5) {
      _playFx('jackpot', volume: 1.0);
      // The matched dice leap in turn, three rounds, landing on the same
      // faces since they only spin about the vertical.
      for (var round = 0; round < 3; round++) {
        for (var k = 0; k < matched.length; k++) {
          final index = matched[k];
          _cue(0.6 + round * 0.55 + k * 0.08, () {
            if (index >= _dice.length) return;
            final die = _dice[index];
            die.body.linearVelocity = vm.Vector3(0, 6.5, 0);
            die.body.angularVelocity = vm.Vector3(0, 16.0, 0);
          });
        }
      }
    }
    if (multiplier >= 6) {
      // The screen gives way: every card cracks and shatters in turn.
      for (var i = 0; i < _cardRects.length; i++) {
        _cue(1.2 + i * 0.22, () => _breakCard(i, const Offset(0.5, 0.5)));
      }
    }
  }

  // --- Breaking cards -----------------------------------------------------

  /// Cracks card [index] where [hit] (0..1 across the card) struck it, then
  /// shatters it into shards that fly and land, leaves the socket empty, and
  /// snaps the card back after a while.
  void _breakCard(int index, Offset hit) {
    if (index >= _cardRects.length || _breakRuns.containsKey(index)) return;
    final seed = _random.nextInt(1 << 30);
    _breakRuns[index] = _BreakRun(hit: hit, seed: seed, start: _realTime);
    _breaks.set(
      index,
      CardBreak(phase: BreakPhase.cracked, hit: hit, progress: 0, seed: seed),
    );
    _kickShake(0.25);
    _playFx('card_crack', volume: 0.9);
    _vfx.shockwave(_screenUv(_cardRects[index].center), strength: 0.015);
    // Grab the pixels while the card is still whole.
    _breaks.capture(index, MediaQuery.devicePixelRatioOf(context)).then((
      image,
    ) {
      if (image == null || !mounted) return;
      _breakRuns[index]?.image = image;
    });
  }

  void _advanceBreaks() {
    for (final entry in _breakRuns.entries.toList()) {
      final index = entry.key;
      final run = entry.value;
      final t = _realTime - run.start;
      const crack = 0.45, shattered = 3.4, rebuild = 0.9;
      if (t < crack) {
        _breaks.set(
          index,
          CardBreak(
            phase: BreakPhase.cracked,
            hit: run.hit,
            progress: t / crack,
            seed: run.seed,
          ),
        );
      } else if (t < crack + shattered) {
        if (!run.shattered) {
          run.shattered = true;
          _shatterCard(index, run);
        }
      } else if (t < crack + shattered + rebuild) {
        if (!run.rebuilding) {
          run.rebuilding = true;
          _setCardCollider(index, true);
          _playFx('card_rewind', volume: 0.8);
        }
        _breaks.set(
          index,
          CardBreak(
            phase: BreakPhase.reassembling,
            hit: run.hit,
            progress: (t - crack - shattered) / rebuild,
            seed: run.seed,
          ),
        );
      } else {
        _breaks.set(index, null);
        _breakRuns.remove(index);
      }
    }
    // Shards fade once they have rested, then go.
    for (final set in _shardSets.toList()) {
      final since = _realTime - set.fadeAt;
      if (since < 0) continue;
      if (since >= 0.9) {
        for (final node in set.nodes) {
          scene.remove(node);
        }
        _shardSets.remove(set);
        continue;
      }
      set.material
        ..alphaMode = AlphaMode.blend
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1.0 - since / 0.9);
    }
  }

  void _shatterCard(int index, _BreakRun run) {
    _breaks.set(
      index,
      CardBreak(
        phase: BreakPhase.shattered,
        hit: run.hit,
        progress: 0,
        seed: run.seed,
      ),
    );
    _setCardCollider(index, false);
    _kickShake(0.55);
    _playFx('card_shatter', volume: 1.0);
    _vfx.shockwave(_screenUv(_cardRects[index].center), strength: 0.03);
    final image = run.image;
    if (image == null || index >= _cardRects.length) return;
    final rect = _cardRects[index];
    Texture2D.fromImage(image).then((texture) {
      if (!mounted) return;
      _spawnShards(rect, run, texture);
    });
  }

  /// Turns the card's captured pixels into thick shards that burst out of
  /// the socket, tumble, and settle on the table as real bodies.
  void _spawnShards(Rect rect, _BreakRun run, Texture2D texture) {
    const height = 0.12, thickness = 0.035;
    final material = PhysicallyBasedMaterial()
      ..baseColorTexture = texture
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.6;
    final hitWorld = _floorHit(
      rect.topLeft + Offset(run.hit.dx * rect.width, run.hit.dy * rect.height),
    );
    final nodes = <Node>[];
    for (final shard in shatter(run.hit, 11, run.seed)) {
      final world = [
        for (final p in shard.polygon)
          _floorHit(
            rect.topLeft + Offset(p.dx * rect.width, p.dy * rect.height),
          )..y = height,
      ];
      var centroid = vm.Vector3.zero();
      for (final p in world) {
        centroid += p;
      }
      centroid /= world.length.toDouble();
      final local = [for (final p in world) p - centroid];
      final geometry = _buildShardGeometry(local, shard.polygon, thickness);
      if (geometry == null) continue;
      var maxX = 0.0, maxZ = 0.0;
      for (final p in local) {
        maxX = math.max(maxX, p.x.abs());
        maxZ = math.max(maxZ, p.z.abs());
      }
      final node = Node(
        mesh: Mesh(geometry, material),
        localTransform: vm.Matrix4.translation(
          centroid + vm.Vector3(0, thickness / 2 + 0.01, 0),
        ),
      );
      // Out from the strike, up, and tumbling.
      final away = (centroid - hitWorld)..y = 0;
      final reach = away.length;
      if (reach > 1e-4) away.normalize();
      final kick = 2.0 + 4.5 / (1.0 + reach * 2.0);
      node.addComponent(
        RigidBody(
          linearVelocity:
              away * kick +
              vm.Vector3(
                _jitter(0.8),
                3.5 + _random.nextDouble() * 3.0,
                _jitter(0.8),
              ),
          angularVelocity: vm.Vector3(_jitter(14), _jitter(6), _jitter(14)),
          angularDamping: 0.6,
        ),
      );
      node.addComponent(
        Collider(
          shape: BoxShape(
            halfExtents: vm.Vector3(
              math.max(maxX, 0.02),
              thickness / 2,
              math.max(maxZ, 0.02),
            ),
          ),
          material: const PhysicsMaterial(friction: 0.7, restitution: 0.15),
        ),
      );
      scene.add(node);
      nodes.add(node);
    }
    _shardSets.add((material: material, fadeAt: _realTime + 2.4, nodes: nodes));
    debugPrint('dice: card broke into ${nodes.length} shards');
  }

  /// A thick slab with the card's pixels on top and bottom.
  MeshGeometry? _buildShardGeometry(
    List<vm.Vector3> ring,
    List<Offset> uvs,
    double thickness,
  ) {
    if (ring.length < 3) return null;
    // Make the ring counter-clockwise seen from above.
    final n = (ring[1] - ring[0]).cross(ring[2] - ring[0]);
    var order = List<int>.generate(ring.length, (i) => i);
    if (n.y < 0) order = order.reversed.toList();
    final positions = <double>[];
    final normals = <double>[];
    final texCoords = <double>[];
    final indices = <int>[];
    final half = thickness / 2;

    int vertex(vm.Vector3 p, vm.Vector3 normal, Offset uv) {
      positions.addAll([p.x, p.y, p.z]);
      normals.addAll([normal.x, normal.y, normal.z]);
      texCoords.addAll([uv.dx, uv.dy]);
      return positions.length ~/ 3 - 1;
    }

    // Top and bottom fans.
    final top = [
      for (final i in order)
        vertex(ring[i] + vm.Vector3(0, half, 0), vm.Vector3(0, 1, 0), uvs[i]),
    ];
    for (var i = 1; i + 1 < top.length; i++) {
      indices.addAll([top[0], top[i], top[i + 1]]);
    }
    final bottom = [
      for (final i in order)
        vertex(ring[i] - vm.Vector3(0, half, 0), vm.Vector3(0, -1, 0), uvs[i]),
    ];
    for (var i = 1; i + 1 < bottom.length; i++) {
      indices.addAll([bottom[0], bottom[i + 1], bottom[i]]);
    }
    // Sides, one quad per edge, facing outward.
    for (var k = 0; k < order.length; k++) {
      final a = ring[order[k]];
      final b = ring[order[(k + 1) % order.length]];
      final edge = b - a;
      final outward = edge.cross(vm.Vector3(0, 1, 0))..normalize();
      final ua = uvs[order[k]], ub = uvs[order[(k + 1) % order.length]];
      final v0 = vertex(a + vm.Vector3(0, half, 0), outward, ua);
      final v1 = vertex(b + vm.Vector3(0, half, 0), outward, ub);
      final v2 = vertex(b - vm.Vector3(0, half, 0), outward, ub);
      final v3 = vertex(a - vm.Vector3(0, half, 0), outward, ua);
      // Winding so the face's normal matches outward.
      final face = (b - a).cross(vm.Vector3(0, -thickness, 0));
      if (face.dot(outward) > 0) {
        indices.addAll([v0, v1, v2, v0, v2, v3]);
      } else {
        indices.addAll([v0, v2, v1, v0, v3, v2]);
      }
    }
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      texCoords: Float32List.fromList(texCoords),
      indices: indices,
    );
  }

  void _setCardCollider(int index, bool present) {
    if (index >= _cardColliders.length) return;
    final node = _cardColliders[index];
    if (node == null) return;
    if (present && node.parent == null) scene.add(node);
    if (!present && node.parent != null) scene.remove(node);
  }

  /// Fires the slow-motion beat the moment a match shows while the dice are
  /// still coming to rest.
  void _watchForMatch() {
    if (!_rolling || _slowFired || _rollTime < 0.5 || _dice.length < 2) return;
    var fastest = 0.0;
    for (final die in _dice) {
      fastest = math.max(fastest, die.body.linearVelocity.length);
      if (die.node.localTransform.getTranslation().y > _dieHalf * 1.4) return;
    }
    // Still moving a little, so the slow motion has something to show.
    if (fastest > 2.4 || fastest < 0.25) return;
    final faces = [for (final d in _dice) _topFace(d.node)];
    if (Celebration.multiplierOf(faces) < 2) return;
    _slowFired = true;
    _slowUntil = _realTime + 0.9;
    _kickShake(0.3);
    _playFx('slowmo', volume: 0.8);
    final matched = Celebration.matchedIndices(faces);
    final center = matched.fold(
      vm.Vector3.zero(),
      (sum, i) => sum + _dice[i].node.localTransform.getTranslation(),
    )..scale(1 / matched.length);
    _vfx.shockwave(
      _screenUv(_camera.worldToScreen(center, _viewSize) ?? Offset.zero),
      strength: 0.02,
    );
  }

  /// Publishes where the dice sit and hit, in global coordinates, for the
  /// widgets under them.
  void _publishContacts(double dt) {
    final time = _contacts.value.time + dt;
    _hits.removeWhere((hit) => time - hit.time > 1.2);
    final resting = <(Offset, double)>[];
    for (final die in _dice) {
      final at = die.node.localTransform.getTranslation();
      if (at.y > _dieHalf * 1.6 + 0.15) continue;
      if (die.body.linearVelocity.length > 0.3) continue;
      resting.add((
        _toGlobal(_screenPositionOf(die)),
        _dieHalf * _pixelsPerUnit,
      ));
    }
    _contacts.value = DiceContacts(
      resting: resting,
      hits: List.of(_hits),
      time: time,
    );
  }

  Offset _toGlobal(Offset viewLocal) {
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    return view?.localToGlobal(viewLocal) ?? viewLocal;
  }

  Offset _toView(Offset global) {
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    return view?.globalToLocal(global) ?? global;
  }

  /// Keeps a glass die's caustic under it, thrown along the light.
  void _placeCaustic(_Die die) {
    final caustic = die.caustic;
    if (caustic == null) return;
    final at = die.node.localTransform.getTranslation();
    // Which way the light comes from, and how steeply.
    vm.Vector3 toLight;
    if (_kind == _LightKind.directional) {
      toLight = vm.Vector3(
        math.cos(_sunAzimuth) * math.cos(_sunElevation),
        math.sin(_sunElevation),
        math.sin(_sunAzimuth) * math.cos(_sunElevation),
      );
    } else {
      toLight = (_lampPosition - at)..normalize();
    }
    final elevation = math.asin(toLight.y.clamp(-1.0, 1.0));
    final tangent = math.max(math.tan(elevation), 0.2);
    final horizontal = vm.Vector2(toLight.x, toLight.z);
    if (horizontal.length > 1e-4) horizontal.normalize();
    final throwDistance = math.min(
      (_dieHalf * 0.7 + at.y) / tangent,
      _dieHalf * 2.5,
    );
    final position = vm.Vector3(
      at.x - horizontal.x * throwDistance,
      0,
      at.z - horizontal.y * throwDistance,
    );
    // Fades as the die lifts off, brightest under a low light.
    final lift = ((at.y - _dieHalf) / (_dieHalf * 1.5)).clamp(0.0, 1.0);
    final intensity =
        (1 - lift) * (0.45 + 0.55 * (1 - elevation / (math.pi / 2)));
    _vfx.placeCaustic(caustic, position, _dieHalf * 2.4, intensity, _realTime);
  }

  /// Leaves ink where a die scuffs along the table.
  void _skid(_Die die) {
    final at = die.node.localTransform.getTranslation();
    if (at.y > _dieHalf * 1.1) return;
    final v = die.body.linearVelocity;
    final along = vm.Vector2(v.x, v.z);
    if (along.length < 2.5) return;
    if (_realTime - die.lastSkidTime < 0.035) return;
    die.lastSkidTime = _realTime;
    final a = _camera.worldToScreen(at, _viewSize);
    final b = _camera.worldToScreen(at + v, _viewSize);
    if (a == null || b == null) return;
    final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    _vfx.skid(at, angle, die.color, _dieHalf * 1.2);
  }

  /// Raised slabs where the screen's cards and button are, so dice bounce
  /// off their edges and come to rest on them.
  void _rebuildUiBounds() {
    final rects = [..._cardRects, if (_buttonRect != null) _buttonRect!];
    final key = rects.map((r) => r.toString()).join();
    if (key == _uiBoundsKey || _viewSize.isEmpty) return;
    _uiBoundsKey = key;
    for (final node in _uiBounds) {
      if (node.parent != null) scene.remove(node);
    }
    _uiBounds.clear();
    _cardColliders.clear();
    const thickness = 0.12;
    for (final rect in rects) {
      final center = _floorHit(rect.center);
      final node = Node(
        localTransform: vm.Matrix4.translation(
          vm.Vector3(center.x, thickness / 2, center.z),
        ),
      );
      node.addComponent(RigidBody(type: BodyType.fixed));
      node.addComponent(
        Collider(
          shape: BoxShape(
            halfExtents: vm.Vector3(
              rect.width / _pixelsPerUnit / 2,
              thickness / 2,
              rect.height / _pixelsPerUnit / 2,
            ),
          ),
          material: const PhysicsMaterial(friction: 0.55, restitution: 0.3),
        ),
      );
      // A broken card's socket has no top to land on.
      final cardIndex = _uiBounds.length;
      final broken =
          cardIndex < _cardRects.length &&
          (_breakRuns[cardIndex]?.shattered ?? false) &&
          !(_breakRuns[cardIndex]?.rebuilding ?? false);
      if (!broken) scene.add(node);
      _uiBounds.add(node);
      if (cardIndex < _cardRects.length) _cardColliders.add(node);
    }
    // The pill's glow and the sticker's flash sit over their widgets.
    final button = _buttonRect;
    if (button != null) {
      _buttonLightNode.localTransform = vm.Matrix4.translation(
        _floorHit(button.center) + vm.Vector3(0, 1.1, 0),
      );
    }
    final banner = _bannerCenter;
    if (banner != null) {
      _stickerLightNode.localTransform = vm.Matrix4.translation(
        _floorHit(banner) + vm.Vector3(0, 1.6, 0),
      );
    }
  }

  void _onScreenLayout(DiceScreenLayout layout) {
    _bannerCenter = _toView(layout.banner);
    if (!_viewSize.isEmpty) {
      _flight.value = _bannerCenter! - _viewSize.center(Offset.zero);
    }
    _cardRects = [
      for (final rect in layout.cards)
        Rect.fromPoints(_toView(rect.topLeft), _toView(rect.bottomRight)),
    ];
    final button = layout.button;
    _buttonRect = Rect.fromPoints(
      _toView(button.topLeft),
      _toView(button.bottomRight),
    );
    _rebuildUiBounds();
  }

  static vm.Vector3 _linear(Color color) {
    double channel(double c) => c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return vm.Vector3(channel(color.r), channel(color.g), channel(color.b));
  }

  void _removeDie(_Die die) {
    final caustic = die.caustic;
    if (caustic != null) _vfx.removeCaustic(caustic);
    scene.remove(die.node);
  }

  // --- Scoring ----------------------------------------------------------------

  /// Counts the settled dice left to right across the screen.
  void _startCelebration(List<int> faces) {
    final order = List<int>.generate(_dice.length, (i) => i);
    order.sort((a, b) {
      final pa = _screenPositionOf(_dice[a]);
      final pb = _screenPositionOf(_dice[b]);
      return pa.dx.compareTo(pb.dx);
    });
    _celebration = Celebration(
      faces: faces,
      order: order,
      total: _total,
      frame: _frame,
    );
  }

  void _endCelebration() {
    if (_celebration == null) return;
    _celebration = null;
    for (final die in _dice) {
      die.visual.highlightColor = null;
    }
    _frame.value = CelebrationFrame(total: _total);
  }

  void _advanceCelebration(double dt) {
    final celebration = _celebration;
    if (celebration == null) return;
    for (final event in celebration.advance(dt)) {
      switch (event) {
        case DieCounted(:final index, :final ordinal):
          final die = _dice[index];
          final position = _dieTop(die);
          die.visual.highlightColor = _highlightFor(die);
          _vfx.sparkle(position, die.color, scale: _dieHalf / 0.35);
          _playFx(
            ordinal.isEven ? 'tick_a' : 'tick_b',
            volume: 0.85,
            pitch: 1.0 + 0.09 * ordinal,
            position: position,
          );
          if (ordinal == 0) _playFx('riser', volume: 0.5);
        case MultiplierRevealed(:final matchedIndices):
          for (final index in matchedIndices) {
            final die = _dice[index];
            die.visual.highlightColor = vm.Vector4(1.0, 0.95, 0.75, 1.0);
            _vfx.emberRing(_dieTop(die)..y = 0.05, die.color);
          }
          _vfx.shockwave(
            _screenUv(_viewSize.center(Offset.zero)),
            strength: 0.02,
          );
          _kickShake(0.35);
          _playFx('multiplier', volume: 1.0);
        case SlamLaunched():
          _playFx('throw', volume: 0.45, pitch: 1.5);
        case SlamLanded(:final scored, :final total):
          _total = total;
          debugPrint(
            'dice: rolled ${_lastRoll.value?.join('+')} '
            'x${celebration.multiplier} = $scored, total $total, '
            'slam to $_bannerCenter in $_viewSize',
          );
          _history.value = [
            (
              faces: _lastRoll.value ?? const [],
              multiplier: celebration.multiplier,
              scored: scored,
            ),
            ..._history.value.take(4),
          ];
          final banner = _bannerWorldPosition();
          final loud = celebration.multiplier > 1;
          _stickerFlash = 1.0;
          // Fire toward the camera, so the pop stays over the sticker as the
          // pieces rise instead of drifting outward in perspective.
          _vfx.confetti(banner, [
            for (final color in _theme.confetti) _linearColor(color),
            if (loud) _linearColor(_theme.confetti[_vfxRandom.nextInt(4)]),
          ], axis: (_camera.position - banner).normalized());
          _vfx.ringPulse(
            banner..y = 0.0,
            vm.Vector4(1.0, 0.8, 0.3, 1.0),
            radius: 3.5,
          );
          _vfx.shockwave(
            _screenUv(
              _camera.worldToScreen(banner, _viewSize) ??
                  _viewSize.center(Offset.zero),
            ),
            strength: loud ? 0.045 : 0.03,
          );
          _kickShake(loud ? 1.0 : 0.7);
          _playFx('slam', volume: 1.0);
          _playFx(
            'fanfare',
            volume: loud ? 1.0 : 0.6,
            pitch: loud ? 1.0 : 1.06,
          );
          _escalate(celebration.multiplier, celebration.matched);
        case CelebrationEnded():
          _endCelebration();
      }
    }
  }

  static vm.Vector4 _linearColor(Color color) {
    final c = _linear(color);
    return vm.Vector4(c.x, c.y, c.z, 1.0);
  }

  vm.Vector4 _highlightFor(_Die die) {
    final c = die.color;
    // Glass and metal dice are lit from inside the outline's color, so keep
    // it warm and bright rather than tinting them.
    if (die.finish.isGlass || die.finish == DiceFinish.gold) {
      return vm.Vector4(1.0, 0.85, 0.45, 1.0);
    }
    return vm.Vector4(0.4 + 0.6 * c.x, 0.4 + 0.6 * c.y, 0.4 + 0.6 * c.z, 1.0);
  }

  vm.Vector3 _dieTop(_Die die) =>
      die.node.globalTransform.getTranslation() + vm.Vector3(0, _dieHalf, 0);

  Offset _screenPositionOf(_Die die) =>
      _camera.worldToScreen(
        die.node.globalTransform.getTranslation(),
        _viewSize,
      ) ??
      Offset.zero;

  vm.Vector2 _screenUv(Offset position) => vm.Vector2(
    (position.dx / _viewSize.width).clamp(0.0, 1.0),
    (position.dy / _viewSize.height).clamp(0.0, 1.0),
  );

  /// The floor point under the score banner, where the confetti pops from.
  vm.Vector3 _bannerWorldPosition() =>
      _floorHit(_bannerCenter ?? _viewSize.center(Offset.zero))..y = 0.05;

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
        // The die's own material speaks on the table, when it has a voice.
        final landing = die.finish.landingSet;
        set = landing != null && _impactClips.containsKey('land_$landing')
            ? 'land_$landing'
            : (_surface == _Surface.glass ? 'glass' : 'table');
        final screen =
            _camera.worldToScreen(position, _viewSize) ?? Offset.zero;
        _hits.add(
          DiceHit(
            _toGlobal(screen),
            (strength / 12.0).clamp(0.15, 1.0),
            _contacts.value.time,
          ),
        );
        // A hard enough landing on a card cracks it.
        if (strength > 11.0) {
          for (var i = 0; i < _cardRects.length; i++) {
            final rect = _cardRects[i];
            if (!rect.contains(screen)) continue;
            _breakCard(
              i,
              Offset(
                (screen.dx - rect.left) / rect.width,
                (screen.dy - rect.top) / rect.height,
              ),
            );
            break;
          }
        }
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
        // Softer hits ring a little lower; glass rings higher than wood.
        pitch: (0.92 + 0.08 * t + _jitter(0.05)) * die.finish.impactPitch,
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
        final handle = _lightHandlePosition();
        _lightHandleRect = handle == null
            ? Rect.zero
            : Rect.fromCenter(center: handle, width: 64, height: 64);
        final screen = DiceGameScreen(
          theme: _theme,
          onRoll: _roll,
          lastRoll: _lastRoll,
          history: _history,
          frame: _frame,
          contacts: _contacts,
          breaks: _breaks,
          onLayout: _onScreenLayout,
        );
        return ValueListenableBuilder<(Offset, double)>(
          valueListenable: _shakeOffset,
          builder: (context, shake, child) => Transform.translate(
            offset: shake.$1,
            child: Transform.rotate(angle: shake.$2, child: child),
          ),
          child: Stack(
            key: _viewKey,
            children: [
              // The live screen takes the taps. With the backdrop embedded, the
              // scene's copy of it covers this one exactly.
              Positioned.fill(
                child: DiceGameScreen.withRollKey(screen, _rollKey),
              ),
              if (_embedBackdrop)
                // Paints nothing here; it only feeds the capture the scene's
                // backdrop plane samples.
                Positioned.fill(
                  child: WidgetTexture(
                    controller: _capture,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    pixelRatio: MediaQuery.devicePixelRatioOf(context),
                    child: screen,
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
                  onPanStart: (d) => _aimStart(d.localPosition),
                  onPanUpdate: (d) => _aimUpdate(d.localPosition),
                  onPanEnd: (_) => _aimRelease(),
                  onPanCancel: () => _aim.value = null,
                ),
              ),
              // The running number sits over the dice, never under them.
              Positioned.fill(
                child: IgnorePointer(
                  child: ScreenThemeScope(
                    theme: _theme,
                    child: Center(
                      child: ValueListenableBuilder<Offset>(
                        valueListenable: _flight,
                        builder: (context, flight, _) =>
                            RollCounter(frame: _frame, flightOffset: flight),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _AimArrowPainter(
                      aim: _aim,
                      spent: _spentAim,
                      dissolve: _aimDissolve,
                    ),
                  ),
                ),
              ),
              if (handle != null)
                Positioned(
                  left: handle.dx - 32,
                  top: handle.dy - 32,
                  child: LightHandle(
                    glyph: _kind == _LightKind.directional
                        ? LightGlyph.sun
                        : LightGlyph.bulb,
                    onDrag: (global) {
                      final view =
                          _viewKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (view == null) return;
                      _dragLight(view.globalToLocal(global));
                    },
                  ),
                ),
              ExampleOverlay.bottomLeftPanel(child: _buildPanel()),
            ],
          ),
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
      maxBodyHeight: 560,
      body: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Drag to aim, release to throw. Drag the light to move it.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            _FinishPicker(selected: _finish, onChanged: _setFinish),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 64, child: Text('Look')),
                Expanded(
                  child: SegmentedButton<ScreenLook>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      selectedForegroundColor: Colors.black,
                      selectedBackgroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      for (final theme in ScreenTheme.all)
                        ButtonSegment(
                          value: theme.look,
                          label: Text(theme.label),
                        ),
                    ],
                    selected: {_theme.look},
                    onSelectionChanged: (selection) => _setTheme(
                      ScreenTheme.all.firstWhere(
                        (t) => t.look == selection.first,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Copy the screen into the scene, so glass refracts it',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Switch(
                  value: _embedBackdrop,
                  onChanged: _setEmbedBackdrop,
                  activeThumbColor: Colors.white,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Caustics under clear glass dice',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                Switch(
                  value: _caustics,
                  onChanged: _setCaustics,
                  activeThumbColor: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 4),
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
                exampleSettings.lightElevationDegrees,
                7,
                90,
                (v) => exampleSettings.lightElevationDegrees = v,
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
            _slider(
              'Size',
              _dieHalf * 2,
              0.4,
              1.3,
              (v) => _setDieSize(v / 2, commit: false),
              onChangeEnd: (v) => _setDieSize(v / 2, commit: true),
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
    ValueChanged<double>? onChangeEnd,
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
            onChangeEnd: onChangeEnd,
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

/// The grabbable light. It lifts and glows under the cursor, and brightens
/// again while being dragged, so it reads as a handle rather than a label.
///
/// The disc and the glyph are painted opaque into one layer, and the layer is
/// what fades. Fading them separately lets the glyph blend into the disc and
/// go muddy.
class LightHandle extends StatefulWidget {
  const LightHandle({
    super.key,
    required this.glyph,
    required this.onDrag,
    this.emphasisOverride,
  });

  /// Diameter of the hit target.
  static const double hitSize = 64.0;

  /// Diameter of the visible disc at rest.
  static const double discSize = 44.0;

  final LightGlyph glyph;
  final ValueChanged<Offset> onDrag;

  /// Pins the hover/press look, for tests.
  final double? emphasisOverride;

  @override
  State<LightHandle> createState() => _LightHandleState();
}

class _LightHandleState extends State<LightHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    // One value drives every part of the look, so they move together.
    final emphasis =
        widget.emphasisOverride ?? (_dragging ? 1.0 : (_hovered ? 0.55 : 0.0));
    return MouseRegion(
      cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          setState(() => _dragging = true);
          widget.onDrag(d.globalPosition);
        },
        onPanUpdate: (d) => widget.onDrag(d.globalPosition),
        onPanEnd: (_) => setState(() => _dragging = false),
        onPanCancel: () => setState(() => _dragging = false),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: emphasis),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) {
            return SizedBox(
              width: LightHandle.hitSize,
              height: LightHandle.hitSize,
              // Opacity draws its subtree into a layer and fades that, so the
              // glyph never mixes with the disc under it.
              child: Opacity(
                opacity: 0.45 + 0.55 * t,
                child: CustomPaint(
                  painter: _LightHandlePainter(
                    glyph: widget.glyph,
                    emphasis: t,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Which light the handle stands for.
enum LightGlyph { sun, bulb }

/// Paints the disc and its glyph. The glyph is a path centred on its own
/// bounds, so it never depends on an icon font's metrics.
class _LightHandlePainter extends CustomPainter {
  _LightHandlePainter({required this.glyph, required this.emphasis});

  final LightGlyph glyph;
  final double emphasis;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final scale = 1.0 + 0.16 * emphasis;
    final radius = LightHandle.discSize / 2 * scale;
    final amber = Color.lerp(
      const Color(0xFFFFB524),
      const Color(0xFFFFF4D2),
      emphasis,
    )!;

    // Glow, dark halo, disc, rim.
    canvas.drawCircle(
      center,
      radius + 2,
      Paint()
        ..color = amber.withValues(alpha: 0.22 + 0.40 * emphasis)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 + 16.0 * emphasis),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25 + 0.20 * emphasis)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Color.lerp(
          const Color(0xFF241A0C),
          const Color(0xFF2E1F06),
          emphasis,
        )!,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + 0.5 * emphasis
        ..color = amber.withValues(alpha: 0.45 + 0.55 * emphasis),
    );

    final path = glyph == LightGlyph.sun
        ? _sunPath(30 * scale)
        : _bulbPath(30 * scale);
    // Sit the drawing in the middle of the disc by its own extents.
    final bounds = path.getBounds();
    canvas.save();
    canvas.translate(
      center.dx - bounds.center.dx,
      center.dy - bounds.center.dy,
    );
    canvas.drawPath(path, Paint()..color = amber);
    canvas.restore();
  }

  /// A round sun with eight rays.
  Path _sunPath(double size) {
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: size * 0.21));
    final ray = RRect.fromRectAndRadius(
      Rect.fromLTWH(-size * 0.045, -size * 0.50, size * 0.09, size * 0.15),
      Radius.circular(size * 0.045),
    );
    for (var i = 0; i < 8; i++) {
      final spoke = Path()..addRRect(ray);
      path.addPath(
        spoke.transform((Matrix4.identity()..rotateZ(i * math.pi / 4)).storage),
        Offset.zero,
      );
    }
    return path;
  }

  /// A bulb with a screw base.
  Path _bulbPath(double size) {
    final glass = Rect.fromCircle(
      center: Offset(0, -size * 0.10),
      radius: size * 0.26,
    );
    final path = Path()..addOval(glass);
    // Neck into the base.
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-size * 0.13, size * 0.10, size * 0.26, size * 0.12),
        Radius.circular(size * 0.03),
      ),
    );
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-size * 0.10, size * 0.24, size * 0.20, size * 0.10),
        Radius.circular(size * 0.04),
      ),
    );
    return path;
  }

  @override
  bool shouldRepaint(_LightHandlePainter oldDelegate) =>
      oldDelegate.emphasis != emphasis || oldDelegate.glyph != glyph;
}

/// Draws the aim arrow under the finger, and the spent one dissolving forward
/// after the throw. Both are repainted from their own listenables so dragging
/// never rebuilds the scene.
class _AimArrowPainter extends CustomPainter {
  _AimArrowPainter({
    required this.aim,
    required this.spent,
    required this.dissolve,
  }) : super(repaint: Listenable.merge([aim, spent, dissolve]));

  final ValueListenable<_Aim?> aim;
  final ValueListenable<_Aim?> spent;
  final AnimationController dissolve;

  static const _weak = Color(0xFFFFE9A8);
  static const _strong = Color(0xFFFF5A3C);

  @override
  void paint(Canvas canvas, Size size) {
    final live = aim.value;
    if (live != null) _drawArrow(canvas, live, 1.0, 0.0);
    final gone = spent.value;
    if (gone != null) _drawArrow(canvas, gone, 1.0, dissolve.value);
  }

  /// [decay] slides the arrow apart and fades it, 0 while the finger is down.
  void _drawArrow(Canvas canvas, _Aim arrow, double opacity, double decay) {
    final delta = arrow.delta;
    final length = delta.distance;
    if (length < 1) return;
    final direction = delta / length;
    final strength = arrow.strength;
    final color = Color.lerp(_weak, _strong, strength)!;
    final width = 5.0 + 9.0 * strength;

    // Fade the arrow as one layer. Drawing the pieces individually translucent
    // shows every overlap between them.
    final alpha = opacity * (1.0 - decay).clamp(0.0, 1.0);
    if (alpha <= 0) return;
    final bounds = Rect.fromPoints(
      arrow.start,
      arrow.end,
    ).inflate(120.0 + decay * 120.0);
    canvas.saveLayer(
      bounds,
      Paint()..color = const Color(0xFF000000).withValues(alpha: alpha),
    );

    // One stroke, never pieces. As it goes the whole arrow drifts along the
    // aim and the tail is eaten away behind it.
    final headLength = math.min(34.0 + 18.0 * strength, length * 0.5);
    final shaft = length - headLength;
    final drift = decay * 26.0;
    final tail = shaft * decay;
    if (shaft > tail) {
      canvas.drawLine(
        arrow.start + direction * (tail + drift),
        arrow.start + direction * (shaft + drift),
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.6 + decay * 3.0),
      );
    }

    final tip = arrow.end + direction * drift;
    final back = tip - direction * headLength;
    final side = Offset(-direction.dy, direction.dx) * (headLength * 0.42);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + side.dx, back.dy + side.dy)
      ..lineTo(
        back.dx + direction.dx * headLength * 0.25,
        back.dy + direction.dy * headLength * 0.25,
      )
      ..lineTo(back.dx - side.dx, back.dy - side.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.8 + decay * 4.0),
    );

    // The anchor belongs to the finger, so it goes the moment the throw does.
    if (decay == 0) {
      canvas.drawCircle(
        arrow.start,
        6.0 + 3.0 * strength,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AimArrowPainter oldDelegate) => false;
}

/// One swatch per finish, plus the mix.
class _FinishPicker extends StatelessWidget {
  const _FinishPicker({required this.selected, required this.onChanged});

  final DiceFinish selected;
  final ValueChanged<DiceFinish> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 64, child: Text('Dice')),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final finish in DiceFinish.values)
                Tooltip(
                  message: finish.label,
                  waitDuration: const Duration(milliseconds: 300),
                  child: GestureDetector(
                    onTap: () => onChanged(finish),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: finish == DiceFinish.mixed
                            ? const SweepGradient(
                                colors: [
                                  Color(0xFFE85D4A),
                                  Color(0xFFE0B04A),
                                  Color(0xFF3CF2B0),
                                  Color(0xFF6FA8FF),
                                  Color(0xFFC9B6F0),
                                  Color(0xFFE85D4A),
                                ],
                              )
                            : null,
                        color: finish == DiceFinish.mixed
                            ? null
                            : finish.swatch,
                        border: Border.all(
                          color: finish == selected
                              ? Colors.white
                              : Colors.white24,
                          width: finish == selected ? 2.5 : 1,
                        ),
                        boxShadow: finish == selected
                            ? [
                                BoxShadow(
                                  color: finish.swatch.withValues(alpha: 0.7),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The ordinary app screen the dice roll over. Built twice when the backdrop
/// is embedded (once live for input, once captured for the scene), so it
/// carries no state of its own beyond the banner measurement. Public so a
/// test can render it without a scene.
/// Where the screen's pieces landed, in global coordinates.
class DiceScreenLayout {
  const DiceScreenLayout({
    required this.cards,
    required this.button,
    required this.banner,
  });

  final List<Rect> cards;
  final Rect button;
  final Offset banner;
}

/// The ordinary app screen the dice roll over. Built twice when the backdrop
/// is embedded (once live for input, once captured for the scene), so it
/// carries no state of its own beyond the layout measurement. Public so a
/// test can render it without a scene.
class DiceGameScreen extends StatefulWidget {
  const DiceGameScreen({
    super.key,
    this.rollKey,
    required this.theme,
    required this.onRoll,
    required this.lastRoll,
    required this.history,
    required this.frame,
    required this.contacts,
    required this.breaks,
    this.onLayout,
  });

  /// The same screen with the roll button keyed, for the live copy. Only
  /// the live copy reports its layout.
  static DiceGameScreen withRollKey(DiceGameScreen screen, GlobalKey rollKey) =>
      DiceGameScreen(
        rollKey: rollKey,
        theme: screen.theme,
        onRoll: screen.onRoll,
        lastRoll: screen.lastRoll,
        history: screen.history,
        frame: screen.frame,
        contacts: screen.contacts,
        breaks: screen.breaks,
        onLayout: screen.onLayout,
      );

  final GlobalKey? rollKey;
  final ScreenTheme theme;
  final VoidCallback onRoll;
  final ValueListenable<List<int>?> lastRoll;
  final ValueListenable<List<RollRecord>> history;
  final ValueListenable<CelebrationFrame> frame;
  final ValueListenable<DiceContacts> contacts;
  final CardBreakController breaks;

  /// Reports where the cards, the button, and the banner landed after
  /// layout, so the host can build colliders and aim effects at them.
  final ValueChanged<DiceScreenLayout>? onLayout;

  @override
  State<DiceGameScreen> createState() => DiceGameScreenState();
}

class DiceGameScreenState extends State<DiceGameScreen>
    with SingleTickerProviderStateMixin {
  // A slow loop the background drifts and the sticker rocks on.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();
  final GlobalKey _bannerKey = GlobalKey();
  final List<GlobalKey> _cardKeys = [for (var i = 0; i < 4; i++) GlobalKey()];
  final List<GlobalKey> _captureKeys = [
    for (var i = 0; i < 4; i++) GlobalKey(),
  ];
  final GlobalKey _buttonKey = GlobalKey();
  DiceScreenLayout? _reported;

  // The cards keep to a column on the left, so the dice have pattern to land
  // on and glass has something to bend.
  static const double _columnWidth = 400;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final insets = ExampleOverlay.safeInsetsOf(context);
    final theme = widget.theme;
    return ScreenThemeScope(
      theme: theme,
      child: Stack(
        children: [
          Positioned.fill(child: ThemedBackground(animation: _clock)),
          Padding(
            padding: EdgeInsets.fromLTRB(28, insets.top + 64, 28, 0),
            // A short window lets the column run off the bottom rather than
            // assert; nothing here scrolls.
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const OutlinedText('Game night', size: 56),
                            const SizedBox(height: 6),
                            Text(
                              'Round 3, your turn',
                              style: theme.labelStyle.copyWith(
                                fontSize: 18,
                                color: theme.look == ScreenLook.pop
                                    ? theme.ink
                                    : theme.cream,
                              ),
                            ),
                          ],
                        ),
                      ),
                      KeyedSubtree(
                        key: _bannerKey,
                        child: ScoreBanner(frame: widget.frame, clock: _clock),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _columnWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _pressable(
                                0,
                                _PlayerCard(
                                  name: 'Ava',
                                  score: 42,
                                  color: theme.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _pressable(
                                1,
                                _PlayerCard(
                                  name: 'Theo',
                                  score: 37,
                                  color: theme.accent2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _pressable(2, _LastRollCard(lastRoll: widget.lastRoll)),
                        const SizedBox(height: 20),
                        _pressable(3, _HistoryCard(history: widget.history)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 32,
            bottom: insets.bottom + 32,
            child: Pressable(
              contacts: widget.contacts,
              child: KeyedSubtree(
                key: _buttonKey,
                child: KeyedSubtree(
                  key: widget.rollKey,
                  child: PopButton(label: 'Roll', onPressed: widget.onRoll),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pressable(int index, Widget child) => Pressable(
    contacts: widget.contacts,
    child: KeyedSubtree(
      key: _cardKeys[index],
      child: widget.rollKey == null
          // The captured copy shows the socket too, but only the live copy
          // supplies the shards' pixels.
          ? Breakable(
              index: index,
              controller: widget.breaks,
              captureKey: GlobalKey(),
              child: child,
            )
          : Breakable(
              index: index,
              controller: widget.breaks,
              captureKey: _captureKeys[index],
              child: child,
            ),
    ),
  );

  static Rect? _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _measure() {
    if (!mounted || widget.rollKey == null) return;
    final banner = _globalRect(_bannerKey);
    final button = _globalRect(_buttonKey);
    if (banner == null || button == null) return;
    final cards = [
      for (final key in _cardKeys)
        if (_globalRect(key) case final rect?) rect,
    ];
    final layout = DiceScreenLayout(
      cards: cards,
      button: button,
      banner: banner.center,
    );
    final last = _reported;
    if (last != null &&
        last.banner == layout.banner &&
        last.button == layout.button &&
        last.cards.length == layout.cards.length &&
        [
          for (var i = 0; i < cards.length; i++) last.cards[i] == cards[i],
        ].every((same) => same)) {
      return;
    }
    _reported = layout;
    widget.onLayout?.call(layout);
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
    final theme = ScreenTheme.of(context);
    return PopCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // A sticker avatar with the player's initial.
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.ink, width: 2.5),
            ),
            alignment: Alignment.center,
            child: OutlinedText(name[0], size: 30, shadow: false),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.labelStyle.copyWith(fontSize: 18)),
              Text(
                '$score',
                style: theme.labelStyle.copyWith(
                  fontSize: 30,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The faces of the roll being scored, and their sum on a colored block.
class _LastRollCard extends StatelessWidget {
  const _LastRollCard({required this.lastRoll});

  final ValueListenable<List<int>?> lastRoll;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    return ValueListenableBuilder<List<int>?>(
      valueListenable: lastRoll,
      builder: (context, faces, _) {
        final total = faces?.fold(0, (a, b) => a + b);
        final light = theme.score.computeLuminance() > 0.5;
        return PopCard(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(theme.radius - theme.stroke),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Last roll',
                            style: theme.labelStyle.copyWith(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          if (faces == null)
                            Text(
                              'Rolling...',
                              style: theme.smallStyle.copyWith(fontSize: 15),
                            )
                          else
                            _PipRow(faces, size: 28),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 112,
                    decoration: BoxDecoration(
                      color: theme.score,
                      border: Border(
                        left: BorderSide(color: theme.ink, width: theme.stroke),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: OutlinedText(
                      total == null ? '-' : '$total',
                      size: 54,
                      shadow: false,
                      letterSpacing: -2,
                      fill: light ? theme.cream : theme.cream,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Recent rolls as pips, with the multiplier and what they scored.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final ValueListenable<List<RollRecord>> history;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    return PopCard(
      child: ValueListenableBuilder<List<RollRecord>>(
        valueListenable: history,
        builder: (context, entries, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Roll history',
              style: theme.labelStyle.copyWith(fontSize: 18),
            ),
            for (final entry in entries) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _PipRow(entry.faces, size: 22)),
                  if (entry.multiplier > 1)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.accent2,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: theme.ink, width: 2),
                      ),
                      child: Text(
                        'x${entry.multiplier}',
                        style: theme.smallStyle.copyWith(color: theme.cream),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Text(
                    '${entry.scored}',
                    style: theme.labelStyle.copyWith(fontSize: 18),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Die faces joined by plus signs.
class _PipRow extends StatelessWidget {
  const _PipRow(this.faces, {required this.size});

  final List<int> faces;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 5,
      runSpacing: 4,
      children: [
        for (var i = 0; i < faces.length; i++) ...[
          if (i > 0)
            Text('+', style: theme.labelStyle.copyWith(fontSize: size * 0.6)),
          PipFace(faces[i], size: size),
        ],
      ],
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
