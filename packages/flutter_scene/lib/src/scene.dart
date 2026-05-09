import 'dart:developer';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'camera.dart';
import 'material/environment.dart';
import 'material/material.dart';
import 'mesh.dart';
import 'node.dart';
import 'scene_encoder.dart';
import 'surface.dart';
import 'package:vector_math/vector_math.dart';

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

  /// Manages the lighting for this [Scene].
  final Environment environment = Environment();

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
    final gpu.RenderTarget renderTarget = surface.getNextRenderTarget(
      pixelSize,
      enableMsaa,
    );

    final env =
        environment.environmentMap.isEmpty()
            ? environment.withNewEnvironmentMap(
              Material.getDefaultEnvironmentMap(),
            )
            : environment;

    final encoder = SceneEncoder(renderTarget, camera, pixelSize, env);
    root.render(encoder, Matrix4.identity());
    encoder.finish();

    final gpu.Texture texture =
        enableMsaa
            ? renderTarget.colorAttachments[0].resolveTexture!
            : renderTarget.colorAttachments[0].texture;
    final image = texture.asImage();
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, pixelSize.width, pixelSize.height),
      drawArea,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
  }
}
