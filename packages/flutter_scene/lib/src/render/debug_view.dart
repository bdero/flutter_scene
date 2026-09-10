import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:vector_math/vector_math.dart';

/// Which family a [SurfaceDebugChannel] belongs to, for grouping a menu and
/// for hiding a family a material does not carry.
/// {@category Rendering}
enum SurfaceDebugGroup {
  /// Nothing selected.
  none,

  /// Read from the mesh: normals, tangents, texture coordinates, vertex color.
  geometry,

  /// The resolved surface description after textures and factors.
  surface,

  /// The advanced physical fields, only on physical materials.
  physical,

  /// Which object or material a pixel belongs to.
  identity,

  /// Authoring errors flagged in color, not values.
  validation,

  /// Whatever a `.fmat` wrote into `material.debug`.
  custom,
}

/// A surface value the renderer can show in place of the lit result.
///
/// Every channel is display-referred: the resolve pass hands its pixels
/// through untouched, so a scalar of 0.5 is mid gray on screen and a color
/// channel is display-encoded in the shader. Scalars run through the
/// [DebugView] range and gain, directions map through `0.5 * v + 0.5`, and a
/// channel a material does not carry draws a gray checkerboard.
/// {@category Rendering}
enum SurfaceDebugChannel {
  none(0, 'none', 'Off', SurfaceDebugGroup.none),

  /// The interpolated geometric normal, before any normal map.
  worldNormal(1, 'world_normal', 'World normal', SurfaceDebugGroup.geometry),

  /// The shading normal after the normal map.
  shadingNormal(
    2,
    'shading_normal',
    'Shading normal',
    SurfaceDebugGroup.geometry,
  ),
  tangent(3, 'tangent', 'Tangent', SurfaceDebugGroup.geometry),
  bitangent(4, 'bitangent', 'Bitangent', SurfaceDebugGroup.geometry),

  /// Black for a left-handed tangent frame, white for right-handed.
  tangentHandedness(
    5,
    'tangent_handedness',
    'Tangent handedness',
    SurfaceDebugGroup.geometry,
  ),
  uv0(6, 'uv0', 'UV 0', SurfaceDebugGroup.geometry),
  uv1(7, 'uv1', 'UV 1', SurfaceDebugGroup.geometry),
  vertexColor(8, 'vertex_color', 'Vertex color', SurfaceDebugGroup.geometry),
  viewDirection(
    9,
    'view_direction',
    'View direction',
    SurfaceDebugGroup.geometry,
  ),

  /// World position remapped through the range (default -10..10 per axis).
  worldPosition(
    10,
    'world_position',
    'World position',
    SurfaceDebugGroup.geometry,
    rangeMin: -10.0,
    rangeMax: 10.0,
  ),

  /// Front faces blue, back faces red. A red face the camera should see is
  /// wound the wrong way.
  faceOrientation(
    11,
    'face_orientation',
    'Face orientation',
    SurfaceDebugGroup.geometry,
  ),

  /// A colored checker on the first UV set, out-of-range cells in red.
  uv0Checker(12, 'uv0_checker', 'UV 0 checker', SurfaceDebugGroup.geometry),

  /// The same checker on the second UV set (the lightmap set).
  uv1Checker(13, 'uv1_checker', 'UV 1 checker', SurfaceDebugGroup.geometry),

  baseColor(20, 'base_color', 'Base color', SurfaceDebugGroup.surface),
  alpha(21, 'alpha', 'Alpha', SurfaceDebugGroup.surface),
  metallic(22, 'metallic', 'Metallic', SurfaceDebugGroup.surface),
  roughness(23, 'roughness', 'Roughness', SurfaceDebugGroup.surface),
  specular(24, 'specular', 'Specular', SurfaceDebugGroup.surface),
  occlusion(25, 'occlusion', 'Occlusion', SurfaceDebugGroup.surface),

  /// Linear emissive radiance, display-encoded; raise the gain for dim
  /// emitters or lower it for bright ones.
  emissive(26, 'emissive', 'Emissive', SurfaceDebugGroup.surface),

