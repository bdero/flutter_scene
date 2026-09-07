/// Codecs for the mesh-derived rendering extras: trails, level-of-detail
/// meshes, and Gaussian splat sets. All three components subclass the mesh
/// component, so their codecs register before the mesh codec and never emit
/// geometry/material references of their own.
library;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/lod_component.dart';
import 'package:flutter_scene/src/components/splat_component.dart';
import 'package:flutter_scene/src/components/trail_component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/component_schema.dart';
import 'package:flutter_scene/src/fscene/realize/declarative_codec.dart';
import 'package:flutter_scene/src/fscene/realize/particle_property_values.dart';
import 'package:flutter_scene/src/fscene/realize/property_read.dart';
import 'package:flutter_scene/src/fscene/realize/resource_copy.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/geometry/splat_geometry.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/splats/gaussian_splats.dart';
import 'package:scene/scene.dart';

// --- Trail ---

/// Codec for [TrailComponent]. The accumulated path and its ages are live
/// runtime state and never persist; the default trail material is owned by
/// the component, so no geometry/material references are emitted.
// TODO(trail-material): a custom trail material does not serialize; the
// component reloads with its default translucent unlit material.
class TrailCodec extends DeclarativeComponentCodec<TrailComponent> {
  @override
  String get type => 'trail';

  @override
  String? get category => 'Effects';

  @override
  List<ComponentField<TrailComponent>> get fields => [
    ComponentField.number(
      'width',
      defaultValue: 0.25,
      doc: 'Ribbon width in world units at curve value 1.',
      constraints: const [Range.nonNegative(), SoftRange(0.01, 2)],
      get: (c) => c.width,
      set: (c, v) => c.width = v,
    ),
    ComponentField.number(
      'lifetime',
      defaultValue: 0.6,
      doc: 'Seconds a recorded point lives before the tail consumes it.',
      constraints: const [Range.nonNegative(), SoftRange(0.1, 5)],
      get: (c) => c.lifetime,
      set: (c, v) => c.lifetime = v,
    ),
    ComponentField.number(
      'minVertexDistance',
      defaultValue: 0.05,
      doc: 'World distance the node must move before a new point anchors.',
      constraints: const [Range.nonNegative(), SoftRange(0.01, 1)],
      get: (c) => c.minVertexDistance,
      set: (c, v) => c.minVertexDistance = v,
    ),
    // Constructor-only; the geometry's capacity is fixed at construction.
    ComponentField.integer(
      'maxPoints',
      defaultValue: 48,
      doc: 'Recorded path capacity (oldest points expire first).',
      constraints: const [IntRange(2, null)],
      get: (c) => c.maxPoints,
    ),
    // No default; absent means the built-in taper from 1 at the head to 0
    // at the tail.
    ComponentField(
      const ComponentPropertyDef(
        'widthOverTrail',
        ComponentPropertyKind.curve,
        doc:
            'Width multiplier from head (0) to tail (1); absent tapers 1 '
            'to 0.',
      ),
      read: (c, _) {
        final curve = c.widthOverTrail;
        return curve == null ? null : encodeParticleCurve(curve);
      },
      write: (c, v, _) {
        if (v is MapValue) c.widthOverTrail = decodeParticleCurve(v);
      },
    ),
    // No default; absent means the built-in white fading out at the tail.
    ComponentField(
      const ComponentPropertyDef(
        'colorOverTrail',
        ComponentPropertyKind.gradient,
        doc:
            'Color from head (0) to tail (1); absent fades white to '
            'transparent.',
      ),
      read: (c, _) {
        final gradient = c.colorOverTrail;
        return gradient == null ? null : encodeColorGradient(gradient);
      },
      write: (c, v, _) {
        if (v is MapValue) c.colorOverTrail = decodeColorGradient(v);
      },
    ),
    ComponentField.boolean(
      'emitting',
      defaultValue: true,
      doc: 'Whether new points are recorded.',
      get: (c) => c.emitting,
      set: (c, v) => c.emitting = v,
    ),
  ];

  @override
  TrailComponent create(PropertyReader props) {
    final maxPoints = props.integer('maxPoints');
    return TrailComponent(maxPoints: maxPoints < 2 ? 2 : maxPoints);
  }
}

// --- Level of detail ---

