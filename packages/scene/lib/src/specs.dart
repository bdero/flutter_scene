import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/id.dart';
import 'package:scene/src/property_value.dart';

/// A node's local transform, stored either as a 4x4 [matrix] or as a
/// decomposed translation/rotation/scale ([TrsTransform]). The importer
/// emits TRS for clean diffs; the runtime composes a [Matrix4].
/// {@category Documents}
sealed class TransformSpec {
  const TransformSpec();

  /// The transform as a 4x4 matrix.
  Matrix4 toMatrix4();
}

/// A transform stored as an explicit 4x4 matrix.
/// {@category Documents}
class MatrixTransform extends TransformSpec {
  MatrixTransform(this.matrix);

  /// The 4x4 local transform.
  final Matrix4 matrix;

  @override
  Matrix4 toMatrix4() => matrix.clone();
}

/// A transform stored as decomposed translation, rotation, and scale.
/// {@category Documents}
class TrsTransform extends TransformSpec {
  TrsTransform({Vector3? translation, Quaternion? rotation, Vector3? scale})
    : translation = translation ?? Vector3.zero(),
      rotation = rotation ?? Quaternion.identity(),
      scale = scale ?? Vector3(1, 1, 1);

  /// The translation component.
  final Vector3 translation;

  /// The rotation component.
  final Quaternion rotation;

  /// The scale component.
  final Vector3 scale;

  @override
  Matrix4 toMatrix4() => Matrix4.compose(translation, rotation, scale);
}

/// A serialized component: a stable [type] name plus a typed property bag.
///
/// The [type] is resolved through the component codec registry at
/// realization; the [properties] hold the component's typed fields.
/// {@category Documents}
class ComponentSpec {
  /// Creates a component of the given [type] with optional [properties].
  ComponentSpec(this.type, {Map<String, PropertyValue>? properties})
    : properties = properties ?? {};

  /// The registered component type name (for example `mesh`,
  /// `directionalLight`, `camera`).
  final String type;

  /// The component's typed fields, keyed by field name.
  final Map<String, PropertyValue> properties;
}

/// Whether a prefab instance's content loads eagerly with the scene or is
/// streamed in on demand.
/// {@category Documents}
enum LoadPolicy {
  /// Loaded with the containing scene.
  eager,

  /// A lightweight placeholder until explicitly loaded (level streaming).
  lazy,
}

/// One per-instance override of a prefab: set the property at [path] on the
/// node [target] (in the prefab's local id space) to [value].
/// {@category Documents}
class PropertyOverride {
  /// Creates an override of [path] on [target] to [value].
  PropertyOverride({
    required this.target,
    required this.path,
    required this.value,
  });

  /// The node in the referenced prefab whose property is overridden.
  final LocalId target;

  /// A dotted property path, for example `components.mesh.material`,
  /// `components.mesh.primitives.0.material`, or `transform.trs.t`.
  final String path;

  /// The overriding value (absolute, not a relative delta).
  final PropertyValue value;
}

/// Grafts a host-scene node (and its subtree) into a prefab instance under one
/// of the prefab's internal nodes. [node] is a real node in the host document
/// (so it edits and deletes like any other node); [parent] is the prefab-local
/// node it attaches under, or null to attach under the instance's root.
///
/// This is how content added to an instance (a prop on a rig's hand bone)
/// stays fully editable: the node lives in the host scene, and composition
/// moves it under the prefab node at realize time.
/// {@category Documents}
class Attachment {
  /// Attaches host node [node] under prefab-local [parent].
  Attachment(this.node, {this.parent});

  /// The host-document node id grafted into the instance.
  final LocalId node;

  /// The prefab-local node this attaches under, or null for the instance root.
  final LocalId? parent;
}

/// The data that makes a [NodeSpec] a prefab instance: a reference to another
/// `.fscene` plus the per-instance delta (overrides and added/removed
/// content). The prefab composer applies these against the referenced
/// document; a plain node leaves [NodeSpec.instance] null.
/// {@category Documents}
class PrefabInstanceSpec {
  /// Creates a prefab instance of [source] with an optional delta.
  PrefabInstanceSpec({
    required this.source,
    this.load = LoadPolicy.eager,
    List<PropertyOverride>? overrides,
    List<Attachment>? attachments,
    List<LocalId>? removedNodes,
    List<ComponentSpec>? addedComponents,
    List<String>? removedComponentTypes,
    List<MemberComponent>? memberComponents,
  }) : overrides = overrides ?? [],
       attachments = attachments ?? [],
       removedNodes = removedNodes ?? [],
       addedComponents = addedComponents ?? [],
       removedComponentTypes = removedComponentTypes ?? [],
       memberComponents = memberComponents ?? [];

  /// The referenced prefab `.fscene`.
  final AssetRef source;

  /// Whether the instance's content loads eagerly or streams in. Asset-backed
  /// loaders resolve [source] relative to the declaring document for both
  /// policies.
  final LoadPolicy load;

  /// Per-property overrides applied on top of the prefab.
  final List<PropertyOverride> overrides;

  /// Host-scene nodes grafted into this instance under prefab-local parents.
  final List<Attachment> attachments;

  /// Prefab nodes (by their local id in the prefab) suppressed on this
  /// instance.
  final List<LocalId> removedNodes;

  /// Components added to the instance's root that the prefab does not have.
  final List<ComponentSpec> addedComponents;

  /// Prefab component types suppressed on this instance's root.
  final List<String> removedComponentTypes;

  /// Components added to prefab member nodes on this instance, targeted by
  /// the member's id in the prefab's own id space. Composed in before the
  /// [overrides], so an override can address their properties.
  final List<MemberComponent> memberComponents;

  /// A copy with the given fields replaced. Copy sites must use this (not a
  /// field-by-field reconstruction) so a new delta field is never dropped.
  PrefabInstanceSpec copyWith({
    AssetRef? source,
    LoadPolicy? load,
    List<PropertyOverride>? overrides,
    List<Attachment>? attachments,
    List<LocalId>? removedNodes,
    List<ComponentSpec>? addedComponents,
    List<String>? removedComponentTypes,
    List<MemberComponent>? memberComponents,
  }) => PrefabInstanceSpec(
    source: source ?? this.source,
    load: load ?? this.load,
    overrides: overrides ?? this.overrides,
    attachments: attachments ?? this.attachments,
    removedNodes: removedNodes ?? this.removedNodes,
    addedComponents: addedComponents ?? this.addedComponents,
    removedComponentTypes: removedComponentTypes ?? this.removedComponentTypes,
    memberComponents: memberComponents ?? this.memberComponents,
  );
}

/// One component an instance adds to a prefab member node.
/// {@category Documents}
class MemberComponent {
  /// Creates a member-component record.
  MemberComponent({required this.member, required this.component});

  /// The target node's id in the prefab's own id space.
  final LocalId member;

  /// The component carried onto that member.
  final ComponentSpec component;
}

/// A node in the document's scene graph.
///
/// Identity is the stable [id]; [name] is a non-identifying label kept for
/// animation binding and name lookup. Hierarchy is by [children] id list.
/// A node is either a plain node or, when [instance] is non-null, a prefab
/// instance.
/// {@category Documents}
class NodeSpec {
  /// Creates a node with the given stable [id].
  NodeSpec({
    required this.id,
    this.name = '',
    TransformSpec? transform,
    List<LocalId>? children,
    List<ComponentSpec>? components,
    this.layers = 1,
    this.lightChannelMask = 0xFF,
    this.skin,
    this.instance,
    this.visible = true,
    this.raycastable = true,
  }) : transform = transform ?? TrsTransform(),
       children = children ?? [],
       components = components ?? [];

  /// This node's stable, document-scoped id.
  final LocalId id;

  /// A non-identifying label (used for animation binding and name lookup).
  String name;

  /// The node's local transform.
  TransformSpec transform;

  /// Child node ids, in order.
  final List<LocalId> children;

  /// The components attached to this node.
  final List<ComponentSpec> components;

  /// The render-layer bitmask (defaults to layer 0).
  int layers;

  /// The light-channel bitmask, 8 bits (defaults to every channel). A light
  /// reaches this node's meshes only where its own channel mask intersects
  /// this one.
  int lightChannelMask;

