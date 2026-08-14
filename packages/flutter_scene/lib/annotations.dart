/// Component annotations for the `flutter_scene_codegen` extractor.
///
/// Annotate a `Component` subclass with [SceneComponent] and its editable
/// fields with [SceneProperty] (or a typed variant), then run
/// `dart run flutter_scene_codegen:generate` to produce the component's
/// codec, schema manifest, and project registrar.
library;

export 'package:scene/schema.dart'
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
        SceneGizmo,
        SceneProperty,
        StringProperty,
        Vec2Property,
        Vec3Property,
        Vec4Property;
