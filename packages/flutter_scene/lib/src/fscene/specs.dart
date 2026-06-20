import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';

/// A node's local transform, stored either as a 4x4 [matrix] or as a
/// decomposed translation/rotation/scale ([TrsTransform]). The importer
/// emits TRS for clean diffs; the runtime composes a [Matrix4].
sealed class TransformSpec {
  const TransformSpec();

  /// The transform as a 4x4 matrix.
  Matrix4 toMatrix4();
}

/// A transform stored as an explicit 4x4 matrix.
class MatrixTransform extends TransformSpec {
  MatrixTransform(this.matrix);

  /// The 4x4 local transform.
  final Matrix4 matrix;

  @override
  Matrix4 toMatrix4() => matrix.clone();
}

/// A transform stored as decomposed translation, rotation, and scale.
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
enum LoadPolicy {
  /// Loaded with the containing scene.
  eager,

  /// A lightweight placeholder until explicitly loaded (level streaming).
  lazy,
}

/// One per-instance override of a prefab: set the property at [path] on the
/// node [target] (in the prefab's local id space) to [value].
class PropertyOverride {
  /// Creates an override of [path] on [target] to [value].
  PropertyOverride({
    required this.target,
    required this.path,
    required this.value,
  });

  /// The node in the referenced prefab whose property is overridden.
  final LocalId target;

  /// A dotted property path, for example `components.mesh.material` or
  /// `transform.trs.t`.
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
  }) : overrides = overrides ?? [],
       attachments = attachments ?? [],
       removedNodes = removedNodes ?? [],
       addedComponents = addedComponents ?? [],
       removedComponentTypes = removedComponentTypes ?? [];

  /// The referenced prefab `.fscene`.
  final AssetRef source;

  /// Whether the instance's content loads eagerly or streams in.
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
}

/// A node in the document's scene graph.
///
/// Identity is the stable [id]; [name] is a non-identifying label kept for
/// animation binding and name lookup. Hierarchy is by [children] id list.
/// A node is either a plain node or, when [instance] is non-null, a prefab
/// instance.
class NodeSpec {
  /// Creates a node with the given stable [id].
  NodeSpec({
    required this.id,
    this.name = '',
    TransformSpec? transform,
    List<LocalId>? children,
    List<ComponentSpec>? components,
    this.layers = 1,
    this.skin,
    this.instance,
    this.excludeFromWindingParity = false,
    this.visible = true,
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

  /// The skin bound to this node, or null.
  LocalId? skin;

  /// Non-null when this node is a prefab instance.
  PrefabInstanceSpec? instance;

  /// Whether this node's mirror transform is excluded from winding-parity
  /// tracking. Set on handedness-adapter nodes (a `scale(1, 1, -1)` that
  /// converts between authoring spaces rather than mirroring content), so
  /// the renderer does not flip triangle winding under it.
  bool excludeFromWindingParity;

  /// Whether this node (and so its subtree) renders. Hidden nodes still
  /// realize and tick; only drawing is skipped.
  bool visible;
}

/// An axis-aligned bounding box in a resource's local space.
class BoundsSpec {
  /// Creates bounds spanning [min] to [max].
  BoundsSpec({required this.min, required this.max});

  /// The minimum corner.
  final Vector3 min;

  /// The maximum corner.
  final Vector3 max;
}

/// A shared, id-keyed resource referenced by nodes (and other resources).
sealed class ResourceSpec {
  ResourceSpec(this.id);

  /// This resource's stable, document-scoped id.
  final LocalId id;
}

/// A procedural geometry the runtime builds from parameters (rather than from
/// baked vertex buffers). Compact and editable; no payload needed.
sealed class ProceduralGeometry {
  const ProceduralGeometry();
}

/// A box of the given [extents], optionally with per-corner debug colors.
class CuboidGeometrySpec extends ProceduralGeometry {
  /// Creates a cuboid spec.
  CuboidGeometrySpec({required this.extents, this.debugColors = false});

  /// The box dimensions.
  final Vector3 extents;

  /// Whether each corner carries a distinct debug color.
  final bool debugColors;
}

/// A flat plane in the XZ plane.
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

/// Mesh geometry, sourced either from a binary [payload] chunk (imported
/// content) or a [procedural] descriptor (a runtime primitive). Exactly one
/// source is set. Carries optional local [bounds].
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
  }) : assert(
         (vertices == null) != (procedural == null),
         'A geometry has exactly one source: a vertex payload or a procedural '
         'descriptor',
       );

  /// The binary chunk holding this geometry's interleaved vertex buffer, or
  /// null when [procedural] is set. The vertex `layout` (`unskinned` /
  /// `skinned`) lives on the referenced payload.
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
}