  /// The skin bound to this node, or null.
  LocalId? skin;

  /// Non-null when this node is a prefab instance.
  PrefabInstanceSpec? instance;

  /// Whether this node (and so its subtree) renders. Hidden nodes still
  /// realize and tick; only drawing is skipped.
  bool visible;

  /// Whether scene raycasts test this node's meshes (defaults to true).
  /// Distinct from [visible]: a hidden node is already skipped by default.
  bool raycastable;
}

/// An axis-aligned bounding box in a resource's local space.
/// {@category Documents}
class BoundsSpec {
  /// Creates bounds spanning [min] to [max].
  BoundsSpec({required this.min, required this.max});

  /// The minimum corner.
  final Vector3 min;

  /// The maximum corner.
  final Vector3 max;
}

/// A shared, id-keyed resource referenced by nodes (and other resources).
/// {@category Documents}
sealed class ResourceSpec {
  ResourceSpec(this.id);

  /// This resource's stable, document-scoped id.
  final LocalId id;
}

/// A procedural geometry the runtime builds from parameters (rather than from
/// baked vertex buffers). Compact and editable; no payload needed.
/// {@category Documents}
sealed class ProceduralGeometry {
  const ProceduralGeometry();
}

/// A box of the given [extents], optionally with per-corner debug colors.
/// {@category Documents}
class CuboidGeometrySpec extends ProceduralGeometry {
  /// Creates a cuboid spec.
  CuboidGeometrySpec({required this.extents, this.debugColors = false});

  /// The box dimensions.
  final Vector3 extents;

  /// Whether each corner carries a distinct debug color.
  final bool debugColors;
}

/// A height-field terrain, either generated from fractal noise or read from a
/// stored heightmap.
///
/// Without [heights] it is described by its parameters: the same seed always
/// produces the same ground, so a document carries a few numbers rather than
/// a megabyte of samples. Sculpting it bakes those samples into a
/// [PayloadEncoding.floats] payload and points [heights] at it, which is the
/// moment terrain stops being a formula and starts being data.
/// {@category Documents}
class TerrainGeometrySpec extends ProceduralGeometry {
  /// Creates a terrain spec.
  TerrainGeometrySpec({
    this.width = 64.0,
    this.depth = 64.0,
    this.columns = 65,
    this.rows = 65,
    this.amplitude = 8.0,
    this.frequency = 0.02,
    this.octaves = 4,
    this.seed = 1337,
    this.heights,
    this.splat,
    this.splatColumns = 256,
    this.splatRows = 256,
  });

  /// World size across X.
  final double width;

  /// World size across Z.
  final double depth;

  /// Height samples across X; one more than the quads.
  final int columns;

  /// Height samples across Z.
  final int rows;

  /// Peak height above and below zero.
  final double amplitude;

  /// Noise scale, in world units.
  final double frequency;

  /// How many layers of detail are summed.
  final int octaves;

  /// The seed; the same one always gives the same ground.
  final int seed;

  /// A packed-float payload of `columns * rows` samples, row-major, or null
  /// to generate them from the parameters above.
  final LocalId? heights;

  /// An RGBA payload of `splatColumns * splatRows` texels holding how much
  /// each of four surface layers shows, or null for a terrain that is one
  /// material throughout.
  final LocalId? splat;

  /// Control-map texels across X.
  ///
  /// Deliberately not [columns]: painting wants finer detail than sculpting,
  /// and tying the two would mean either a heightmap denser than anyone needs
  /// or a paintable resolution nobody can work at.
  final int splatColumns;

  /// Control-map texels across Z.
  final int splatRows;

  /// Whether this terrain carries its own samples rather than a recipe.
  bool get isSculpted => heights != null;

  /// Whether this terrain carries painted surface layers.
  bool get isPainted => splat != null;

  /// A copy with the given fields replaced.
  ///
  /// Editing one part of a terrain means writing a new spec, and a terrain has
  /// enough parts that rebuilding it field by field at each call site is a
  /// standing invitation to drop one: sculpting a painted terrain would lose
  /// its painting, and the loss would show up a save later.
  TerrainGeometrySpec copyWith({
    double? width,
    double? depth,
    int? columns,
    int? rows,
    double? amplitude,
    double? frequency,
    int? octaves,
    int? seed,
    LocalId? heights,
    LocalId? splat,
    int? splatColumns,
    int? splatRows,
  }) => TerrainGeometrySpec(
    width: width ?? this.width,
    depth: depth ?? this.depth,
    columns: columns ?? this.columns,
    rows: rows ?? this.rows,
    amplitude: amplitude ?? this.amplitude,
    frequency: frequency ?? this.frequency,
    octaves: octaves ?? this.octaves,
    seed: seed ?? this.seed,
    heights: heights ?? this.heights,
    splat: splat ?? this.splat,
    splatColumns: splatColumns ?? this.splatColumns,
    splatRows: splatRows ?? this.splatRows,
  );
}

/// A cylinder or cone about the Y axis; a smaller [topRadius] tapers it, and
/// zero makes a cone.
/// {@category Documents}
class CylinderGeometrySpec extends ProceduralGeometry {
  /// Creates a cylinder spec.
  CylinderGeometrySpec({
    this.bottomRadius = 0.5,
    this.topRadius = 0.5,
    this.height = 1.0,
    this.radialSegments = 32,
    this.heightSegments = 1,
    this.bottomCap = true,
    this.topCap = true,
  });

  /// Radius at the base.
  final double bottomRadius;

  /// Radius at the top; zero makes a cone.
  final double topRadius;

  /// Height along Y.
  final double height;

  /// Segments around the axis.
  final int radialSegments;

  /// Segments along the axis.
  final int heightSegments;

  /// Whether the base is closed.
  final bool bottomCap;

  /// Whether the top is closed.
  final bool topCap;
}

/// A capsule about the Y axis: a cylinder with a hemisphere on each end.
/// {@category Documents}
class CapsuleGeometrySpec extends ProceduralGeometry {
  /// Creates a capsule spec.
  CapsuleGeometrySpec({
    this.radius = 0.5,
    this.height = 1.0,
    this.radialSegments = 32,
    this.capRings = 8,
  });

  /// Radius of the shaft and of both caps.
  final double radius;

  /// Height of the cylindrical section, excluding the caps.
  final double height;

  /// Segments around the axis.
  final int radialSegments;

  /// Rings making up each hemisphere.
  final int capRings;
}

/// A filled circle in the XZ plane.
/// {@category Documents}
class DiscGeometrySpec extends ProceduralGeometry {
  /// Creates a disc spec.
  DiscGeometrySpec({this.radius = 0.5, this.segments = 32});

  /// Radius of the disc.
  final double radius;

  /// Segments around the rim.
  final int segments;
}

/// A right-triangular prism, the ramp shape.
/// {@category Documents}
class WedgeGeometrySpec extends ProceduralGeometry {
  /// Creates a wedge spec sized to [size] = `(width, height, run)`.
  WedgeGeometrySpec({required this.size});

  /// Width, height and run of the ramp.
  final Vector3 size;
}

/// A flat plane in the XZ plane.
/// {@category Documents}
class PlaneGeometrySpec extends ProceduralGeometry {
  /// Creates a plane spec.
  PlaneGeometrySpec({
    this.width = 1.0,
    this.depth = 1.0,
    this.segmentsX = 1,
    this.segmentsZ = 1,
  });

  /// Size along X.
  final double width;

  /// Size along Z.
  final double depth;

  /// Grid subdivisions along X.
  final int segmentsX;

  /// Grid subdivisions along Z.
  final int segmentsZ;
}

/// A UV sphere.
/// {@category Documents}
class SphereGeometrySpec extends ProceduralGeometry {
  /// Creates a sphere spec.
  SphereGeometrySpec({this.radius = 0.5, this.segments = 32, this.rings = 16});

  /// The sphere radius.
  final double radius;

  /// Divisions around the equator.
  final int segments;

  /// Divisions from pole to pole.
  final int rings;
}

