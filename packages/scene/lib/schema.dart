/// The component schema descriptor model, pure-data descriptions of
/// component types (properties, kinds, defaults, constraints) that travel
/// across process boundaries. See `component_schema.dart` for the model and
/// `property_constraints.dart` for the constraint taxonomy.
library;

export 'src/schema/component_schema.dart'
    show
        ComponentPropertyDef,
        ComponentPropertyKind,
        ComponentSchema,
        decodeComponentSchemas,
        encodeComponentSchemas;
export 'src/schema/gizmo_spec.dart'
    show
        GizmoArrow,
        GizmoColor,
        GizmoCondition,
        GizmoFrustum,
        GizmoIcon,
        GizmoLines,
        GizmoPrimitive,
        GizmoScalar,
        GizmoSpec,
        GizmoVisibility,
        GizmoWireBox,
        GizmoWireCapsule,
        GizmoWireCircle,
        GizmoWireCone,
        GizmoWireCylinder,
        GizmoWireRect,
        GizmoWireSphere;
export 'src/schema/property_value_equality.dart' show propertyValuesEqual;
export 'src/schema/property_constraints.dart'
    show
        AngleRadians,
        AssetExtensions,
        IntRange,
        LayerMask32,
        MinCount,
        Multiline,
        Normalized,
        TextPattern,
        PowerOfTwo,
        PropertyConstraint,
        Range,
        ReadOnly,
        RgbColor,
        SoftRange,
        SortedDescending,
        Step,
        UnknownConstraint;
