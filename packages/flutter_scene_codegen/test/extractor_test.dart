import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:test/test.dart';

import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';

ExtractedComponent _single(String source) {
  final result = extractComponents(source);
  expect(result.components, hasLength(1));
  return result.components.single;
}

ComponentPropertyDef _prop(ExtractedComponent component, String name) {
  final def = component.schema.property(name);
  expect(def, isNotNull, reason: 'missing property $name');
  return def!;
}

void main() {
  group('component extraction', () {
    test('reads the type tag, class doc comment, icon, and formerTypes', () {
      final component = _single('''
/// Spins the node around an axis.
@SceneComponent('spinner', icon: 'S', formerTypes: ['rotator'])
class Spinner extends Component {
  @SceneProperty()
  double speed = 1.0;
}
''');
      expect(component.className, 'Spinner');
      expect(component.schema.type, 'spinner');
      expect(component.schema.doc, 'Spins the node around an axis.');
      expect(component.schema.icon, 'S');
      expect(component.schema.formerTypes, ['rotator']);
    });

    test('annotation doc wins over the class doc comment', () {
      final component = _single('''
/// Class comment.
@SceneComponent('spinner', doc: 'Annotation doc.')
class Spinner extends Component {}
''');
      expect(component.schema.doc, 'Annotation doc.');
    });

    test('ignores unannotated classes', () {
      final result = extractComponents('''
class NotAComponent {
  double speed = 1.0;
}
''');
      expect(result.components, isEmpty);
      expect(result.diagnostics, isEmpty);
    });

    test('a class without a zero-arg constructor is skipped with an error', () {
      final result = extractComponents('''
@SceneComponent('spinner')
class Spinner extends Component {
  Spinner(this.speed);
  @SceneProperty()
  double speed;
}
''');
      expect(result.components, isEmpty);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.severity, ExtractionSeverity.error);
      expect(
        result.diagnostics.single.message,
        contains('zero-argument constructor'),
      );
    });

    test('a class with only optional constructor parameters is accepted', () {
      final result = extractComponents('''
@SceneComponent('spinner')
class Spinner extends Component {
  Spinner({double speed = 1.0}) : speed = speed;
  @SceneProperty()
  double speed;
}
''');
      expect(result.components, hasLength(1));
    });
  });

  group('kind from declared type (bare @SceneProperty)', () {
    test('scalar and vector types', () {
      final component = _single('''
@SceneComponent('kinds')
class Kinds extends Component {
  @SceneProperty()
  bool flag = true;
  @SceneProperty()
  int count = 3;
  @SceneProperty()
  double speed = 1.5;
  @SceneProperty()
  String label = 'hi';
  @SceneProperty()
  Vector2 uv = Vector2(0.5, 0.5);
  @SceneProperty()
  Vector3 axis = Vector3(0.0, 1.0, 0.0);
  @SceneProperty()
  Vector4 weights = Vector4(1.0, 0.0, 0.0, 0.0);
  @SceneProperty()
  Quaternion rotation = Quaternion(0.0, 0.0, 0.0, 1.0);
  @SceneProperty()
  Color tint = Color(0xff336699);
  @SceneProperty()
  Matrix4 offset = Matrix4.identity();
}
''');
      expect(_prop(component, 'flag').kind, ComponentPropertyKind.boolean);
      expect(_prop(component, 'count').kind, ComponentPropertyKind.integer);
      expect(_prop(component, 'speed').kind, ComponentPropertyKind.number);
      expect(_prop(component, 'label').kind, ComponentPropertyKind.string);
      expect(_prop(component, 'uv').kind, ComponentPropertyKind.vec2);
      expect(_prop(component, 'axis').kind, ComponentPropertyKind.vec3);
      expect(_prop(component, 'weights').kind, ComponentPropertyKind.vec4);
      expect(
        _prop(component, 'rotation').kind,
        ComponentPropertyKind.quaternion,
      );
      expect(_prop(component, 'tint').kind, ComponentPropertyKind.color);
      expect(_prop(component, 'offset').kind, ComponentPropertyKind.matrix4);
    });

    test('reference types', () {
      final component = _single('''
@SceneComponent('refs')
class Refs extends Component {
  @SceneProperty()
  Node? target;
  @SceneProperty()
  Geometry? shape;
  @SceneProperty()
  Material? surface;
  @SceneProperty()
  Texture? image;
}
''');
      expect(_prop(component, 'target').kind, ComponentPropertyKind.nodeRef);
      final shape = _prop(component, 'shape');
      expect(shape.kind, ComponentPropertyKind.resourceRef);
      expect(shape.resourceKind, 'geometry');
      expect(_prop(component, 'surface').resourceKind, 'material');
      expect(_prop(component, 'image').resourceKind, 'texture');
    });

    test('a same-file enum type becomes a string with options', () {
      final component = _single('''
enum SpinMode { slow, fast }

@SceneComponent('spinner')
class Spinner extends Component {
  @SceneProperty()
  SpinMode mode = SpinMode.slow;
}
''');
      final mode = _prop(component, 'mode');
      expect(mode.kind, ComponentPropertyKind.string);
      expect(mode.options, ['slow', 'fast']);
      expect((mode.defaultValue! as StringValue).value, 'slow');
      expect(component.properties.single.enumResolved, isTrue);
    });

    test('an unknown type is skipped with a diagnostic', () {
      final result = extractComponents('''
@SceneComponent('bad')
class Bad extends Component {
  @SceneProperty()
  Widget child;
}
''');
      expect(result.components.single.schema.properties, isEmpty);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.severity, ExtractionSeverity.error);
      expect(result.diagnostics.single.message, contains('Widget'));
    });
  });

  group('typed annotation variants', () {
    test('pin the kind regardless of literal-friendly types', () {
      final component = _single('''
@SceneComponent('typed')
class Typed extends Component {
  @NumberProperty()
  double speed = 1.0;
  @IntProperty()
  int count = 1;
  @BoolProperty()
  bool flag = false;
  @StringProperty()
  String label = '';
  @Vec2Property()
  Vector2 uv = Vector2.zero();
  @Vec3Property()
  Vector3 axis = Vector3.zero();
  @Vec4Property()
  Vector4 weights = Vector4.zero();
  @QuaternionProperty()
  Quaternion rotation = Quaternion(0.0, 0.0, 0.0, 1.0);
  @ColorProperty()
  Color tint = Color(0xffffffff);
}
''');
      expect(_prop(component, 'speed').kind, ComponentPropertyKind.number);
      expect(_prop(component, 'count').kind, ComponentPropertyKind.integer);
      expect(_prop(component, 'flag').kind, ComponentPropertyKind.boolean);
      expect(_prop(component, 'label').kind, ComponentPropertyKind.string);
      expect(_prop(component, 'uv').kind, ComponentPropertyKind.vec2);
      expect(_prop(component, 'axis').kind, ComponentPropertyKind.vec3);
      expect(_prop(component, 'weights').kind, ComponentPropertyKind.vec4);
      expect(
        _prop(component, 'rotation').kind,
        ComponentPropertyKind.quaternion,
      );
      expect(_prop(component, 'tint').kind, ComponentPropertyKind.color);
    });

    test('IntProperty min/max lowers to IntRange', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @IntProperty(min: 1, max: 8)
  int count = 4;
}
''');
      final range = _prop(component, 'count').constraint<IntRange>();
      expect(range, isNotNull);
      expect(range!.min, 1);
      expect(range.max, 8);
    });

    test('NumberProperty lowers Range, SoftRange, and Step', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @NumberProperty(min: 0, max: 10, softMin: 0, softMax: 1, step: 0.5)
  double gain = 1.0;
}
''');
      final def = _prop(component, 'gain');
      expect(def.constraint<Range>()!.min, 0);
      expect(def.constraint<Range>()!.max, 10);
      expect(def.constraint<SoftRange>()!.min, 0);
      expect(def.constraint<SoftRange>()!.max, 1);
      expect(def.constraint<Step>()!.step, 0.5);
    });

    test('softMax alone lowers a SoftRange floored at min, then zero', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @NumberProperty(min: 2, softMax: 10)
  double speed = 3.0;

  @NumberProperty(softMax: 5)
  double drift = 0.0;
}
''');
      final speed = _prop(component, 'speed');
      expect(speed.constraint<SoftRange>()!.min, 2);
      expect(speed.constraint<SoftRange>()!.max, 10);
      final drift = _prop(component, 'drift');
      expect(drift.constraint<SoftRange>()!.min, 0);
      expect(drift.constraint<SoftRange>()!.max, 5);
    });

    test('StringProperty lowers Multiline and TextPattern', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @StringProperty(multiline: true, pattern: '^[a-z]+')
  String name = '';
}
''');
      final def = _prop(component, 'name');
      expect(def.constraint<Multiline>(), isNotNull);
      expect(def.constraint<TextPattern>()!.pattern, '^[a-z]+');
    });

    test('Vec3Property lowers RgbColor and Normalized', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @Vec3Property(rgbColor: true)
  Vector3 lightColor = Vector3.all(1.0);
  @Vec3Property(normalized: true)
  Vector3 axis = Vector3(0.0, 1.0, 0.0);
}
''');
      expect(_prop(component, 'lightColor').constraint<RgbColor>(), isNotNull);
      expect(_prop(component, 'axis').constraint<Normalized>(), isNotNull);
      expect(
        component.properties.firstWhere((p) => p.def.name == 'axis').normalized,
        isTrue,
      );
    });

    test('AssetProperty is an assetRef with AssetExtensions', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @AssetProperty(extensions: ['.wav', '.ogg'])
  String? clip;
}
''');
      final def = _prop(component, 'clip');
      expect(def.kind, ComponentPropertyKind.assetRef);
      expect(def.constraint<AssetExtensions>()!.extensions, ['.wav', '.ogg']);
    });

    test('ResourceProperty carries its resourceKind', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @ResourceProperty(resourceKind: 'environment')
  Object? environment;
}
''');
      final def = _prop(component, 'environment');
      expect(def.kind, ComponentPropertyKind.resourceRef);
      expect(def.resourceKind, 'environment');
    });

    test('NodeProperty is a nodeRef', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @NodeProperty()
  Node? target;
}
''');
      expect(_prop(component, 'target').kind, ComponentPropertyKind.nodeRef);
    });

    test('AngleProperty is a number with AngleRadians plus Range', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @AngleProperty(min: 0, max: 3.14159)
  double cone = 0.5;
}
''');
      final def = _prop(component, 'cone');
      expect(def.kind, ComponentPropertyKind.number);
      expect(def.constraint<AngleRadians>(), isNotNull);
      expect(def.constraint<Range>()!.max, closeTo(3.14159, 1e-9));
    });

    test('EnumProperty resolves same-file options and warns otherwise', () {
      final resolved = _single('''