/// A torus centered on the origin around the Y axis.
/// {@category Documents}
class TorusGeometrySpec extends ProceduralGeometry {
  /// Creates a torus spec.
  TorusGeometrySpec({
    this.radius = 0.5,
    this.tubeRadius = 0.15,
    this.radialSegments = 32,
    this.tubularSegments = 16,
  });

  /// Distance from the origin to the tube center.
  final double radius;

  /// Tube radius.
  final double tubeRadius;

  /// Divisions around the main ring.
  final int radialSegments;

  /// Divisions around the tube.
  final int tubularSegments;
}

/// A geodesic sphere made by subdividing an icosahedron.
/// {@category Documents}
class IcosphereGeometrySpec extends ProceduralGeometry {
  /// Creates an icosphere spec.
  IcosphereGeometrySpec({this.radius = 0.5, this.subdivisions = 2});

  /// Sphere radius.
  final double radius;

  /// Recursive triangle subdivision count.
  final int subdivisions;
}

/// Mesh geometry, sourced either from a binary [payload] chunk (imported
/// content) or a [procedural] descriptor (a runtime primitive). Exactly one
/// source is set. Carries optional local [bounds] and optional
/// [morphTargets].
/// {@category Documents}
class GeometryResource extends ResourceSpec {
  /// Creates a geometry resource from payload chunks (a [vertices] buffer and
  /// optional [indices] buffer) or a [procedural] descriptor.
  GeometryResource(
    super.id, {
    this.vertices,
    this.indices,
    this.procedural,
    this.bounds,
    this.topology = 'triangle',
    this.morphTargets,
    this.legacyWinding = false,
  }) : assert(
         (vertices == null) != (procedural == null),
         'A geometry has exactly one source: a vertex payload or a procedural '
         'descriptor',
       );

  /// The binary chunk holding this geometry's vertex buffer, or null when
  /// [procedural] is set. Its layout lives on the referenced payload.
  final LocalId? vertices;

  /// The binary chunk holding this geometry's index buffer, or null for a
  /// non-indexed payload geometry (always null when [procedural] is set). The
  /// element width (`uint16` / `uint32`) lives on the referenced payload's
  /// `format`.
  final LocalId? indices;

  /// The procedural descriptor, or null when [vertices] is set.
  final ProceduralGeometry? procedural;

  /// The geometry's local-space bounds, when known.
  final BoundsSpec? bounds;

  /// How the vertex/index data assembles into primitives (mapped to the
  /// runtime enum at realization): `triangle`, `triangleStrip`, `line`,
  /// `lineStrip`, or `point`.
  final String topology;

  /// The geometry's morph target (blend shape) data, or null when unmorphed.
  final MorphTargetsSpec? morphTargets;

  /// Whether this geometry was migrated from an older document version (< 5)
  /// that stored indices with clockwise winding.
  final bool legacyWinding;
}

/// Morph target data on a [GeometryResource]: the delta payload plus target
/// metadata.
///
/// The [deltas] chunk holds dense float32 delta slabs, target-major and
/// aligned with the geometry's vertex order: every target's position deltas
/// (`targetCount * vertexCount * 3` floats), then the same shape of normal
/// deltas when [hasNormalDeltas], then tangent deltas (xyz) when
/// [hasTangentDeltas].
/// {@category Documents}
class MorphTargetsSpec {
  /// Creates a morph targets description over the [deltas] payload.
  MorphTargetsSpec({
    required this.deltas,
    required this.targetCount,
    this.hasNormalDeltas = false,
    this.hasTangentDeltas = false,
    List<String>? targetNames,
    List<double>? defaultWeights,
  }) : targetNames = targetNames ?? const [],
       defaultWeights = defaultWeights ?? const [];

  /// The binary chunk holding the delta slabs.
  final LocalId deltas;

  /// The number of morph targets.
  final int targetCount;

  /// Whether [deltas] carries a normal-delta slab after the positions.
  final bool hasNormalDeltas;

  /// Whether [deltas] carries a tangent-delta slab after the normals.
  final bool hasTangentDeltas;

  /// The target names (from the source asset's `extras.targetNames`), or
  /// empty when unnamed.
  final List<String> targetNames;

  /// The mesh-authored default weights, or empty for all-zero defaults.
  final List<double> defaultWeights;
}

/// A texture sourced either from an embedded [payload] chunk or an external
/// image [asset].
/// {@category Documents}
class TextureResource extends ResourceSpec {
  /// Creates a texture from an embedded [payload] or an external [asset].
  TextureResource(super.id, {this.payload, this.asset, this.content = 'color'})
    : assert(
        (payload == null) != (asset == null),
        'A texture has exactly one source: a payload or an asset',
      );

  /// The embedded image chunk, or null when [asset] is set.
  final LocalId? payload;

  /// The external image asset, or null when [payload] is set.
  final AssetRef? asset;

  /// What the pixels represent (`color`, `data`, `normal`), mapped to the
  /// runtime `TextureContent` at realization. Mip levels downsample by this
  /// rule, so a normal map averages as vectors rather than as color.
  final String content;
}

/// An offscreen render target a serialized render view draws into and
/// materials sample by id (the runtime `RenderTexture`).
/// {@category Documents}
class RenderTextureResource extends ResourceSpec {
  /// Creates a render-texture resource.
  RenderTextureResource(
    super.id, {
    required this.width,
    required this.height,
    this.update = 'everyFrame',
    this.intervalMilliseconds,
    this.filter = 'linear',
    this.wrap = 'clampToEdge',
  });

  /// Target width in physical pixels.
  final int width;

  /// Target height in physical pixels.
  final int height;

  /// The update policy name (`everyFrame`, `interval`, `manual`), mapped
  /// to the runtime `RenderTextureUpdate` at realization.
  final String update;

  /// The interval for the `interval` policy, in milliseconds.
  final int? intervalMilliseconds;

  /// The sampling filter name (`linear`, `nearest`).
  final String filter;

  /// The sampling wrap-mode name (`clampToEdge`, `repeat`, `mirror`).
  final String wrap;
}

/// A material: a [type] (for example `physicallyBased`, `unlit`, `fmat`)
/// plus typed [properties]. An `fmat` material references its `.fmat` source
/// via [asset].
/// {@category Documents}
class MaterialResource extends ResourceSpec {
  /// Creates a material of the given [type].
  MaterialResource(
    super.id, {
    required this.type,
    this.name = '',
    Map<String, PropertyValue>? properties,
    this.asset,
  }) : properties = properties ?? {};

  /// The material kind (`physicallyBased`, `unlit`, `fmat`, ...).
  final String type;

  /// The material's name, empty when the source asset left it unnamed.
  final String name;

  /// Typed material parameters (factors, texture refs, alpha mode, ...).
  final Map<String, PropertyValue> properties;

  /// For `fmat` materials, the `.fmat` source asset; otherwise null.
  final AssetRef? asset;

  /// A copy with the given fields replaced, so rewriters carry every other
  /// field (including ones added later) without listing them.
  MaterialResource copyWith({
    String? type,
    String? name,
    Map<String, PropertyValue>? properties,
    AssetRef? asset,
  }) => MaterialResource(
    id,
    type: type ?? this.type,
    name: name ?? this.name,
    properties: properties ?? this.properties,
    asset: asset ?? this.asset,
  );
}

/// A reusable image-based-lighting environment in the resource pool, referenced
/// by the stage's global environment and by environment-volume components.
///
/// Bundles the blendable look (the same fields the stage carries): the
/// image-based-lighting environment, its intensity and reflection-cube size,
/// exposure, tone mapping, the skybox, and sky-driven lighting. Realizes to a
/// runtime `EnvironmentSettings`.
/// {@category Documents}
class EnvironmentResource extends ResourceSpec {
  /// Creates an environment resource with the documented defaults.
  EnvironmentResource(
    super.id, {
    this.name = '',
    this.environment = const StudioEnvironment(),
    this.environmentIntensity = 1.0,
    this.exposure = 1.0,
    this.toneMapping = 'pbrNeutral',
    this.agxWhite = 16.29,
    this.agxContrast = 1.25,
    this.environmentRotationY = 0.0,
    this.radianceCubeSize,
    this.skybox,
    this.skyEnvironment,
    EnvironmentEffectsSpec? effects,
    this.overridesEffects = true,
  }) : effects = effects ?? EnvironmentEffectsSpec();

