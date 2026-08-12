import 'dart:io';

import 'package:test/test.dart';

import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';

const String _fixtureSource = '''
import 'package:flutter_scene/annotations.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'dart:ui' show Color;

enum SpinMode { slow, fast }

/// Spins the node around an axis.
@SceneComponent('spinner', icon: 'S', formerTypes: ['rotator'])
class Spinner extends Component {
  /// Angular velocity in radians per second.
  @NumberProperty(min: 0, softMin: 0, softMax: 10, step: 0.1, group: 'Motion')
  double speed = 1.0;

  @IntProperty(min: 1, max: 8)
  int turns = 1;

  @BoolProperty()
  bool active = true;

  @StringProperty(formerNames: ['label'])
  String name = 'spinner';

  @EnumProperty()
  SpinMode mode = SpinMode.slow;

  @Vec3Property(normalized: true)
  Vector3 axis = Vector3(0.0, 1.0, 0.0);

  @Vec3Property(normalized: true)
  Vector3? swayAxis;

  @Vec2Property()
  Vector2 wobble = Vector2.zero();

  @Vec4Property()
  Vector4 weights = Vector4(1.0, 0.0, 0.0, 0.0);

  @QuaternionProperty()
  Quaternion rest = Quaternion(0.0, 0.0, 0.0, 1.0);

  @ColorProperty()
  Color tint = Color(0xffffffff);

  @AssetProperty(extensions: ['.wav'])
  String? clip;

  @NodeProperty()
  Node? lookTarget;

  @SceneProperty()
  Geometry? shape;

  @SceneProperty(transient: true)
  double phase = 0.0;
}
''';

