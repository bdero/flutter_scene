/// The viewport debug-output modes: a registry of full-viewport
/// visualizations of the engine's intermediate buffers (depth, normals, AO,
/// shadow atlas, ...), rendered by one custom pass through the editor's
/// parametric remap shader. The registry drives both the viewport dropdown
/// and the MCP `list/set_viewport_debug_mode` tools.
library;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import '../render_graph/debug_shaders.dart';

/// One selectable debug output.
class ViewportDebugMode {
  const ViewportDebugMode({
    required this.id,
    required this.label,
    this.inputs = const {},
    this.resolve,
  });

  /// Stable id used by settings and MCP (`final`, `linear_depth`, ...).
  final String id;

  /// The menu label.
  final String label;

  /// Engine buffers this mode requires the frame to produce.
  final Set<RenderInput> inputs;

  /// Picks the source texture and remap for this frame, or null when the
  /// frame did not produce the buffer (the mode shows the normal output).
  /// Null for the passthrough mode.
  final (gpu.Texture, RemapSettings)? Function(RenderPassContext context)?
  resolve;
}

/// The registered debug outputs, in menu order. The first entry is the
/// passthrough (no debug output).
final List<ViewportDebugMode> viewportDebugModes = [
  const ViewportDebugMode(id: 'final', label: 'Final output'),
  ViewportDebugMode(
    id: 'hdr_color',
    label: 'HDR scene color',
    resolve: (context) =>
        (context.sceneColorHdr, const RemapSettings(mode: RemapMode.color)),
  ),
  ViewportDebugMode(
    id: 'linear_depth',
    label: 'Linear depth',
    inputs: const {RenderInput.depth},
    resolve: (context) {
      final depth = context.sceneDepthLinear;
      if (depth == null) return null;
      final projection = context.camera.projection;
      final far = projection is PerspectiveProjection ? projection.far : 100.0;
      return (depth, RemapSettings(mode: RemapMode.depth, near: 0, far: far));
    },
  ),
  ViewportDebugMode(
    id: 'view_normals',
    label: 'View normals',
    inputs: const {RenderInput.normals},
    resolve: (context) {
      final depth = context.sceneDepthLinear;
      if (depth == null) return null;
      return (depth, const RemapSettings(mode: RemapMode.octahedralNormal));
    },
  ),
  ViewportDebugMode(
    id: 'ambient_occlusion',
    label: 'Ambient occlusion',
    resolve: (context) {
      final ao = context.debugBlackboardTexture('ssao_texture');
      if (ao == null) return null;
      return (ao, const RemapSettings(mode: RemapMode.color));
    },
  ),
  ViewportDebugMode(
    id: 'shadow_atlas',
    label: 'Shadow atlas',
    inputs: const {RenderInput.shadowMap},
    resolve: (context) {
      final atlas = context.debugBlackboardTexture('directional_shadow_map');
      if (atlas == null) return null;
      return (
        atlas,
        const RemapSettings(mode: RemapMode.singleChannel, channel: 0),
      );
    },
  ),
  ViewportDebugMode(
    id: 'bloom',
    label: 'Bloom',
    resolve: (context) {
      final bloom = context.debugBlackboardTexture('bloom_texture');
      if (bloom == null) return null;
      return (bloom, const RemapSettings(mode: RemapMode.color));
    },
  ),
  ViewportDebugMode(
    id: 'selection_mask',
    label: 'Selection mask',
    resolve: (context) {
      final mask = context.debugBlackboardTexture('selection_mask');
      if (mask == null) return null;
      return (mask, const RemapSettings(mode: RemapMode.color));
    },
  ),
];

/// The mode with [id], or null.
ViewportDebugMode? viewportDebugModeById(String id) {
  for (final mode in viewportDebugModes) {
    if (mode.id == id) return mode;
  }
  return null;
}

/// The one custom pass that renders the selected debug output full-viewport,
/// at the end of the display chain. Disabled (passthrough) it never touches
/// the frame.
class DebugVisualizePass extends CustomRenderPass {
  ViewportDebugMode _mode = viewportDebugModes.first;

  ViewportDebugMode get mode => _mode;
  set mode(ViewportDebugMode value) {
    _mode = value;
    enabled = value.resolve != null;
  }

  DebugVisualizePass() {
    enabled = false;
  }

  @override
  String get name => 'DebugVisualize';

  @override
  RenderStage get stage => RenderStage.afterAntiAliasing;

  @override
  Set<RenderInput> get inputs => _mode.inputs;

  static final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  @override
  void execute(RenderPassContext context) {
    final resolve = _mode.resolve;
    if (resolve == null || !editorDebugShadersLoaded) return;
    final resolved = resolve(context);
    if (resolved == null) return;
    final (source, settings) = resolved;
    // fp32 sources (linear depth, the shadow atlas) filter nearest.
    final nearest =
        source.format == gpu.PixelFormat.r32g32b32a32Float ||
        source.format == gpu.PixelFormat.r32Float;
    context.applyShader(
      editorRemapFragment,
      textures: {'source_texture': source},
      samplers: {if (nearest) 'source_texture': _nearestClamp},
      uniforms: {'RemapInfo': packRemapInfo(settings)},
    );
  }
}

// One pass per scene, registered on first use so every viewport (and MCP)
// shares the same mode state for that scene.
final Expando<DebugVisualizePass> _passPerScene = Expando(
  'debug visualize pass',
);

/// The scene's debug visualize pass, created and registered on first use.
DebugVisualizePass debugVisualizePassFor(Scene scene) {
  var pass = _passPerScene[scene];
  if (pass == null) {
    pass = DebugVisualizePass();
    _passPerScene[scene] = pass;
    scene.addRenderPass(pass);
  }
  return pass;
}
