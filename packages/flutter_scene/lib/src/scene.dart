import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Matrix3;
import 'ambient_occlusion.dart';
import 'camera.dart';
import 'components/directional_light_component.dart';
import 'light.dart';
import 'material/environment.dart';
import 'material/material.dart';
import 'mesh.dart';
import 'node.dart';
import 'physics/physics_world.dart';
import 'post_process/post_effect.dart';
import 'post_process/post_process.dart';
import 'render/bloom_pass.dart';
import 'render/depth_prepass.dart';
import 'render/post_effect_pass.dart';
import 'render/render_graph.dart';
import 'render/render_scene.dart';
import 'render/scene_pass.dart';
import 'render/shadow_pass.dart';
import 'render/ssao_pass.dart';
import 'render/resolve_pass.dart';
import 'shaders.dart';
import 'surface.dart';
import 'tone_mapping.dart';

/// Defines a common interface for managing a scene graph, allowing the addition and removal of [Nodes].
///
/// `SceneGraph` provides a set of methods that can be implemented by a class
/// to manage a hierarchy of nodes within a 3D scene.
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
/// Set on a [Scene] via [Scene.antiAliasingMode]. The default is [msaa]
/// when the GPU backend supports offscreen MSAA, otherwise [none].
enum AntiAliasingMode {
  /// No anti-aliasing. Geometry edges are rendered at the render target's
  /// native resolution.
  none,

  /// 4x multi-sample anti-aliasing. Requires offscreen MSAA support on
  /// the active Flutter GPU backend; setting this mode is silently
  /// ignored (with a debug warning) when MSAA is unavailable.
  msaa,
}