/// Codec for [LodComponent]. The level list is constructor-only; each entry
/// references a document geometry and material resource, recovered at
/// serialize time from the origin tags the realizer stamped on them.
// TODO(lod-hand-built): levels built from hand-made geometry/materials carry
// no origin tag, so the component does not serialize; route them through the
// mesh codec's re-packing path to lift that.
class LodCodec extends DeclarativeComponentCodec<LodComponent> {
  @override
  String get type => 'lod';

  @override
  String? get category => 'Mesh';

  static const ComponentPropertyDef _levelsDef = ComponentPropertyDef(
    'levels',
    ComponentPropertyKind.list,
    doc: 'Drawable variants, highest detail first.',
    constraints: [MinCount(1), SortedDescending('screenSize')],
    itemDef: ComponentPropertyDef(
      'level',
      ComponentPropertyKind.object,
      objectFields: [
        ComponentPropertyDef(
          'geometry',
          ComponentPropertyKind.resourceRef,
          resourceKind: 'geometry',
        ),
        ComponentPropertyDef(
          'material',
          ComponentPropertyKind.resourceRef,
          resourceKind: 'material',
        ),
        ComponentPropertyDef(
          'screenSize',
          ComponentPropertyKind.number,
          defaultValue: DoubleValue(0.0),
          doc:
              'Smallest projected size (fraction of viewport height) at '
              'which this level draws.',
          constraints: [Range(0, 1)],
        ),
      ],
    ),
  );

  @override
  List<ComponentField<LodComponent>> get fields => [
    ComponentField(
      _levelsDef,
      read: (c, context) {
        final entries = <PropertyValue>[];
        for (final level in c.levels) {
          final geometry = resourceOrigin(level.geometry);
          final material = resourceOrigin(level.material);
          if (geometry == null || material == null) return null;
          entries.add(
            MapValue({
              'geometry': ResourceRefValue(
                copyResourceInto(
                  context.document,
                  geometry.document,
                  geometry.resourceId,
                ),
              ),
              'material': ResourceRefValue(
                copyResourceInto(
                  context.document,
                  material.document,
                  material.resourceId,
                ),
              ),
              'screenSize': DoubleValue(level.screenSize),
            }),
          );
        }
        return entries.isEmpty ? null : ListValue(entries);
      },
    ),
    ComponentField.number(
      'lodBias',
      defaultValue: 1.0,
      doc: 'Projected-size multiplier; above 1 keeps detail farther away.',
      constraints: const [Range.nonNegative(), SoftRange(0.5, 2)],
      get: (c) => c.lodBias,
      set: (c, v) => c.lodBias = v,
    ),
    // Constructor-only; the selection's dead-band is fixed at construction.
    ComponentField.number(
      'hysteresis',
      defaultValue: 0.1,
      doc: 'Fractional dead-band around each threshold.',
      constraints: const [Range(0, 1)],
      get: (c) => c.hysteresis,
    ),
    ComponentField.number(
      'blendRange',
      defaultValue: 0.0,
      doc: 'Cross-fade band half-width; 0 hard-switches between levels.',
      constraints: const [Range(0, 1)],
      get: (c) => c.blendRange,
      set: (c, v) => c.blendRange = v,
    ),
  ];

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    if (context.resources == null) {
      debugPrint('fscene: lod component skipped (no resource realizer)');
      return null;
    }
    final entries = _levelEntries(spec.properties);
    if (entries.isEmpty) {
      debugPrint('fscene: lod component has no well-formed levels; skipped');
      return null;
    }
    for (var i = 1; i < entries.length; i++) {
      if (entries[i].screenSize >= entries[i - 1].screenSize) {
        debugPrint(
          'fscene: lod component skipped (screenSize thresholds must '
          'strictly descend)',
        );
        return null;
      }
    }
    return super.realize(spec, context);
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    if (component is! LodComponent) return null;
    for (final level in component.levels) {
      if (resourceOrigin(level.geometry) == null ||
          resourceOrigin(level.material) == null) {
        debugPrint(
          'fscene: lod component not serialized; a level\'s geometry or '
          'material was not realized from a document',
        );
        return null;
      }
    }
    return super.serialize(component, context);
  }

  @override
  LodComponent create(PropertyReader props) {
    // realize() guarded these.
    final resources = props.context.resources!;
    final levels = [
      for (final entry in _levelEntries(props.properties))
        LodLevel(
          geometry: resources.geometry(entry.geometry),
          material: resources.material(entry.material),
          screenSize: entry.screenSize,
        ),
    ];
    return LodComponent(
      levels,
      lodBias: props.number('lodBias'),
      hysteresis: props.number('hysteresis'),
      blendRange: props.number('blendRange'),
    );
  }

  static List<({LocalId geometry, LocalId material, double screenSize})>
  _levelEntries(Map<String, PropertyValue> properties) {
    final levels = properties['levels'];
    if (levels is! ListValue) return const [];
    final out = <({LocalId geometry, LocalId material, double screenSize})>[];
    for (final entry in levels.values) {
      if (entry is! MapValue) continue;
      final geometry = entry.values['geometry'];
      final material = entry.values['material'];
      if (geometry is! ResourceRefValue || material is! ResourceRefValue) {
        continue;
      }
      out.add((
        geometry: geometry.id,
        material: material.id,
        screenSize: switch (entry.values['screenSize']) {
          DoubleValue(:final value) => value,
          IntValue(:final value) => value.toDouble(),
          _ => 0.0,
        },
      ));
    }
    return out;
  }
}