  /// A human-readable label shown in the editor (not load-bearing).
  String name;

  /// The image-based-lighting environment.
  EnvironmentSpec environment;

  /// Scalar multiplier on the environment's contribution.
  double environmentIntensity;

  /// Linear exposure multiplier applied before tone mapping.
  double exposure;

  /// The tone-mapping operator name.
  String toneMapping;

  /// Linear scene value mapped to display white by AgX.
  double agxWhite;

  /// Contrast applied by AgX around middle gray.
  double agxContrast;

  /// Rotation around the world Y axis applied when sampling the environment.
  double environmentRotationY;

  /// The reflection/ambient cubemap size, or null for the engine default.
  int? radianceCubeSize;

  /// The visible background sky, when set.
  SkyboxSpec? skybox;

  /// Sky-driven lighting, when set.
  SkyEnvironmentSpec? skyEnvironment;

  /// Blendable rendering and post-processing settings for this look.
  EnvironmentEffectsSpec effects;

  /// Whether [effects] replace the live scene's current effect settings.
  ///
  /// Version 1 documents without authored effects leave them unchanged.
  bool overridesEffects;
}

/// Rendering and post-processing settings carried by an environment resource.
///
/// These settings are shared by the global environment and spatial environment
/// volumes, so every field can be blended when the camera enters a volume.
/// {@category Documents}
class EnvironmentEffectsSpec {
  /// Creates effect settings with the runtime defaults.
  EnvironmentEffectsSpec({
    this.colorGradingEnabled = false,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    Vector3? lift,
    Vector3? gamma,
    Vector3? gain,
    this.colorGradingLut,
    this.colorGradingLutBlend = 1.0,
    this.bloomEnabled = false,
    this.bloomThreshold = 1.0,
    this.bloomIntensity = 0.15,
    this.bloomScatter = 0.7,
    this.lensFlareEnabled = false,
    this.lensFlareIntensity = 1.0,
    this.lensFlareGhostCount = 4,
    this.lensFlareGhostSpacing = 0.3,
    this.lensFlareHaloRadius = 0.35,
    this.lensFlareHaloIntensity = 1.0,
    this.lensFlareChromaticAberration = 0.005,
    this.vignetteEnabled = false,
    this.vignetteIntensity = 0.5,
    this.vignetteRadius = 0.75,
    this.vignetteSmoothness = 0.5,
    this.chromaticAberrationEnabled = false,
    this.chromaticAberrationIntensity = 0.2,
    this.filmGrainEnabled = false,
    this.filmGrainIntensity = 0.3,
    this.ambientOcclusionEnabled = false,
    this.ambientOcclusionMethod = 'obscurance',
    this.ambientOcclusionRadius = 0.33,
    this.ambientOcclusionIntensity = 1.0,
    this.ambientOcclusionBias = 0.07,
    this.ambientOcclusionPower = 1.5,
    this.ambientOcclusionDetail = 0.5,
    this.ambientOcclusionHorizonAngle = 0.06,
    this.ambientOcclusionDirectLightAffect = 0.0,
    this.ambientOcclusionMultiBounce = 0.0,
    this.ambientOcclusionSampleCount = 16,
    this.ambientOcclusionSliceCount = 3,
    this.ambientOcclusionStepsPerSlice = 3,
    this.ambientOcclusionVisibilityBitmask = false,
    this.ambientOcclusionThickness = 0.5,
    this.ambientOcclusionThicknessHeuristic = 0.004,
    this.ambientOcclusionBentNormals = false,
    this.ambientOcclusionIndirectLight = 0.0,
    this.ambientOcclusionHalfResolution = true,
    this.ambientOcclusionDepthMipChain = false,
    this.ambientOcclusionSpecularMode = 'none',
    this.screenSpaceReflectionsEnabled = false,
    this.screenSpaceReflectionsIntensity = 1.0,
    this.screenSpaceReflectionsMaxDistance = 24.4,
    this.screenSpaceReflectionsThickness = 0.46,
    this.screenSpaceReflectionsStride = 9.0,
    this.screenSpaceReflectionsMaxSteps = 90,
    this.screenSpaceReflectionsBlur = 0.3,
    this.screenSpaceReflectionsDistanceFadeStart = 0.0,
    this.screenSpaceReflectionsResolutionScale = 1.0,
    this.globalIlluminationEnabled = false,
    this.globalIlluminationVolumeMode = 'followCamera',
    Vector3? globalIlluminationResolution,
    Vector3? globalIlluminationExtents,
    this.globalIlluminationIntensity = 1.0,
    this.globalIlluminationHysteresis = 0.95,
    this.globalIlluminationShadowBias = 0.3,
    this.globalIlluminationVisibility = 0.7,
    this.globalIlluminationVisibilityBias = 0.08,
    this.globalIlluminationProbeUpdateBudget = 0,
    this.globalIlluminationInjectionResolution = 'eighth',
    this.globalIlluminationFireflyClamp = 8.0,
    this.globalIlluminationEmissiveBoost = 1.0,
    this.globalIlluminationUpdateWhenIdleOnly = false,
    this.globalIlluminationBakeOnly = false,
    this.temporalAntiAliasingEnabled = false,
    this.temporalAntiAliasingMinimumCurrentWeight = 0.1,
    this.temporalAntiAliasingVarianceGamma = 1.0,
    this.temporalAntiAliasingSharpness = 0.0,
    this.temporalAntiAliasingJitterSequenceLength = 16,
    this.temporalAntiAliasingJitterScale = 1.0,
    this.temporalAntiAliasingObjectMotion = true,
    this.temporalAntiAliasingSkinnedMotion = true,
    this.fogEnabled = false,
    this.fogMode = 'exponential',
    Vector3? fogColor,
    this.fogSkyColorInfluence = 0.0,
    this.fogDensity = 0.02,
    this.fogStart = 0.0,
    this.fogEnd = 200.0,
    this.fogMaxOpacity = 1.0,
    this.fogCutoffDistance = 0.0,
    this.fogHeight = 0.0,
    this.fogHeightFalloff = 0.0,
    this.fogSunInScatter = 0.0,
    this.fogSunInScatterExponent = 8.0,
    this.godRaysEnabled = false,
    this.godRaysIntensity = 1.0,
    this.godRaysDensity = 0.5,
    this.godRaysAnisotropy = 0.7,
    this.godRaysStepCount = 24,
    this.godRaysMaxDistance = 200.0,
    this.godRaysJitter = 1.0,
    Vector3? godRaysColor,
    this.depthOfFieldEnabled = false,
    this.depthOfFieldFocusDistance = 10.0,
    this.depthOfFieldFStop = 2.8,
    this.depthOfFieldFocalLength = 0.0,
    this.depthOfFieldSensorHeight = 0.024,
    this.depthOfFieldBlurScale = 1.0,
    this.depthOfFieldMaxForegroundBlur = 24.0,
    this.depthOfFieldMaxBackgroundBlur = 32.0,
    this.depthOfFieldBladeCount = 0,
    this.depthOfFieldBladeRotation = 0.0,
    this.depthOfFieldBladeCurvature = 0.0,
    this.depthOfFieldQuality = 'medium',
    this.autoExposureEnabled = false,
    this.autoExposureStrength = 0.55,
    this.autoExposureCompensation = 0.0,
    this.autoExposureMinEv = -4.0,
    this.autoExposureMaxEv = 4.0,
    this.autoExposureSpeedUp = 3.0,
    this.autoExposureSpeedDown = 1.0,
  }) : lift = lift ?? Vector3.zero(),
       gamma = gamma ?? Vector3.all(1.0),
       gain = gain ?? Vector3.all(1.0),
       globalIlluminationResolution =
           globalIlluminationResolution ?? Vector3(16, 8, 16),
       globalIlluminationExtents =
           globalIlluminationExtents ?? Vector3(20, 10, 20),
       fogColor = fogColor ?? Vector3(0.6, 0.7, 0.8),
       godRaysColor = godRaysColor ?? Vector3.all(1.0);

