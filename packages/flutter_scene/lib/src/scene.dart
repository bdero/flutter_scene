import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Matrix3, Ray;
import 'ambient_occlusion.dart';
import 'camera.dart';
import 'components/directional_light_component.dart';
import 'light.dart';
import 'material/environment.dart';
import 'material/material.dart';
import 'mesh.dart';
import 'node.dart';
import 'raycast.dart';
import 'physics/physics_world.dart';
import 'environment_settings.dart';
import 'environment_volume.dart';
import 'post_process/post_effect.dart';
import 'post_process/post_process.dart';
import 'render/bloom_pass.dart';
import 'render/custom_render_pass.dart';
import 'render/depth_prepass.dart';
import 'render/fxaa_pass.dart';
import 'render/post_effect_pass.dart';
import 'render/render_graph.dart';
import 'render/render_scene.dart';
import 'render/instance_packing.dart';
import 'render/scene_pass.dart';
import 'render/selection_outline_pass.dart';
import 'render/shadow_pass.dart';
import 'render/ssao_pass.dart';
import 'render/resolve_pass.dart';
import 'render_texture.dart';
import 'render_view.dart';
import 'shaders.dart';
import 'sky_environment.dart';
import 'skybox.dart';
import 'sun_light.dart';
import 'surface.dart';
import 'tone_mapping.dart';

/// Defines a common interface for managing a scene graph, allowing the addition and removal of [Nodes].
///
/// `SceneGraph` provides a set of methods that can be implemented by a class
/// to manage a hierarchy of nodes within a 3D scene.
/// {@category Scene graph}
mixin SceneGraph {
  /// Add a child node.
  void add(Node child);

  /// Add a list of child nodes.
  void addAll(Iterable<Node> children);

  /// Add a mesh as a child node.
  void addMesh(Mesh mesh);

  /// Remove a child node.
  void remove(Node child);

  /// Remove all children nodes.
  void removeAll();
}

/// Anti-aliasing strategy used when rendering a [Scene].
///
/// Set on a [Scene] via [Scene.antiAliasingMode]. The default is [auto],
/// which selects [msaa] when the GPU backend supports offscreen MSAA and
/// [fxaa] otherwise, so every backend gets anti-aliasing out of the box.
/// Query support with [Scene.isAntiAliasingModeSupported] and read the
/// technique that actually runs from [Scene.effectiveAntiAliasingMode].
/// {@category Scene graph}
enum AntiAliasingMode {
  /// No anti-aliasing. Geometry edges are rendered at the render target's
  /// native resolution.
  none,

  /// 4x multi-sample anti-aliasing on the scene pass. The highest quality
  /// option for geometry edges, and cheap on mobile GPUs. Not supported
  /// on every Flutter GPU backend; where it is unavailable, rendering
  /// falls back to [fxaa] (see [Scene.effectiveAntiAliasingMode]).
  msaa,

  /// Fast approximate anti-aliasing, a single post-process pass over the
  /// tone-mapped image. Supported on every backend. Softens all
  /// high-contrast edges, including texture detail, so prefer [msaa]
  /// where it is available.
  fxaa,

  /// Selects [msaa] when the backend supports it and [fxaa] otherwise.
  auto,
}

