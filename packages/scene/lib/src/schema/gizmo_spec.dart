/// The declarative gizmo model, pure data describing the editor-only
/// viewport indicators a component type draws (icons, wire shapes, arrows).
///
/// Like the rest of the schema it is closure-free, const-constructible, and
/// JSON-round-trippable, so a gizmo block travels with [ComponentSchema]
/// through manifests, project caches, and MCP, and doubles as the
/// `@SceneGizmo` annotation vocabulary. Scalar and color parameters either
/// carry a literal or bind to a property by (dotted) path, evaluated by the
/// editor against the component's current property values.
library;

/// When a primitive draws relative to the owning node's selection state.
enum GizmoVisibility {
  /// Drawn whenever the gizmo layer shows the component's type.
  always,

  /// Drawn only while the owning node is selected.
  selected,
}

/// A scalar parameter, a literal or a binding to a numeric property.
class GizmoScalar {
  /// A literal scalar.
  const GizmoScalar(double this.value) : bind = null, scale = 1;

  /// Binds to the property at dotted path [bind], multiplied by [scale].
  const GizmoScalar.bind(String this.bind, {this.scale = 1}) : value = null;

  /// The literal value, or null when bound.
  final double? value;

  /// The bound property path, or null for a literal.
  final String? bind;

  /// Multiplier applied to a bound value.
  final double scale;

  Object toJson() => bind == null
      ? (value ?? 0)
      : {'bind': bind, if (scale != 1) 'scale': scale};

  static GizmoScalar? fromJson(Object? json) {
    if (json is num) return GizmoScalar(json.toDouble());
    if (json is Map && json['bind'] is String) {
      return GizmoScalar.bind(
        json['bind'] as String,
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
      );
    }
    return null;
  }
}

/// A color parameter, a literal linear RGBA or a binding to a color/vec3
/// property. A null [GizmoPrimitive.color] means the editor theme's gizmo
/// color (accent when selected).
class GizmoColor {
  /// A literal linear RGBA color.
  const GizmoColor(this.r, this.g, this.b, [this.a = 1]) : bind = null;

  /// Binds to the color or vec3 property at dotted path [bind].
  const GizmoColor.bind(String this.bind) : r = 0, g = 0, b = 0, a = 1;

  final double r, g, b, a;

  /// The bound property path, or null for a literal.
  final String? bind;

  Object toJson() => bind == null ? [r, g, b, a] : {'bind': bind};

  static GizmoColor? fromJson(Object? json) {
    if (json is Map && json['bind'] is String) {
      return GizmoColor.bind(json['bind'] as String);
    }
    if (json is List && json.length >= 3 && json.every((c) => c is num)) {
      double channel(int i) => (json[i] as num).toDouble();
      return GizmoColor(
        channel(0),
        channel(1),
        channel(2),
        json.length > 3 ? channel(3) : 1,
      );
    }
    return null;
  }
}

/// Draws a primitive only when the property at [path] equals [equals], for
/// union-kind properties (a collider's shape variant).
class GizmoCondition {
  const GizmoCondition(this.path, this.equals);

  final String path;
  final String equals;

  Map<String, Object?> toJson() => {'path': path, 'equals': equals};

  static GizmoCondition? fromJson(Object? json) {
    if (json is! Map || json['path'] is! String || json['equals'] is! String) {
      return null;
    }
    return GizmoCondition(json['path'] as String, json['equals'] as String);
  }
}

/// One drawable unit of a gizmo. Subtypes carry their geometry parameters;
/// the shared fields govern visibility, color, and conditional drawing.
sealed class GizmoPrimitive {
  const GizmoPrimitive({
    this.visibility = GizmoVisibility.always,
    this.color,
    this.xray = true,
    this.when,
  });

  final GizmoVisibility visibility;

  /// Overrides the theme gizmo color; null uses the theme (accent when
  /// selected).
  final GizmoColor? color;

  /// Whether the primitive stays visible when occluded, once depth-aware
  /// drawing exists. The v1 painter draws everything on top.
  final bool xray;