  /// Creates an independent copy of [other].
  EnvironmentEffectsSpec.copy(EnvironmentEffectsSpec other)
    : this(
        colorGradingEnabled: other.colorGradingEnabled,
        brightness: other.brightness,
        contrast: other.contrast,
        saturation: other.saturation,
        temperature: other.temperature,
        tint: other.tint,
        lift: other.lift.clone(),
        gamma: other.gamma.clone(),
        gain: other.gain.clone(),
        colorGradingLut: other.colorGradingLut,
        colorGradingLutBlend: other.colorGradingLutBlend,
        bloomEnabled: other.bloomEnabled,
        bloomThreshold: other.bloomThreshold,
        bloomIntensity: other.bloomIntensity,
        bloomScatter: other.bloomScatter,
        lensFlareEnabled: other.lensFlareEnabled,
        lensFlareIntensity: other.lensFlareIntensity,
        lensFlareGhostCount: other.lensFlareGhostCount,
        lensFlareGhostSpacing: other.lensFlareGhostSpacing,
        lensFlareHaloRadius: other.lensFlareHaloRadius,
        lensFlareHaloIntensity: other.lensFlareHaloIntensity,
        lensFlareChromaticAberration: other.lensFlareChromaticAberration,
        vignetteEnabled: other.vignetteEnabled,
        vignetteIntensity: other.vignetteIntensity,
        vignetteRadius: other.vignetteRadius,
        vignetteSmoothness: other.vignetteSmoothness,
        chromaticAberrationEnabled: other.chromaticAberrationEnabled,
        chromaticAberrationIntensity: other.chromaticAberrationIntensity,
        filmGrainEnabled: other.filmGrainEnabled,
        filmGrainIntensity: other.filmGrainIntensity,
        ambientOcclusionEnabled: other.ambientOcclusionEnabled,
        ambientOcclusionMethod: other.ambientOcclusionMethod,
        ambientOcclusionRadius: other.ambientOcclusionRadius,
        ambientOcclusionIntensity: other.ambientOcclusionIntensity,
        ambientOcclusionBias: other.ambientOcclusionBias,
        ambientOcclusionPower: other.ambientOcclusionPower,
        ambientOcclusionDetail: other.ambientOcclusionDetail,
        ambientOcclusionHorizonAngle: other.ambientOcclusionHorizonAngle,
        ambientOcclusionDirectLightAffect:
            other.ambientOcclusionDirectLightAffect,
        ambientOcclusionMultiBounce: other.ambientOcclusionMultiBounce,
        ambientOcclusionSampleCount: other.ambientOcclusionSampleCount,
        ambientOcclusionSliceCount: other.ambientOcclusionSliceCount,
        ambientOcclusionStepsPerSlice: other.ambientOcclusionStepsPerSlice,
        ambientOcclusionVisibilityBitmask:
            other.ambientOcclusionVisibilityBitmask,
        ambientOcclusionThickness: other.ambientOcclusionThickness,
        ambientOcclusionThicknessHeuristic:
            other.ambientOcclusionThicknessHeuristic,
        ambientOcclusionBentNormals: other.ambientOcclusionBentNormals,
        ambientOcclusionIndirectLight: other.ambientOcclusionIndirectLight,
        ambientOcclusionHalfResolution: other.ambientOcclusionHalfResolution,
        ambientOcclusionDepthMipChain: other.ambientOcclusionDepthMipChain,
        ambientOcclusionSpecularMode: other.ambientOcclusionSpecularMode,
        screenSpaceReflectionsEnabled: other.screenSpaceReflectionsEnabled,
        screenSpaceReflectionsIntensity: other.screenSpaceReflectionsIntensity,
        screenSpaceReflectionsMaxDistance:
            other.screenSpaceReflectionsMaxDistance,
        screenSpaceReflectionsThickness: other.screenSpaceReflectionsThickness,
        screenSpaceReflectionsStride: other.screenSpaceReflectionsStride,
        screenSpaceReflectionsMaxSteps: other.screenSpaceReflectionsMaxSteps,
        screenSpaceReflectionsBlur: other.screenSpaceReflectionsBlur,
        screenSpaceReflectionsDistanceFadeStart:
            other.screenSpaceReflectionsDistanceFadeStart,
        screenSpaceReflectionsResolutionScale:
            other.screenSpaceReflectionsResolutionScale,
        globalIlluminationEnabled: other.globalIlluminationEnabled,
        globalIlluminationVolumeMode: other.globalIlluminationVolumeMode,
        globalIlluminationResolution: other.globalIlluminationResolution
            .clone(),
        globalIlluminationExtents: other.globalIlluminationExtents.clone(),
        globalIlluminationIntensity: other.globalIlluminationIntensity,
        globalIlluminationHysteresis: other.globalIlluminationHysteresis,
        globalIlluminationShadowBias: other.globalIlluminationShadowBias,
        globalIlluminationVisibility: other.globalIlluminationVisibility,
        globalIlluminationVisibilityBias:
            other.globalIlluminationVisibilityBias,
        globalIlluminationProbeUpdateBudget:
            other.globalIlluminationProbeUpdateBudget,
        globalIlluminationInjectionResolution:
            other.globalIlluminationInjectionResolution,
        globalIlluminationFireflyClamp: other.globalIlluminationFireflyClamp,
        globalIlluminationEmissiveBoost: other.globalIlluminationEmissiveBoost,
        globalIlluminationUpdateWhenIdleOnly:
            other.globalIlluminationUpdateWhenIdleOnly,
        globalIlluminationBakeOnly: other.globalIlluminationBakeOnly,
        temporalAntiAliasingEnabled: other.temporalAntiAliasingEnabled,
        temporalAntiAliasingMinimumCurrentWeight:
            other.temporalAntiAliasingMinimumCurrentWeight,
        temporalAntiAliasingVarianceGamma:
            other.temporalAntiAliasingVarianceGamma,
        temporalAntiAliasingSharpness: other.temporalAntiAliasingSharpness,
        temporalAntiAliasingJitterSequenceLength:
            other.temporalAntiAliasingJitterSequenceLength,
        temporalAntiAliasingJitterScale: other.temporalAntiAliasingJitterScale,
        temporalAntiAliasingObjectMotion:
            other.temporalAntiAliasingObjectMotion,
        temporalAntiAliasingSkinnedMotion:
            other.temporalAntiAliasingSkinnedMotion,
        fogEnabled: other.fogEnabled,
        fogMode: other.fogMode,
        fogColor: other.fogColor.clone(),
        fogSkyColorInfluence: other.fogSkyColorInfluence,
        fogDensity: other.fogDensity,
        fogStart: other.fogStart,
        fogEnd: other.fogEnd,
        fogMaxOpacity: other.fogMaxOpacity,
        fogCutoffDistance: other.fogCutoffDistance,
        fogHeight: other.fogHeight,
        fogHeightFalloff: other.fogHeightFalloff,
        fogSunInScatter: other.fogSunInScatter,
        fogSunInScatterExponent: other.fogSunInScatterExponent,
        godRaysEnabled: other.godRaysEnabled,
        godRaysIntensity: other.godRaysIntensity,
        godRaysDensity: other.godRaysDensity,
        godRaysAnisotropy: other.godRaysAnisotropy,
        godRaysStepCount: other.godRaysStepCount,
        godRaysMaxDistance: other.godRaysMaxDistance,
        godRaysJitter: other.godRaysJitter,
        godRaysColor: other.godRaysColor.clone(),
        depthOfFieldEnabled: other.depthOfFieldEnabled,
        depthOfFieldFocusDistance: other.depthOfFieldFocusDistance,
        depthOfFieldFStop: other.depthOfFieldFStop,
        depthOfFieldFocalLength: other.depthOfFieldFocalLength,
        depthOfFieldSensorHeight: other.depthOfFieldSensorHeight,
        depthOfFieldBlurScale: other.depthOfFieldBlurScale,
        depthOfFieldMaxForegroundBlur: other.depthOfFieldMaxForegroundBlur,
        depthOfFieldMaxBackgroundBlur: other.depthOfFieldMaxBackgroundBlur,
        depthOfFieldBladeCount: other.depthOfFieldBladeCount,
        depthOfFieldBladeRotation: other.depthOfFieldBladeRotation,
        depthOfFieldBladeCurvature: other.depthOfFieldBladeCurvature,
        depthOfFieldQuality: other.depthOfFieldQuality,
        autoExposureEnabled: other.autoExposureEnabled,
        autoExposureStrength: other.autoExposureStrength,
        autoExposureCompensation: other.autoExposureCompensation,
        autoExposureMinEv: other.autoExposureMinEv,
        autoExposureMaxEv: other.autoExposureMaxEv,
        autoExposureSpeedUp: other.autoExposureSpeedUp,
        autoExposureSpeedDown: other.autoExposureSpeedDown,
      );

