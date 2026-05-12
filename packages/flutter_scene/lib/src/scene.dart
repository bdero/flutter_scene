import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'camera.dart';
import 'light.dart';
import 'material/environment.dart';
import 'material/material.dart';
import 'mesh.dart';
import 'node.dart';
import 'render/render_graph.dart';
import 'render/scene_pass.dart';
import 'render/shadow_pass.dart';
import 'render/tonemap_pass.dart';
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
    environment = Material.getDefaultEnvironmentMap();
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
    _initializeStaticResources = Material.initializeStaticResources()
        .onError((e, stacktrace) {
          log(
            'Failed to initialize static Flutter Scene resources',
            error: e,
            stackTrace: stacktrace,
          );
          _initializeStaticResources = null;
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

  /// Handles the creation and management of render targets for this [Scene].
  final Surface surface = Surface();

  /// The image-based-lighting environment.
  ///
  /// Defaults to [EnvironmentMap.studio] (the built-in procedural studio
  /// environment), assigned in the constructor; assign your own to change
  /// it. A [PhysicallyBasedMaterial] can override this per material.
  late EnvironmentMap environment;

  /// Scalar multiplier applied to [environment]'s contribution. `1.0`
  /// (the default) is neutral.
  double environmentIntensity = 1.0;

  /// Optional analytic directional light (e.g. a sun) layered on top of
  /// the image-based lighting. Null (the default) means IBL only.
  DirectionalLight? directionalLight;

  /// Linear exposure multiplier applied to the HDR scene color before
  /// tone mapping. `1.0` (the default) is neutral; see
  /// [physicalCameraExposure] to derive a value from camera settings.
  double exposure = 1.0;

  /// Tone mapping operator used when resolving the HDR scene color to the
  /// display image. Defaults to [ToneMappingMode.pbrNeutral].
  ToneMappingMode toneMapping = ToneMappingMode.pbrNeutral;

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
    final swapchainTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: swapchainColor),
    );

    final transientsBuffer = gpu.gpuContext.createHostBuffer();

    final light = directionalLight;
    final castsShadow = light != null && light.castsShadow;
    final lightSpaceMatrix =
        castsShadow ? light.computeLightSpaceMatrix() : null;

    final graph = RenderGraph();
    if (castsShadow) {
      graph.addPass(
        ShadowPass(
          root: root,
          lightSpaceMatrix: lightSpaceMatrix!,
          resolution: light.shadowMapResolution,
        ),
      );
    }
    graph.addPass(
      ScenePass(
        camera: camera,
        root: root,
        dimensions: pixelSize,
        environmentMap: environment,
        environmentIntensity: environmentIntensity,
        enableMsaa: enableMsaa,
        directionalLight: light,
        lightSpaceMatrix: lightSpaceMatrix,
      ),
    );
    graph.addPass(
      TonemapPass(
        target: swapchainTarget,
        exposure: exposure,
        toneMappingMode: toneMapping,
      ),
    );
    graph.execute(
      transientsBuffer: transientsBuffer,
      texturePool: surface.transientTexturePool,
    );

    final image = swapchainColor.asImage();
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, pixelSize.width, pixelSize.height),
      drawArea,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }
}