  /// Draw only while the condition holds; null always draws.
  final GizmoCondition? when;

  /// The JSON tag for this primitive's kind.
  String get kind;

  /// Subtype-specific JSON fields, merged into the tagged map.
  Map<String, Object?> fieldsToJson();

  Map<String, Object?> toJson() => {
    'kind': kind,
    if (visibility != GizmoVisibility.always) 'visibility': visibility.name,
    if (color != null) 'color': color!.toJson(),
    if (!xray) 'xray': false,
    if (when != null) 'when': when!.toJson(),
    ...fieldsToJson(),
  };

  /// Decodes one tagged primitive, or null for malformed entries and kinds
  /// this build does not know (newer manifests degrade to fewer primitives).
  static GizmoPrimitive? fromJson(Object? json) {
    if (json is! Map) return null;
    final visibility =
        GizmoVisibility.values.asNameMap()[json['visibility']] ??
        GizmoVisibility.always;
    final color = GizmoColor.fromJson(json['color']);
    final xray = json['xray'] != false;
    final when = GizmoCondition.fromJson(json['when']);
    GizmoScalar scalar(String key, double fallback) =>
        GizmoScalar.fromJson(json[key]) ?? GizmoScalar(fallback);
    List<double>? vector(String key) {
      final raw = json[key];
      if (raw is! List || !raw.every((c) => c is num)) return null;
      return [for (final component in raw) (component as num).toDouble()];
    }

    switch (json['kind']) {
      case 'icon':
        return GizmoIcon(
          glyph: json['glyph'] is String ? json['glyph'] as String : null,
          size: (json['size'] as num?)?.toDouble() ?? 28,
          color: color,
          when: when,
        );
      case 'arrow':
        return GizmoArrow(
          axis: vector('axis') ?? const [0, 0, 1],
          axisBind: json['axisBind'] is String
              ? json['axisBind'] as String
              : null,
          length: scalar('length', 1),
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'lines':
        final points = vector('points');
        if (points == null) return null;
        return GizmoLines(
          points,
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'wireSphere':
        return GizmoWireSphere(
          radius: scalar('radius', 1),
          center: vector('center') ?? const [0, 0, 0],
          inflate: scalar('inflate', 0),
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'wireBox':
        return GizmoWireBox(
          halfExtents: vector('halfExtents'),
          halfExtentsBind: json['halfExtentsBind'] is String
              ? json['halfExtentsBind'] as String
              : null,
          center: vector('center') ?? const [0, 0, 0],
          inflate: scalar('inflate', 0),
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'wireRect':
        return GizmoWireRect(
          width: scalar('width', 1),
          height: scalar('height', 1),
          axis: vector('axis') ?? const [0, 0, 1],
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'wireCircle':
        return GizmoWireCircle(
          radius: scalar('radius', 1),
          axis: vector('axis') ?? const [0, 0, 1],
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'wireCone':
        return GizmoWireCone(
          angle: scalar('angle', 0.5),
          range: scalar('range', 1),
          axis: vector('axis') ?? const [0, 0, 1],
          axisBind: json['axisBind'] is String
              ? json['axisBind'] as String
              : null,
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'wireCapsule':
        return GizmoWireCapsule(
          radius: scalar('radius', 0.5),
          halfHeight: scalar('halfHeight', 0.5),
          axis: vector('axis') ?? const [0, 1, 0],
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'wireCylinder':
        return GizmoWireCylinder(
          radius: scalar('radius', 0.5),
          halfHeight: scalar('halfHeight', 0.5),
          axis: vector('axis') ?? const [0, 1, 0],
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
      case 'frustum':
        return GizmoFrustum(
          fovY: scalar('fovY', 0.8),
          near: scalar('near', 0.1),
          far: scalar('far', 1000),
          aspect: GizmoScalar.fromJson(json['aspect']),
          visibility: visibility,
          color: color,
          xray: xray,
          when: when,
        );
    }
    return null;
  }
}

/// An unscaled billboard glyph at the node origin, the component's clickable
/// presence when the node has no mesh.
class GizmoIcon extends GizmoPrimitive {
  const GizmoIcon({this.glyph, this.size = 28, super.color, super.when});

  /// Named glyph from the editor's icon set, or null for the schema's
  /// [ComponentSchema.icon] hint.
  final String? glyph;

  /// Screen size in logical pixels.
  final double size;

  @override
  String get kind => 'icon';

  @override
  Map<String, Object?> fieldsToJson() => {
    if (glyph != null) 'glyph': glyph,
    if (size != 28) 'size': size,
  };
}

/// An arrow from the node origin along a node-local [axis].
class GizmoArrow extends GizmoPrimitive {
  const GizmoArrow({
    this.axis = const [0, 0, 1],
    this.axisBind,
    this.length = const GizmoScalar(1),
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  /// Node-local unit direction.
  final List<double> axis;

  /// A vec3 property path supplying the direction; overrides [axis].
  final String? axisBind;

  final GizmoScalar length;

  @override
  String get kind => 'arrow';

  @override
  Map<String, Object?> fieldsToJson() => {
    'axis': axis,
    if (axisBind != null) 'axisBind': axisBind,
    'length': length.toJson(),
  };
}

/// Literal node-local line segments, consumed as point pairs.
class GizmoLines extends GizmoPrimitive {
  const GizmoLines(
    this.points, {
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  /// Flat x,y,z triples; every two points form one segment.
  final List<double> points;

  @override
  String get kind => 'lines';

  @override
  Map<String, Object?> fieldsToJson() => {'points': points};
}

/// A wireframe sphere (three great circles).
class GizmoWireSphere extends GizmoPrimitive {
  const GizmoWireSphere({
    required this.radius,
    this.center = const [0, 0, 0],
    this.inflate = const GizmoScalar(0),
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  final GizmoScalar radius;
  final List<double> center;

  /// Added to the radius (a blend or falloff shell around the base shape).
  final GizmoScalar inflate;

  @override
  String get kind => 'wireSphere';

  @override
  Map<String, Object?> fieldsToJson() => {
    'radius': radius.toJson(),
    if (center.any((component) => component != 0)) 'center': center,
    if (inflate.bind != null || inflate.value != 0) 'inflate': inflate.toJson(),
  };
}

/// A wireframe box, sized by literal half extents or a bound vec3 property.
class GizmoWireBox extends GizmoPrimitive {
  const GizmoWireBox({
    this.halfExtents,
    this.halfExtentsBind,
    this.center = const [0, 0, 0],
    this.inflate = const GizmoScalar(0),
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  final List<double>? halfExtents;

  /// A vec3 property path supplying the half extents.
  final String? halfExtentsBind;

  final List<double> center;

  /// Added to every half extent (a blend or falloff shell).
  final GizmoScalar inflate;

  @override
  String get kind => 'wireBox';

  @override
  Map<String, Object?> fieldsToJson() => {
    if (halfExtents != null) 'halfExtents': halfExtents,
    if (halfExtentsBind != null) 'halfExtentsBind': halfExtentsBind,
    if (center.any((component) => component != 0)) 'center': center,
    if (inflate.bind != null || inflate.value != 0) 'inflate': inflate.toJson(),
  };
}

/// A wireframe rectangle centered on the node origin, in the plane normal to
/// [axis].
class GizmoWireRect extends GizmoPrimitive {
  const GizmoWireRect({
    required this.width,
    required this.height,
    this.axis = const [0, 0, 1],
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  final GizmoScalar width;
  final GizmoScalar height;

  /// The plane normal.
  final List<double> axis;

  @override
  String get kind => 'wireRect';

  @override
  Map<String, Object?> fieldsToJson() => {
    'width': width.toJson(),
    'height': height.toJson(),
    'axis': axis,
  };
}

/// A wireframe circle centered on the node origin, in the plane normal to
/// [axis].
class GizmoWireCircle extends GizmoPrimitive {
  const GizmoWireCircle({
    required this.radius,
    this.axis = const [0, 0, 1],
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  final GizmoScalar radius;

  /// The plane normal.
  final List<double> axis;

  @override
  String get kind => 'wireCircle';

  @override
  Map<String, Object?> fieldsToJson() => {
    'radius': radius.toJson(),
    'axis': axis,
  };
}

/// A wireframe cone with its apex at the node origin, opening along [axis].
class GizmoWireCone extends GizmoPrimitive {
  const GizmoWireCone({
    required this.angle,
    required this.range,
    this.axis = const [0, 0, 1],
    this.axisBind,
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  /// Half-angle in radians.
  final GizmoScalar angle;

  /// Distance from apex to base along [axis].
  final GizmoScalar range;

  final List<double> axis;

  /// A vec3 property path supplying the axis; overrides [axis].
  final String? axisBind;

  @override
  String get kind => 'wireCone';

  @override
  Map<String, Object?> fieldsToJson() => {
    'angle': angle.toJson(),
    'range': range.toJson(),
    'axis': axis,
    if (axisBind != null) 'axisBind': axisBind,
  };
}

/// A wireframe capsule centered on the node origin, its length along [axis].
class GizmoWireCapsule extends GizmoPrimitive {
  const GizmoWireCapsule({
    required this.radius,
    required this.halfHeight,
    this.axis = const [0, 1, 0],
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  final GizmoScalar radius;

  /// Half length of the cylindrical section, excluding the caps.
  final GizmoScalar halfHeight;

  final List<double> axis;

  @override
  String get kind => 'wireCapsule';

  @override
  Map<String, Object?> fieldsToJson() => {
    'radius': radius.toJson(),
    'halfHeight': halfHeight.toJson(),
    'axis': axis,
  };
}

/// A wireframe cylinder centered on the node origin, its length along
/// [axis].
class GizmoWireCylinder extends GizmoPrimitive {
  const GizmoWireCylinder({
    required this.radius,
    required this.halfHeight,
    this.axis = const [0, 1, 0],
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  final GizmoScalar radius;

  /// Half length along [axis].
  final GizmoScalar halfHeight;

  final List<double> axis;

  @override
  String get kind => 'wireCylinder';

  @override
  Map<String, Object?> fieldsToJson() => {
    'radius': radius.toJson(),
    'halfHeight': halfHeight.toJson(),
    'axis': axis,
  };
}

/// A perspective view frustum opening along node-local +Z (the engine camera
/// looks along its node's local +Z).
class GizmoFrustum extends GizmoPrimitive {
  const GizmoFrustum({
    required this.fovY,
    required this.near,
    required this.far,
    this.aspect,
    super.visibility,
    super.color,
    super.xray,
    super.when,
  });

  /// Vertical field of view in radians.
  final GizmoScalar fovY;

  final GizmoScalar near;
  final GizmoScalar far;

  /// Width over height; null uses the viewport's current aspect.
  final GizmoScalar? aspect;

  @override
  String get kind => 'frustum';

  @override
  Map<String, Object?> fieldsToJson() => {
    'fovY': fovY.toJson(),
    'near': near.toJson(),
    'far': far.toJson(),
    if (aspect != null) 'aspect': aspect!.toJson(),
  };
}

/// The declarative gizmo block a component schema carries, an ordered list
/// of primitives the editor draws for components of that type.
class GizmoSpec {
  const GizmoSpec(this.primitives);

  final List<GizmoPrimitive> primitives;

  Map<String, Object?> toJson() => {
    'primitives': [for (final primitive in primitives) primitive.toJson()],
  };

  /// Decodes a gizmo block, skipping malformed or unknown primitives; null
  /// when [json] is not a gizmo block at all.
  static GizmoSpec? fromJson(Object? json) {
    if (json is! Map) return null;
    final primitives = json['primitives'];
    if (primitives is! List) return null;
    return GizmoSpec([
      for (final entry in primitives)
        if (GizmoPrimitive.fromJson(entry) case final primitive?) primitive,
    ]);
  }
}