/// Represents a 3D scene, which is a collection of nodes that can be rendered onto the screen.
///
/// `Scene` manages the scene graph and handles rendering operations.
/// It contains a root [Node] that serves as the entry point for all nodes in this `Scene`, and
/// it provides methods for adding and removing nodes from the scene graph.
/// {@category Scene graph}
base class Scene implements SceneGraph {
  Scene() {
    initializeStaticResources();
    root.registerAsRoot(this);
  }

  static Future<void>? _initializeStaticResources;
  static bool _readyToRender = false;

  /// Computes the linear exposure multiplier for a physical pinhole
  /// camera, the way photographers reason about it: [aperture] (f-stops),
  /// [shutterSpeed] (seconds), and sensor [iso].
  ///
  /// Returns `1 / (1.2 * 2^EV100)` with
  /// `EV100 = log2(aperture^2 / shutterSpeed * 100 / iso)`, matching
  /// Filament's exposure model. Assign the result to [exposure].
  ///
  /// Reference values (sunlit exterior): `aperture: 16, shutterSpeed:
  /// 1/125, iso: 100`. Lower the aperture or ISO, or lengthen the
  /// shutter, to brighten.
  static double physicalCameraExposure({
    required double aperture,
    required double shutterSpeed,
    required double iso,
  }) {
    final ev100 =
        math.log(aperture * aperture / shutterSpeed * 100.0 / iso) / math.ln2;
    return 1.0 / (1.2 * math.pow(2.0, ev100));
  }

  // Resolved once at construction; the capability is fixed per context, so
  // this avoids a backend query per frame. The eager read also makes
  // Scene() fail fast when no usable Flutter GPU context exists, which the
  // GPU-gated test suites rely on to skip without a device.
  final bool _offscreenMsaaSupported = gpu.gpuContext.doesSupportOffscreenMSAA;

  AntiAliasingMode _antiAliasingMode = AntiAliasingMode.auto;
  bool _warnedUnsupportedAntiAliasing = false;

  /// The requested anti-aliasing strategy for this [Scene].
  ///
  /// Defaults to [AntiAliasingMode.auto]. The requested mode is always
  /// kept; when it isn't supported by the active Flutter GPU backend
  /// (currently only [AntiAliasingMode.msaa] can be unsupported),
  /// rendering uses [AntiAliasingMode.fxaa] instead and a warning is
  /// printed once in debug mode. Read [effectiveAntiAliasingMode] for the
  /// technique that actually runs, and check support up front with
  /// [isAntiAliasingModeSupported].
  set antiAliasingMode(AntiAliasingMode value) {
    _antiAliasingMode = value;
    final supported = value != AntiAliasingMode.msaa || _offscreenMsaaSupported;
    if (!supported && !_warnedUnsupportedAntiAliasing) {
      _warnedUnsupportedAntiAliasing = true;
      debugPrint(
        'Scene.antiAliasingMode: $value is not supported by the active GPU '
        'backend; rendering with $effectiveAntiAliasingMode instead. Use '
        'Scene.isAntiAliasingModeSupported to query support.',
      );
    }
  }

  AntiAliasingMode get antiAliasingMode {
    return _antiAliasingMode;
  }

  /// The anti-aliasing technique that actually runs when this [Scene]
  /// renders.
  ///
  /// Resolves the requested [antiAliasingMode] against backend support:
  /// [AntiAliasingMode.auto] becomes [AntiAliasingMode.msaa] where
  /// offscreen MSAA is supported and [AntiAliasingMode.fxaa] otherwise,
  /// and an unsupported [AntiAliasingMode.msaa] request also resolves to
  /// [AntiAliasingMode.fxaa]. Never returns [AntiAliasingMode.auto].
  AntiAliasingMode get effectiveAntiAliasingMode =>
      _resolveAntiAliasingMode(_antiAliasingMode);

  AntiAliasingMode _resolveAntiAliasingMode(AntiAliasingMode requested) {
    switch (requested) {
      case AntiAliasingMode.none:
        return AntiAliasingMode.none;
      case AntiAliasingMode.fxaa:
        return AntiAliasingMode.fxaa;
      case AntiAliasingMode.msaa:
      case AntiAliasingMode.auto:
        return _offscreenMsaaSupported
            ? AntiAliasingMode.msaa
            : AntiAliasingMode.fxaa;
    }
  }

  /// Whether [mode] is supported by the active Flutter GPU backend.
  ///
  /// Every mode except [AntiAliasingMode.msaa] is supported everywhere;
  /// MSAA requires offscreen MSAA support, which a subset of GLES-only
  /// devices lacks. [AntiAliasingMode.auto] always reports supported
  /// since it resolves to a supported technique by definition. Useful for
  /// building settings UI without touching the Flutter GPU API directly.
  static bool isAntiAliasingModeSupported(AntiAliasingMode mode) {
    return mode != AntiAliasingMode.msaa ||
        gpu.gpuContext.doesSupportOffscreenMSAA;
  }

  double _renderScale = 1.0;

  /// Scales the resolution screen views render at, relative to the
  /// display's native resolution. Defaults to `1.0`.
  ///
  /// Values below `1.0` trade sharpness for proportionally less fragment
  /// work on every device (the multiplier applies on top of the device
  /// pixel ratio, so the cost saving is display-relative); values above
  /// `1.0` supersample. Combine a low scale with
  /// [FilterQuality.none] in [filterQuality] for a pixelated look.
  ///
  /// Per-view overrides via `RenderView.renderScale`. Ignored by views
  /// targeting a `RenderTexture`, whose resolution is the texture's
  /// explicit size. Changing the scale reallocates the view's swapchain
  /// at the new size, so treat it as a settings-style knob rather than a
  /// per-frame animation target.
  double get renderScale => _renderScale;

  set renderScale(double value) {
    assert(
      value.isFinite && value > 0.0,
      'renderScale must be a positive, finite number.',
    );
    _renderScale = value;
  }

  /// The sampling quality used when compositing screen views onto the
  /// canvas. Defaults to [ui.FilterQuality.medium].
  ///
  /// This matters most when [renderScale] is not `1.0`. The values map to
  /// concrete sampling modes, [ui.FilterQuality.none] is nearest-neighbor
  /// (hard pixel blocks), [ui.FilterQuality.low] is bilinear,
  /// [ui.FilterQuality.medium] adds mipmaps, and [ui.FilterQuality.high]
  /// is bicubic where the backend implements it. On native (Impeller),
  /// `high` currently behaves like `medium`, and since the composited
  /// image has no mipmaps every value except `none` resolves to plain
  /// bilinear there; the web renderers (CanvasKit and Skwasm, both
  /// Skia-backed) implement the tiers distinctly, including bicubic.
  ///
  /// Per-view overrides via `RenderView.filterQuality`. Ignored by views
  /// targeting a `RenderTexture` (display filtering belongs to the
  /// consumer there, for example `RenderTextureView.filterQuality`).
  ui.FilterQuality filterQuality = ui.FilterQuality.medium;

  /// Views this scene owns and renders every frame, in addition to the
  /// views passed to each [renderViews] call.
  ///
  /// This is the home for views targeting a [RenderTexture]
  /// ([RenderView.target]): add one here and it re-renders whenever the
  /// scene renders, subject to the target's [RenderTexture.update] policy,
  /// without being threaded through every render call. Views in this list
  /// without a target are ignored by [renderViews] (the screen views come
  /// from the call's argument).
  final List<RenderView> views = [];

  /// Casts [ray] through the scene's render geometry and returns the nearest
  /// hit, or null.
  ///
  /// Tests the meshes as rendered (no colliders or physics setup), with the
  /// hit's texture coordinate interpolated from the vertex data. Invisible
  /// subtrees are skipped unless [includeInvisible] is set; nodes must
  /// intersect [layerMask] (against [Node.layers]), have [Node.raycastable]
  /// set, and pass [where] when provided. Distinct from the physics queries
  /// (`PhysicsWorld.raycast`), which test collision shapes.
  SceneRaycastHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool Function(Node node)? where,
    bool includeInvisible = false,
  }) => raycastNode(
    root,
    ray,
    maxDistance: maxDistance,
    layerMask: layerMask,
    where: where,
    includeInvisible: includeInvisible,
  );

  /// Casts [ray] through the scene's render geometry and returns every hit,
  /// sorted nearest-first. Parameters as in [raycast].
  List<SceneRaycastHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool Function(Node node)? where,
    bool includeInvisible = false,
  }) => raycastNodeAll(
    root,
    ray,
    maxDistance: maxDistance,
    layerMask: layerMask,
    where: where,
    includeInvisible: includeInvisible,
  );

  /// Prepares the rendering resources, such as textures and shaders,
  /// that are used to display models in this [Scene].
  ///
  /// This method ensures all necessary resources are loaded and ready to be used in the rendering pipeline.
  /// If the initialization fails, the resources are reset, and the scene
  /// will not be marked as ready to render.
  ///
  /// Returns a [Future] that completes when the initialization is finished.
  static Future<void> initializeStaticResources() {
    if (_initializeStaticResources != null) {
      return _initializeStaticResources!;
    }
    _initializeStaticResources =
        Future.wait([
              loadBaseShaderLibrary(),
              Material.initializeStaticResources(),
            ])
            .onError((e, stacktrace) {
              log(
                'Failed to initialize static Flutter Scene resources',
                error: e,
                stackTrace: stacktrace,
              );
              _initializeStaticResources = null;
              return const <void>[];
            })
            .then((_) {
              _readyToRender = true;
            });
    return _initializeStaticResources!;
  }

  /// The root [Node] of the scene graph.
  ///
  /// All [Node] objects in the scene are connected to this node, either directly or indirectly.
  /// Transformations applied to this [Node] affect all child [Node] objects.
  final Node root = Node();

  /// The flat list of drawable items the render passes iterate.
  ///
  /// Kept in sync by the node graph as mesh-bearing nodes are added and
  /// removed. Engine-internal; not part of the stable public API.
  final RenderScene renderScene = RenderScene();

  /// Handles the creation and management of render targets for this [Scene].
  final Surface surface = Surface();

  /// Transient-uniform allocator, created once and reused every frame.
  ///
  /// A [gpu.HostBuffer] cycles through several frames of backing storage on
  /// `reset()`, so one instance is meant to live for the scene's lifetime
  /// rather than being recreated per frame.
  gpu.HostBuffer? _transientsBuffer;

  /// The image-based-lighting environment, or null to use the engine's
  /// default (the built-in procedural [EnvironmentMap.studio], built
  /// lazily on first render).
  ///
  /// Assign an [EnvironmentMap] to override it. A [PhysicallyBasedMaterial]
  /// can override this per material.
  EnvironmentMap? environment;

  /// Scalar multiplier applied to [environment]'s contribution. `1.0`
  /// (the default) is neutral.
  double environmentIntensity = 1.0;

  /// Rotation applied to the image-based-lighting [environment] when it is
  /// sampled. Identity (the default) leaves the environment unrotated.
  Matrix3 environmentTransform = Matrix3.identity();

  /// The visible background drawn behind the scene, or null (the default)
  /// to clear to transparent.
  ///
  /// Decoupled from the image-based lighting ([environment]): a default
  /// [Skybox] with an [EnvironmentSkySource] shows that same environment
  /// (optionally blurred), but the two can be set independently. The engine
  /// draws the skybox behind all geometry; you do not place any geometry.
  Skybox? skybox;

  /// Drives [environment] from a sky on a refresh policy, or null (the
  /// default) to leave [environment] caller-managed.
  ///
  /// While set, the binding owns [environment]: the sky is baked into the
  /// image-based lighting when the binding is assigned, then re-baked per
  /// [SkyEnvironment.refresh] (manually invalidated, on an interval, or every
  /// frame). Setting it back to null keeps the last baked environment.
  SkyEnvironment? skyEnvironment;

  SunLight? _sunLight;

  /// Aims [directionalLight] at a sky's sun so cast shadows track the sky.
  ///
  /// While set, the binding owns [directionalLight]: each frame the engine
  /// points the light opposite the sky's sun and recolors it. Clearing it
  /// (setting null) removes the light the binding was driving. Pair it with a
  /// [skyEnvironment] on the same sky so soft IBL and the hard shadow agree.
  SunLight? get sunLight => _sunLight;

  set sunLight(SunLight? value) {
    // The binding owns the convenience light; when it is cleared, retire the
    // light it was driving so shadows stop.
    if (value == null &&
        _sunLight != null &&
        identical(directionalLight, _sunLight!.light)) {
      directionalLight = null;
    }
    _sunLight = value;
  }

  // The component backing the [directionalLight] convenience: a single
  // light attached to [root]. Null when no scene-level light is set.
  DirectionalLightComponent? _directionalLightComponent;

  /// A single analytic directional light (e.g. a sun) layered on top of
  /// the image-based lighting. Null (the default) means IBL only.
  ///
  /// This is a convenience over attaching a [DirectionalLightComponent] to
  /// a node: the light is attached to [root] (so its direction is the
  /// light's own [DirectionalLight.direction], unaffected by any node
  /// transform). For lights that should move or aim with a node, attach a
  /// [DirectionalLightComponent] to that node instead. The renderer shades
  /// the first directional light it finds in the graph.
  DirectionalLight? get directionalLight => _directionalLightComponent?.light;

  set directionalLight(DirectionalLight? value) {
    final existing = _directionalLightComponent;
    if (existing != null) {
      root.removeComponent(existing);
      _directionalLightComponent = null;
    }
    if (value != null) {
      final component = DirectionalLightComponent(value);
      root.addComponent(component);
      _directionalLightComponent = component;
    }
  }

  /// Linear exposure multiplier applied to the HDR scene color before
  /// tone mapping. `1.0` (the default) is neutral; see
  /// [physicalCameraExposure] to derive a value from camera settings.
  double exposure = 1.0;

  /// Tone mapping operator used when resolving the HDR scene color to the
  /// display image. Defaults to [ToneMappingMode.pbrNeutral].
  ToneMappingMode toneMapping = ToneMappingMode.pbrNeutral;

  /// Built-in post-processing settings, such as color grading. Every
  /// effect is off by default.
  final PostProcessSettings postProcess = PostProcessSettings();

  /// The scene's blendable look (image-based lighting, exposure, tone mapping,
  /// and post-processing) as a copyable value.
  ///
  /// Reading snapshots the current look; assigning applies one. Use
  /// [EnvironmentSettings.lerp] to interpolate between two looks for a scripted
  /// transition (drive `t` from an animation each frame).
  EnvironmentSettings get environmentSettings =>
      EnvironmentSettings.fromScene(this);
  set environmentSettings(EnvironmentSettings value) => value.applyTo(this);

  /// The global base look that [environmentVolumes] blend over.
  ///
  /// Set this and add volumes to drive the scene look spatially: each frame the
  /// engine blends the volumes over this base by the camera position and
  /// applies the result to the live look fields. Null (the default) disables
  /// volume blending, the live fields are used directly.
  EnvironmentSettings? baseEnvironment;

  /// Environment volumes blended over [baseEnvironment] by camera position, so
  /// the look transitions as the camera moves between areas. Ignored when
  /// [baseEnvironment] is null. See [EnvironmentVolume].
  final List<EnvironmentVolume> environmentVolumes = [];

  // The secondary image-based-lighting environment and the factor blending the
  // live [environment] toward it this frame, resolved from the volume blend so
  // reflections and ambient cross-fade instead of switching. Null/0 when a
  // single environment is in effect. Read by the render path into ScenePass.
  EnvironmentMap? _crossfadeEnvironment;
  double _crossfadeBlend = 0.0;

  // Applies the camera-position blend of [environmentVolumes] over
  // [baseEnvironment] to the live look fields, before the environment is used
  // this frame. A no-op unless both a base and volumes are set.
  void _applyEnvironmentVolumes(Camera camera) {
    final base = baseEnvironment;
    if (base == null || environmentVolumes.isEmpty) {
      _crossfadeEnvironment = null;
      _crossfadeBlend = 0.0;
      return;
    }
    final position = camera.position;
    blendEnvironmentVolumes(base, environmentVolumes, position).applyTo(this);
    // Keep the image-based lighting continuous across the midpoint: hold the
    // primary environment and pass the secondary plus a blend factor to the
    // material, rather than letting applyTo switch it.
    final crossfade = resolveEnvironmentCrossfade(
      base,
      environmentVolumes,
      position,
    );
    if (crossfade.secondary != null) {
      environment = crossfade.primary;
      _crossfadeEnvironment = crossfade.secondary;
      _crossfadeBlend = crossfade.blend;
    } else {
      _crossfadeEnvironment = null;
      _crossfadeBlend = 0.0;
    }
  }

  /// How the selection outline is drawn around nodes that have a
  /// [Node.highlightColor]. No outline is drawn when no node is highlighted.
  final HighlightStyle highlightStyle = HighlightStyle();

  final List<CustomRenderPass> _renderPasses = [];

  /// The custom render passes inserted into the pipeline, in the order they
  /// were added. Use [addRenderPass] / [removeRenderPass] to change the set.
  /// {@category Rendering}
  List<CustomRenderPass> get renderPasses =>
      List<CustomRenderPass>.unmodifiable(_renderPasses);

  /// Inserts [pass] into the render pipeline at its [CustomRenderPass.stage].
  /// Passes at the same stage run in the order they were added. Adding the
  /// same pass twice is a no-op.
  /// {@category Rendering}
  void addRenderPass(CustomRenderPass pass) {
    if (_renderPasses.contains(pass)) return;
    _renderPasses.add(pass);
  }

  /// Removes a previously [addRenderPass]ed [pass]. Returns whether it was
  /// present.
  /// {@category Rendering}
  bool removeRenderPass(CustomRenderPass pass) => _renderPasses.remove(pass);

  Iterable<CustomRenderPass> _passesAt(RenderStage stage) =>
      _renderPasses.where((p) => p.enabled && p.stage == stage);

  /// Screen-space ambient occlusion settings. Off by default; set
  /// [AmbientOcclusionSettings.enabled] to turn it on. Requires a
  /// [PerspectiveCamera] (the occlusion is reconstructed from the camera's
  /// perspective depth); it is skipped for other camera types.
  final AmbientOcclusionSettings ambientOcclusion = AmbientOcclusionSettings();

  @override
  void add(Node child) {
    root.add(child);
  }

  @override
  void addAll(Iterable<Node> children) {
    root.addAll(children);
  }

  @override
  void addMesh(Mesh mesh) {
    final node = Node(mesh: mesh);
    add(node);
  }

  @override
  void remove(Node child) {
    root.remove(child);
  }

  @override
  void removeAll() {
    root.removeAll();
  }

  // Whether the per-frame tick already ran for the upcoming render.
  bool _tickedThisFrame = false;

  // Wall-clock timestamp of the previous tick, used to derive a delta
  // when only [render] is called.
  int? _lastTickMillis;

  // Unconsumed wall-clock time carried between frames so the fixed-step
  // physics driver can take an integer number of steps per frame.
  double _physicsAccumulator = 0;

  void _tick(double deltaSeconds) {
    _lastTickMillis = DateTime.now().millisecondsSinceEpoch;
    _stepPhysics(deltaSeconds);
    root.scenePrePass(deltaSeconds);
  }

  // Advances the active [PhysicsWorld] (if any) on a fixed timestep.
  void _stepPhysics(double frameDt) {
    final world = root.getComponent<PhysicsWorld>();
    if (world == null) {
      // Reset the accumulator so the first frame after a world is added
      // does not consume stale wall-clock time.
      _physicsAccumulator = 0;
      return;
    }
    _physicsAccumulator = advancePhysics(
      world: world,
      fixedUpdateWalk: root.sceneFixedPass,
      accumulator: _physicsAccumulator,
      frameDt: frameDt,
    );
  }

  /// Fixed-step substepping driver. Adds [frameDt] to [accumulator],
  /// takes up to [PhysicsWorld.maxSubsteps] fixed steps to consume it
  /// (walking [fixedUpdateWalk] then [world.step] each step), drops
  /// leftover time when the renderer falls far behind, and finishes by
  /// calling [world.interpolateTransforms] with the residual fraction.
  ///
  /// Returns the new accumulator value. Exposed as a static method so
  /// the loop can be exercised without constructing a [Scene] (which
  /// otherwise requires a live Flutter GPU context).
  @visibleForTesting
  static double advancePhysics({
    required PhysicsWorld world,
    required void Function(double fixedDt) fixedUpdateWalk,
    required double accumulator,
    required double frameDt,
  }) {
    accumulator += frameDt;
    final fixed = world.fixedTimestep;
    var steps = 0;
    while (accumulator >= fixed && steps < world.maxSubsteps) {
      fixedUpdateWalk(fixed);
      world.step(fixed);
      accumulator -= fixed;
      steps++;
    }
    if (accumulator > fixed * world.maxSubsteps) {
      // Drop unconsumed time to avoid spiralling when the renderer is
      // running far behind the physics rate.
      accumulator = 0;
    }
    final alpha = (accumulator / fixed).clamp(0.0, 1.0);
    world.interpolateTransforms(alpha);
    return accumulator;
  }

  /// Advances the scene by [deltaSeconds]: ticks every node's components
  /// and animation players, and refreshes the flat render layer.
  ///
  /// Calling this is optional. A caller that only calls [render] gets an
  /// implicit tick with a wall-clock delta. Call [update] explicitly to
  /// drive the scene with a fixed or supplied timestep, then call
  /// [render]; the render then skips its implicit tick.
  void update(double deltaSeconds) {
    _tick(deltaSeconds);
    _tickedThisFrame = true;
  }

  /// Renders [camera]'s view of this scene onto [canvas].
  ///
  /// The [Camera] provides the perspective from which the scene is viewed,
  /// and the [ui.Canvas] is the drawing surface onto which this [Scene] is
  /// rendered.
  ///
  /// Optionally, a [ui.Rect] [viewport] limits the rendering area on the
  /// canvas. If none is specified, the entire canvas is rendered.
  ///
  /// [pixelRatio] is the multiplier from logical to physical pixels used
  /// when allocating the offscreen render target. Defaults to the
  /// implicit view's `devicePixelRatio` (or `1.0` if no view is attached),
  /// so the scene is rasterized at the same density Flutter is
  /// compositing the surrounding UI at. Pass a smaller value to trade
  /// fidelity for performance, or a larger one for supersampling.
  ///
  /// This is the single-view convenience over [renderViews].
  void render(
    Camera camera,
    ui.Canvas canvas, {
    ui.Rect? viewport,
    double? pixelRatio,
  }) {
    renderViews(
      [RenderView(camera: camera)],
      canvas,
      region: viewport,
      pixelRatio: pixelRatio,
    );
  }

  /// Renders a list of [views] of this scene onto [canvas].
  ///
  /// Each [RenderView] binds a camera to a normalized sub-rectangle of
  /// [region] (its [RenderView.viewport]), a [RenderView.layerMask], and a
  /// compositing [RenderView.order]; views are drawn lowest-order first.
  /// This is how split-screen and picture-in-picture are rendered. [render]
  /// is the single-view convenience over this.
  ///
  /// Each view renders into its own offscreen target (its own swapchain
  /// texture and transient texture pool), so simultaneous views never share
  /// a render target within a frame.
  ///
  /// [region] is the canvas rectangle the views subdivide; it defaults to
  /// the canvas clip bounds. [pixelRatio] is the logical-to-physical
  /// multiplier for the offscreen render targets (defaults to the view's
  /// device pixel ratio).
  ///
  /// The scene is advanced once per call (a single per-frame tick), then
  /// every view is rendered from that shared scene state.
  void renderViews(
    List<RenderView> views,
    ui.Canvas canvas, {
    ui.Rect? region,
    double? pixelRatio,
  }) {
    if (!_readyToRender) {
      debugPrint('Flutter Scene is not ready to render. Skipping frame.');
      debugPrint(
        'You may wait on the Future returned by Scene.initializeStaticResources() before rendering.',
      );
      return;
    }

    final drawArea = region ?? canvas.getLocalClipBounds();
    if (drawArea.isEmpty || views.isEmpty) {
      return;
    }

    // Blend the environment volumes over the base by the primary view's camera
    // position, before the environment, sky bake, and sun light are read.
    _applyEnvironmentVolumes(views.first.camera);

    final dpr =
        pixelRatio ??
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
        1.0;

    // Re-bake the sky-driven environment when its refresh policy says one is
    // due. The bake submits its own passes, so like the lazy default-prefilter
    // below it must run before this frame's render graph is built.
    final skyEnv = skyEnvironment;
    if (skyEnv != null) {
      final baked = skyEnv.bakeIfDue(DateTime.now());
      if (baked != null) {
        environment = baked;
        // When volume blending holds a sky-lit base, the base snapshot's
        // environment is captured once and would otherwise go stale as the sky
        // re-bakes. Refresh it, but only while the active binding is the base's
        // own (not a volume's), so a volume's bake never overwrites the base.
        final base = baseEnvironment;
        if (base != null && identical(skyEnv, base.skyEnvironment)) {
          base.environment = baked;
        }
      }
    }

    // Aim the sky-driven sun light before the tick collects lights, so its
    // direction/color follow the sky this frame. The binding mutates one light
    // in place, so it is registered with the graph once and updated thereafter.
    final sun = _sunLight;
    if (sun != null) {
      final resolved = sun.resolve();
      if (!identical(directionalLight, resolved)) {
        directionalLight = resolved;
      }
    }

    // The web radiance prefilter is degenerate when built on a cold WebGL
    // context (before the first frame composites); environments built then
    // (the lazily built default below, or any the app built up front) are
    // re-baked once a frame has been presented and the context is warm. No-op
    // on other backends and after the one-time rebuild. See
    // EnvironmentMap.markContextWarmAndRebakeRadiance.
    if (_hasPresentedFrame) {
      EnvironmentMap.markContextWarmAndRebakeRadiance();
    }

    // Resolve the IBL environment up front (before building any render
    // graph): the default is built lazily here on first use, which submits
    // a one-time prefilter pass that must not be nested inside the frame's
    // render passes. Doing this in the constructor instead would break the
    // OpenGL ES backend, which sets up its context lazily on the raster
    // thread only after the first frame.
    final environmentMap = environment ?? Material.getDefaultEnvironmentMap();

    // Reuse one host buffer across frames; reset() cycles it to the next
    // frame's backing storage. Shared by every view this frame.
    final transientsBuffer = _transientsBuffer ??= gpu.gpuContext
        .createHostBuffer();
    transientsBuffer.reset();
    // Advance the instance-transform buffer pool to this frame's set (it
    // backs the instance-rate vertex buffer, separate from the uniform
    // host buffer above; see instance_packing.dart).
    instanceTransformBuffers.beginFrame();

    // Advance the scene once per frame (not once per view): tick components
    // and animations and refresh the flat render list before the passes
    // iterate it. Skipped when update() already ran the tick this frame.
    if (!_tickedThisFrame) {
      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final lastMillis = _lastTickMillis ?? nowMillis;
      _tick((nowMillis - lastMillis) / 1000.0);
    }
    _tickedThisFrame = false;

    // Rebuild the spatial culling structure once if the pre-pass changed the
    // scene, before the views' render passes query it.
    renderScene.rebuildIfDirty();

    // The renderer shades a single directional light: the first one
    // registered in the graph (the [directionalLight] convenience, or a
    // [DirectionalLightComponent] attached to any node).
    final lightComponent = renderScene.directionalLights.isEmpty
        ? null
        : renderScene.directionalLights.first;

    // Texture-target views render first so screen views (and the HUD)
    // composite this frame's captures, the simple form of the
    // produce-before-consume rule.
    // TODO(rendertarget): order texture views among themselves by
    // resource read/write edges once materials can sample render textures.
    final textureViews = <RenderView>[
      for (final view in this.views)
        if (view.target != null) view,
      for (final view in views)
        if (view.target != null) view,
    ]..sort((a, b) => a.order.compareTo(b.order));
    final now = DateTime.now();
    for (final view in textureViews) {
      final target = view.target!;
      if (!target.shouldUpdate(now)) {
        continue;
      }
      _renderViewToTexture(
        view: view,
        outputColor: target.acquireNextTexture(),
        pixelSize: ui.Size(target.width.toDouble(), target.height.toDouble()),
        pool: target.transientTexturePool,
        environmentMap: environmentMap,
        transientsBuffer: transientsBuffer,
        lightComponent: lightComponent,
      );
      target.markUpdated(now);
    }

    // Composite lower-order screen views first.
    final screenViews = [
      for (final view in views)
        if (view.target == null) view,
    ];
    final ordered = screenViews.length == 1
        ? screenViews
        : (screenViews..sort((a, b) => a.order.compareTo(b.order)));

    for (var i = 0; i < ordered.length; i++) {
      final view = ordered[i];
      final viewArea = _viewDrawArea(drawArea, view.viewport);
      if (viewArea.isEmpty) {
        continue;
      }
      _renderViewToCanvas(
        view: view,
        canvas: canvas,
        drawArea: viewArea,
        dpr: dpr,
        viewIndex: i,
        environmentMap: environmentMap,
        transientsBuffer: transientsBuffer,
        lightComponent: lightComponent,
      );
    }

    // A frame has now been submitted; the next one runs on a warm context (see
    // the rebuild near the environment resolution above).
    _hasPresentedFrame = true;
  }

  // Whether at least one frame has been rendered and presented, so the web
  // GL context is warm enough for a correct radiance prefilter.
  static bool _hasPresentedFrame = false;

  // Maps a view's normalized viewport rectangle (0..1) into a canvas
  // sub-rectangle of [area]; a null viewport fills [area].
  ui.Rect _viewDrawArea(ui.Rect area, ui.Rect? viewport) {
    if (viewport == null) return area;
    return ui.Rect.fromLTWH(
      area.left + viewport.left * area.width,
      area.top + viewport.top * area.height,
      viewport.width * area.width,
      viewport.height * area.height,
    );
  }

  // Renders one [view] into [drawArea] on [canvas], using that view's own
  // swapchain texture and transient texture pool (so simultaneous views in a
  // frame do not share render targets). The per-frame work (tick, spatial
  // rebuild, environment resolve, host-buffer reset) is done once by the
  // caller; this builds and submits one view's render graph and composites
  // the result.
  void _renderViewToCanvas({
    required RenderView view,
    required ui.Canvas canvas,
    required ui.Rect drawArea,
    required double dpr,
    required int viewIndex,
    required EnvironmentMap environmentMap,
    required gpu.HostBuffer transientsBuffer,
    required DirectionalLightComponent? lightComponent,
  }) {
    // Allocate the offscreen render target at physical-pixel resolution so
    // the rasterized 3D content matches Flutter's framebuffer density.
    // Without this, the texture is sized in logical pixels and the
    // framebuffer compositor upscales it (visible as pixelation on
    // high-DPI devices). See: https://github.com/bdero/flutter_scene/issues/60
    // The render scale multiplies on top, trading resolution for fragment
    // work (or supersampling above 1.0).
    final scale = dpr * (view.renderScale ?? _renderScale);
    final pixelSize = ui.Size(
      (drawArea.width * scale).ceilToDouble(),
      (drawArea.height * scale).ceilToDouble(),
    );
    if (pixelSize.width < 1 || pixelSize.height < 1) {
      return;
    }

    final gpu.Texture swapchainColor = surface.getNextSwapchainColorTexture(
      pixelSize,
      viewIndex,
    );
    _renderViewToTexture(
      view: view,
      outputColor: swapchainColor,
      pixelSize: pixelSize,
      pool: surface.transientTexturePool(viewIndex),
      environmentMap: environmentMap,
      transientsBuffer: transientsBuffer,
      lightComponent: lightComponent,
    );

    final image = swapchainColor.asImage();
    final srcRect = ui.Rect.fromLTWH(0, 0, pixelSize.width, pixelSize.height);
    final paint = ui.Paint()
      ..filterQuality = view.filterQuality ?? filterQuality;
    canvas.drawImageRect(image, srcRect, drawArea, paint);
  }

  // Builds and submits one view's render graph into [outputColor] (a
  // swapchain texture for screen views, or a [RenderTexture] ring slot).
  // [pool] supplies the view's transient attachments; each view (and each
  // render texture) has its own so simultaneous renders never share one.
  void _renderViewToTexture({
    required RenderView view,
    required gpu.Texture outputColor,
    required ui.Size pixelSize,
    required TransientTexturePool pool,
    required EnvironmentMap environmentMap,
    required gpu.HostBuffer transientsBuffer,
    required DirectionalLightComponent? lightComponent,
  }) {
    final camera = view.camera;
    final effectiveAa = _resolveAntiAliasingMode(
      view.antiAliasingMode ?? _antiAliasingMode,
    );
    final enableMsaa = effectiveAa == AntiAliasingMode.msaa;
    final enableFxaa = effectiveAa == AntiAliasingMode.fxaa;

    final light = lightComponent?.light;
    final lightDirection = lightComponent?.worldDirection;
    // Cascaded shadows fit the camera frustum, so they require a
    // perspective projection; other projections render without shadows.
    final cascades =
        light != null &&
            light.castsShadow &&
            camera.projection is PerspectiveProjection
        ? light.computeCascades(
            camera,
            pixelSize.width / pixelSize.height,
            lightDirection,
          )
        : const <ShadowCascade>[];

    final graph = RenderGraph();
    if (cascades.isNotEmpty) {
      graph.addPass(
        ShadowPass(
          renderScene: renderScene,
          cascades: cascades,
          tileResolution: light!.shadowMapResolution,
        ),
      );
    }
    // Ambient occlusion is reconstructed from a camera depth prepass, so it
    // needs a perspective projection (others render without it).
    final perspective = camera.projection;
    if (ambientOcclusion.enabled && perspective is PerspectiveProjection) {
      // The whole occlusion chain (depth prepass, occlusion, blur) runs at one
      // resolution so depth is sampled 1:1; sampling a full-resolution depth
      // from the half-resolution occlusion pass would alias on fine geometry.
      final aoDimensions = ambientOcclusionTargetSize(
        pixelSize,
        ambientOcclusion,
      );
      graph.addPass(
        DepthPrepass(
          camera: camera,
          renderScene: renderScene,
          dimensions: aoDimensions,
          cameraForward: camera.forward,
          farDepth: perspective.far,
          layerMask: view.layerMask,
        ),
      );
      graph.addPass(
        SsaoPass(
          dimensions: pixelSize,
          settings: ambientOcclusion,
          fovRadiansY: perspective.fovRadiansY,
          near: perspective.near,
          far: perspective.far,
        ),
      );
      graph.addPass(
        SsaoBlurPass(dimensions: pixelSize, settings: ambientOcclusion),
      );
    }
    graph.addPass(
      ScenePass(
        camera: camera,
        renderScene: renderScene,
        dimensions: pixelSize,
        environmentMap: environmentMap,
        environmentMapB: _crossfadeEnvironment,
        environmentBlend: _crossfadeBlend,
        environmentIntensity: environmentIntensity,
        environmentTransform: environmentTransform,
        skybox: skybox,
        enableMsaa: enableMsaa,
        directionalLight: light,
        directionalLightDirection: lightDirection,
        cascades: cascades,
        specularOcclusionMode: ambientOcclusion.specularMode.index.toDouble(),
        layerMask: view.layerMask,
      ),
    );
    // Split custom effects by where they run in the chain.
    final beforeTonemap = <PostEffect>[];
    final afterTonemap = <PostEffect>[];
    for (final effect in postProcess.customEffects) {
      if (!effect.enabled) {
        continue;
      }
      if (effect.insertion == PostInsertion.beforeTonemap) {
        beforeTonemap.add(effect);
      } else {
        afterTonemap.add(effect);
      }
    }

    final width = pixelSize.width.toInt();
    final height = pixelSize.height.toInt();
    final postTime =
        DateTime.now().millisecondsSinceEpoch.remainder(100000) / 1000.0;

    // Custom HDR passes right after the scene is drawn.
    _addHdrCustomPasses(
      graph,
      RenderStage.afterScene,
      camera,
      pixelSize,
      pool,
      width,
      height,
      view.layerMask,
      postTime,
    );

    // Custom effects on the linear HDR scene color, ping-ponging through
    // HDR buffers and republishing the scene-color handle that bloom and
    // the resolve read.
    for (var i = 0; i < beforeTonemap.length; i++) {
      final output = pool.acquire(
        TransientTextureDescriptor.color(
          width: width,
          height: height,
          format: gpu.PixelFormat.r16g16b16a16Float,
          debugName: i.isEven ? 'post_hdr_a' : 'post_hdr_b',
        ),
      );
      graph.addPass(
        PostEffectPass(
          effect: beforeTonemap[i],
          inputKey: kSceneColorBlackboardKey,
          outputKey: kSceneColorBlackboardKey,
          output: output,
          dimensions: pixelSize,
          time: postTime,
        ),
      );
    }

    // Bloom runs in HDR before the resolve, which composites it back in.
    if (postProcess.bloom.enabled) {
      graph.addPass(
        BloomPass(dimensions: pixelSize, settings: postProcess.bloom),
      );
    }

    // Custom HDR passes just before tone mapping.
    _addHdrCustomPasses(
      graph,
      RenderStage.beforeToneMapping,
      camera,
      pixelSize,
      pool,
      width,
      height,
      view.layerMask,
      postTime,
    );

    // The display-referred chain is an ordered list of color-writing passes.
    // The last one writes [outputColor]; each earlier one writes a pooled
    // transient the next pass samples. The resolve produces the first
    // display image; FXAA, custom display passes, after-tone-mapping
    // effects, and the selection outline composite onto it in order.
    final outlineActive = sceneHasHighlights(renderScene);
    final displaySteps = <RenderGraphPass Function(gpu.Texture output)>[];

    displaySteps.add(
      (output) => ResolvePass(
        outputColor: output,
        exposure: exposure,
        toneMappingMode: toneMapping,
        postProcess: postProcess,
      ),
    );

    var userPassIndex = 0;
    for (final pass in _passesAt(RenderStage.afterToneMapping)) {
      final index = userPassIndex++;
      displaySteps.add(
        (output) => UserRenderGraphPass(
          pass: pass,
          camera: camera,
          dimensions: pixelSize,
          destination: output,
          renderScene: renderScene,
          viewLayerMask: view.layerMask,
          passIndex: index,
          time: postTime,
        ),
      );
    }

    // FXAA runs after the resolve so custom after-tone-mapping effects
    // receive the anti-aliased image. The resolve applies film grain and
    // vignette first, so heavy grain is softened slightly here.
    // TODO(antialiasing): if that softening bothers anyone, move grain
    // application after the FXAA pass.
    if (enableFxaa) {
      displaySteps.add(
        (output) => FxaaPass(output: output, dimensions: pixelSize),
      );
    }

    for (final effect in afterTonemap) {
      displaySteps.add(
        (output) => PostEffectPass(
          effect: effect,
          inputKey: kDisplayColorBlackboardKey,
          outputKey: kDisplayColorBlackboardKey,
          output: output,
          dimensions: pixelSize,
          time: postTime,
        ),
      );
    }

    for (final pass in _passesAt(RenderStage.afterAntiAliasing)) {
      final index = userPassIndex++;
      displaySteps.add(
        (output) => UserRenderGraphPass(
          pass: pass,
          camera: camera,
          dimensions: pixelSize,
          destination: output,
          renderScene: renderScene,
          viewLayerMask: view.layerMask,
          passIndex: index,
          time: postTime,
        ),
      );
    }

    // Selection outline runs last: draw the highlighted silhouettes into a
    // mask, then composite a uniform-width outline onto the display image.
    // The mask only needs the scene geometry, so it can run before the
    // display chain; the outline composite is the final display step.
    if (outlineActive) {
      graph.addPass(
        SelectionMaskPass(
          camera: camera,
          renderScene: renderScene,
          dimensions: pixelSize,
          colorFormat: outputColor.format,
          layerMask: view.layerMask,
        ),
      );
      displaySteps.add(
        (output) => SelectionOutlinePass(
          output: output,
          dimensions: pixelSize,
          thickness: highlightStyle.thickness,
        ),
      );
    }

    for (var i = 0; i < displaySteps.length; i++) {
      final isLast = i == displaySteps.length - 1;
      final output = isLast
          ? outputColor
          : pool.acquire(
              TransientTextureDescriptor.color(
                width: width,
                height: height,
                format: outputColor.format,
                debugName: 'display_step_$i',
              ),
            );
      graph.addPass(displaySteps[i](output));
    }

    graph.execute(transientsBuffer: transientsBuffer, texturePool: pool);
  }

  // Inserts the enabled custom HDR passes registered for [stage], each
  // writing its own pooled HDR transient and republishing the scene color
  // when it draws.
  void _addHdrCustomPasses(
    RenderGraph graph,
    RenderStage stage,
    Camera camera,
    ui.Size pixelSize,
    TransientTexturePool pool,
    int width,
    int height,
    int viewLayerMask,
    double time,
  ) {
    var i = 0;
    for (final pass in _passesAt(stage)) {
      final output = pool.acquire(
        TransientTextureDescriptor.color(
          width: width,
          height: height,
          format: gpu.PixelFormat.r16g16b16a16Float,
          debugName: 'custom_hdr_${stage.name}_$i',
        ),
      );
      graph.addPass(
        UserRenderGraphPass(
          pass: pass,
          camera: camera,
          dimensions: pixelSize,
          destination: output,
          renderScene: renderScene,
          viewLayerMask: viewLayerMask,
          passIndex: i,
          time: time,
        ),
      );
      i++;
    }
  }
}
