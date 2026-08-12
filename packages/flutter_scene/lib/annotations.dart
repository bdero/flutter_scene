/// Component annotations for the `flutter_scene_codegen` extractor.
///
/// Annotate a `Component` subclass with [SceneComponent] and its editable
/// fields with [SceneProperty] (or a typed variant), then run
/// `dart run flutter_scene_codegen:generate` to produce the component's
/// codec, schema manifest, and project registrar.
library;

export 'src/fscene/annotations.dart'
    show
        AngleProperty,
        AssetProperty,
        BoolProperty,
        ColorProperty,
        EnumProperty,
        IntProperty,
        NodeProperty,
        NumberProperty,
        QuaternionProperty,
        ResourceProperty,
        SceneComponent,
        SceneProperty,
        StringProperty,
        Vec2Property,
        Vec3Property,
        Vec4Property;
