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
        RgbColor,
        SoftRange,
        SortedDescending,
        Step,
        UnknownConstraint;