  bool colorGradingEnabled;
  double brightness;
  double contrast;
  double saturation;
  double temperature;
  double tint;
  Vector3 lift;
  Vector3 gamma;
  Vector3 gain;

  /// A `.cube` lookup-table film look, or null for none. Applies
  /// independently of [colorGradingEnabled].
  AssetRef? colorGradingLut;

  /// How strongly [colorGradingLut] applies, `0.0` to `1.0`.
  double colorGradingLutBlend;

  bool bloomEnabled;
  double bloomThreshold;
  double bloomIntensity;
  double bloomScatter;

  /// Screen-space lens flares, generated inside the bloom chain (bloom
  /// must be enabled for them to run).
  bool lensFlareEnabled;
  double lensFlareIntensity;
  int lensFlareGhostCount;
  double lensFlareGhostSpacing;
  double lensFlareHaloRadius;
  double lensFlareHaloIntensity;
  double lensFlareChromaticAberration;
  bool vignetteEnabled;
  double vignetteIntensity;
  double vignetteRadius;
  double vignetteSmoothness;
  bool chromaticAberrationEnabled;
  double chromaticAberrationIntensity;
  bool filmGrainEnabled;
  double filmGrainIntensity;
  bool ambientOcclusionEnabled;
  String ambientOcclusionMethod;
  double ambientOcclusionRadius;
  double ambientOcclusionIntensity;
  double ambientOcclusionBias;
  double ambientOcclusionPower;
  double ambientOcclusionDetail;
  double ambientOcclusionHorizonAngle;
  double ambientOcclusionDirectLightAffect;
  double ambientOcclusionMultiBounce;
  int ambientOcclusionSampleCount;
  int ambientOcclusionSliceCount;
  int ambientOcclusionStepsPerSlice;
  bool ambientOcclusionVisibilityBitmask;
  double ambientOcclusionThickness;
  double ambientOcclusionThicknessHeuristic;
  bool ambientOcclusionBentNormals;
  double ambientOcclusionIndirectLight;
  bool ambientOcclusionHalfResolution;
  bool ambientOcclusionDepthMipChain;
  String ambientOcclusionSpecularMode;
  bool screenSpaceReflectionsEnabled;
  double screenSpaceReflectionsIntensity;
  double screenSpaceReflectionsMaxDistance;
  double screenSpaceReflectionsThickness;
  double screenSpaceReflectionsStride;
  int screenSpaceReflectionsMaxSteps;
  double screenSpaceReflectionsBlur;
  double screenSpaceReflectionsDistanceFadeStart;
  double screenSpaceReflectionsResolutionScale;
  bool fogEnabled;
  String fogMode;

  /// World-space global illumination. See `GlobalIlluminationSettings`.
  bool globalIlluminationEnabled;
  String globalIlluminationVolumeMode;
  Vector3 globalIlluminationResolution;
  Vector3 globalIlluminationExtents;
  double globalIlluminationIntensity;
  double globalIlluminationHysteresis;
  double globalIlluminationShadowBias;
  double globalIlluminationVisibility;
  double globalIlluminationVisibilityBias;
  int globalIlluminationProbeUpdateBudget;
  String globalIlluminationInjectionResolution;
  double globalIlluminationFireflyClamp;
  double globalIlluminationEmissiveBoost;
  bool globalIlluminationUpdateWhenIdleOnly;
  bool globalIlluminationBakeOnly;

  /// Temporal anti-aliasing. See `TemporalAntiAliasingSettings`.
  bool temporalAntiAliasingEnabled;
  double temporalAntiAliasingMinimumCurrentWeight;
  double temporalAntiAliasingVarianceGamma;
  double temporalAntiAliasingSharpness;
  int temporalAntiAliasingJitterSequenceLength;
  double temporalAntiAliasingJitterScale;
  bool temporalAntiAliasingObjectMotion;
  bool temporalAntiAliasingSkinnedMotion;

  Vector3 fogColor;
  double fogSkyColorInfluence;
  double fogDensity;
  double fogStart;
  double fogEnd;
  double fogMaxOpacity;
  double fogCutoffDistance;
  double fogHeight;
  double fogHeightFalloff;
  double fogSunInScatter;
  double fogSunInScatterExponent;
  bool godRaysEnabled;
  double godRaysIntensity;
  double godRaysDensity;
  double godRaysAnisotropy;
  int godRaysStepCount;
  double godRaysMaxDistance;
  double godRaysJitter;
  Vector3 godRaysColor;
  bool depthOfFieldEnabled;
  double depthOfFieldFocusDistance;
  double depthOfFieldFStop;
  double depthOfFieldFocalLength;
  double depthOfFieldSensorHeight;
  double depthOfFieldBlurScale;
  double depthOfFieldMaxForegroundBlur;
  double depthOfFieldMaxBackgroundBlur;
  int depthOfFieldBladeCount;
  double depthOfFieldBladeRotation;
  double depthOfFieldBladeCurvature;
  String depthOfFieldQuality;
  bool autoExposureEnabled;
  double autoExposureStrength;
  double autoExposureCompensation;
  double autoExposureMinEv;
  double autoExposureMaxEv;
  double autoExposureSpeedUp;
  double autoExposureSpeedDown;
}

/// A skin: the joint nodes it drives, its inverse-bind matrices (a binary
/// chunk), and the optional skeleton root.
/// {@category Documents}
class SkinSpec {
  /// Creates a skin with the given stable [id].
  SkinSpec(
    this.id, {
    List<LocalId>? joints,
    required this.inverseBindMatrices,
    this.skeleton,
  }) : joints = joints ?? [];

  /// This skin's stable id.
  final LocalId id;

  /// The joint node ids, in joint order.
  final List<LocalId> joints;

  /// The binary chunk holding the inverse-bind matrices.
  final LocalId inverseBindMatrices;

  /// The skeleton root joint node, when known.
  final LocalId? skeleton;
}

/// The node property an animation channel drives on its target node.
/// {@category Documents}
enum AnimationProperty {
  /// Drives the target's translation.
  translation,

  /// Drives the target's rotation.
  rotation,

  /// Drives the target's scale.
  scale,

  /// Drives the target's morph target weights. The keyframes payload is the
  /// flattened glTF shape, one weight per target per keyframe; the target
  /// count is the keyframe count divided by the timeline length.
  weights,
}

/// One animation channel: a keyframe timeline driving one [property] of one
/// target node.
///
/// Binds to its target by stable id ([target]); [targetName] is retained as
/// a clone-friendly fallback and for readable merges.
/// {@category Documents}
class AnimationChannelSpec {
  /// Creates a channel driving [property] of [target].
  AnimationChannelSpec({
    required this.target,
    this.targetName,
    required this.property,
    required this.timeline,
    required this.keyframes,
  });

  /// The node this channel animates (primary, id-based binding).
  final LocalId target;

  /// The target node's name (fallback binding, for clones and merges).
  final String? targetName;

  /// Which transform channel this drives.
  final AnimationProperty property;

  /// The binary chunk of keyframe times (seconds).
  final LocalId timeline;

  /// The binary chunk of keyframe values.
  final LocalId keyframes;
}

/// A named animation: a set of channels driving target nodes.
/// {@category Documents}
class AnimationSpec {
  /// Creates an animation with the given stable [id].
  AnimationSpec(this.id, {this.name = '', List<AnimationChannelSpec>? channels})
    : channels = channels ?? [];

  /// This animation's stable id.
  final LocalId id;

  /// The animation's name.
  String name;

  /// The channels this animation drives.
  final List<AnimationChannelSpec> channels;
}

/// How a binary payload chunk's bytes are interpreted.
/// {@category Documents}
enum PayloadEncoding {
  /// An interleaved vertex buffer (see [PayloadSpec.layout]).
  vertexBuffer,

