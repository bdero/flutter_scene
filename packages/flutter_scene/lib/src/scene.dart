import 'dart:async' show Completer, FutureExtensions, Timer;
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/mip_sampling_probe.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart'
    show Frustum, Matrix3, Matrix4, Plane, Ray, Vector2, Vector3, Vector4;

import 'ambient_occlusion.dart';
import 'global_illumination.dart';
import 'audio/audio_engine.dart';
import 'auto_exposure.dart';
import 'camera.dart';
import 'components/camera_component.dart';
import 'components/directional_light_component.dart';
import 'components/irradiance_volume_component.dart';
import 'components/planar_reflector_component.dart';
import 'components/point_light_component.dart';
import 'components/reflection_probe_component.dart';
import 'components/spot_light_component.dart';
import 'fog.dart';
import 'god_rays.dart';
import 'light.dart';
import 'material/environment.dart';
import 'material/material.dart';
import 'memory_report.dart' show listenForMemoryPressure;
import 'mesh.dart';
import 'node.dart';
import 'raycast.dart';
import 'physics/physics_world.dart';
import 'environment_settings.dart';
import 'environment_volume.dart';
import 'post_process/post_effect.dart';
import 'post_process/post_process.dart';
import 'render/auto_exposure_pass.dart';
import 'render/bloom_pass.dart';
import 'render/custom_render_pass.dart';
import 'render/depth_prepass.dart';
import 'render/fxaa_pass.dart';
import 'render/scene_color_blit_pass.dart';
import 'render/sky_bake.dart'
    show
        buildEnvironmentFromFaces,
        createHdrCaptureTarget,
        cubeFaceBases,
        cubeFaceOverscan;
