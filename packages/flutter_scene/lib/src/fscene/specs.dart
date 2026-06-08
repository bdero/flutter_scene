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
    List<NodeSpec>? addedNodes,
    List<LocalId>? removedNodes,
    List<ComponentSpec>? addedComponents,
    List<String>? removedComponentTypes,
  }) : overrides = overrides ?? [],
       addedNodes = addedNodes ?? [],
       removedNodes = removedNodes ?? [],
       addedComponents = addedComponents ?? [],
       removedComponentTypes = removedComponentTypes ?? [];

  /// The referenced prefab `.fscene`.
  final AssetRef source;

  /// Whether the instance's content loads eagerly or streams in.
  final LoadPolicy load;

  /// Per-property overrides applied on top of the prefab.
  final List<PropertyOverride> overrides;

  /// Nodes added to this instance that the prefab does not have.
  final List<NodeSpec> addedNodes;

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
  /// Creates a geometry resource from a [payload] chunk or a [procedural]
  /// descriptor.
  GeometryResource(super.id, {this.payload, this.procedural, this.bounds})
    : assert(
        (payload == null) != (procedural == null),
        'A geometry has exactly one source: a payload or a procedural '
        'descriptor',
      );

  /// The binary chunk holding this geometry's vertex/index buffers, or null
  /// when [procedural] is set.
  final LocalId? payload;

  /// The procedural descriptor, or null when [payload] is set.
  final ProceduralGeometry? procedural;

  /// The geometry's local-space bounds, when known.
  final BoundsSpec? bounds;
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
}
