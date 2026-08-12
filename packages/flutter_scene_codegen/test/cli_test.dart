import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';

const String _componentSource = '''
import 'package:flutter_scene/annotations.dart';
import 'package:flutter_scene/scene.dart';

@SceneComponent('spinner')
class Spinner extends Component {
  @NumberProperty(min: 0)
  double speed = 1.0;
}
''';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fscene_cli_test');
    File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: demo_app\n');
    Directory('${tmp.path}/lib/components').createSync(recursive: true);
    File(
      '${tmp.path}/lib/components/spinner.dart',
    ).writeAsStringSync(_componentSource);
    // A file with no components, and files the scan must skip.
    File('${tmp.path}/lib/plain.dart').writeAsStringSync('class Plain {}\n');
    File(
      '${tmp.path}/lib/skipped.g.dart',
    ).writeAsStringSync('@SceneComponent still skipped\n');
    // A dependency package shipping a manifest with a registrar.
    final dep = Directory('${tmp.path}/dep_pkg')..createSync(recursive: true);
    File('${dep.path}/$componentManifestFileName').writeAsStringSync(
      encodeComponentManifest(
        schemas: const [],
        registrarLibrary: 'package:dep_pkg/src/fscene_registrar.g.dart',
        registrarFunction: 'registerProjectComponents',
      ),
    );
    Directory('${tmp.path}/.dart_tool').createSync();
    File('${tmp.path}/.dart_tool/package_config.json').writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'demo_app', 'rootUri': '../', 'packageUri': 'lib/'},
          {'name': 'dep_pkg', 'rootUri': '../dep_pkg', 'packageUri': 'lib/'},
        ],
      }),
    );
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  ProcessResult run() => Process.runSync(Platform.resolvedExecutable, [
    'run',
    'bin/generate.dart',
    tmp.path,
  ]);

  test('generates codecs, the registrar, and the manifest', () {
    final result = run();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

    final codec = File('${tmp.path}/lib/components/spinner.fscene.dart');
    expect(codec.existsSync(), isTrue);
    expect(codec.readAsStringSync(), contains('class SpinnerCodec'));

    expect(File('${tmp.path}/lib/plain.fscene.dart').existsSync(), isFalse);
    expect(File('${tmp.path}/lib/skipped.g.fscene.dart').existsSync(), isFalse);

    final registrar = File('${tmp.path}/lib/src/fscene_registrar.g.dart');
    expect(registrar.existsSync(), isTrue);
    final registrarSource = registrar.readAsStringSync();
    expect(registrarSource, contains('registerProjectComponents'));
    expect(
      registrarSource,
      contains(
        "import 'package:demo_app/components/spinner.fscene.dart' as codecs0;",
      ),
    );
    expect(registrarSource, contains('codecs0.SpinnerCodec()'));
    expect(
      registrarSource,
      contains(
        "import 'package:dep_pkg/src/fscene_registrar.g.dart' as deps0;",
      ),
    );
    expect(
      registrarSource,
      contains('deps0.registerProjectComponents(target);'),
    );

    final manifest = File('${tmp.path}/$componentManifestFileName');
    expect(manifest.existsSync(), isTrue);
    final decoded = decodeComponentManifest(manifest.readAsStringSync());
    expect(decoded.schemas.single.type, 'spinner');
    expect(
      decoded.registrarLibrary,
      'package:demo_app/src/fscene_registrar.g.dart',
    );
    expect(decoded.registrarFunction, 'registerProjectComponents');
  });

  test('is idempotent, a second run rewrites nothing', () {
    expect(run().exitCode, 0);
    final second = run();
    expect(second.exitCode, 0);
    expect(second.stdout, isNot(contains('wrote ')));
  });

  test('exits nonzero on an error diagnostic', () {
    File('${tmp.path}/lib/components/broken.dart').writeAsStringSync('''
@SceneComponent('broken')
class Broken extends Component {
  Broken(this.speed);
  @SceneProperty()
  double speed;
}
''');
    final result = run();
    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('zero-argument constructor'));
  });
}
