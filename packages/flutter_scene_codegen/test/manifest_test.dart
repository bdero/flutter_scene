import 'dart:convert';
import 'dart:io';

import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:test/test.dart';

import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';

void main() {
  group('encode/decode', () {
    const schemas = [
      ComponentSchema(
        'spinner',
        doc: 'Spins the node.',
        icon: 'S',
        formerTypes: ['rotator'],
        properties: [
          ComponentPropertyDef(
            'speed',
            ComponentPropertyKind.number,
            defaultValue: DoubleValue(1.0),
            doc: 'Angular velocity.',
            group: 'Motion',
            constraints: [Range(0, null), Step(0.1)],
            formerNames: ['rate'],
          ),
          ComponentPropertyDef(
            'mode',
            ComponentPropertyKind.string,
            defaultValue: StringValue('slow'),
            options: ['slow', 'fast'],
          ),
        ],
      ),
      ComponentSchema('marker'),
    ];

    test('round trips schemas and the registrar entry', () {
      final encoded = encodeComponentManifest(
        schemas: schemas,
        registrarLibrary: 'package:app/src/fscene_registrar.g.dart',
        registrarFunction: 'registerProjectComponents',
      );
      final decoded = decodeComponentManifest(encoded);
      expect(
        decoded.registrarLibrary,
        'package:app/src/fscene_registrar.g.dart',
      );
      expect(decoded.registrarFunction, 'registerProjectComponents');
      expect(decoded.schemas, hasLength(2));
      final spinner = decoded.schemas.first;
      expect(spinner.type, 'spinner');
      expect(spinner.doc, 'Spins the node.');
      expect(spinner.icon, 'S');
      expect(spinner.formerTypes, ['rotator']);
      final speed = spinner.property('speed')!;
      expect(speed.kind, ComponentPropertyKind.number);
      expect((speed.defaultValue! as DoubleValue).value, 1.0);
      expect(speed.doc, 'Angular velocity.');
      expect(speed.group, 'Motion');
      expect(speed.formerNames, ['rate']);
      expect(speed.constraint<Range>()!.min, 0);
      expect(speed.constraint<Step>()!.step, 0.1);
      expect(spinner.property('mode')!.options, ['slow', 'fast']);
    });

    test('omits the registrar block when no registrar is given', () {
      final encoded = encodeComponentManifest(schemas: schemas);
      final json = jsonDecode(encoded) as Map;
      expect(json.containsKey('registrar'), isFalse);
      final decoded = decodeComponentManifest(encoded);
      expect(decoded.registrarLibrary, isNull);
      expect(decoded.registrarFunction, isNull);
    });

    test('tolerates malformed content', () {
      final decoded = decodeComponentManifest('{"schemas": "nope"}');
      expect(decoded.schemas, isEmpty);
      expect(decoded.registrarLibrary, isNull);
    });
  });

  group('scanPackageManifests', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('fscene_manifest_test');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('finds manifests at resolved package roots', () {
      final withManifest = Directory('${tmp.path}/pkg_a')
        ..createSync(recursive: true);
      File('${withManifest.path}/$componentManifestFileName').writeAsStringSync(
        encodeComponentManifest(
          schemas: const [ComponentSchema('spinner')],
          registrarLibrary: 'package:pkg_a/src/fscene_registrar.g.dart',
          registrarFunction: 'registerProjectComponents',
        ),
      );
      Directory('${tmp.path}/pkg_b').createSync(recursive: true);
      final projectDartTool = Directory('${tmp.path}/project/.dart_tool')
        ..createSync(recursive: true);
      final configPath = '${projectDartTool.path}/package_config.json';
      File(configPath).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'pkg_a', 'rootUri': '../../pkg_a', 'packageUri': 'lib/'},
            {'name': 'pkg_b', 'rootUri': '../../pkg_b', 'packageUri': 'lib/'},
          ],
        }),
      );
      final found = scanPackageManifests(configPath);
      expect(found, hasLength(1));
      expect(found.single.package, 'pkg_a');
      expect(
        Directory(found.single.rootPath).absolute.path,
        Directory(withManifest.path).absolute.path,
      );
      final registrar = found.single.manifest['registrar'] as Map?;
      expect(
        registrar!['library'],
        'package:pkg_a/src/fscene_registrar.g.dart',
      );
    });

    test('returns empty for a missing or malformed package config', () {
      expect(scanPackageManifests('${tmp.path}/nope.json'), isEmpty);
      final bad = File('${tmp.path}/bad.json')..writeAsStringSync('not json');
      expect(scanPackageManifests(bad.path), isEmpty);
    });

    test('skips a package whose manifest is malformed', () {
      final pkg = Directory('${tmp.path}/pkg_bad')..createSync(recursive: true);
      File(
        '${pkg.path}/$componentManifestFileName',
      ).writeAsStringSync('not json');
      final dartTool = Directory('${tmp.path}/project/.dart_tool')
        ..createSync(recursive: true);
      final configPath = '${dartTool.path}/package_config.json';
      File(configPath).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'pkg_bad',
              'rootUri': '../../pkg_bad',
              'packageUri': 'lib/',
            },
          ],
        }),
      );
      expect(scanPackageManifests(configPath), isEmpty);
    });
  });
}
