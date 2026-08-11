import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings round trip installations and project state', () {
    final settings = EditorSettings(
      flutterInstallations: const [
        FlutterInstallation(
          id: 'aa',
          name: 'Managed 3.47 (c83f80b)',
          flutterBin: '/data/sdks/versions/c83f80b/bin/flutter',
          managed: true,
        ),
        FlutterInstallation(
          id: 'bb',
          name: 'Fork',
          flutterBin: '/x/flutter/bin/flutter',
          impellerc: '/x/out/host_debug/impellerc',
        ),
      ],
      selectedInstallationId: 'aa',
    );
    settings.rememberProject('/tmp/game/game.fproject');
    settings.selectedBuildConfigurations['/tmp/game/game.fproject'] = 'cfg1';

    final decoded = EditorSettings.fromJsonString(settings.toJsonString());

    expect(decoded.flutterInstallations, hasLength(2));
    expect(decoded.flutterInstallations[0].managed, isTrue);
    expect(
      decoded.flutterInstallations[1].impellerc,
      '/x/out/host_debug/impellerc',
    );
    expect(decoded.selectedInstallationId, 'aa');
    expect(decoded.selectedInstallation?.name, 'Managed 3.47 (c83f80b)');
    expect(decoded.recentProjects, [
      File('/tmp/game/game.fproject').absolute.path,
    ]);
    expect(
      decoded.selectedBuildConfigurations['/tmp/game/game.fproject'],
      'cfg1',
    );
  });

  test('settings without new sections still parse (forward compatible)', () {
    final decoded = EditorSettings.fromJsonString(
      jsonEncode({'version': 1, 'recentScenes': []}),
    );
    expect(decoded.flutterInstallations, isEmpty);
    expect(decoded.selectedInstallation, isNull);
    expect(decoded.recentProjects, isEmpty);
  });

  test('installation derives sdk root and impellerc override precedence', () {
    const installation = FlutterInstallation(
      id: 'x',
      name: 'X',
      flutterBin: '/sdk/bin/flutter',
      impellerc: '/custom/impellerc',
    );
    expect(installation.sdkRoot, '/sdk');
    expect(installation.resolvedImpellerc, '/custom/impellerc');
  });

  test('validation reports a missing CLI as an error', () async {
    final inspector = InstallationInspector();
    final validation = await inspector.validate(
      const FlutterInstallation(
        id: 'x',
        name: 'X',
        flutterBin: '/definitely/not/here/bin/flutter',
      ),
      EditorBuildInfo.unknown,
    );
    expect(validation.severity, InstallationSeverity.error);
    expect(validation.summary, contains('was not found'));
  });

  test(
    'validation flags an unbootstrapped SDK and a revision mismatch',
    () async {
      final root = Directory.systemTemp.createTempSync('fake_sdk_');
      addTearDown(() => root.deleteSync(recursive: true));
      final bin = File('${root.path}/bin/flutter')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      final installation = FlutterInstallation(
        id: 'x',
        name: 'X',
        flutterBin: bin.path,
      );
      final inspector = InstallationInspector();

      // No bin/cache at all, an unbootstrapped SDK is an error.
      final unbootstrapped = await inspector.validate(
        installation,
        EditorBuildInfo.unknown,
      );
      expect(unbootstrapped.severity, InstallationSeverity.error);
      expect(unbootstrapped.summary, contains('Bootstrap'));

      // Bootstrapped with impellerc present but a different revision, a warning.
      File('${root.path}/bin/cache/flutter.version.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'frameworkVersion': '3.47.0',
            'frameworkRevision': 'a' * 40,
          }),
        );
      File(
        '${root.path}/bin/cache/artifacts/engine/darwin-x64/impellerc',
      ).createSync(recursive: true);
      File(
        '${root.path}/bin/cache/artifacts/engine/linux-x64/impellerc',
      ).createSync(recursive: true);
      inspector.invalidate();
      final mismatched = await inspector.validate(
        installation,
        EditorBuildInfo(
          frameworkVersion: '3.48.0',
          frameworkRevision: 'b' * 40,
        ),
      );
      expect(mismatched.severity, InstallationSeverity.warning);
      expect(mismatched.summary, contains('editor was built with'));

      // Matching revision, ok.
      inspector.invalidate();
      final matching = await inspector.validate(
        installation,
        EditorBuildInfo(frameworkRevision: 'a' * 40),
      );
      expect(matching.severity, InstallationSeverity.ok);
    },
  );
}