// --- Gaussian splats ---

// The asset key the component's splat set was loaded from, stamped at
// realize so serialize can recover it (GaussianSplats does not retain it).
// TODO(splat-hand-built): hand-built splat components carry no stamp, so
// they do not serialize; retain the source key on GaussianSplats.fromAsset
// to lift that.
final Expando<String> _splatAsset = Expando('splat component asset');

/// Stands in for a [SplatComponent] while its splat asset decodes (decoding
/// is asynchronous, realization is not). [onLoad] loads the set, mounts the
/// real component in its place, and removes itself; until then it serializes
/// back as its retained spec, losslessly.
class _DeferredSplatComponent extends Component {
  _DeferredSplatComponent(this.spec);

  /// The splat component spec, retained verbatim.
  final ComponentSpec spec;

  @override
  Future<void> onLoad() async {
    final asset = spec.properties['splats'];
    if (asset is! StringValue) return;
    final GaussianSplats splats;
    try {
      splats = await GaussianSplats.fromAsset(asset.value);
    } catch (error) {
      debugPrint('fscene: splat asset "${asset.value}" failed to load: $error');
      return;
    }
    if (!isAttached) return;
    final component = SplatCodec.buildSplatComponent(splats, spec.properties)
      ..enabled = enabled;
    final owner = node;
    owner.addComponent(component);
    owner.removeComponent(this);
  }
}

/// Codec for [SplatComponent]. The splat set is carried as an asset key and
/// decoded asynchronously, so realize returns a deferred stand-in that swaps
/// in the real component once the asset finishes loading (on mount).
class SplatCodec extends ComponentCodec {
  @override
  String get type => 'splat';

  @override
  String? get category => 'Mesh';

  @override
  Type get componentType => SplatComponent;

  @override
  bool claims(Component component) =>
      component is SplatComponent || component is _DeferredSplatComponent;

  @override
  List<ComponentPropertyDef> get propertySchema => [
    const ComponentPropertyDef(
      'splats',
      ComponentPropertyKind.assetRef,
      doc: 'Asset key of the splat file this component draws.',
      constraints: [
        AssetExtensions(['.ply', '.splat']),
      ],
    ),
    const ComponentPropertyDef(
      'opacity',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(1.0),
      doc: 'Global opacity multiplier.',
      constraints: [Range(0, 1), SoftRange(0, 1)],
    ),
    const ComponentPropertyDef(
      'splatScale',
      ComponentPropertyKind.number,
      defaultValue: DoubleValue(1.0),
      doc: 'Multiplier on every splat\'s footprint; 1 is the captured size.',
      constraints: [Range.nonNegative(), SoftRange(0.1, 4)],
    ),
    ComponentPropertyDef(
      'tint',
      ComponentPropertyKind.vec4,
      defaultValue: Vec4Value(Vector4(1, 1, 1, 1)),
      doc: 'Linear RGBA tint multiplied into every splat.',
    ),
    const ComponentPropertyDef(
      'shDegree',
      ComponentPropertyKind.integer,
      defaultValue: IntValue(2),
      doc: 'Spherical-harmonic degree evaluated per splat.',
      constraints: [IntRange(0, 2)],
    ),
    const ComponentPropertyDef(
      'antialiased',
      ComponentPropertyKind.boolean,
      defaultValue: BoolValue(true),
      doc: 'Compensate small-footprint opacity (anti-aliased rasterization).',
    ),
    // No default; absent means no crop.
    ComponentPropertyDef(
      'crop',
      ComponentPropertyKind.object,
      doc: 'Crop box (a placed unit cube) filtering the splats.',
      objectFields: [
        ComponentPropertyDef(
          'mode',
          ComponentPropertyKind.string,
          defaultValue: const StringValue('none'),
          doc: 'How the box filters splats.',
          options: [for (final mode in SplatCropMode.values) mode.name],
        ),
        ComponentPropertyDef(
          'box',
          ComponentPropertyKind.matrix4,
          defaultValue: Matrix4Value(Matrix4.identity()),
          doc: 'Placement of the unit cube in the set\'s local space.',
        ),
      ],
    ),
  ];