  clearcoat(40, 'clearcoat', 'Clearcoat', SurfaceDebugGroup.physical),
  clearcoatRoughness(
    41,
    'clearcoat_roughness',
    'Clearcoat roughness',
    SurfaceDebugGroup.physical,
  ),
  clearcoatNormal(
    42,
    'clearcoat_normal',
    'Clearcoat normal',
    SurfaceDebugGroup.physical,
  ),
  sheenColor(43, 'sheen_color', 'Sheen color', SurfaceDebugGroup.physical),
  sheenRoughness(
    44,
    'sheen_roughness',
    'Sheen roughness',
    SurfaceDebugGroup.physical,
  ),
  transmission(45, 'transmission', 'Transmission', SurfaceDebugGroup.physical),
  transmissionColor(
    46,
    'transmission_color',
    'Transmission color',
    SurfaceDebugGroup.physical,
  ),
  diffuseTransmission(
    47,
    'diffuse_transmission',
    'Diffuse transmission',
    SurfaceDebugGroup.physical,
  ),
  anisotropy(48, 'anisotropy', 'Anisotropy', SurfaceDebugGroup.physical),
  anisotropyDirection(
    49,
    'anisotropy_direction',
    'Anisotropy direction',
    SurfaceDebugGroup.physical,
  ),
  iridescence(50, 'iridescence', 'Iridescence', SurfaceDebugGroup.physical),

  /// Iridescence film thickness in nanometers (default range 0..1200).
  iridescenceThickness(
    51,
    'iridescence_thickness',
    'Iridescence thickness',
    SurfaceDebugGroup.physical,
    rangeMin: 0.0,
    rangeMax: 1200.0,
  ),

  /// Index of refraction (default range 1..3).
  ior(
    52,
    'ior',
    'Index of refraction',
    SurfaceDebugGroup.physical,
    rangeMin: 1.0,
    rangeMax: 3.0,
  ),
  specularColor(
    53,
    'specular_color',
    'Specular color',
    SurfaceDebugGroup.physical,
  ),

  /// A stable color per node, so joined meshes, duplicates, and instance
  /// boundaries read at a glance.
  objectColor(60, 'object_color', 'Object color', SurfaceDebugGroup.identity),

  /// A stable color per material instance.
  materialColor(
    61,
    'material_color',
    'Material color',
    SurfaceDebugGroup.identity,
  ),

  /// Every validation flag at once, over a flat gray.
  validation(70, 'validation', 'Validation', SurfaceDebugGroup.validation),

  /// Red for NaN, green for infinity, blue for a negative color.
  nonFinite(
    71,
    'non_finite',
    'Non-finite values',
    SurfaceDebugGroup.validation,
  ),

  /// Dielectric base color outside the plausible albedo band, blue too dark
  /// and red too bright.
  baseColorRange(
    72,
    'base_color_range',
    'Base color range',
    SurfaceDebugGroup.validation,
  ),

  /// Yellow where metallic is neither 0 nor 1.
  metallicBinary(
    73,
    'metallic_binary',
    'Non-binary metallic',
    SurfaceDebugGroup.validation,
  ),

  /// Orange where the interpolated normal is far from unit length.
  normalLength(
    74,
    'normal_length',
    'Normal length',
    SurfaceDebugGroup.validation,
  ),

  /// Pink where a normal map perturbs a surface that has no tangents.
  missingTangent(
    75,
    'missing_tangent',
    'Missing tangent',
    SurfaceDebugGroup.validation,
  ),

  /// Yellow where the first UV set leaves the unit square.
  uvRange(76, 'uv_range', 'UV range', SurfaceDebugGroup.validation),

  /// The `material.debug` value a `.fmat` wrote in `Surface()`, shown raw.
  custom(80, 'custom', 'Custom (material.debug)', SurfaceDebugGroup.custom);

  const SurfaceDebugChannel(
    this.shaderId,
    this.id,
    this.label,
    this.group, {
    this.rangeMin = 0.0,
    this.rangeMax = 1.0,
  });

  /// The id the shader switches on; mirrors `DEBUG_CHANNEL_*` in
  /// `material_debug.glsl`.
  final int shaderId;

  /// Stable snake-case id for settings, tools, and the registry.
  final String id;

  /// Menu label.
  final String label;

