import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

const _devicesJson = '''
Some tool banner noise
[
  {"name": "macOS", "id": "macos", "targetPlatform": "darwin", "emulator": false},
  {"name": "iPhone 16", "id": "ABCD-1234", "targetPlatform": "ios", "emulator": true},
  {"name": "Chrome", "id": "chrome", "targetPlatform": "web-javascript", "emulator": false}
]
trailing noise
''';

void main() {
  test('parses devices from machine output with banner noise', () {
    final devices = DeviceCatalog.parseDevicesJson(_devicesJson);
    expect(devices, hasLength(3));
    expect(devices[0].id, 'macos');
    expect(devices[0].buildTarget, 'macos');
    expect(devices[1].emulator, isTrue);
    expect(devices[1].buildTarget, 'ios');
    expect(devices[2].buildTarget, 'web');
  });

  test('build target mapping covers every platform family', () {
    expect(FlutterDevice.buildTargetFor('darwin'), 'macos');
    expect(FlutterDevice.buildTargetFor('android-arm64'), 'apk');
    expect(FlutterDevice.buildTargetFor('ios'), 'ios');
    expect(FlutterDevice.buildTargetFor('linux-x64'), 'linux');
    expect(FlutterDevice.buildTargetFor('windows-x64'), 'windows');
    expect(FlutterDevice.buildTargetFor('web-javascript'), 'web');
  });

  test('catalog caches per installation until refresh', () async {
    var calls = 0;
    final catalog = DeviceCatalog(
      run: (executable, args) async {
        calls++;
        return ProcessResult(0, 0, _devicesJson, '');
      },
    );
    const installation = FlutterInstallation(
      id: 'x',
      name: 'X',
      flutterBin: '/sdk/bin/flutter',
    );
    expect(catalog.cached(installation), isNull);
    await catalog.list(installation);
    await catalog.list(installation);
    expect(calls, 1);
    expect(catalog.cached(installation), hasLength(3));
    await catalog.list(installation, refresh: true);
    expect(calls, 2);
  });

  test('working directory override resolves against the project root', () {
    final root = Directory.systemTemp.createTempSync('wd_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: x\n');
    final project = FProject.createDefault(root.path);
    final base = project.resolvedProjectRoot;
    final variables = {'PROJECT_ROOT': base, 'MODE': 'debug'};
    BuildConfiguration config(String workingDirectory) => BuildConfiguration(
      id: 'x',
      name: 'X',
      mode: 'debug',
      buildCommand: '',
      workingDirectory: workingDirectory,
    );

    expect(resolveWorkingDirectory(project, config(''), variables), base);
    expect(
      resolveWorkingDirectory(project, config('tool'), variables),
      '$base/tool',
    );
    expect(
      resolveWorkingDirectory(
        project,
        config(r'${PROJECT_ROOT}/sub'),
        variables,
      ),
      '$base/sub',
    );
    expect(
      resolveWorkingDirectory(project, config('/abs/path'), variables),
      '/abs/path',
    );
  });
}