  @override
  Component? realize(ComponentSpec spec, RealizeContext context) {
    final asset = spec.properties['splats'];
    if (asset is! StringValue || asset.value.isEmpty) {
      debugPrint('fscene: splat component has no splats asset; skipped');
      return null;
    }
    return _DeferredSplatComponent(
      ComponentSpec(spec.type, properties: {...spec.properties}),
    );
  }

  /// Builds the live component from a loaded [splats] set plus its spec
  /// [properties], stamping the asset key so it serializes back. Called by
  /// the deferred stand-in once the asset decodes.
  static SplatComponent buildSplatComponent(
    GaussianSplats splats,
    Map<String, PropertyValue> properties,
  ) {
    final component = SplatComponent(splats);
    final asset = properties['splats'];
    if (asset is StringValue && asset.value.isNotEmpty) {
      _splatAsset[component] = asset.value;
    }
    component.opacity = readDouble(properties, 'opacity', component.opacity);
    component.splatScale = readDouble(
      properties,
      'splatScale',
      component.splatScale,
    );
    final tint = properties['tint'];
    if (tint is Vec4Value) component.tint = tint.value.clone();
    component.shDegree = readInt(properties, 'shDegree', component.shDegree);
    final antialiased = properties['antialiased'];
    if (antialiased is BoolValue) component.antialiased = antialiased.value;
    final crop = properties['crop'];
    if (crop is MapValue) {
      final mode = crop.values['mode'];
      final box = crop.values['box'];
      component.setCropBox(
        box is Matrix4Value ? box.value.clone() : null,
        mode: mode is StringValue
            ? SplatCropMode.values.asNameMap()[mode.value] ?? SplatCropMode.none
            : SplatCropMode.none,
      );
    }
    return component;
  }

  @override
  ComponentSpec? serialize(Component component, SerializeContext context) {
    // Still loading; the retained spec is the lossless serialization.
    if (component is _DeferredSplatComponent) {
      return ComponentSpec(
        component.spec.type,
        properties: {...component.spec.properties},
      );
    }
    if (component is! SplatComponent) return null;
    final asset = _splatAsset[component];
    if (asset == null) {
      debugPrint(
        'fscene: splat component not serialized; its splat set was not '
        'loaded from a known asset',
      );
      return null;
    }
    final properties = <String, PropertyValue>{'splats': StringValue(asset)};
    if (component.opacity != 1.0) {
      properties['opacity'] = DoubleValue(component.opacity);
    }
    if (component.splatScale != 1.0) {
      properties['splatScale'] = DoubleValue(component.splatScale);
    }
    final tint = component.tint;
    if (tint.x != 1 || tint.y != 1 || tint.z != 1 || tint.w != 1) {
      properties['tint'] = Vec4Value(tint.clone());
    }
    if (component.shDegree != 2) {
      properties['shDegree'] = IntValue(component.shDegree);
    }
    if (!component.antialiased) {
      properties['antialiased'] = const BoolValue(false);
    }
    final box = component.cropBox;
    if (box != null && component.cropMode != SplatCropMode.none) {
      properties['crop'] = MapValue({
        'mode': StringValue(component.cropMode.name),
        'box': Matrix4Value(box.clone()),
      });
    }
    return ComponentSpec(type, properties: properties);
  }
}