  final SurfaceDebugGroup group;

  /// The default scalar remap range for this channel.
  final double rangeMin;
  final double rangeMax;

  /// The channel with [id], or null.
  static SurfaceDebugChannel? byId(String id) {
    for (final channel in values) {
      if (channel.id == id) return channel;
    }
    return null;
  }
}

/// What a scalar channel does with a value outside the [DebugView] range.
/// {@category Rendering}
enum DebugRangePolicy {
  /// Clamp to the nearest end.
  clamp,

  /// Draw black.
  blackOut,

  /// Wrap around, so a value of 1.3 draws like 0.3.
  cycle,
}

/// One surface debug view: a [SurfaceDebugChannel] plus how its values are
/// mapped to the screen.
///
/// Set on [SceneDebugSettings.view] for the whole scene, or on a `Node` to
/// override the scene for that subtree ([DebugView.none] on a node excludes
/// its subtree from an active scene view).
/// {@category Rendering}
class DebugView {
  const DebugView({
    required this.channel,
    this.gain = 1.0,
    double? rangeMin,
    double? rangeMax,
    this.rangePolicy = DebugRangePolicy.clamp,
  }) : _rangeMin = rangeMin,
       _rangeMax = rangeMax;

  /// No view: the surface shades normally.
  static const DebugView none = DebugView(channel: SurfaceDebugChannel.none);

  final SurfaceDebugChannel channel;

  /// A multiplier on the output, for reading small or bright values.
  final double gain;

  /// The scalar remap range; a value at [rangeMin] draws black and one at
  /// [rangeMax] draws white. Defaults to the channel's own range.
  double get rangeMin => _rangeMin ?? channel.rangeMin;
  double get rangeMax => _rangeMax ?? channel.rangeMax;
  final double? _rangeMin;
  final double? _rangeMax;

  final DebugRangePolicy rangePolicy;

  /// Whether this view replaces the lit result.
  bool get isActive => channel != SurfaceDebugChannel.none;

  DebugView copyWith({
    SurfaceDebugChannel? channel,
    double? gain,
    double? rangeMin,
    double? rangeMax,
    DebugRangePolicy? rangePolicy,
  }) => DebugView(
    channel: channel ?? this.channel,
    gain: gain ?? this.gain,
    rangeMin: rangeMin ?? _rangeMin,
    rangeMax: rangeMax ?? _rangeMax,
    rangePolicy: rangePolicy ?? this.rangePolicy,
  );

  @override
  bool operator ==(Object other) =>
      other is DebugView &&
      other.channel == channel &&
      other.gain == gain &&
      other._rangeMin == _rangeMin &&
      other._rangeMax == _rangeMax &&
      other.rangePolicy == rangePolicy;

  @override
  int get hashCode =>
      Object.hash(channel, gain, _rangeMin, _rangeMax, rangePolicy);

  @override
  String toString() => 'DebugView(${channel.id})';
}

/// A debug drawing stacked on top of whatever the surface shows.
/// {@category Rendering}
enum DebugOverlay {
  /// Every triangle edge as a line, drawn with each mesh's own vertex path
  /// so skinning, morphing, and instancing hold.
  wireframe,
}

/// The scene's debug views: one surface [view], an optional [split], and a
/// set of [overlays]. Read every frame; nothing is cached across frames.
/// {@category Rendering}
class SceneDebugSettings {
  /// The surface view for every node that does not override it.
  DebugView view = DebugView.none;

  /// Where the view starts, as a fraction of the viewport width. Pixels at or
  /// right of it show the view, pixels left of it the lit result, so a
  /// channel can be compared against the image it came from. Null shows the
  /// view everywhere.
  double? split;

  /// Overlays drawn after the surfaces.
  final Set<DebugOverlay> overlays = {};

  /// The wireframe overlay color, straight (non-premultiplied) alpha.
  Vector4 wireframeColor = Vector4(0.1, 0.9, 1.0, 0.85);

  /// Whether anything here changes the frame.
  bool get isActive => view.isActive || overlays.isNotEmpty;

  /// The registry id of [view], or `none`.
  String get viewId => view.channel.id;
}