/// Represents a 3D scene, which is a collection of nodes that can be rendered onto the screen.
///
/// `Scene` manages the scene graph and handles rendering operations.
/// It contains a root [Node] that serves as the entry point for all nodes in this `Scene`, and
/// it provides methods for adding and removing nodes from the scene graph.
base class Scene implements SceneGraph {
  Scene() {
    initializeStaticResources();
    root.registerAsRoot(this);
    antiAliasingMode = AntiAliasingMode.msaa;
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

  AntiAliasingMode _antiAliasingMode = AntiAliasingMode.none;

  /// The anti-aliasing strategy used when rendering this [Scene].
  ///
  /// Defaults to [AntiAliasingMode.msaa] (set in the constructor) and falls
  /// back to [AntiAliasingMode.none] when the active Flutter GPU backend
  /// does not support offscreen MSAA. Assigning [AntiAliasingMode.msaa]
  /// on an unsupported backend is silently ignored, leaving the previous
  /// value in place.
  set antiAliasingMode(AntiAliasingMode value) {
    switch (value) {
      case AntiAliasingMode.none:
        break;
      case AntiAliasingMode.msaa:
        if (!gpu.gpuContext.doesSupportOffscreenMSAA) {
          debugPrint("MSAA is not currently supported on this backend.");
          return;
        }
        break;
    }

    _antiAliasingMode = value;
  }

  AntiAliasingMode get antiAliasingMode {
    return _antiAliasingMode;
  }

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

  /// Renders the current state of this [Scene] onto the given [ui.Canvas] using the specified [Camera].
  ///
  /// The [Camera] provides the perspective from which the scene is viewed, and the [ui.Canvas]
  /// is the drawing surface onto which this [Scene] will be rendered.
  ///
  /// Optionally, a [ui.Rect] can be provided to define a viewport, limiting the rendering area on the canvas.
  /// If no [ui.Rect] is specified, the entire canvas will be rendered.
  ///
  /// [pixelRatio] is the multiplier from logical to physical pixels used
  /// when allocating the offscreen render target. Defaults to the
  /// implicit view's `devicePixelRatio` (or `1.0` if no view is attached),
  /// so the scene is rasterized at the same density Flutter is
  /// compositing the surrounding UI at. Pass a smaller value to trade
  /// fidelity for performance, or a larger one for supersampling.
  void render(
    Camera camera,
    ui.Canvas canvas, {
    ui.Rect? viewport,
    double? pixelRatio,
  }) {
    if (!_readyToRender) {
      debugPrint('Flutter Scene is not ready to render. Skipping frame.');
      debugPrint(
        'You may wait on the Future returned by Scene.initializeStaticResources() before rendering.',
      );
      return;
    }

    final drawArea = viewport ?? canvas.getLocalClipBounds();
    if (drawArea.isEmpty) {
      return;
    }

    // Allocate the offscreen render target at physical-pixel resolution so
    // the rasterized 3D content matches Flutter's framebuffer density.
    // Without this, the texture is sized in logical pixels and the
    // framebuffer compositor upscales it (visible as pixelation on
    // high-DPI devices). See: https://github.com/bdero/flutter_scene/issues/60
    final dpr =
        pixelRatio ??
        ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
        1.0;
    final pixelSize = ui.Size(
      (drawArea.width * dpr).ceilToDouble(),
      (drawArea.height * dpr).ceilToDouble(),
    );

    final enableMsaa = _antiAliasingMode == AntiAliasingMode.msaa;
    final gpu.Texture swapchainColor = surface.getNextSwapchainColorTexture(
      pixelSize,
    );

    // Resolve the IBL environment up front (before building the render
    // graph): the default is built lazily here on first use, which submits
    // a one-time prefilter pass that must not be nested inside the frame's
    // render passes. Doing this in the constructor instead would break the
    // OpenGL ES backend, which sets up its context lazily on the raster
    // thread only after the first frame.
    final environmentMap = environment ?? Material.getDefaultEnvironmentMap();

    // Reuse one host buffer across frames; reset() cycles it to the next
    // frame's backing storage.
    final transientsBuffer = _transientsBuffer ??= gpu.gpuContext
        .createHostBuffer();
    transientsBuffer.reset();

    // The renderer shades a single directional light: the first one
    // registered in the graph (the [directionalLight] convenience, or a
    // [DirectionalLightComponent] attached to any node). Its travel
    // direction comes from the owning node's world transform.
    final lightComponent = renderScene.directionalLights.isEmpty
        ? null
        : renderScene.directionalLights.first;
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

    // Walk the graph once to tick components and animations and refresh
    // the flat render list before the passes iterate it. Skipped when
    // update() already ran the tick for this frame.
    if (!_tickedThisFrame) {
      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final lastMillis = _lastTickMillis ?? nowMillis;
      _tick((nowMillis - lastMillis) / 1000.0);
    }
    _tickedThisFrame = false;

    // Rebuild the spatial culling structure if the pre-pass changed the
    // scene, before the render passes query it.
    renderScene.rebuildIfDirty();

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
        environmentIntensity: environmentIntensity,
        environmentTransform: environmentTransform,
        enableMsaa: enableMsaa,
        directionalLight: light,
        directionalLightDirection: lightDirection,
        cascades: cascades,
        specularOcclusionMode: ambientOcclusion.specularMode.index.toDouble(),
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

    final pool = surface.transientTexturePool;
    final width = pixelSize.width.toInt();
    final height = pixelSize.height.toInt();
    final postTime =
        DateTime.now().millisecondsSinceEpoch.remainder(100000) / 1000.0;

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

    // The resolve writes the swapchain directly unless after-tone-mapping
    // effects need an intermediate buffer to chain on.
    final gpu.Texture resolveOutput = afterTonemap.isEmpty
        ? swapchainColor
        : pool.acquire(
            TransientTextureDescriptor.color(
              width: width,
              height: height,
              format: swapchainColor.format,
              debugName: 'post_ldr_resolve',
            ),
          );
    graph.addPass(
      ResolvePass(
        outputColor: resolveOutput,
        exposure: exposure,
        toneMappingMode: toneMapping,
        postProcess: postProcess,
      ),
    );

    // Custom effects on the display-referred image. The last one writes
    // the swapchain that gets composited onto the canvas.
    for (var i = 0; i < afterTonemap.length; i++) {
      final isLast = i == afterTonemap.length - 1;
      final output = isLast
          ? swapchainColor
          : pool.acquire(
              TransientTextureDescriptor.color(
                width: width,
                height: height,
                format: swapchainColor.format,
                debugName: i.isEven ? 'post_ldr_a' : 'post_ldr_b',
              ),
            );
      graph.addPass(
        PostEffectPass(
          effect: afterTonemap[i],
          inputKey: kDisplayColorBlackboardKey,
          outputKey: kDisplayColorBlackboardKey,
          output: output,
          dimensions: pixelSize,
          time: postTime,
        ),
      );
    }

    graph.execute(
      transientsBuffer: transientsBuffer,
      texturePool: surface.transientTexturePool,
    );

    final image = swapchainColor.asImage();
    final srcRect = ui.Rect.fromLTWH(0, 0, pixelSize.width, pixelSize.height);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
    canvas.drawImageRect(image, srcRect, drawArea, paint);
  }
}