enum Mode { a, b }

@SceneComponent('c')
class C extends Component {
  @EnumProperty()
  Mode mode = Mode.b;
}
''');
      expect(_prop(resolved, 'mode').options, ['a', 'b']);

      final unresolved = extractComponents('''
@SceneComponent('c')
class C extends Component {
  @EnumProperty()
  ExternalMode mode = ExternalMode.a;
}
''');
      final def = unresolved.components.single.schema.property('mode')!;
      expect(def.kind, ComponentPropertyKind.string);
      expect(def.options, isNull);
      expect(
        unresolved.diagnostics.single.message,
        contains('enum options unresolved'),
      );
      expect(
        unresolved.diagnostics.single.severity,
        ExtractionSeverity.warning,
      );
    });

    test('extra constraints are parsed from const constructor forms', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @NumberProperty(extra: [SoftRange(0, 2), Range.nonNegative()])
  double pitch = 1.0;
  @IntProperty(extra: [PowerOfTwo(min: 64, max: 4096)])
  int resolution = 1024;
  @IntProperty(extra: [LayerMask32()])
  int layers = 1;
}
''');
      final pitch = _prop(component, 'pitch');
      expect(pitch.constraint<SoftRange>()!.max, 2);
      expect(pitch.constraint<Range>()!.min, 0);
      final resolution = _prop(component, 'resolution');
      expect(resolution.constraint<PowerOfTwo>()!.min, 64);
      expect(resolution.constraint<PowerOfTwo>()!.max, 4096);
      expect(_prop(component, 'layers').constraint<LayerMask32>(), isNotNull);
    });

    test('an unrecognized extra constraint expression warns', () {
      final result = extractComponents('''
@SceneComponent('c')
class C extends Component {
  @NumberProperty(extra: [SoftRange(min, max)])
  double pitch = 1.0;
}
''');
      expect(
        result.diagnostics.single.message,
        contains('unrecognized constraint expression'),
      );
    });
  });

  group('defaults', () {
    test('recognized literal forms', () {
      final component = _single('''
enum Mode { a, b }

@SceneComponent('defaults')
class Defaults extends Component {
  @SceneProperty()
  double negative = -2.5;
  @SceneProperty()
  int negativeInt = -3;
  @SceneProperty()
  bool flag = true;
  @SceneProperty()
  String label = 'hello';
  @SceneProperty()
  Mode mode = Mode.b;
  @SceneProperty()
  Vector2 uv = Vector2(0.25, 0.75);
  @SceneProperty()
  Vector3 zero = Vector3.zero();
  @SceneProperty()
  Vector3 ones = Vector3.all(1.0);
  @SceneProperty()
  Vector4 weights = Vector4(1.0, 2.0, 3.0, 4.0);
  @SceneProperty()
  Quaternion rotation = Quaternion(0.0, 0.0, 0.0, 1.0);
  @SceneProperty()
  Color tint = Color(0x80336699);
}
''');
      expect(
        (_prop(component, 'negative').defaultValue! as DoubleValue).value,
        -2.5,
      );
      expect(
        (_prop(component, 'negativeInt').defaultValue! as IntValue).value,
        -3,
      );
      expect(
        (_prop(component, 'flag').defaultValue! as BoolValue).value,
        isTrue,
      );
      expect(
        (_prop(component, 'label').defaultValue! as StringValue).value,
        'hello',
      );
      expect(
        (_prop(component, 'mode').defaultValue! as StringValue).value,
        'b',
      );
      final uv = (_prop(component, 'uv').defaultValue! as Vec2Value).value;
      expect(uv.x, 0.25);
      expect(uv.y, 0.75);
      final zero = (_prop(component, 'zero').defaultValue! as Vec3Value).value;
      expect(zero.length2, 0);
      final ones = (_prop(component, 'ones').defaultValue! as Vec3Value).value;
      expect(ones.x, 1.0);
      expect(ones.z, 1.0);
      final weights =
          (_prop(component, 'weights').defaultValue! as Vec4Value).value;
      expect(weights.w, 4.0);
      final rotation =
          (_prop(component, 'rotation').defaultValue! as QuaternionValue).value;
      expect(rotation.w, 1.0);
      final tint = _prop(component, 'tint').defaultValue! as ColorValue;
      expect(tint.a, closeTo(0x80 / 255, 1e-9));
      expect(tint.r, closeTo(0x33 / 255, 1e-9));
      expect(tint.g, closeTo(0x66 / 255, 1e-9));
      expect(tint.b, closeTo(0x99 / 255, 1e-9));
    });

    test('an unrecognized initializer records no default and warns', () {
      final result = extractComponents('''
@SceneComponent('c')
class C extends Component {
  @SceneProperty()
  double speed = computeSpeed();
}
''');
      final def = result.components.single.schema.property('speed')!;
      expect(def.defaultValue, isNull);
      expect(result.diagnostics.single.message, contains('dynamic default'));
      expect(result.diagnostics.single.severity, ExtractionSeverity.warning);
    });

    test('a field without an initializer records no default silently', () {
      final result = extractComponents('''
@SceneComponent('c')
class C extends Component {
  @SceneProperty()
  double? speed;
}
''');
      expect(
        result.components.single.schema.property('speed')!.defaultValue,
        isNull,
      );
      expect(result.diagnostics, isEmpty);
    });
  });

  group('common property arguments', () {
    test('group, formerNames, transient, and field doc comments', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  /// Angular velocity in radians per second.
  @NumberProperty(group: 'Motion', formerNames: ['rate'], transient: true)
  double speed = 1.0;
}
''');
      final def = _prop(component, 'speed');
      expect(def.doc, 'Angular velocity in radians per second.');
      expect(def.group, 'Motion');
      expect(def.formerNames, ['rate']);
      expect(def.transient, isTrue);
    });

    test('diagnostics carry the path and line', () {
      final result = extractComponents('''
@SceneComponent('c')
class C extends Component {
  @SceneProperty()
  Widget child;
}
''', path: 'lib/c.dart');
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.path, 'lib/c.dart');
      // The unknown-type diagnostic points at the property annotation.
      expect(diagnostic.line, 3);
    });

    test('static fields are ignored', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {
  @SceneProperty()
  static double shared = 1.0;
  @SceneProperty()
  double speed = 1.0;
}
''');
      expect(component.schema.properties, hasLength(1));
      expect(component.schema.properties.single.name, 'speed');
    });
  });

  group('@SceneGizmo lowering', () {
    test('lowers primitives, binds, conditions, and visibility', () {
      final component = _single('''
@SceneComponent('pickup', icon: 'heart')
@SceneGizmo([
  GizmoIcon(),
  GizmoWireSphere(
    radius: GizmoScalar.bind('radius', scale: 2),
    color: GizmoColor.bind('tint'),
    visibility: GizmoVisibility.selected,
  ),
  GizmoArrow(axis: [0, 1, 0], length: GizmoScalar(0.5), xray: false),
  GizmoWireBox(
    halfExtentsBind: 'bounds',
    when: GizmoCondition('shape', 'box'),
    color: GizmoColor(1, 0.5, 0),
  ),
])
class Pickup extends Component {
  @NumberProperty(min: 0)
  double radius = 1.0;
}
''');
      final gizmo = component.schema.gizmo;
      expect(gizmo, isNotNull);
      expect(gizmo!.primitives, hasLength(4));
      expect(gizmo.primitives[0], isA<GizmoIcon>());
      final sphere = gizmo.primitives[1] as GizmoWireSphere;
      expect(sphere.radius.bind, 'radius');
      expect(sphere.radius.scale, 2);
      expect(sphere.color!.bind, 'tint');
      expect(sphere.visibility, GizmoVisibility.selected);
      final arrow = gizmo.primitives[2] as GizmoArrow;
      expect(arrow.axis, [0, 1, 0]);
      expect(arrow.length.value, 0.5);
      expect(arrow.xray, isFalse);
      final box = gizmo.primitives[3] as GizmoWireBox;
      expect(box.halfExtentsBind, 'bounds');
      expect(box.when!.path, 'shape');
      expect(box.when!.equals, 'box');
      expect(box.color!.r, 1);
      expect(box.color!.a, 1);
    });

    test('unreadable primitives are skipped with a warning', () {
      final result = extractComponents('''
@SceneComponent('c')
@SceneGizmo([
  GizmoIcon(),
  GizmoWireSphere(radius: someDynamicValue),
])
class C extends Component {}
''');
      final gizmo = result.components.single.schema.gizmo;
      expect(gizmo!.primitives, hasLength(1));
      expect(
        result.diagnostics.any(
          (d) =>
              d.severity == ExtractionSeverity.warning &&
              d.message.contains('gizmo primitive'),
        ),
        isTrue,
      );
    });

    test('a component without the annotation has no gizmo', () {
      final component = _single('''
@SceneComponent('c')
class C extends Component {}
''');
      expect(component.schema.gizmo, isNull);
    });
  });

  group('parse failures', () {
    test('flag the result instead of reading as component-free', () {
      final result = extractComponents('''
@SceneComponent('c')
class C extends Component {
  double speed = 1.0
}
''');
      expect(result.parseFailed, isTrue);
      expect(
        result.diagnostics.any(
          (d) =>
              d.severity == ExtractionSeverity.error &&
              d.message.startsWith('syntax error'),
        ),
        isTrue,
      );
    });

    test('a clean source is not flagged', () {
      final result = extractComponents('''
@SceneComponent('c')
class C extends Component {}
''');
      expect(result.parseFailed, isFalse);
    });
  });

  test('softMin without softMax warns instead of silently dropping', () {
    final result = extractComponents('''
@SceneComponent('c')
class C extends Component {
  @NumberProperty(softMin: 1)
  double speed = 2.0;
}
''');
    expect(
      result.diagnostics.any(
        (d) =>
            d.severity == ExtractionSeverity.warning &&
            d.message.contains('softMin'),
      ),
      isTrue,
    );
    expect(
      _single('''
@SceneComponent('c')
class C extends Component {
  @NumberProperty(softMin: 1, softMax: 5)
  double speed = 2.0;
}
''').schema.property('speed')!.constraint<SoftRange>(),
      isNotNull,
    );
  });
}