/// A texture sourced either from an embedded [payload] chunk or an external
/// image [asset].
class TextureResource extends ResourceSpec {
  /// Creates a texture from an embedded [payload] or an external [asset].
  TextureResource(super.id, {this.payload, this.asset})
    : assert(
        (payload == null) != (asset == null),
        'A texture has exactly one source: a payload or an asset',
      );

  /// The embedded image chunk, or null when [asset] is set.
  final LocalId? payload;

  /// The external image asset, or null when [payload] is set.
  final AssetRef? asset;
}

/// An offscreen render target a serialized render view draws into and
/// materials sample by id (the runtime `RenderTexture`).
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
class MaterialResource extends ResourceSpec {
  /// Creates a material of the given [type].
  MaterialResource(
    super.id, {
    required this.type,
    Map<String, PropertyValue>? properties,
    this.asset,
  }) : properties = properties ?? {};

  /// The material kind (`physicallyBased`, `unlit`, `fmat`, ...).
  final String type;

  /// Typed material parameters (factors, texture refs, alpha mode, ...).
  final Map<String, PropertyValue> properties;

  /// For `fmat` materials, the `.fmat` source asset; otherwise null.
  final AssetRef? asset;
}

/// A reusable image-based-lighting environment in the resource pool, referenced
/// by the stage's global environment and by environment-volume components.
///
/// Bundles the blendable look (the same fields the stage carries): the
/// image-based-lighting environment, its intensity and reflection-cube size,
/// exposure, tone mapping, the skybox, and sky-driven lighting. Realizes to a
/// runtime `EnvironmentSettings`.
class EnvironmentResource extends ResourceSpec {
  /// Creates an environment resource with the documented defaults.
  EnvironmentResource(
    super.id, {
    this.name = '',
    this.environment = const StudioEnvironment(),
    this.environmentIntensity = 1.0,
    this.exposure = 1.0,
    this.toneMapping = 'pbrNeutral',
    this.radianceCubeSize,
    this.skybox,
    this.skyEnvironment,
  });

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

  /// The reflection/ambient cubemap size, or null for the engine default.
  int? radianceCubeSize;

  /// The visible background sky, when set.
  SkyboxSpec? skybox;

  /// Sky-driven lighting, when set.
  SkyEnvironmentSpec? skyEnvironment;
}

/// A skin: the joint nodes it drives, its inverse-bind matrices (a binary
/// chunk), and the optional skeleton root.
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

/// The transform channel an animation drives on its target node.
enum AnimationProperty {
  /// Drives the target's translation.
  translation,

  /// Drives the target's rotation.
  rotation,

  /// Drives the target's scale.
  scale,
}

/// One animation channel: a keyframe timeline driving one [property] of one
/// target node.
///
/// Binds to its target by stable id ([target]); [targetName] is retained as
/// a clone-friendly fallback and for readable merges.
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

  /// For [PayloadEncoding.vertexBuffer], the vertex layout (`unskinned` /
  /// `skinned`); otherwise null.
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

/// The up axis convention a document was authored in.
enum UpAxis {
  /// X is up.
  x,

  /// Y is up (the glTF convention).
  y,

  /// Z is up.
  z,
}

/// The chirality of the coordinate system a document's positions and geometry
/// are expressed in. Drives the scene-root mirror the realizer applies, kept
/// as metadata rather than a literal node transform.
enum Handedness {
  /// The engine's native, left-handed space (`+Z` into the screen). Content
  /// authored in code or an editor against the runtime is already in this
  /// space, so the realizer applies no mirror. This is the default.
  left,

  /// Right-handed (the glTF convention, `+Z` out of the screen). The importer
  /// declares this; the realizer mirrors `scale(1, 1, -1)` to convert it to
  /// the engine's space.
  right,
}

/// The image-based-lighting environment for a scene.
sealed class EnvironmentSpec {
  const EnvironmentSpec();
}

/// The built-in procedural studio environment.
class StudioEnvironment extends EnvironmentSpec {
  /// The studio environment.
  const StudioEnvironment();
}

/// An environment built from an external image [asset].
class AssetEnvironment extends EnvironmentSpec {
  /// An environment sourced from [asset].
  const AssetEnvironment(this.asset);