  /// An index buffer.
  indexBuffer,

  /// An encoded or raw image (see [PayloadSpec.format]).
  image,

  /// A packed array of 4x4 matrices.
  matrices,

  /// A packed array of 32-bit floats.
  floats,

  /// Opaque bytes.
  bytes,
}

/// A binary chunk in the document's payload manifest: a descriptor plus, when
/// the document's payloads are loaded, the chunk [bytes].
///
/// The descriptor is what the text form carries; the bytes live in the
/// package and are attached when the document's payloads are loaded.
/// {@category Documents}
class PayloadSpec {
  /// Creates a payload descriptor with the given stable [id].
  PayloadSpec(
    this.id, {
    required this.encoding,
    this.layout,
    this.format,
    this.width,
    this.height,
    this.length,
    this.bytes,
  });

  /// This payload's stable id.
  final LocalId id;

  /// How the bytes are interpreted.
  final PayloadEncoding encoding;

  /// For [PayloadEncoding.vertexBuffer], the vertex layout; otherwise null.
  final String? layout;

  /// For [PayloadEncoding.image], the pixel format (`rgba8`, ...); otherwise
  /// null.
  final String? format;

  /// For image payloads, the pixel width.
  final int? width;

  /// For image payloads, the pixel height.
  final int? height;

  /// The chunk's byte length, when known.
  final int? length;

  /// The chunk bytes, when the document's payloads are loaded; otherwise
  /// null (a manifest-only document).
  Uint8List? bytes;
}

/// The image-based-lighting environment for a scene.
/// {@category Documents}
sealed class EnvironmentSpec {
  const EnvironmentSpec();
}

/// The built-in procedural studio environment.
/// {@category Documents}
class StudioEnvironment extends EnvironmentSpec {
  /// The studio environment.
  const StudioEnvironment();
}

/// An environment built from an external image [asset].
/// {@category Documents}
class AssetEnvironment extends EnvironmentSpec {
  /// An environment sourced from [asset].
  const AssetEnvironment(this.asset);

  /// The environment image asset.
  final AssetRef asset;
}

/// An empty (black) environment.
/// {@category Documents}
class EmptyEnvironment extends EnvironmentSpec {
  /// The empty environment.
  const EmptyEnvironment();
}

/// A reflection-free environment with uniform diffuse ambient radiance.
/// {@category Documents}
class ConstantEnvironment extends EnvironmentSpec {
  /// Creates a uniform diffuse environment with linear RGB [color].
  ConstantEnvironment(Vector3 color) : color = color.clone();

  /// Linear RGB radiance received by a white Lambertian surface.
  final Vector3 color;
}

/// An environment built from an embedded image [payload] chunk (a Radiance
/// HDR, OpenEXR, or LDR equirect), the self-contained form a build produces by
/// inlining an [AssetEnvironment]'s external image. The realizer detects the
/// decoder from the payload bytes; the payload's `format` tag (the source file
/// extension) is informational. Not part of the public surface; produced by
/// the build hook and consumed by the realizer.
/// {@category Documents}
class PayloadEnvironment extends EnvironmentSpec {
  /// An environment sourced from the embedded image [payload].
  const PayloadEnvironment(this.payload);

  /// The embedded image chunk holding the equirect environment.
  final LocalId payload;
}

/// What a stage sky looks like, serialized.
///
/// Realized to a runtime `SkySource` by the stage realizer: the environment
/// sky and the built-in gradient/physical skies realize from their fields;
/// an fmat sky loads its `.fmat` by source path.
/// {@category Documents}
sealed class SkySourceSpec {
  /// Const base.
  const SkySourceSpec();
}

/// Shows the scene's image-based-lighting environment, optionally blurred.
/// {@category Documents}
class EnvironmentSkySpec extends SkySourceSpec {
  /// Creates the spec.
  EnvironmentSkySpec({this.blurriness = 0.0});

  /// How blurred the background is, from `0.0` (sharp) to `1.0`.
  double blurriness;
}

/// A sky `.fmat` loaded by source path, with optional parameter overrides
/// applied to the loaded sky's parameters by name.
/// {@category Documents}
class FmatSkySpec extends SkySourceSpec {
  /// Creates the spec.
  FmatSkySpec(this.asset, {Map<String, PropertyValue>? properties})
    : properties = properties ?? {};

  /// The `.fmat` source path (relative to the owning package's root).
  final AssetRef asset;

  /// Parameter overrides, keyed by parameter name.
  final Map<String, PropertyValue> properties;
}

/// The built-in stylized gradient sky.
/// {@category Documents}
class GradientSkySpec extends SkySourceSpec {
  /// Creates the spec with the runtime defaults.
  GradientSkySpec({
    Vector3? zenithColor,
    Vector3? horizonColor,
    Vector3? groundColor,
    Vector3? sunDirection,
    Vector3? sunColor,
    this.sunSharpness = 400.0,
  }) : zenithColor = zenithColor ?? Vector3(0.05, 0.18, 0.55),
       horizonColor = horizonColor ?? Vector3(0.45, 0.62, 0.90),
       groundColor = groundColor ?? Vector3(0.16, 0.14, 0.12),
       sunDirection = sunDirection ?? Vector3(0.4, 0.5, 0.6),
       sunColor = sunColor ?? Vector3(3.0, 2.7, 2.2);

  /// The sky color straight up.
  Vector3 zenithColor;

  /// The sky color at the horizon.
  Vector3 horizonColor;

  /// The color below the horizon.
  Vector3 groundColor;

  /// Direction toward the sun.
  Vector3 sunDirection;

  /// The sun disk color, linear HDR.
  Vector3 sunColor;

  /// Sharpness exponent of the sun disk.
  double sunSharpness;
}

/// The built-in physically based daylight sky.
/// {@category Documents}
class PhysicalSkySpec extends SkySourceSpec {
  /// Creates the spec with the runtime defaults.
  PhysicalSkySpec({
    Vector3? sunDirection,
    this.sunAngularRadius = 0.0175,
    this.rayleighCoefficient = 2.0,
    Vector3? rayleighColor,
    this.mieCoefficient = 0.005,
    this.mieEccentricity = 0.8,
    Vector3? mieColor,
    this.turbidity = 10.0,
    Vector3? groundColor,
    this.energy = 1.0,
  }) : sunDirection = sunDirection ?? Vector3(0.4, 0.5, 0.6),
       rayleighColor = rayleighColor ?? Vector3(0.26, 0.41, 0.58),
       mieColor = mieColor ?? Vector3(0.69, 0.73, 0.81),
       groundColor = groundColor ?? Vector3(0.12, 0.12, 0.13);

  /// Direction toward the sun.
  Vector3 sunDirection;

  /// Angular radius of the sun disk, in radians.
  double sunAngularRadius;

  /// Strength of molecular (Rayleigh) scattering.
  double rayleighCoefficient;

  /// Wavelength tint of the Rayleigh term.
  Vector3 rayleighColor;

  /// Strength of aerosol (Mie) scattering.
  double mieCoefficient;

  /// Forward-scattering eccentricity of the Mie term.
  double mieEccentricity;

  /// Wavelength tint of the Mie term.
  Vector3 mieColor;

  /// Aerosol density.
  double turbidity;

  /// The color below the horizon.
  Vector3 groundColor;

  /// Overall output multiplier.
  double energy;
}

/// The built-in daylight sky with a procedural cloud layer and storm
/// controls.
/// {@category Documents}
class WeatherSkySpec extends SkySourceSpec {
  /// Creates the spec with the runtime defaults.
  WeatherSkySpec({
    Vector3? sunDirection,
    this.sunAngularRadius = 0.0175,
    this.rayleighCoefficient = 2.0,
    Vector3? rayleighColor,
    this.mieCoefficient = 0.005,
    this.mieEccentricity = 0.8,
    Vector3? mieColor,
    this.turbidity = 10.0,
    Vector3? groundColor,
    this.energy = 1.0,
    this.coverage = 0.45,
    this.density = 0.95,
    this.altitude = 1.6,
    this.detail = 0.5,
    this.softness = 0.12,
    this.seed = 1337,
    Vector2? wind,
    Vector3? cloudColor,
    this.cloudShading = 0.85,
    this.stormDarkening = 0.0,
  }) : sunDirection = sunDirection ?? Vector3(0.4, 0.5, 0.6),
       rayleighColor = rayleighColor ?? Vector3(0.26, 0.41, 0.58),
       mieColor = mieColor ?? Vector3(0.69, 0.73, 0.81),
       groundColor = groundColor ?? Vector3(0.12, 0.12, 0.13),
       wind = wind ?? Vector2(0.35, 0.1),
       cloudColor = cloudColor ?? Vector3(1.0, 1.0, 1.02);