import 'render/smaa_pass.dart';
import 'render/post_effect_pass.dart';
import 'render/irradiance_field.dart';
import 'render/irradiance_pass.dart';
import 'render/render_graph.dart';
import 'render/render_graph_capture.dart';
import 'render/render_scene.dart';
import 'render/planar_reflection.dart';
import 'render/planar_reflection_pass.dart';
import 'render/punctual_lights.dart';
import 'render/point_shadow.dart';
import 'render/spot_shadow.dart';
import 'render/scene_pass.dart';
import 'render/ssr_pass.dart';
import 'screen_space_reflections.dart';
import 'render/selection_outline_pass.dart';
import 'depth_of_field.dart';
import 'render/dof_pass.dart';
import 'material/shadow_catcher_material.dart';
import 'render/shadow_catcher_bake_pass.dart';
import 'render/shadow_cache.dart';
import 'render/shadow_pass.dart';
import 'render/ssao_pass.dart';
import 'render/resolve_pass.dart';
import 'render_texture.dart';
import 'render_view.dart';
import 'screen_distortion.dart';
import 'shaders.dart';
import 'sky_environment.dart';
import 'skybox.dart';
import 'sun_light.dart';
import 'surface.dart';
import 'tone_mapping.dart';
import 'render/temporal_anti_aliasing.dart';
import 'render/velocity_pass.dart';
import 'render/taa_pass.dart';
import 'render/irradiance_bake.dart';

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

  /// Enhanced subpixel morphological anti-aliasing (SMAA 1x), three
  /// post-process passes over the tone-mapped image. Supported on every
  /// backend. Reconstructs edge shapes from their neighborhood, so edges
  /// come out cleaner than [fxaa] with far less blurring of texture
  /// detail, at roughly three times the anti-aliasing cost.
  smaa,

  /// Temporal anti-aliasing. Jitters the camera each frame and resolves
  /// against a reprojected history, so edges, specular shimmer, and
  /// screen-space effect noise all resolve. Needs the depth prepass, and
  /// adds a velocity pass when the scene has moving geometry. Tuned by
  /// [Scene.temporalAntiAliasing].
  taa,

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
  int _renderMetadataStructureRevision = -1;
  int _materialInputStructureRevision = -1;
  int _materialInputMaterialRevision = -1;
  int _renderMetadataStaticShadowRevision = -1;
  Set<RenderInput> _cachedWholeSceneMaterialInputs = const {};
  int _cachedStaticShadowSignature = 0;
  bool _cachedHasStaticShadowCasters = false;

  Scene() {
    // Kicked off, not awaited: rendering is gated on isReadyToRender, and a
    // SceneView shows its loadingBuilder until then. initializeStaticResources
    // completes with its error for callers that do await it, and has already
    // logged the failure by the time this handler runs, so this only keeps an
    // unawaited future from being reported a second time as an unhandled error.
    initializeStaticResources().ignore();
    renderScene.owner = this;
    root.registerAsRoot(this);
  }

  static Future<void>? _initializeStaticResources;
  static bool _readyToRender = false;

  /// Whether the engine's shared shader libraries and material lookup
  /// resources have finished loading, so any scene can render this frame.
  ///
  /// Rendering is gated on this: a `SceneView` shows its loading widget, and a
  /// direct [render] call is skipped, until it is `true`. Await
  /// [initializeStaticResources] (or use a `SceneView` with a `loadingBuilder`)
  /// to react to it.
  /// {@category Assets and loading}
  static bool get isReadyToRender => _readyToRender;

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

  // Latches the "nothing was drawn" diagnostic so a one-frame layout transient
  // does not spam. Reset whenever a frame draws, so a later regression prints
  // again. See _reportBlankFrame.
  bool _warnedBlankFrame = false;

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
      case AntiAliasingMode.smaa:
        return AntiAliasingMode.smaa;
      case AntiAliasingMode.taa:
        return AntiAliasingMode.taa;
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
  /// This method ensures all necessary resources are loaded and ready to be
  /// used in the rendering pipeline.
  ///
  /// Returns a [Future] that completes when the initialization is finished,
  /// and that completes with the load's error when it fails. A failure also
  /// resets the resources and leaves the scene not ready to render, so a
  /// caller that awaits this without catching gets the error rather than a
  /// misleading one from the first draw. `SceneView` reports it and stays on
  /// its loading builder.
  static Future<void> initializeStaticResources() {
    if (_initializeStaticResources != null) {
      return _initializeStaticResources!;
    }
    // Attached before the loads rather than after them: loading is when an
    // app is most likely to be pushed over a memory limit, and by then it
    // should already be listening. Asset loading below means a binding exists.
    listenForMemoryPressure();
    _initializeStaticResources =
        Future.wait([
              loadBaseShaderLibrary(),
              Material.initializeStaticResources(),
              SmaaPass.initializeStaticResources(),
            ])
            // Needs the shader library, so it runs after the load and before
            // rendering unblocks (environment radiance builds consult it).
            .then((_) => probePlatformMipSampling())
            .then((_) {
              _readyToRender = true;
            })
            .onError<Object>((e, stacktrace) {
              // Only a successful load marks the scene ready to render;
              // rendering with these resources missing throws mid-frame.
              // The memoized future is reset so a later call retries.
              log(
                'Failed to initialize static Flutter Scene resources',
                error: e,
                stackTrace: stacktrace,
              );
              _initializeStaticResources = null;
              // Rethrow so an awaiting caller sees the real cause. Completing
              // normally here left the failure visible only through
              // `dart:developer` log(), which web does not surface, and sent
              // the developer to the baseShaderLibrary getter's "await
              // initializeStaticResources()" instead, the call they just made.
              Error.throwWithStackTrace(e, stacktrace);
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

  // Builds the per-frame data texture carrying the scene's point, spot, and
  // extra directional lights. Rebuilt once per frame in [render].
  final PunctualLightBuffer _punctualLightBuffer = PunctualLightBuffer();

  /// How many drawable items (or, under clustered lighting, screen froxels)
  /// dropped punctual lights last frame because more lights reached them than
  /// the per-slice budget can shade. Zero when everything fit. A persistent
  /// nonzero value means light ranges need authoring (an unranged light
  /// reaches everything) or large meshes need splitting.
  /// {@category Lighting and environment}
  int get punctualLightOverflowCount =>
      _punctualLightBuffer.overflowedItemCount;

  // The lights that held a shadow slot last frame, by identity, plus how many
  // asked for one and missed. Refreshed once per frame alongside the caster
  // selection; empty until the first frame renders.
  final Set<Object> _grantedShadowCasters = Set.identity();
  int _shadowCasterOverflowCount = 0;

  /// How many lights asked to cast a shadow last frame but got no slot in the
  /// shared shadow atlas, which caps shadow-casting spots and point lights
  /// separately (see `kMaxSpotShadows` and `kMaxPointShadows`).
  ///
  /// Those lights still light the scene; they just throw no shadow, silently.
  /// A nonzero value means the scene asks for more shadowed local lights than
  /// the atlas holds, so some authored shadows are not being drawn.
  /// {@category Lighting and environment}
  int get shadowCasterOverflowCount => _shadowCasterOverflowCount;

  /// Whether [lightComponent] (a `SpotLightComponent` or
  /// `PointLightComponent`) held a shadow slot last frame.
  ///
  /// False for a light that does not cast at all, and also for one whose
  /// `castsShadow` is set but which lost the slot to the budget. Editors pair
  /// this with [shadowCasterOverflowCount] to point at the specific lights
  /// whose authored shadow is not being drawn.
  /// {@category Lighting and environment}
  bool isShadowCasterGranted(Object lightComponent) =>
      _grantedShadowCasters.contains(lightComponent);

  // Records this frame's caster selection for the two queries above.
  void _recordShadowCasterBudget({
    required List<SpotLightComponent> spots,
    required List<PointLightComponent> points,
    required SpotShadowFrame? spotShadows,
    required PointShadowFrame? pointShadows,
  }) {
    _grantedShadowCasters.clear();
    final granted =
        (spotShadows?.casters.length ?? 0) +
        (pointShadows?.casters.length ?? 0);
    if (spotShadows != null) _grantedShadowCasters.addAll(spotShadows.casters);
    if (pointShadows != null) {
      _grantedShadowCasters.addAll(pointShadows.casters);
    }
    var requested = 0;
    for (final spot in spots) {
      if (spot.light.castsShadow) requested++;
    }
    for (final point in points) {
      if (point.light.castsShadow) requested++;
    }
    _shadowCasterOverflowCount = requested - granted;
  }

  /// Whether punctual lights shade through per-view froxel clustering (the
  /// view frustum subdivided into screen tiles and depth slices, each shading
  /// only the lights that reach it) instead of per-object light lists. On by
  /// default; perspective views use it automatically, while orthographic
  /// views and frames using light channel masks fall back to the per-object
  /// path. Clustering removes the per-object light cap, so a large mesh
  /// reached by many lights shades them all. Disable to compare, or to force
  /// the per-object path.
  /// {@category Lighting and environment}
  bool punctualLightClustering = true;

  /// The scene's primary camera.
  ///
  /// A `SceneView` with no `camera`, `cameraBuilder`, or `viewsBuilder`
  /// renders through this. It resolves to an explicit override (assign any
  /// [Camera] here) if set, otherwise to the first [CameraComponent] mounted
  /// in the scene (auto-promotion), otherwise null. When it is null, a
  /// `SceneView` falls back to a default camera so a scene with no camera set
  /// up still renders.
  ///
  /// Assigning a value sets the override; assign null to clear it and revert
  /// to auto-promotion. See also [CameraComponent.makeActive].
  /// {@category Rendering}
  Camera? get camera => renderScene.primaryCamera;
  set camera(Camera? value) => renderScene.cameraOverride = value;

  /// Handles the creation and management of render targets for this [Scene].
  final Surface surface = Surface();

  /// Transient-uniform allocator, created once and reused every frame.
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

  /// Loads an equirectangular image ([EnvironmentMap.fromEquirectImageAsset],
  /// so Radiance `.hdr`, OpenEXR `.exr`, or a standard sRGB image), lights the
  /// scene with it, and (when [showSkybox]) shows it as the [skybox]. A
  /// one-call setup so [environment] and [skybox] cannot drift apart.
  ///
  /// [skyBlur] blurs the visible sky (0 sharp, 1 fully blurred) without
  /// touching the lighting. [intensity], [exposure], and [rotationY] set
  /// [environmentIntensity], [exposure], and [environmentTransform]; each
  /// defaults to null, which leaves the scene's current value untouched.
  /// [maxWidth] caps the working equirect for high-dynamic-range sources
  /// (see [EnvironmentMap.fromEquirectImageBytes]).
  ///
  /// Clears [skyEnvironment], which would otherwise own [environment] and
  /// re-bake over the loaded image on its next refresh. In debug builds the
  /// load re-runs automatically when the asset's content changes on hot
  /// reload, as long as the loaded environment is still active.
  ///
  /// Overlapping calls resolve to the most recent one; an earlier call that
  /// finishes late does not clobber a later call's environment.
  Future<void> loadEnvironment(
    String assetPath, {
    bool showSkybox = true,
    double skyBlur = 0.0,
    double? intensity,
    double? exposure,
    double? rotationY,
    int maxWidth = 4096,
    AssetBundle? bundle,
  }) async {
    final epoch = ++_environmentLoadEpoch;
    final map = await EnvironmentMap.fromEquirectImageAsset(
      assetPath: assetPath,
      maxWidth: maxWidth,
      bundle: bundle,
    );
    if (epoch != _environmentLoadEpoch) return;
    skyEnvironment = null;
    environment = map;
    if (intensity != null) environmentIntensity = intensity;
    if (exposure != null) this.exposure = exposure;
    if (rotationY != null) environmentTransform = Matrix3.rotationY(rotationY);
    skybox = showSkybox
        ? Skybox(EnvironmentSkySource(blurriness: skyBlur))
        : null;
    if (!kDebugMode) return;
    // Weak captures so the registration never keeps the scene (or a replaced
    // environment) alive; the coordinator prunes it once the scene is gone.
    final weakScene = WeakReference(this);
    final weakMap = WeakReference(map);
    HotReloadCoordinator.instance.registerEnvironment(
      this,
      assetKey: assetPath,
      bundle: bundle,
      onReload: () async {
        final scene = weakScene.target;
        // Reload only while the loaded environment is still active; an
        // environment the caller swapped in manually is left alone.
        if (scene == null || !identical(scene.environment, weakMap.target)) {
          return;
        }
        await scene.loadEnvironment(
          assetPath,
          showSkybox: showSkybox,
          skyBlur: skyBlur,
          intensity: intensity,
          exposure: exposure,
          rotationY: rotationY,
          maxWidth: maxWidth,
          bundle: bundle,
        );
      },
    );
  }

  // Orders overlapping loadEnvironment calls; only the newest applies.
  int _environmentLoadEpoch = 0;

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
  /// [DirectionalLightComponent] to that node instead. The renderer selects
  /// the highest-priority directional light for cascaded shadows and other
  /// single-sun features; all directional lights contribute direct lighting.
  DirectionalLight? get directionalLight => _directionalLightComponent?.light;

  set directionalLight(DirectionalLight? value) {
    final existing = _directionalLightComponent;
    if (existing != null) {
      root.removeComponent(existing);
      _directionalLightComponent = null;
    }
    if (value != null) {
      final component = DirectionalLightComponent.fromLightDirection(value);
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

  /// AgX reference white. Only used by [ToneMappingMode.agx].
  double agxWhite = 16.29;

  /// AgX curve contrast. Only used by [ToneMappingMode.agx].
  double agxContrast = 1.25;

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
  // Last frame's scene color, held one frame for the screen-space
  // indirect-light gather (the transient pool's two-frame ring keeps the
  // texture valid until then).
  gpu.Texture? _ssgiHistoryColor;

  // The view-projection that rendered [_ssgiHistoryColor], so the gather can
  // reproject its radiance taps to where each point sat last frame. Null
  // until the first indirect-light frame stores one.
  Matrix4? _ssgiHistoryViewProjection;

  EnvironmentMap? _crossfadeEnvironment;
  double _crossfadeBlend = 0.0;

  // Reused across probe-capture faces; each face's beginFrame recycles the
  // previous face's intermediate attachments, which is safe on one
  // submission queue (the GPU executes the faces in submission order).
  TransientTexturePool? _probeCapturePool;

  // Cross-frame planar reflection capture targets, one per active reflection
  // group, keyed by the shared group id (or the reflector component for an
  // ungrouped one). Pruned as groups disappear.
  final Map<Object, _PlanarCaptureResources> _planarCaptureResources = {};

  /// The planar reflection capture passes built for the most recent capturing
  /// view, for tests that assert graph composition. Empty when no reflector
  /// captured.
  @visibleForTesting
  List<PlanarReflectionCapturePass> debugLastPlanarCapturePasses = const [];

  // Builds this frame's planar reflection capture passes for the primary
  // view: groups the visible reflectors, allocates or reuses each group's
  // capture target, routes the resulting frame to the mirror surfaces'
  // materials, and returns one capture pass per group. Distributes a null
  // frame to reflectors that do not capture this frame so their surfaces
  // fall back to the base look.
  List<PlanarReflectionCapturePass> _buildPlanarCapturePasses({
    required RenderView view,
    required Camera camera,
    required ui.Size pixelSize,
    required EnvironmentMap environmentMap,
    required DirectionalLightComponent? lightComponent,
    required PunctualLighting punctualLighting,
    required List<ShadowCascade> cascades,
    required double time,
  }) {
    final reflectors = renderScene.planarReflectorComponents;
    if (reflectors.isEmpty) {
      _planarCaptureResources.clear();
      debugLastPlanarCapturePasses = const [];
      return const [];
    }
    // The oblique near-plane clip is a perspective-projection modification;
    // other projections render without planar reflections (like the other
    // camera-reconstruction effects).
    final perspective = camera.projection is PerspectiveProjection;
    final groups = <Object, List<PlanarReflectorComponent>>{};
    Frustum? frustum;
    for (final reflector in reflectors) {
      var active =
          perspective &&
          reflector.enabled &&
          reflector.node.internalEffectiveVisible &&
          (reflector.node.layers & view.layerMask) != 0;
      if (active) {
        // A camera on or behind the mirror plane sees the surface's back (or
        // nothing), so there is no reflection to capture.
        final plane = reflector.worldPlane();
        if (plane.normal.dot(camera.position) + plane.constant <= 0.0) {
          active = false;
        }
      }
      if (active) {
        final bounds = reflector.node.combinedWorldBounds;
        if (bounds != null) {
          frustum ??= camera.getFrustum(pixelSize);
          if (!frustum.intersectsWithAabb3(bounds)) {
            active = false;
          }
        }
      }
      if (!active) {
        reflector.internalDistributeFrame(null);
        continue;
      }
      final Object key = reflector.reflectionGroupId >= 0
          ? reflector.reflectionGroupId
          : reflector;
      groups.putIfAbsent(key, () => []).add(reflector);
    }
    _planarCaptureResources.removeWhere((key, _) => !groups.containsKey(key));
    if (groups.isEmpty) {
      debugLastPlanarCapturePasses = const [];
      return const [];
    }

    final light = lightComponent?.light;
    final lightDirection = lightComponent?.worldDirection;
    final passes = <PlanarReflectionCapturePass>[];
    groups.forEach((key, members) {
      // Members of a shared group are co-planar by contract; the first one
      // supplies the plane and capture settings.
      final lead = members.first;
      final plane = lead.worldPlane();
      final scale = lead.resolutionScale.clamp(0.1, 1.0);
      final width = math.max(1, (pixelSize.width * scale).round());
      final height = math.max(1, (pixelSize.height * scale).round());
      final captureSize = ui.Size(width.toDouble(), height.toDouble());
      final resources = _planarCaptureResources.putIfAbsent(
        key,
        _PlanarCaptureResources.new,
      );
      final texture = resources.acquire(width, height);
      final reflectedCamera = PlanarReflectionCamera(
        source: camera,
        plane: plane,
        clipBias: lead.clipBias,
      );
      final frame = PlanarReflectionFrame(
        texture: texture,
        viewProjection: reflectedCamera.getViewTransform(captureSize),
      );
      for (final member in members) {
        member.internalDistributeFrame(frame);
      }
      passes.add(
        PlanarReflectionCapturePass(
          scenePass: ScenePass(
            camera: reflectedCamera,
            renderScene: renderScene,
            dimensions: captureSize,
            environmentMap: environmentMap,
            environmentMapB: _crossfadeEnvironment,
            environmentBlend: _crossfadeBlend,
            environmentIntensity: environmentIntensity,
            environmentTransform: environmentTransform,
            skybox: skybox,
            enableMsaa: false,
            directionalLight: light,
            directionalLightDirection: lightDirection,
            punctualLighting: punctualLighting,
            cascades: cascades,
            layerMask: lead.layerMask,
            fog: fog,
            time: time,
            // Rejects whole objects behind the mirror on the CPU; the
            // oblique projection clips whatever straddles the plane.
            cullingPlanes: [
              Plane.normalconstant(
                plane.normal,
                plane.constant - lead.clipBias,
              ),
            ],
            suppressPlanarReflections: true,
          ),
          output: texture,
          pool: resources.pool,
          groupKey: key,
          layerMask: lead.layerMask,
          dimensions: captureSize,
        ),
      );
    });
    debugLastPlanarCapturePasses = passes;
    return passes;
  }

  /// Captures the scene's linear HDR lighting at [position] into a new
  /// [EnvironmentMap]: renders the scene into six cube faces (with shadows
  /// and analytic lights, without screen-space effects or post-processing),
  /// then prefilters the result like any other environment.
  ///
  /// The returned environment reflects the scene at the moment of capture;
  /// nothing re-captures it. For a node-anchored probe with
  /// parallax-corrected sampling and automatic blending, use
  /// [ReflectionProbeComponent] instead.
  ///
  /// The engine resources must be loaded ([isReadyToRender]); throws
  /// [StateError] otherwise.
  /// {@category Lighting and environment}
  EnvironmentMap captureEnvironment({
    required Vector3 position,
    int faceResolution = 128,
    int equirectWidth = 512,
    int layerMask = 0xFFFFFFFF,
  }) {
    if (!isReadyToRender) {
      throw StateError(
        'Scene.captureEnvironment requires the engine resources; await '
        'Scene.initializeStaticResources() first.',
      );
    }
    renderScene.rebuildIfDirty();
    final lightComponent = renderScene.primaryDirectionalLight;
    final spotShadowFrame = collectSpotShadows(renderScene.spotLights);
    final pointShadowFrame = collectPointShadows(renderScene.pointLights);
    final punctualLighting = _punctualLightBuffer.build(
      directionals: renderScene.directionalLights,
      primaryDirectional: lightComponent,
      points: renderScene.pointLights,
      spots: renderScene.spotLights,
      areas: renderScene.rectAreaLights,
      items: renderScene.items,
      bvh: renderScene.bvh,
      spotShadows: spotShadowFrame,
      pointShadows: pointShadowFrame,
      enableFroxels: punctualLightClustering,
    );
    return _captureEnvironmentAt(
      position: position,
      faceResolution: faceResolution,
      equirectWidth: equirectWidth,
      layerMask: layerMask,
      environmentMap: environment ?? Material.getDefaultEnvironmentMap(),
      transientsBuffer: uniformTransients,
      lightComponent: lightComponent,
      punctualLighting: punctualLighting,
      spotShadowFrame: spotShadowFrame,
      pointShadowFrame: pointShadowFrame,
    );
  }

  EnvironmentMap _captureEnvironmentAt({
    required Vector3 position,
    required int faceResolution,
    required int equirectWidth,
    required int layerMask,
    required EnvironmentMap environmentMap,
    required TransientWriter transientsBuffer,
    required DirectionalLightComponent? lightComponent,
    required PunctualLighting punctualLighting,
    required SpotShadowFrame? spotShadowFrame,
    required PointShadowFrame? pointShadowFrame,
  }) {
    final pool = _probeCapturePool ??= TransientTexturePool();
    // Faces render with the cube-seam overscan widening so the assembled
    // equirect's edge texel centers land on the cube-edge directions.
    final fov = 2.0 * math.atan(1.0 / cubeFaceOverscan(faceResolution));
    final size = ui.Size(faceResolution.toDouble(), faceResolution.toDouble());
    final faces = <gpu.Texture>[];
    for (final (forward, up) in cubeFaceBases) {
      final face = createHdrCaptureTarget(faceResolution);
      pool.beginFrame();
      _renderViewToTexture(
        view: RenderView(
          camera: PerspectiveCamera(
            fovRadiansY: fov,
            position: position,
            target: position + forward,
            up: up,
          ),
          layerMask: layerMask,
        ),
        outputColor: face,
        pixelSize: size,
        pool: pool,
        environmentMap: environmentMap,
        transientsBuffer: transientsBuffer,
        lightComponent: lightComponent,
        punctualLighting: punctualLighting,
        spotShadowFrame: spotShadowFrame,
        pointShadowFrame: pointShadowFrame,
        captureLinearColor: true,
      );
      faces.add(face);
    }
    return buildEnvironmentFromFaces(
      faces,
      faceResolution,
      equirectWidth: equirectWidth,
    );
  }

  /// Bakes the irradiance field by rendering the scene from every probe in the
  /// active volume.
  ///
  /// Runs [probesPerStep] probes per call to the returned stepper so a load
  /// screen can stay responsive.
  /// {@category Lighting and environment}
  IrradianceFieldBakeStepper bakeIrradianceField({
    int faceResolution = 16,
    int probesPerStep = 8,
    int layerMask = 0xFFFFFFFF,
  }) {
    if (!isReadyToRender) {
      throw StateError(
        'Scene.bakeIrradianceField requires the engine resources; await '
        'Scene.initializeStaticResources() first.',
      );
    }
    renderScene.rebuildIfDirty();
    final lightComponent = renderScene.primaryDirectionalLight;
    final spotShadowFrame = collectSpotShadows(renderScene.spotLights);
    final pointShadowFrame = collectPointShadows(renderScene.pointLights);
    final punctualLighting = _punctualLightBuffer.build(
      directionals: renderScene.directionalLights,
      primaryDirectional: lightComponent,
      points: renderScene.pointLights,
      spots: renderScene.spotLights,
      areas: renderScene.rectAreaLights,
      items: renderScene.items,
      bvh: renderScene.bvh,
      spotShadows: spotShadowFrame,
      pointShadows: pointShadowFrame,
      enableFroxels: punctualLightClustering,
    );
    final chosen = renderScene.irradianceVolumeComponents.isNotEmpty
        ? renderScene.irradianceVolumeComponents.first
        : null;
    final center = chosen != null ? chosen.worldCenter : Vector3.zero();
    final extents = chosen != null
        ? chosen.extents * 2.0
        : globalIllumination.extents;
    final resolution = chosen != null
        ? chosen.resolution
        : globalIllumination.resolution;
    final layout = IrradianceFieldLayout(resolution);
    final origin = center - extents * 0.5;
    final spacing = Vector3(
      resolution.x > 1 ? extents.x / (resolution.x - 1) : extents.x,
      resolution.y > 1 ? extents.y / (resolution.y - 1) : extents.y,
      resolution.z > 1 ? extents.z / (resolution.z - 1) : extents.z,
    );
    return IrradianceFieldBakeStepper(
      layout: layout,
      origin: origin,
      spacing: spacing,
      faceResolution: faceResolution,
      probesPerStep: probesPerStep,
      layerMask: layerMask,
      renderScene: renderScene,
      environmentMap: environment ?? Material.getDefaultEnvironmentMap(),
      transientsBuffer: uniformTransients,
      lightComponent: lightComponent,
      punctualLighting: punctualLighting,
      spotShadowFrame: spotShadowFrame,
      pointShadowFrame: pointShadowFrame,
      renderView: _renderViewToTexture,
    );
  }

  // Applies the camera-position blend of the manual [environmentVolumes] and
  // the mounted environment-volume components over [baseEnvironment] to the
  // live look fields, before the environment is used this frame. A no-op unless
  // a base is set and there is at least one volume.
  void _applyEnvironmentVolumes(Camera camera) {
    final base = baseEnvironment;
    final components = renderScene.environmentVolumeComponents;
    final probes = <ReflectionProbeComponent>[
      for (final p in renderScene.reflectionProbeComponents)
        if (p.internalCrossfadeSettings != null) p,
    ];
    final hasVolumes = environmentVolumes.isNotEmpty || components.isNotEmpty;
    if ((base == null && probes.isEmpty) || (!hasVolumes && probes.isEmpty)) {
      _crossfadeEnvironment = null;
      _crossfadeBlend = 0.0;
      return;
    }
    final position = camera.position;
    final contributions = <EnvironmentContribution>[
      for (final v in environmentVolumes)
        EnvironmentContribution(
          v.settings,
          (v.coverage(position) * v.weight).clamp(0.0, 1.0),
          v.priority,
        ),
      for (final c in components)
        EnvironmentContribution(
          c.settings,
          (c.coverage(position) * c.weight).clamp(0.0, 1.0),
          c.priority,
        ),
    ];
    if (base != null && contributions.isNotEmpty) {
      blendEnvironmentContributions(base, contributions).applyTo(this);
    }
    // Reflection probes join only the image-based-lighting cross-fade; their
    // settings carry nothing but the captured environment, so they never
    // drag the scene's other look fields. Without a base environment
    // snapshot, the current environment stands in as the cross-fade base.
    final crossfadeBase =
        base ??
        EnvironmentSettings(
          environment: environment ?? Material.getDefaultEnvironmentMap(),
          skyEnvironment: skyEnvironment,
        );
    final crossfadeContributions = <EnvironmentContribution>[
      ...contributions,
      for (final p in probes)
        EnvironmentContribution(
          p.internalCrossfadeSettings!,
          (p.coverage(position) * p.weight).clamp(0.0, 1.0),
          p.priority,
        ),
    ];
    // Keep the image-based lighting continuous across the midpoint: hold the
    // primary environment and pass the secondary plus a blend factor to the
    // material, rather than letting applyTo switch it.
    final crossfade = resolveEnvironmentCrossfadeFromContributions(
      crossfadeBase,
      crossfadeContributions,
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

  /// Opt-in for [captureRenderGraph] and the render-graph debug hooks.
  /// False (the shipping default) keeps the capture branch tree-shakeable;
  /// an editor or debugging host sets it at startup.
  /// {@category Rendering}
  static bool get debugAllowRenderGraphCapture => RenderGraphDebug.enabled;
  static set debugAllowRenderGraphCapture(bool value) =>
      RenderGraphDebug.enabled = value;

  ({
    int viewIndex,
    RenderGraphCaptureRequest request,
    Completer<RenderGraphCaptureResult> completer,
  })?
  _pendingGraphCapture;

  /// Captures the next rendered frame of screen view [viewIndex]: the pass
  /// list with CPU timings, the blackboard data flow, and (per [request])
  /// GPU copies of the textures each pass wrote. Resolves after that frame's
  /// graph executes; the caller must ensure a frame renders (schedule one).
  ///
  /// Requires [debugAllowRenderGraphCapture]. A second call before the
  /// pending one resolves replaces it, and a capture no frame fulfills
  /// within [timeout] (the view hidden, zero-sized, or the scene not ready)
  /// fails instead of hanging its caller; either way the first future
  /// completes with an error.
  /// {@category Rendering}
  Future<RenderGraphCaptureResult> captureRenderGraph({
    int viewIndex = 0,
    RenderGraphCaptureRequest request = const RenderGraphCaptureRequest(),
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (!debugAllowRenderGraphCapture) {
      throw StateError(
        'Render graph capture is disabled; set '
        'Scene.debugAllowRenderGraphCapture first.',
      );
    }
    final pending = _pendingGraphCapture;
    if (pending != null) {
      _pendingGraphCapture = null;
      pending.completer.completeError(
        StateError('Superseded by a newer render graph capture'),
      );
    }
    final completer = Completer<RenderGraphCaptureResult>();
    final armed = (
      viewIndex: viewIndex,
      request: request,
      completer: completer,
    );
    _pendingGraphCapture = armed;
    Timer(timeout, () {
      if (!identical(_pendingGraphCapture, armed)) return;
      _pendingGraphCapture = null;
      completer.completeError(
        StateError(
          'Render graph capture timed out; no frame rendered view '
          '$viewIndex (is the viewport visible and the scene ready?)',
        ),
      );
    });
    return completer.future;
  }

  Iterable<CustomRenderPass> _passesAt(RenderStage stage) =>
      _renderPasses.where((p) => p.enabled && p.stage == stage);

  /// Screen-space ambient occlusion settings. Off by default; set
  /// [AmbientOcclusionSettings.enabled] to turn it on. Requires a
  /// [PerspectiveCamera] (the occlusion is reconstructed from the camera's
  /// perspective depth); it is skipped for other camera types.
  final AmbientOcclusionSettings ambientOcclusion = AmbientOcclusionSettings();

  /// Screen-space reflection settings. Off by default; set
  /// [ScreenSpaceReflectionsSettings.enabled] to turn it on. Requires a
  /// [PerspectiveCamera] (the reflection trace is reconstructed from the
  /// camera's perspective depth); it is skipped for other camera types.
  final ScreenSpaceReflectionsSettings screenSpaceReflections =
      ScreenSpaceReflectionsSettings();

  /// World-space global illumination settings. Off by default; set
  /// [GlobalIlluminationSettings.enabled] to turn the irradiance field on.
  /// Requires a [PerspectiveCamera] (the injection scatter reconstructs world
  /// positions from the camera's perspective depth); it is skipped for other
  /// camera types, and it forces the depth prepass with normals on.
  final GlobalIlluminationSettings globalIllumination =
      GlobalIlluminationSettings();

  final IrradianceFieldState _irradianceField = IrradianceFieldState();

  /// The probe lattice the global-illumination field is filling this frame,
  /// or null when the field is off or has not run a frame yet.
  ///
  /// The placement depends on the volume mode, the camera, and the scene
  /// bounds, and is resolved per frame inside the renderer, so this is the
  /// only reliable source for drawing where the probes actually are.
  /// {@category Lighting and environment}
  IrradianceProbeGrid? get globalIlluminationProbeGrid {
    final placement = _irradianceField.placement;
    final layout = _irradianceField.layout;
    if (placement == null || layout == null) return null;
    return IrradianceProbeGrid(
      origin: placement.origin,
      spacing: placement.spacing,
      counts: layout.resolution,
    );
  }

  /// Discards the accumulated irradiance field so it refills from scratch,
  /// for a hard camera cut or a wholesale lighting change that should not
  /// converge in over the hysteresis tail.
  void invalidateGlobalIllumination() => _irradianceField.invalidate();

  /// Temporal anti-aliasing settings. Active when [antiAliasingMode] is
  /// [AntiAliasingMode.taa].
  final TemporalAntiAliasingSettings temporalAntiAliasing =
      TemporalAntiAliasingSettings();

  /// SMAA quality settings. Active when [antiAliasingMode] is
  /// [AntiAliasingMode.smaa].
  final SmaaSettings smaa = SmaaSettings();

  // TODO(taa-multiview): track TAA history and jitter per view rather than
  // per scene so multiview configurations do not share history.
  TaaHistoryState? _taaState;
  int _taaFrameIndex = 0;

  /// Distance fog. Off by default; set [Fog.enabled] and a [Fog.mode] to turn it
  /// on. Applied per-fragment by every material in linear HDR before tone
  /// mapping, so it works on any camera type.
  final Fog fog = Fog();

  /// Directional volumetric god rays. Off by default; set
  /// [GodRaysSettings.enabled] to turn them on. Requires a shadow-casting
  /// [DirectionalLight] and a [PerspectiveCamera] (they march the cascaded
  /// shadow map against the camera depth); skipped otherwise.
  final GodRaysSettings godRays = GodRaysSettings();
  late final GodRaysPass _godRaysPass = GodRaysPass(godRays);

  /// Parametric radial screen distortion pulses. Off by default; set
  /// [ScreenDistortionSettings.enabled] and add a [DistortionPulse] to turn
  /// it on. Runs on the display-referred image after tone mapping.
  final ScreenDistortionSettings screenDistortion = ScreenDistortionSettings();
  late final ScreenDistortionPass _screenDistortionPass = ScreenDistortionPass(
    screenDistortion,
  );

  /// Depth of field with bokeh. Off by default; set [DepthOfField.enabled]
  /// to turn it on. Requires a [PerspectiveCamera] (it reconstructs blur from
  /// camera depth); skipped otherwise.
  final DepthOfField depthOfField = DepthOfField();

  /// Automatic exposure (eye adaptation). Off by default; set
  /// [AutoExposureSettings.enabled] to turn it on. Meters the rendered HDR
  /// image on the GPU each frame and eases a correction factor the resolve
  /// multiplies with [exposure], so [exposure] stays the artistic base.
  final AutoExposureSettings autoExposure = AutoExposureSettings();

  // Cross-frame auto exposure adaptation state (the persistent 1x1 factor
  // ping-pong), created the first enabled frame and dropped when disabled,
  // so re-enabling starts fresh and snaps to the metered target.
  AutoExposureState? _autoExposureState;

  // Cross-frame cache for the directional light's shadow tiles, created the
  // first frame any visible caster is `shadowStatic` and dropped when none
  // are (or the light stops casting). See DirectionalShadowCache.
  DirectionalShadowCache? _directionalShadowCache;

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
    _syncAudio(deltaSeconds);
  }

  // Syncs the active [AudioEngine] (if any) after component ticks, so
  // source transforms pushed during the tick land in the same frame's
  // backend flush.
  void _syncAudio(double frameDt) {
    root.getComponent<AudioEngine>()?.frameSync(
      frameDt,
      fallbackCamera: camera,
    );
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

  /// Compiles the render pipelines and uploads the GPU resources this scene
  /// needs, by encoding one frame offscreen and discarding it, so the first
  /// visible frame does not stall while shaders compile or textures upload.
  ///
  /// Pass the same [views] the scene will be shown with: their cameras,
  /// anti-aliasing, render targets, and this scene's lights and post-process
  /// settings determine which pipeline variants compile, so a warm-up frame
  /// must match the real one (the offscreen frame is rendered tiny, since a
  /// pipeline's identity does not depend on resolution). Populate the scene
  /// first; warm-up encodes whatever is attached when it runs.
  ///
  /// A `SceneView` with `warmUp: true` calls this before it reveals the scene.
  /// Awaiting it is optional and safe to repeat. It awaits
  /// [initializeStaticResources] first. On backends that compile pipelines
  /// lazily on first draw (the common case) this front-loads that cost; on a
  /// backend that compiles asynchronously it kicks compilation off without
  /// blocking on completion.
  ///
  /// Set [includeOffscreen] to encode every render item once. This costs more
  /// during loading, but avoids later pipeline stalls as a moving camera first
  /// reaches parts of a large scene.
  /// {@category Assets and loading}
  Future<void> warmUp(
    List<RenderView> views, {
    bool includeOffscreen = false,
  }) async {
    await initializeStaticResources();
    if (views.isEmpty) {
      return;
    }
    // Advance a zero step so the warm-up frame does not move the scene's clock
    // forward before the first real frame (render then skips its implicit
    // wall-clock tick).
    update(0.0);
    // Encode one real frame into a discarded recording. The GPU passes (and so
    // the pipeline compilations and resource uploads) are submitted during
    // rendering; only the final canvas blit is thrown away. A small area is
    // enough because pipeline identity is resolution-independent.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    _warmUpIncludeOffscreen = includeOffscreen;
    try {
      renderViews(views, canvas, region: const ui.Rect.fromLTWH(0, 0, 64, 64));
    } finally {
      _warmUpIncludeOffscreen = false;
      recorder.endRecording().dispose();
    }
  }

  bool _warmUpIncludeOffscreen = false;

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
      assert(() {
        _reportBlankFrame(
          const <RenderView>[],
          regionEmpty: drawArea.isEmpty,
          noViews: views.isEmpty,
        );
        return true;
      }());
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

    // Advance the per-frame transient arenas (uniform blocks and
    // instance-rate vertex data): recycle blocks whose GPU work completed
    // and reset the frame stats. Shared by every view this frame.
    uniformTransients.beginFrame();
    instanceTransients.beginFrame();
    final TransientWriter transientsBuffer = uniformTransients;

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

    // A hidden node's lights stop contributing, matching its meshes.
    final visibleDirectionals = [
      for (final light in renderScene.directionalLights)
        if (light.node.internalEffectiveVisible) light,
    ];
    final visiblePoints = [
      for (final light in renderScene.pointLights)
        if (light.node.internalEffectiveVisible) light,
    ];
    final visibleSpots = [
      for (final light in renderScene.spotLights)
        if (light.node.internalEffectiveVisible) light,
    ];
    final visibleAreas = [
      for (final light in renderScene.rectAreaLights)
        if (light.node.internalEffectiveVisible) light,
    ];

    // Cascaded shadows and other single-sun features use the selected primary.
    // All other directional lights remain in the additional-light buffer.
    final lightComponent = renderScene.primaryDirectionalLight;

    // Select this frame's shadow-casting spots and point lights
    // (view-independent).
    final spotShadowFrame = collectSpotShadows(visibleSpots);
    final pointShadowFrame = collectPointShadows(visiblePoints);
    // Every tile in the shared atlas is one size, so resolve it once here
    // rather than per view: the point rows stamp their face resolution from
    // it, and ShadowPass renders the faces at the same size. The directional
    // light wins because its cascades need the resolution most.
    // TODO(shadow-atlas-per-light-tiles): a per-light tile size needs the
    // atlas to stop being one uniform strip, at which point
    // PointLight.shadowMapResolution and SpotLight.shadowMapResolution can
    // mean what they say for every light rather than only the first caster.
    final shadowTileResolution = lightComponent?.light.castsShadow == true
        ? lightComponent!.light.shadowMapResolution
        : spotShadowFrame?.tileResolution ??
              (pointShadowFrame == null
                  ? 1024
                  : pointShadowFrame.casters.first.light.shadowMapResolution *
                        2);

    _recordShadowCasterBudget(
      spots: visibleSpots,
      points: visiblePoints,
      spotShadows: spotShadowFrame,
      pointShadows: pointShadowFrame,
    );

    // The additional analytic lights (point, spot, and directional lights past
    // the first) are view-independent, so build their shared data texture once
    // per frame here rather than per view.
    final punctualLighting = _punctualLightBuffer.build(
      directionals: visibleDirectionals,
      primaryDirectional: lightComponent,
      points: visiblePoints,
      spots: visibleSpots,
      areas: visibleAreas,
      items: renderScene.items,
      bvh: renderScene.bvh,
      spotShadows: spotShadowFrame,
      pointShadows: pointShadowFrame,
      pointFaceResolution: shadowTileResolution ~/ 2,
      enableFroxels: punctualLightClustering,
    );

    // Pending reflection-probe captures render before any view. The frame's
    // cross-fade was resolved before this point, so a probe's very first
    // capture reaches the lighting one frame later.
    for (final probe in renderScene.reflectionProbeComponents) {
      if (!probe.capturePending) {
        continue;
      }
      probe.internalStoreCapture(
        _captureEnvironmentAt(
          position: probe.worldCenter,
          faceResolution: probe.faceResolution,
          equirectWidth: 512,
          layerMask: 0xFFFFFFFF,
          environmentMap: environmentMap,
          transientsBuffer: transientsBuffer,
          lightComponent: lightComponent,
          punctualLighting: punctualLighting,
          spotShadowFrame: spotShadowFrame,
          pointShadowFrame: pointShadowFrame,
        ),
      );
    }

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

    // Planar reflection captures follow one view's camera: the first screen
    // view, or the first texture view of a frame with no screen views.
    // Texture views render before the screen views' captures, so they
    // composite the previous frame's capture.
    RenderView? planarCaptureView;
    for (final view in views) {
      if (view.target == null) {
        planarCaptureView = view;
        break;
      }
    }
    planarCaptureView ??= textureViews.isNotEmpty ? textureViews.first : null;

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
        punctualLighting: punctualLighting,
        spotShadowFrame: spotShadowFrame,
        pointShadowFrame: pointShadowFrame,
        capturePlanarReflections: identical(view, planarCaptureView),
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
        punctualLighting: punctualLighting,
        spotShadowFrame: spotShadowFrame,
        pointShadowFrame: pointShadowFrame,
        capturePlanarReflections: identical(view, planarCaptureView),
      );
    }

    // A frame has now been submitted; the next one runs on a warm context (see
    // the rebuild near the environment resolution above).
    _hasPresentedFrame = true;

    assert(() {
      _reportBlankFrame(ordered, regionEmpty: false, noViews: false);
      return true;
    }());
  }

  // Debug-only. Detects a frame that issued zero draw calls and, once per
  // occurrence, prints a message naming the causes it can tell apart, so a
  // blank frame is not left unexplained. The latch resets whenever a frame
  // draws, so a later regression prints again. Called only inside asserts, so
  // it never runs in a release build; even in debug it stops at the first
  // visible on-layer node, doing no extra work on a frame that draws.
  void _reportBlankFrame(
    List<RenderView> screenViews, {
    required bool regionEmpty,
    required bool noViews,
  }) {
    // Cheap draw test. A skybox fills the frame; otherwise a frame draws when
    // some on-screen view has a visible node on its layer mask. A blank frame
    // from a degenerate camera basis or a frustum-excluded camera aim is left
    // to the camera asserts (a per-frame frustum cull here would tax the
    // drawing path), so this test intentionally ignores the frustum.
    var drewSomething = false;
    if (!regionEmpty && !noViews && screenViews.isNotEmpty) {
      if (skybox != null) {
        drewSomething = true;
      } else {
        outer:
        for (final view in screenViews) {
          if (view.layerMask == 0) continue;
          for (final item in renderScene.items) {
            if (item.visible && (item.layers & view.layerMask) != 0) {
              drewSomething = true;
              break outer;
            }
          }
        }
      }
    }

    // Only tallied when nothing drew (the broken case); skipped entirely on a
    // frame that drew.
    var visibleMeshCount = 0;
    var visibleLayersUnion = 0;
    if (!drewSomething) {
      for (final item in renderScene.items) {
        if (item.visible) {
          visibleMeshCount++;
          visibleLayersUnion |= item.layers;
        }
      }
    }

    final result = debugEmptyFrameDiagnosis(
      warned: _warnedBlankFrame,
      drewSomething: drewSomething,
      regionEmpty: regionEmpty,
      noViews: noViews,
      noScreenViews: !regionEmpty && !noViews && screenViews.isEmpty,
      meshCount: renderScene.items.length,
      visibleMeshCount: visibleMeshCount,
      anyLayerMaskZero: screenViews.any((v) => v.layerMask == 0),
      screenViewMasks: [for (final v in screenViews) v.layerMask],
      visibleLayersUnion: visibleLayersUnion,
    );
    _warnedBlankFrame = result.warned;
    final message = result.message;
    if (message != null) debugPrint(message);
  }

  /// Diagnoses a frame that issued zero draw calls, for [renderViews].
  ///
  /// Returns the message to print (null when nothing should print) and the
  /// next state of the once-only latch. A frame that drew ([drewSomething])
  /// clears the latch so a later regression prints again; a blank frame prints
  /// one message the first time and stays silent until a frame draws. The
  /// caller invokes this inside an assert, so neither it nor the scan feeding
  /// it costs anything in a release build.
  @visibleForTesting
  static ({String? message, bool warned}) debugEmptyFrameDiagnosis({
    required bool warned,
    required bool drewSomething,
    required bool regionEmpty,
    required bool noViews,
    required bool noScreenViews,
    required int meshCount,
    required int visibleMeshCount,
    required bool anyLayerMaskZero,
    required List<int> screenViewMasks,
    required int visibleLayersUnion,
  }) {
    if (drewSomething) return (message: null, warned: false);
    if (warned) return (message: null, warned: true);
    final cause = _blankFrameCause(
      regionEmpty: regionEmpty,
      noViews: noViews,
      noScreenViews: noScreenViews,
      meshCount: meshCount,
      visibleMeshCount: visibleMeshCount,
      anyLayerMaskZero: anyLayerMaskZero,
      screenViewMasks: screenViewMasks,
      visibleLayersUnion: visibleLayersUnion,
    );
    return (
      message: 'Flutter Scene rendered a blank frame (zero draw calls). $cause',
      warned: true,
    );
  }

  // Names the most specific blank-frame cause that the given facts pin down.
  // Every rung is a fact the diagnostic actually checked, in priority order,
  // so the message never guesses. A degenerate camera basis and a
  // frustum-excluded camera aim are handled by the camera asserts, not here.
  static String _blankFrameCause({
    required bool regionEmpty,
    required bool noViews,
    required bool noScreenViews,
    required int meshCount,
    required int visibleMeshCount,
    required bool anyLayerMaskZero,
    required List<int> screenViewMasks,
    required int visibleLayersUnion,
  }) {
    if (noViews) {
      return 'No RenderViews were supplied. Pass at least one RenderView to '
          'renderViews, or use render for the single-camera case.';
    }
    if (regionEmpty) {
      return 'The draw region is zero-sized, so there is nowhere to draw. Pass '
          'an explicit region to renderViews, or check the widget constraints '
          '(a collapsed or unconstrained layout gives an empty canvas clip).';
    }
    if (noScreenViews) {
      return 'Every RenderView has a target, so nothing composites to the '
          'screen. Add a RenderView whose target is null for the on-screen '
          'view.';
    }
    if (meshCount == 0) {
      return 'The scene graph holds no meshes. Add a Node with a Mesh under '
          'the scene root before rendering.';
    }
    if (visibleMeshCount == 0) {
      return 'Every mesh in the scene is hidden. Node.visible is false on each '
          'mesh or on an ancestor; set visible to true on the nodes to draw.';
    }
    if (anyLayerMaskZero) {
      return 'A RenderView.layerMask is 0, which matches no Node.layers, so '
          'that view draws nothing. Use kRenderLayerAll to see every layer, or '
          'a bitmask such as (1 << 2) to select layer 2.';
    }
    final masks = screenViewMasks.map(_hexMask).join(', ');
    return 'No visible node is on any view layerMask (view masks $masks, node '
        'layers ${_hexMask(visibleLayersUnion)}). Node.layers is not inherited '
        'by children, so set it on each node the view should see, or widen the '
        'view mask.';
  }

  static String _hexMask(int mask) =>
      '0x${(mask & 0xFFFFFFFF).toRadixString(16)}';

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
    required TransientWriter transientsBuffer,
    required DirectionalLightComponent? lightComponent,
    required PunctualLighting punctualLighting,
    required SpotShadowFrame? spotShadowFrame,
    required PointShadowFrame? pointShadowFrame,
    bool capturePlanarReflections = false,
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

    // Consume a pending render-graph capture aimed at this screen view.
    RenderGraphCapturer? capturer;
    final pendingCapture = _pendingGraphCapture;
    if (pendingCapture != null && pendingCapture.viewIndex == viewIndex) {
      _pendingGraphCapture = null;
      capturer = RenderGraphCapturer(request: pendingCapture.request);
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
      punctualLighting: punctualLighting,
      spotShadowFrame: spotShadowFrame,
      pointShadowFrame: pointShadowFrame,
      capturer: capturer,
      capturePlanarReflections: capturePlanarReflections,
    );
    if (capturer != null) {
      pendingCapture!.completer.complete(
        capturer.finish(
          pixelWidth: pixelSize.width.toInt(),
          pixelHeight: pixelSize.height.toInt(),
        ),
      );
    }

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
    required TransientWriter transientsBuffer,
    required DirectionalLightComponent? lightComponent,
    required PunctualLighting punctualLighting,
    required SpotShadowFrame? spotShadowFrame,
    required PointShadowFrame? pointShadowFrame,
    RenderGraphCapturer? capturer,
    // A linear-HDR capture (environment probes): the graph stops after the
    // scene pass and blits the lit scene color into [outputColor], with no
    // reflections, indirect-light history, post-processing, anti-aliasing,
    // or display-referred chain.
    bool captureLinearColor = false,
    // Whether this view renders the frame's planar reflection captures (the
    // primary view only; captures follow its camera and other views reuse
    // its result). Never set for a linear-color capture.
    bool capturePlanarReflections = false,
  }) {
    // A capture frame observes the pool from graph construction on, so
    // display-chain and custom-pass destinations acquired before execute are
    // attributed and identified by their descriptor debug names.
    if (capturer != null) {
      pool = ObservedTexturePool(pool, capturer);
    }
    final camera = view.camera;
    final effectiveAa = captureLinearColor
        ? AntiAliasingMode.none
        : _resolveAntiAliasingMode(view.antiAliasingMode ?? _antiAliasingMode);
    final enableMsaa = effectiveAa == AntiAliasingMode.msaa;
    final enableFxaa = effectiveAa == AntiAliasingMode.fxaa;
    final enableSmaa =
        effectiveAa == AntiAliasingMode.smaa && SmaaPass.isInitialized;

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

    // God rays march the cascaded shadow map against the camera depth, so they
    // need both and a shadow-casting directional light.
    final wantGodRays =
        godRays.enabled &&
        camera.projection is PerspectiveProjection &&
        cascades.isNotEmpty;

    // A pure display-referred image warp; no depth, shadow, or camera
    // projection needed.
    final wantScreenDistortion =
        screenDistortion.enabled && screenDistortion.pulses.isNotEmpty;

    // The geometry buffers the enabled custom passes (and god rays) request, so
    // the engine produces depth/normals even without AO/SSR and publishes the
    // shadow uniform for depth-aware passes.
    final customInputs = <RenderInput>{};
    for (final pass in _renderPasses) {
      if (pass.enabled) customInputs.addAll(pass.inputs);
    }
    if (wantGodRays) customInputs.addAll(_godRaysPass.inputs);

    // Most scenes request no material scene inputs. Cache that whole-scene
    // answer across movement, then cull per view only when at least one
    // material can need an attachment. Opaque occlusion remains a GPU
    // depth-test concern because an AABB cannot prove a mesh is hidden.
    // TODO(occlusion-culling): use a previous-frame hierarchical depth buffer
    // to reject fully hidden render items and scene-input requests.
    final structureRevision = renderScene.structureRevision;
    final materialRevision = materialSceneInputsRevision;
    if (_materialInputStructureRevision != structureRevision ||
        _materialInputMaterialRevision != materialRevision) {
      _cachedWholeSceneMaterialInputs = renderScene.collectAllMaterialInputs();
      _materialInputStructureRevision = structureRevision;
      _materialInputMaterialRevision = materialRevision;
    }
    final wholeSceneMaterialInputs = _cachedWholeSceneMaterialInputs;
    final materialInputs = wholeSceneMaterialInputs.isEmpty
        ? wholeSceneMaterialInputs
        : renderScene.collectMaterialInputs(
            camera.getFrustum(pixelSize),
            layerMask: view.layerMask,
            additionalPlanes: view.cullingPlanes,
            includeOffscreen: _warmUpIncludeOffscreen,
          );

    // The retained metadata below fingerprints static shadow casters.
    final staticShadowRevision = renderScene.staticShadowRevision;
    final refreshStaticShadows =
        _renderMetadataStructureRevision != structureRevision ||
        _renderMetadataStaticShadowRevision != staticShadowRevision;
    if (refreshStaticShadows) {
      var staticShadowSignature = _cachedStaticShadowSignature;
      var hasStaticShadowCasters = _cachedHasStaticShadowCasters;
      staticShadowSignature = 0;
      hasStaticShadowCasters = false;
      for (final item in renderScene.items) {
        if (item.shadowStatic && item.castsShadows && item.visible) {
          hasStaticShadowCasters = true;
          final t = item.worldTransform.storage;
          staticShadowSignature =
              0x3fffffff &
              (staticShadowSignature * 31 +
                  identityHashCode(item.geometry) +
                  identityHashCode(item.instanceTransforms) +
                  // Material identity matters to the depth pass (alpha-masked
                  // casters render through the masked depth shader), so a
                  // swapped material must invalidate cached static tiles.
                  identityHashCode(item.material) +
                  // A caster's channels decide which lights it casts into.
                  item.lightChannelMask +
                  t[12].hashCode * 3 +
                  t[13].hashCode * 7 +
                  t[14].hashCode * 13);
        }
      }
      _cachedStaticShadowSignature = staticShadowSignature;
      _cachedHasStaticShadowCasters = hasStaticShadowCasters;
      _renderMetadataStaticShadowRevision = staticShadowRevision;
      _renderMetadataStructureRevision = structureRevision;
    }
    final staticShadowSignature = _cachedStaticShadowSignature;
    final hasStaticShadowCasters = _cachedHasStaticShadowCasters;
    final captureOpaqueColor =
        materialInputs.contains(RenderInput.opaqueSceneColor) ||
        materialInputs.contains(RenderInput.filteredSceneColor);
    final bindSceneDepth = materialInputs.contains(RenderInput.depth);
    if (bindSceneDepth) customInputs.add(RenderInput.depth);
    // Depth of field reconstructs blur from camera depth.
    if (depthOfField.enabled) customInputs.add(RenderInput.depth);

    // When any visible caster is static, route the cascades through the
    // shadow cache: static casters render into persistent tiles only when
    // coverage or content changes, and every consumer samples through the
    // cached matrices. Without static casters the cache is dropped and the
    // shadow pass renders everything per frame, exactly as before.
    ShadowCachePlan? shadowCachePlan;
    var effectiveCascades = cascades;
    if (cascades.isNotEmpty &&
        hasStaticShadowCasters &&
        light != null &&
        light.cacheStaticShadows) {
      shadowCachePlan = (_directionalShadowCache ??= DirectionalShadowCache())
          .plan(
            light: light,
            lightDirection: lightDirection ?? light.direction,
            idealCascades: cascades,
            staticSignature: staticShadowSignature,
          );
      effectiveCascades = shadowCachePlan.cascades;
    } else {
      _directionalShadowCache = null;
    }

    final graph = RenderGraph();
    // Directional cascades, shadow-casting spots, and shadow-casting point
    // lights share one atlas (and so one sampler in the lit shader). All tiles
    // use one resolution, the directional light's when it casts, otherwise the
    // spots', otherwise twice a point caster's face resolution (faces pack
    // four to a tile at half the tile edge).
    if (cascades.isNotEmpty ||
        spotShadowFrame != null ||
        pointShadowFrame != null) {
      graph.addPass(
        ShadowPass(
          renderScene: renderScene,
          cascades: effectiveCascades,
          tileResolution: cascades.isNotEmpty
              ? light!.shadowMapResolution
              : spotShadowFrame?.tileResolution ??
                    pointShadowFrame!.casters.first.light.shadowMapResolution *
                        2,
          casterFaces: cascades.isNotEmpty
              ? light!.shadowCasterFaces
              : ShadowCasterFaces.front,
          casterChannelMask: cascades.isNotEmpty
              ? light!.shadowCasterChannelMask
              : 0xFF,
          cameraPosition: camera.position,
          spotShadows: spotShadowFrame,
          pointShadows: pointShadowFrame,
          cachePlan: shadowCachePlan,
          // PostShadowInfo describes the directional cascades, so publish it
          // only when they exist (a spot-only atlas has no directional light).
          shadowUniform:
              cascades.isNotEmpty &&
                  customInputs.contains(RenderInput.shadowMap)
              ? packPostShadowInfo(
                  effectiveCascades,
                  lightDirection ?? light!.direction,
                  light!.color * light.intensity,
                )
              : null,
        ),
      );
    }
    // Baked shadow catchers refresh their footprint caches right after the
    // atlas renders, so the scene pass samples a current cache this frame.
    List<RenderItem>? catcherBakes;
    for (final item in renderScene.items) {
      final material = item.material;
      if (item.visible &&
          material is ShadowCatcherMaterial &&
          material.needsBakedShadowRefresh) {
        (catcherBakes ??= []).add(item);
      }
    }
    if (catcherBakes != null) {
      graph.addPass(
        ShadowCatcherBakePass(
          items: catcherBakes,
          environmentMap: environmentMap,
          directionalLight: light,
          directionalLightDirection: lightDirection,
          punctualLighting: punctualLighting,
          cascades: effectiveCascades,
        ),
      );
    }

    // Planar reflection captures render right after the shadow atlas they
    // reuse and before the view's own scene work, so mirror surfaces sample
    // this frame's captures. A frame without reflectors adds nothing here.
    if (capturePlanarReflections && !captureLinearColor) {
      final capturePasses = _buildPlanarCapturePasses(
        view: view,
        camera: camera,
        pixelSize: pixelSize,
        environmentMap: environmentMap,
        lightComponent: lightComponent,
        punctualLighting: punctualLighting,
        cascades: effectiveCascades,
        time: DateTime.now().millisecondsSinceEpoch.remainder(100000) / 1000.0,
      );
      for (final pass in capturePasses) {
        graph.addPass(pass);
      }
    }
    // Ambient occlusion, screen-space reflections, normals, and materials
    // that sample scene depth need the geometry prepass. Depth-only post
    // effects reuse the stored main-pass depth when it is single-sampled.
    // Depth and normal pre-passes need a perspective camera. Orthographic
    // cameras skip these effects.
    final perspective = camera.projection;
    final perspectiveCamera = perspective is PerspectiveProjection
        ? perspective
        : null;

    final enableTaa =
        effectiveAa == AntiAliasingMode.taa &&
        perspectiveCamera != null &&
        !captureLinearColor;

    Vector2 currentJitterNdc = Vector2.zero();
    Vector2 currentJitterUv = Vector2.zero();
    Vector2 prevJitterNdc = Vector2.zero();
    TaaHistoryState? taaState;
    if (enableTaa) {
      taaState = _taaState ??= TaaHistoryState();
      final haltonPt = halton23(
        (_taaFrameIndex % temporalAntiAliasing.jitterSequenceLength) + 1,
      );
      _taaFrameIndex++;
      currentJitterNdc = Vector2(
        (2 * haltonPt.x - 1) /
            pixelSize.width *
            temporalAntiAliasing.jitterScale,
        (2 * haltonPt.y - 1) /
            pixelSize.height *
            temporalAntiAliasing.jitterScale,
      );
      currentJitterUv = Vector2(
        currentJitterNdc.x * 0.5,
        -currentJitterNdc.y * 0.5,
      );
      prevJitterNdc = taaState.previousJitterNdc;
      taaState.previousJitterNdc = currentJitterNdc;
      taaState.previousJitterUv = currentJitterUv;
    }

    final currentJitteredViewProjection = enableTaa
        ? camera.getViewTransform(pixelSize, jitter: currentJitterNdc)
        : null;

    // Reflections run after the scene is drawn (they sample the lit color),
    // so capture whether they apply here and add the pass below.
    final wantSsr =
        !captureLinearColor &&
        perspectiveCamera != null &&
        screenSpaceReflections.enabled;
    // A custom pass may request depth/normals; normals imply depth.
    final wantCustomNormals = customInputs.contains(RenderInput.normals);
    final wantCustomDepth =
        wantCustomNormals || customInputs.contains(RenderInput.depth);
    // Flutter GPU does not expose whether a stored depth/stencil attachment is
    // shader-readable, so its readability cannot be assumed.
    // TODO(flutter-gpu): Reuse stored depth once that capability is exposed.
    final wantIndirectLight =
        !captureLinearColor &&
        ambientOcclusionCarriesIndirectLight(ambientOcclusion);
    // The irradiance field scatters from the depth prepass' normals and from
    // the previous frame's lit color, so it forces both on.
    final wantIrradianceField =
        !captureLinearColor &&
        perspectiveCamera != null &&
        globalIllumination.enabled;
    final wantSceneColorHistory = wantIndirectLight || wantIrradianceField;
    // The occlusion texture's channels carry radiance while indirect light
    // is on, so the contact-shadow term has nowhere to ride.
    // TODO(sampler-budget): lift this exclusivity with a dedicated sampler
    // once flutter/flutter#189332 raises the practical fragment budget.
    final wantContactShadows =
        !wantIndirectLight &&
        light != null &&
        light.contactShadows &&
        (lightDirection ?? light.direction).length2 > 0.0;
    final wantDepthPrepass =
        bindSceneDepth ||
        wantCustomNormals ||
        wantSsr ||
        wantIrradianceField ||
        enableTaa ||
        ambientOcclusion.enabled ||
        wantContactShadows ||
        wantCustomDepth;
    IrradianceFieldBinding? irradianceBinding;
    if (perspectiveCamera != null) {
      // The occlusion chain also carries the sun contact-shadow term, so it
      // runs (with occlusion sampling zeroed) when only contact shadows ask
      // for it.
      final wantAo = ambientOcclusion.enabled || wantContactShadows;
      final cameraForward = camera.forward;
      final cameraRight = camera.up.cross(cameraForward)..normalize();
      final cameraUp = cameraForward.cross(cameraRight)..normalize();
      if (wantDepthPrepass) {
        // Ambient occlusion evaluates its chain (depth prepass, occlusion,
        // blur) at one resolution so depth is sampled 1:1 (a half-resolution
        // occlusion pass reading a full-resolution depth would alias on fine
        // geometry). Size the prepass to occlusion's target whenever it is on
        // so its behavior is unchanged; reflections sample whatever resolution
        // is published. With only reflections on, use full resolution. The
        // depth-mip-chain path (SsaoPass builds the reduced levels) wants a
        // full-resolution base, so it also renders the prepass full size. A
        // material sampling scene depth reads it as an image, so it also gets
        // full resolution; a reduced prepass stair-steps every depth-driven
        // edge it draws.
        final depthDimensions =
            (wantAo &&
                !ambientOcclusion.depthMipChain &&
                !enableTaa &&
                !wantSsr &&
                !wantCustomNormals &&
                !wantIrradianceField &&
                !bindSceneDepth)
            ? ambientOcclusionTargetSize(pixelSize, ambientOcclusion)
            : pixelSize;
        // Reflections need the interpolated view-space normal, so the prepass
        // writes it alongside depth (it carries the camera basis to rotate
        // world normals into view space). Occlusion needs only depth.
        graph.addPass(
          DepthPrepass(
            camera: camera,
            renderScene: renderScene,
            dimensions: depthDimensions,
            cameraForward: cameraForward,
            farDepth: perspectiveCamera.far,
            layerMask: view.layerMask,
            writeNormals: wantSsr || wantCustomNormals || wantIrradianceField,
            // Depth of field patches translucent surfaces into the linear
            // depth later; the patch depth-tests against this attachment.
            // Storing it (a non-transient attachment plus store bandwidth)
            // is paid whenever depth of field is on, patch or no patch.
            keepDepthStencil:
                depthOfField.enabled ||
                (enableTaa && temporalAntiAliasing.objectMotion),
            cameraRight: cameraRight,
            cameraUp: cameraUp,
            cullingPlanes: view.cullingPlanes,
            cameraTransform: currentJitteredViewProjection,
          ),
        );
      }
      if (enableTaa && temporalAntiAliasing.objectMotion) {
        final prevViewProj =
            taaState!.previousViewTransform ??
            (currentJitteredViewProjection ??
                camera.getViewTransform(pixelSize));
        graph.addPass(
          VelocityPass(
            camera: camera,
            renderScene: renderScene,
            dimensions: pixelSize,
            currentViewProjection:
                currentJitteredViewProjection ??
                camera.getViewTransform(pixelSize),
            previousViewProjection: prevViewProj,
            currentJitterNdc: currentJitterNdc,
            previousJitterNdc: prevJitterNdc,
            layerMask: view.layerMask,
            cullingPlanes: view.cullingPlanes,
            skinnedMotion: temporalAntiAliasing.skinnedMotion,
          ),
        );
      }
      if (wantAo) {
        Vector3? contactDirectionView;
        if (wantContactShadows) {
          final toLight = -(lightDirection ?? light.direction).normalized();
          contactDirectionView = Vector3(
            toLight.dot(cameraRight),
            toLight.dot(cameraUp),
            toLight.dot(cameraForward),
          );
        }
        Matrix4? ssgiReprojection;
        if (wantIndirectLight) {
          // Maps the gather's view-space positions (the camera basis above,
          // forward along +z) to the history frame's clip space. On the
          // first frame the current view-projection stands in, which lands
          // every tap back on its own screen position.
          final position = camera.position;
          final viewToWorld = Matrix4(
            cameraRight.x,
            cameraRight.y,
            cameraRight.z,
            0.0, //
            cameraUp.x,
            cameraUp.y,
            cameraUp.z,
            0.0, //
            cameraForward.x,
            cameraForward.y,
            cameraForward.z,
            0.0, //
            position.x,
            position.y,
            position.z,
            1.0,
          );
          ssgiReprojection =
              (_ssgiHistoryViewProjection ??
                  camera.getViewTransform(pixelSize)) *
              viewToWorld;
        }
        graph.addPass(
          SsaoPass(
            dimensions: pixelSize,
            settings: ambientOcclusion,
            fovRadiansY: perspectiveCamera.fovRadiansY,
            near: perspectiveCamera.near,
            far: perspectiveCamera.far,
            contactDirectionView: contactDirectionView,
            contactDistance: wantContactShadows
                ? light.contactShadowDistance
                : 0.0,
            sceneRadiance: wantIndirectLight ? _ssgiHistoryColor : null,
            ssgiReprojection: ssgiReprojection,
          ),
        );
        graph.addPass(
          SsaoBlurPass(dimensions: pixelSize, settings: ambientOcclusion),
        );
      }
      if (wantIrradianceField) {
        irradianceBinding = _addIrradianceFieldPasses(
          graph: graph,
          camera: camera,
          pixelSize: pixelSize,
          cameraForward: cameraForward,
          cameraRight: cameraRight,
          cameraUp: cameraUp,
          perspectiveCamera: perspectiveCamera,
          environmentMap: environmentMap,
        );
      }
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
        punctualLighting: punctualLighting,
        cascades: effectiveCascades,
        // The cone mode needs the bent normal; fall back to the simple
        // estimate when the chain does not carry one.
        specularOcclusionMode:
            (ambientOcclusion.specularMode ==
                            SpecularAmbientOcclusionMode.bentCone &&
                        !ambientOcclusionCarriesBentNormals(ambientOcclusion)
                    ? SpecularAmbientOcclusionMode.simple
                    : ambientOcclusion.specularMode)
                .index
                .toDouble(),
        ssaoDirectLightAffect: ambientOcclusion.directLightAffect,
        ssaoMultiBounce: ambientOcclusion.multiBounce,
        ssaoBentNormals: ambientOcclusionCarriesBentNormals(ambientOcclusion),
        ssaoContactShadows: wantContactShadows && perspectiveCamera != null,
        ssaoIndirectLight: wantIndirectLight && perspectiveCamera != null,
        irradianceField: irradianceBinding,
        layerMask: view.layerMask,
        fog: fog,
        captureOpaqueColor: captureOpaqueColor,
        // Depth binding needs the prepass, which needs a perspective camera.
        bindSceneDepth: bindSceneDepth && perspectiveCamera != null,
        time: DateTime.now().millisecondsSinceEpoch.remainder(100000) / 1000.0,
        cullingPlanes: view.cullingPlanes,
        includeOffscreen: _warmUpIncludeOffscreen,
        cameraTransform: currentJitteredViewProjection,
      ),
    );
    if (wantSceneColorHistory) {
      graph.addPass(
        SceneColorHistoryPass(
          current: _ssgiHistoryColor,
          store: (texture) => _ssgiHistoryColor = texture,
        ),
      );
      _ssgiHistoryViewProjection = camera.getViewTransform(pixelSize);
    }
    if (captureLinearColor) {
      graph.addPass(SceneColorBlitPass(output: outputColor));
      graph.execute(
        transientsBuffer: transientsBuffer,
        texturePool: pool,
        observer: capturer,
      );
      return;
    }
    // Screen-space reflections refine the lit HDR color in place, before
    // bloom and tone mapping, so reflected highlights bloom and tone-map
    // with the rest of the image.
    if (wantSsr) {
      graph.addPass(
        SsrPass(
          dimensions: pixelSize,
          settings: screenSpaceReflections,
          fovRadiansY: perspectiveCamera.fovRadiansY,
          near: perspectiveCamera.near,
          far: perspectiveCamera.far,
        ),
      );
    }
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

    // Volumetric god rays, in HDR right after the scene (and reflections), so
    // the in-scattered light tone-maps with the rest of the frame. Built on the
    // custom-pass API: it reads the depth + shadow inputs it declared.
    if (wantGodRays) {
      graph.addPass(
        UserRenderGraphPass(
          pass: _godRaysPass,
          camera: camera,
          dimensions: pixelSize,
          destination: pool.acquire(
            TransientTextureDescriptor.color(
              width: width,
              height: height,
              format: gpu.PixelFormat.r16g16b16a16Float,
              debugName: 'god_rays',
            ),
          ),
          renderScene: renderScene,
          viewLayerMask: view.layerMask,
          passIndex: 0,
          time: postTime,
        ),
      );
    }

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

    // Depth of field on the linear HDR scene color, before the custom
    // effects and bloom so both act on the defocused image (bokeh highlights
    // still bloom). Needs the perspective camera's FOV for the thin-lens
    // math and camera depth.
    if (depthOfField.enabled && perspectiveCamera != null) {
      // Translucent depth-writing surfaces (glass) join the linear depth
      // here, after the opaque-only consumers above, so depth of field
      // focuses on the visible surface instead of the backdrop behind it.
      graph.addPass(
        TranslucentDepthPatchPass(
          camera: camera,
          renderScene: renderScene,
          cameraForward: camera.forward,
          layerMask: view.layerMask,
          cullingPlanes: view.cullingPlanes,
        ),
      );
      graph.addPass(
        DofPass(
          settings: depthOfField,
          dimensions: pixelSize,
          fovRadiansY: perspectiveCamera.fovRadiansY,
        ),
      );
    }

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

    // Temporal anti-aliasing resolve on the linear HDR scene color, before
    // auto exposure and bloom so the resolved image is what blooms and tone-maps.
    if (enableTaa) {
      final unjitteredViewProj = camera.getViewTransform(pixelSize);
      final prevViewProj =
          taaState!.previousViewTransform ?? unjitteredViewProj;
      final cameraForward = camera.forward;
      final cameraRight = camera.up.cross(cameraForward)..normalize();
      final cameraUp = cameraForward.cross(cameraRight)..normalize();
      final viewToWorld = Matrix4.identity();
      viewToWorld.setColumns(
        Vector4(cameraRight.x, cameraRight.y, cameraRight.z, 0.0),
        Vector4(cameraUp.x, cameraUp.y, cameraUp.z, 0.0),
        Vector4(cameraForward.x, cameraForward.y, cameraForward.z, 0.0),
        Vector4(camera.position.x, camera.position.y, camera.position.z, 1.0),
      );
      final currentToPrev = prevViewProj * viewToWorld;
      final halfFovY = perspectiveCamera.fovRadiansY * 0.5;
      final tanHalfFovY = math.tan(halfFovY);
      final tanHalfFovX = tanHalfFovY * (pixelSize.width / pixelSize.height);

      graph.addPass(
        TaaPass(
          dimensions: pixelSize,
          settings: temporalAntiAliasing,
          state: taaState,
          currentToPreviousViewProjection: currentToPrev,
          cameraPosition: camera.position,
          tanHalfFovX: tanHalfFovX,
          tanHalfFovY: tanHalfFovY,
          far: perspectiveCamera.far,
          near: perspectiveCamera.near,
          currentJitterNdc: currentJitterNdc,
          previousJitterNdc: prevJitterNdc,
        ),
      );
      taaState.previousViewTransform = unjitteredViewProj;
    }

    // Auto exposure meters the HDR image the resolve will consume, after
    // depth of field and the custom effects republish the scene color and
    // before bloom (bloom feeds off the exposure-independent HDR color and
    // its own contribution should not drive the metering).
    if (autoExposure.enabled) {
      graph.addPass(
        AutoExposurePass(
          settings: autoExposure,
          state: _autoExposureState ??= AutoExposureState(),
        ),
      );
    } else {
      _autoExposureState = null;
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
        agxWhite: agxWhite,
        agxContrast: agxContrast,
        postProcess: postProcess,
      ),
    );

    // Radial distortion pulses warp the composed image (including bloom)
    // right after tone mapping, so FXAA cleans up the resampled edges
    // afterward. Built on the custom-pass API, ahead of any user-added
    // afterToneMapping passes.
    if (wantScreenDistortion) {
      displaySteps.add(
        (output) => UserRenderGraphPass(
          pass: _screenDistortionPass,
          camera: camera,
          dimensions: pixelSize,
          destination: output,
          renderScene: renderScene,
          viewLayerMask: view.layerMask,
          passIndex: 0,
          time: postTime,
        ),
      );
    }

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

    // FXAA/SMAA run after the resolve so custom after-tone-mapping effects
    // receive the anti-aliased image. The resolve applies film grain and
    // vignette first, so heavy grain is softened slightly here.
    // TODO(antialiasing): if that softening bothers anyone, move grain
    // application after the anti-aliasing pass.
    if (enableFxaa) {
      displaySteps.add(
        (output) => FxaaPass(output: output, dimensions: pixelSize),
      );
    }
    if (enableSmaa) {
      displaySteps.add(
        (output) =>
            SmaaPass(output: output, dimensions: pixelSize, settings: smaa),
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

    graph.execute(
      transientsBuffer: transientsBuffer,
      texturePool: pool,
      observer: capturer,
    );
  }

  // Places the irradiance volume for this frame, adds the scatter, blend, and
  // filter passes, and returns what the lit draws bind. Returns null when the
  // field could not be built (no atlas yet, or no scene color to scatter).
  IrradianceFieldBinding? _addIrradianceFieldPasses({
    required RenderGraph graph,
    required Camera camera,
    required ui.Size pixelSize,
    required Vector3 cameraForward,
    required Vector3 cameraRight,
    required Vector3 cameraUp,
    required PerspectiveProjection perspectiveCamera,
    required EnvironmentMap environmentMap,
  }) {
    final settings = globalIllumination;
    final (center, extents, resolution) = _planIrradianceVolume(
      settings,
      camera,
    );
    if (!_irradianceField.update(
      settings: settings,
      center: center,
      extents: extents,
      resolution: resolution,
    )) {
      return null;
    }

    // An inspect-style viewer can hold the field static while the camera
    // moves and let it resume once the camera rests, which is near-lossless
    // there and takes the whole per-frame cost to zero.
    final cameraMoved =
        _irradianceCameraPosition == null ||
        (_irradianceCameraPosition! - camera.position).length2 > 1e-8 ||
        (_irradianceCameraForward! - cameraForward).length2 > 1e-10;
    _irradianceCameraPosition = camera.position.clone();
    _irradianceCameraForward = cameraForward.clone();
    final solve =
        !settings.bakeOnly && !(settings.updateWhenIdleOnly && cameraMoved);

    if (solve) {
      final shStrip = _crossfadeEnvironment == null || _crossfadeBlend <= 0.0
          ? environmentMap.diffuseShTexture
          : null;
      graph.addPass(
        IrradianceInjectPass(
          state: _irradianceField,
          settings: settings,
          dimensions: pixelSize,
          cameraPosition: camera.position,
          cameraRight: cameraRight,
          cameraUp: cameraUp,
          cameraForward: cameraForward,
          tanHalfFovX:
              math.tan(perspectiveCamera.fovRadiansY * 0.5) *
              (pixelSize.height <= 0
                  ? 1.0
                  : pixelSize.width / pixelSize.height),
          tanHalfFovY: math.tan(perspectiveCamera.fovRadiansY * 0.5),
          far: perspectiveCamera.far,
          sceneRadiance: _ssgiHistoryColor,
        ),
      );
      graph.addPass(
        IrradianceBlendPass(
          state: _irradianceField,
          settings: settings,
          // The blend's fallback content is the environment, so a cross-fade
          // needs the composited pair. The scene pass builds that composite,
          // which runs later, so a cross-fading frame falls back to the
          // primary until it settles.
          // TODO(gi-crossfade): hoist the coefficient composite ahead of the
          // field so a cross-fade feeds the fallback exactly.
          shStrip: shStrip ?? environmentMap.diffuseShTexture,
          environmentTransform: environmentTransform,
          environmentBlend: 0.0,
          environmentIntensity: environmentIntensity,
        ),
      );
      graph.addPass(
        IrradianceFilterPass(
          state: _irradianceField,
          settings: settings,
          shStrip: shStrip ?? environmentMap.diffuseShTexture,
        ),
      );
    }

    final atlas = _irradianceField.sampledAtlas;
    if (atlas == null) return null;
    return IrradianceFieldBinding(
      atlas: atlas,
      layout: _irradianceField.layout!,
      placement: _irradianceField.placement!,
      intensity: settings.intensity,
      shadowBias: settings.shadowBias,
      visibility: settings.visibility.clamp(0.0, 1.0),
      visibilityBias: settings.visibilityBias,
    );
  }

  Vector3? _irradianceCameraPosition;
  Vector3? _irradianceCameraForward;
  IrradianceVolumeComponent? _activeIrradianceVolume;

  // Where the irradiance volume sits this frame, as a center and a full size.
  (Vector3, Vector3, Vector3) _planIrradianceVolume(
    GlobalIlluminationSettings settings,
    Camera camera,
  ) {
    switch (settings.volumeMode) {
      case IrradianceVolumeMode.followCamera:
        return (
          camera.position.clone(),
          settings.extents.clone(),
          settings.resolution,
        );
      case IrradianceVolumeMode.component:
        // Exactly one volume is active per frame. Among those containing the
        // camera the highest priority wins; with none containing it the
        // highest-priority volume overall keeps the field somewhere sane
        // rather than snapping it to the camera.
        IrradianceVolumeComponent? chosen;
        var chosenContains = false;
        for (final volume in renderScene.irradianceVolumeComponents) {
          final contains = volume.contains(camera.position);
          if (chosen != null) {
            if (chosenContains && !contains) continue;
            if (contains == chosenContains &&
                volume.priority <= chosen.priority) {
              continue;
            }
          }
          chosen = volume;
          chosenContains = contains;
        }
        if (chosen != null) {
          if (!identical(chosen, _activeIrradianceVolume) ||
              chosen.consumeInvalidation()) {
            _activeIrradianceVolume = chosen;
            _irradianceField.invalidate();
          }
          return (chosen.worldCenter, chosen.extents * 2.0, chosen.resolution);
        }
        _activeIrradianceVolume = null;
        return (
          camera.position.clone(),
          settings.extents.clone(),
          settings.resolution,
        );
      case IrradianceVolumeMode.fitScene:
        Vector3? low;
        Vector3? high;
        for (final item in renderScene.items) {
          final bounds = item.worldBounds;
          if (bounds == null || !item.visible) continue;
          if (low == null) {
            low = bounds.min.clone();
            high = bounds.max.clone();
            continue;
          }
          Vector3.min(low, bounds.min, low);
          Vector3.max(high!, bounds.max, high);
        }
        if (low == null || high == null) {
          return (
            camera.position.clone(),
            settings.extents.clone(),
            settings.resolution,
          );
        }
        // Pad by a probe spacing so surfaces on the bounds are inside the
        // cage rather than on its outermost plane.
        final size = (high - low)
          ..add(
            Vector3(
              (high.x - low.x) / math.max(2.0, settings.resolution.x),
              (high.y - low.y) / math.max(2.0, settings.resolution.y),
              (high.z - low.z) / math.max(2.0, settings.resolution.z),
            ),
          );
        return ((low + high)..scale(0.5), size, settings.resolution);
    }
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

// Cross-frame GPU resources for one planar reflection group: the persistent
// capture target mirror surfaces sample and the transient pool the capture
// renders through (its own, so capture attachments never collide with a
// view's same-sized transients).
class _PlanarCaptureResources {
  final TransientTexturePool pool = TransientTexturePool();
  gpu.Texture? _texture;
  int _width = 0;
  int _height = 0;

  // The group's capture target at the requested size, reallocated when the
  // size changes (the old texture is released to finalizers; any in-flight
  // frame object keeps it alive until sampled).
  gpu.Texture acquire(int width, int height) {
    var texture = _texture;
    if (texture == null || _width != width || _height != height) {
      texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: gpu.PixelFormat.r16g16b16a16Float,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      _texture = texture;
      _width = width;
      _height = height;
      pool.clear();
    }
    return texture;
  }
}