/// One entry in [DebugViewRegistry]: a named view an editor menu or an agent
/// tool can select by id.
/// {@category Rendering}
class DebugViewEntry {
  const DebugViewEntry({
    required this.id,
    required this.label,
    required this.group,
    required this.view,
  });

  /// Stable id (`roughness`, `uv1_checker`, or a consumer's own).
  final String id;
  final String label;
  final SurfaceDebugGroup group;

  /// The view selecting this entry applies.
  final DebugView view;
}

/// The named surface debug views: every [SurfaceDebugChannel] as a default
/// [DebugView], plus whatever a consumer registers (a channel with its own
/// remap, for instance). Editors and agent tools list this instead of
/// hard-coding the channel enum, so a registered view is one call and no UI.
/// {@category Rendering}
abstract final class DebugViewRegistry {
  static final List<DebugViewEntry> _entries = [
    for (final channel in SurfaceDebugChannel.values)
      DebugViewEntry(
        id: channel.id,
        label: channel.label,
        group: channel.group,
        view: DebugView(channel: channel),
      ),
  ];

  /// Every entry, built-ins first, in registration order.
  static List<DebugViewEntry> get entries => List.unmodifiable(_entries);

  /// The entry with [id], or null.
  static DebugViewEntry? byId(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Adds [entry], replacing any entry with the same id.
  static void register(DebugViewEntry entry) {
    _entries.removeWhere((existing) => existing.id == entry.id);
    _entries.add(entry);
  }

  /// Removes the entry with [id]; the built-in channel entries cannot be
  /// removed.
  static bool unregister(String id) {
    if (SurfaceDebugChannel.byId(id) != null) return false;
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.id == id);
    return _entries.length != before;
  }
}

/// The per-frame debug view state the scene pass hands the encoder.
@internal
class DebugViewFrame {
  DebugViewFrame({
    required this.sceneView,
    required this.splitPixels,
    required this.hasNodeOverrides,
    required this.overlays,
    required this.wireframeColor,
  });

  /// The scene-level view.
  final DebugView sceneView;

  /// The split as a pixel column of the scene color target, negative for no
  /// split.
  final double splitPixels;

  /// Whether any node overrides the scene view this frame, which makes the
  /// effective view a per-item question.
  final bool hasNodeOverrides;

  final Set<DebugOverlay> overlays;
  final Vector4 wireframeColor;

  /// Whether any draw this frame may show a view.
  bool get anyViewActive => sceneView.isActive || hasNodeOverrides;

  /// The view an item with [nodeOverride] shows.
  DebugView effectiveView(DebugView? nodeOverride) => nodeOverride ?? sceneView;

  /// Float count of the `DebugViewInfo` uniform block (two vec4s).
  static const int floatCount = 8;

  /// Writes the `DebugViewInfo` block for one draw into [out].
  ///
  /// [objectSeed] and [materialSeed] feed the identity channels; small
  /// integers spread well through the shader's golden-ratio hue walk.
  void pack(
    Float32List out,
    DebugView view, {
    required int objectSeed,
    required int materialSeed,
  }) {
    out[0] = view.channel.shaderId.toDouble();
    out[1] = splitPixels;
    out[2] = view.gain;
    out[3] = view.rangePolicy.index.toDouble();
    out[4] = view.rangeMin;
    out[5] = view.rangeMax;
    out[6] = (objectSeed & 0xFFFF).toDouble();
    out[7] = (materialSeed & 0xFFFF).toDouble();
  }

  /// The block that turns the view off for a draw.
  static final Float32List inactive = Float32List(floatCount);

  /// Binds the off block to [shader]'s `DebugViewInfo` slot on [pass].
  ///
  /// Every participating fragment shader declares the block and reads it, so
  /// a pass that draws such a material outside the scene encoder (the shadow
  /// catcher bake) must bind it too; an unbound block reads undefined data on
  /// GLES, which turned the catcher's bake into a debug view there.
  static void bindInactive(
    gpu.RenderPass pass,
    TransientWriter transients,
    gpu.Shader shader,
  ) {
    pass.bindUniform(
      shader.getUniformSlot('DebugViewInfo'),
      transients.emplace(ByteData.sublistView(inactive)),
    );
  }
}