  /// Direction toward the sun.
  Vector3 sunDirection;

  /// Angular radius of the sun disk, in radians.
  double sunAngularRadius;

  /// Strength of molecular (Rayleigh) scattering.
  double rayleighCoefficient;

  /// Wavelength tint of the Rayleigh term.
  Vector3 rayleighColor;

  /// Strength of aerosol (Mie) scattering.
  double mieCoefficient;

  /// Forward-scattering eccentricity of the Mie term.
  double mieEccentricity;

  /// Wavelength tint of the Mie term.
  Vector3 mieColor;

  /// Aerosol density.
  double turbidity;

  /// The color below the horizon.
  Vector3 groundColor;

  /// Overall output multiplier.
  double energy;

  /// How much of the sky the clouds take, `0` clear to `1` overcast.
  double coverage;

  /// How opaque the clouds are where they are thickest.
  double density;

  /// How high the cloud layer sits in the dome projection.
  double altitude;

  /// Extra noise octaves, `0` to `1`.
  double detail;

  /// How wide the transition from clear sky to cloud is.
  double softness;

  /// The cloud noise seed.
  int seed;

  /// Layer-space cloud drift per second.
  Vector2 wind;

  /// The colour lit cloud tops take.
  Vector3 cloudColor;

  /// How far a cloud's shadowed underside darkens.
  double cloudShading;

  /// How overcast the sky is, `0` none to `1` full gloom.
  double stormDarkening;
}

/// The stage skybox: the visible background drawn behind all geometry.
/// {@category Documents}
class SkyboxSpec {
  /// Creates the spec.
  SkyboxSpec(this.source, {this.intensity = 1.0});

  /// What the sky looks like.
  SkySourceSpec source;

  /// Scales the sampled radiance for an environment sky source.
  double intensity;
}

/// A sky-driven analytic sun and its cascaded-shadow configuration.
/// {@category Documents}
class SunLightSpec {
  /// Creates the spec with the runtime defaults.
  SunLightSpec({
    this.castsShadow = true,
    this.intensityScale = 1.0,
    this.priority = 0,
    this.cacheStaticShadows = true,
    this.shadowSoftness = 0.08,
    this.shadowMaxDistance = 150.0,
    this.shadowCascadeCount = 4,
    this.shadowMapResolution = 1024,
    this.shadowDepthBias = 0.02,
    this.shadowNormalBias = 0.02,
    this.shadowFadeRange = 2.0,
    this.shadowCascadeSplitLambda = 0.6,
    this.shadowAmbientStrength = 0.0,
    this.shadowFilter = 'rotatedPoisson',
    this.contactShadows = false,
    this.contactShadowDistance = 0.3,
    this.angularRadius = 0.005,
    this.shadowCasterFaces = 'front',
  });

  /// Whether the sun casts cascaded shadows.
  bool castsShadow;

  /// Multiplier applied to the sky-derived sun intensity.
  double intensityScale;

  /// Priority for primary directional-light features.
  int priority;

  /// Whether static shadow casters are cached between frames.
  bool cacheStaticShadows;

  /// World-space shadow penumbra radius.
  double shadowSoftness;

  /// Maximum camera distance covered by cascaded shadows.
  double shadowMaxDistance;

  /// Number of shadow cascades.
  int shadowCascadeCount;

  /// Resolution of each cascade tile.
  int shadowMapResolution;

  /// Receiver depth bias in world units.
  double shadowDepthBias;

  /// Receiver normal bias in world units.
  double shadowNormalBias;

  /// Distance over which far shadows fade out.
  double shadowFadeRange;

  /// Blend between uniform and logarithmic cascade splits.
  double shadowCascadeSplitLambda;

  /// How strongly shadows darken image-based ambient lighting.
  double shadowAmbientStrength;

  /// Shadow sampling filter name.
  String shadowFilter;
  bool contactShadows;
  double contactShadowDistance;
  double angularRadius;

  /// Caster faces rendered into the shadow map.
  String shadowCasterFaces;
}

/// Sky-driven lighting: bakes a shader sky into the scene's image-based
/// lighting on a refresh policy.
/// {@category Documents}
class SkyEnvironmentSpec {
  /// Creates the spec with the runtime defaults.
  SkyEnvironmentSpec(
    this.source, {
    this.refresh = 'manual',
    this.intervalSeconds = 1.0,
    this.faceResolution = 128,
    this.equirectWidth = 512,
    this.sunLight,
  });

  /// The sky baked into the lighting. Must be a shader sky
  /// ([FmatSkySpec], [GradientSkySpec], or [PhysicalSkySpec]); an
  /// [EnvironmentSkySpec] cannot light itself and is skipped with a warning
  /// at realization.
  SkySourceSpec source;

  /// The refresh policy name (mapped to the runtime enum at realization):
  /// `manual`, `interval`, or `everyFrame`.
  String refresh;

  /// Minimum time between bakes for the `interval` policy, in seconds.
  double intervalSeconds;

  /// Cube-face capture resolution for the bake.
  int faceResolution;

  /// Width of the assembled equirect the prefilter and SH projection read.
  int equirectWidth;

  /// The sky-driven analytic sun, or null for image-based sky lighting only.
  /// Applies only when [source] is a sky with a sun.
  SunLightSpec? sunLight;
}

/// One serialized view of the scene: a camera node bound to a target and
/// the view's render settings (the runtime `RenderView`).
/// {@category Documents}
class RenderViewSpec {
  /// Creates a render-view spec.
  RenderViewSpec({
    required this.cameraNode,
    this.target,
    this.layerMask = 0xFFFFFFFF,
    this.order = 0,
    this.antiAliasingMode,
    this.renderScale,
    this.filterQuality,
  });

  /// The node whose `CameraComponent` provides this view's camera.
  final LocalId cameraNode;

  /// The render-texture resource this view draws into, or null for the
  /// screen.
  final LocalId? target;

  /// A bitmask selecting which node layers this view renders.
  final int layerMask;

  /// Compositing order among views sharing a target (lower first).
  final int order;

  /// The anti-aliasing mode name (`none`, `msaa`, `fxaa`, `auto`), or
  /// null to inherit the stage's.
  final String? antiAliasingMode;

  /// Resolution scale relative to the display's native, or null to
  /// inherit the stage's.
  final double? renderScale;

  /// The composite filter-quality name (`none`, `low`, `medium`, `high`),
  /// or null to inherit the stage's.
  final String? filterQuality;
}

/// Scene-wide, non-spatial render settings.
///
/// Every document uses the native left-handed coordinate system with +Y up,
/// +Z forward, and meters as world units. Lights and cameras are per-node
/// components.
/// {@category Documents}
class StageMetadata {
  /// Creates stage metadata with the documented defaults.
  StageMetadata({
    this.environmentRef,
    this.antiAliasingMode = 'auto',
    this.renderScale = 1.0,
    this.filterQuality = 'medium',
  });

  /// The anti-aliasing mode name (`none`, `msaa`, `fxaa`, `auto`), the
  /// scene-wide default views inherit.
  String antiAliasingMode;

  /// Resolution scale relative to the display's native, the scene-wide
  /// default views inherit.
  double renderScale;

  /// The composite filter-quality name (`none`, `low`, `medium`, `high`),
  /// the scene-wide default views inherit.
  String filterQuality;

  /// The global environment resource the stage's look comes from (the
  /// image-based-lighting environment, intensity, exposure, tone mapping,
  /// reflection size, skybox, and sky lighting). The realizer defaults to a
  /// studio look when this is null or does not resolve.
  LocalId? environmentRef;
}