  /// The environment image asset.
  final AssetRef asset;
}

/// An empty (black) environment.
class EmptyEnvironment extends EnvironmentSpec {
  /// The empty environment.
  const EmptyEnvironment();
}

/// What a stage sky looks like, serialized.
///
/// Realized to a runtime `SkySource` by the stage realizer: the environment
/// sky and the built-in gradient/physical skies realize from their fields;
/// an fmat sky loads its `.fmat` by source path.
sealed class SkySourceSpec {
  /// Const base.
  const SkySourceSpec();
}

/// Shows the scene's image-based-lighting environment, optionally blurred.
class EnvironmentSkySpec extends SkySourceSpec {
  /// Creates the spec.
  EnvironmentSkySpec({this.blurriness = 0.0});

  /// How blurred the background is, from `0.0` (sharp) to `1.0`.
  double blurriness;
}

/// A sky `.fmat` loaded by source path, with optional parameter overrides
/// applied to the loaded sky's parameters by name.
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

/// The stage skybox: the visible background drawn behind all geometry.
class SkyboxSpec {
  /// Creates the spec.
  SkyboxSpec(this.source, {this.intensity = 1.0});

  /// What the sky looks like.
  SkySourceSpec source;

  /// Scales the sampled radiance for an environment sky source.
  double intensity;
}

/// Sky-driven lighting: bakes a shader sky into the scene's image-based
/// lighting on a refresh policy.
class SkyEnvironmentSpec {
  /// Creates the spec with the runtime defaults.
  SkyEnvironmentSpec(
    this.source, {
    this.refresh = 'manual',
    this.intervalSeconds = 1.0,
    this.faceResolution = 128,
    this.equirectWidth = 512,
    this.castShadows = false,
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

  /// Whether the sky's sun also casts hard shadows (a sky-driven
  /// `SunLight`). Applies only when [source] is a sky with a sun
  /// (`GradientSkySpec`/`PhysicalSkySpec`); ignored otherwise.
  bool castShadows;
}

/// One serialized view of the scene: a camera node bound to a target and
/// the view's render settings (the runtime `RenderView`).
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

/// Scene-wide, non-spatial render settings (lights and cameras are per-node
/// components, not stage data).
class StageMetadata {
  /// Creates stage metadata with the documented defaults.
  StageMetadata({
    this.upAxis = UpAxis.y,
    this.handedness = Handedness.left,
    this.unitsPerMeter = 1.0,
    this.environment = const StudioEnvironment(),
    this.environmentIntensity = 1.0,
    this.exposure = 1.0,
    this.toneMapping = 'pbrNeutral',
    this.radianceCubeSize,
    this.environmentRef,
    this.antiAliasingMode = 'auto',
    this.renderScale = 1.0,
    this.filterQuality = 'medium',
    this.skybox,
    this.skyEnvironment,
  });

  /// The authored up axis.
  UpAxis upAxis;

  /// The authored handedness.
  Handedness handedness;

  /// World units per meter.
  double unitsPerMeter;

  /// The image-based-lighting environment.
  EnvironmentSpec environment;

  /// Scalar multiplier on the environment's contribution.
  double environmentIntensity;

  /// Linear exposure multiplier applied before tone mapping.
  double exposure;

  /// The tone-mapping operator name (mapped to the runtime enum at
  /// realization).
  String toneMapping;

  /// The reflection/ambient cubemap size for the base environment, or null to
  /// use the engine default.
  int? radianceCubeSize;

  /// The anti-aliasing mode name (`none`, `msaa`, `fxaa`, `auto`), the
  /// scene-wide default views inherit.
  String antiAliasingMode;

  /// Resolution scale relative to the display's native, the scene-wide
  /// default views inherit.
  double renderScale;

  /// The composite filter-quality name (`none`, `low`, `medium`, `high`),
  /// the scene-wide default views inherit.
  String filterQuality;

  /// The visible background sky, when set.
  SkyboxSpec? skybox;

  /// Sky-driven lighting (a sky baked into the environment on a refresh
  /// policy), when set. While set, it owns the scene environment, so
  /// [environment] is not applied.
  SkyEnvironmentSpec? skyEnvironment;

  /// The global environment resource the stage's look comes from. When set, it
  /// overrides the inline look fields above (the realizer resolves it to the
  /// base look); when null, the inline fields are used.
  //
  // TODO(stage-env-inline): once authoring always uses a resource, remove the
  // inline look fields and make this the only path.
  LocalId? environmentRef;
}