void main() {
  group('generateCodecLibrary', () {
    late String generated;

    setUpAll(() {
      final result = extractComponents(_fixtureSource, path: 'spinner.dart');
      expect(
        result.diagnostics.where((d) => d.severity == ExtractionSeverity.error),
        isEmpty,
      );
      generated = generateCodecLibrary(
        components: result.components,
        sourceImport: 'spinner.dart',
      );
    });

    test('declares the codec class over the component type', () {
      expect(
        generated,
        contains(
          'class SpinnerCodec extends DeclarativeComponentCodec<Spinner>',
        ),
      );
      expect(generated, contains("String get type => 'spinner'"));
      expect(
        generated,
        contains('Spinner create(PropertyReader props) => Spinner()'),
      );
    });

    test('overrides schema for doc, icon, and formerTypes', () {
      expect(generated, contains('ComponentSchema get schema'));
      expect(generated, contains("icon: 'S'"));
      expect(generated, contains("formerTypes: ['rotator']"));
      expect(generated, contains('Spins the node around an axis.'));
    });

    test('imports only what the fields need', () {
      expect(
        generated,
        contains("import 'package:flutter_scene/fscene.dart';"),
      );
      expect(
        generated,
        contains("import 'package:vector_math/vector_math.dart';"),
      );
      expect(generated, contains("import 'dart:ui' show Color;"));
      expect(generated, contains("import 'spinner.dart';"));
    });

    test('emits factory fields with constraints and bindings', () {
      expect(generated, contains("ComponentField.number("));
      expect(generated, contains('Range(0.0, null)'));
      expect(generated, contains('SoftRange'));
      expect(generated, contains('Step(0.1)'));
      expect(generated, contains('IntRange(1, 8)'));
      expect(generated, contains('get: (c) => c.speed'));
      expect(generated, contains('set: (c, v) => c.speed = v'));
      expect(generated, contains("formerNames: ['label']"));
      expect(generated, contains('transient: true'));
    });

    test('emits the enum field through enumString', () {
      expect(generated, contains('ComponentField.enumString('));
      expect(generated, contains('values: SpinMode.values'));
      expect(generated, contains('defaultValue: SpinMode.slow'));
    });

    test('emits reference fields with realizer and resolver writes', () {
      expect(generated, contains('ComponentField.resourceRef('));
      expect(generated, contains("resourceKind: 'geometry'"));
      expect(generated, contains('resources.geometry(id)'));
      expect(generated, contains('NodeRefValue'));
      expect(generated, contains('context.resolveNode?.call(v.id)'));
      expect(generated, contains('context.afterRealize.add'));
    });

    test('emits color and quaternion raw bindings', () {
      expect(generated, contains('ColorValue(c.tint.r'));
      expect(generated, contains('Color.from(alpha: v.a'));
      expect(generated, contains('QuaternionValue(c.rest.clone())'));
    });

    test('normalized vec3 fields carry the constraint and renormalize', () {
      // The defaulted field routes through the factory, which normalizes
      // from its constraint; the nullable field gets a raw write binding.
      expect(generated, contains('constraints: const [Normalized()]'));
      expect(generated, contains('vector.normalize()'));
    });

    test('is idempotent for the same input', () {
      final result = extractComponents(_fixtureSource, path: 'spinner.dart');
      final again = generateCodecLibrary(
        components: result.components,
        sourceImport: 'spinner.dart',
      );
      expect(again, generated);
    });
  });

  group('generateProjectRegistrar', () {
    test('registers codecs and calls dependency registrars', () {
      final registrar = generateProjectRegistrar(
        codecLibraries: [
          (
            importUri: 'package:app/spinner.fscene.dart',
            codecClassNames: ['SpinnerCodec'],
          ),
        ],
        dependencyRegistrars: [
          (
            importUri: 'package:dep/src/fscene_registrar.g.dart',
            functionName: 'registerProjectComponents',
          ),
        ],
      );
      expect(
        registrar,
        contains(
          'void registerProjectComponents([FsceneComponentRegistry? registry])',
        ),
      );
      expect(
        registrar,
        contains('final target = registry ?? defaultComponentRegistry();'),
      );
      expect(registrar, contains('target.register(codecs0.SpinnerCodec());'));
      expect(registrar, contains('deps0.registerProjectComponents(target);'));
      expect(
        registrar,
        contains("import 'package:app/spinner.fscene.dart' as codecs0;"),
      );
    });

    test('an empty project still produces a valid registrar', () {
      final registrar = generateProjectRegistrar(codecLibraries: const []);
      expect(registrar, contains('void registerProjectComponents'));
    });
  });

  group('generated code compiles', () {
    late Directory fixtureDir;

    setUpAll(() {
      // The fixture lives inside this package so the workspace package
      // config resolves package:flutter_scene for `dart analyze`.
      fixtureDir = Directory(
        '${Directory.current.path}/test/_compile_fixture_tmp',
      );
      if (fixtureDir.existsSync()) fixtureDir.deleteSync(recursive: true);
      fixtureDir.createSync(recursive: true);
    });

    tearDownAll(() {
      if (fixtureDir.existsSync()) fixtureDir.deleteSync(recursive: true);
    });

    test(
      'dart analyze reports no errors on the generated codec and registrar',
      () {
        File(
          '${fixtureDir.path}/spinner.dart',
        ).writeAsStringSync(_fixtureSource);
        final result = extractComponents(_fixtureSource, path: 'spinner.dart');
        final codec = generateCodecLibrary(
          components: result.components,
          sourceImport: 'spinner.dart',
        );
        File('${fixtureDir.path}/spinner.fscene.dart').writeAsStringSync(codec);
        final registrar = generateProjectRegistrar(
          codecLibraries: [
            (
              importUri: 'spinner.fscene.dart',
              codecClassNames: [
                for (final component in result.components)
                  codecClassNameFor(component.className),
              ],
            ),
          ],
        );
        File('${fixtureDir.path}/registrar.dart').writeAsStringSync(registrar);

        final analyze = Process.runSync(Platform.resolvedExecutable, [
          'analyze',
          '--format=machine',
          fixtureDir.path,
        ]);
        final output = '${analyze.stdout}\n${analyze.stderr}';
        final errors = output
            .split('\n')
            .where((line) => line.startsWith('ERROR|'))
            .toList();
        expect(errors, isEmpty, reason: output);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
