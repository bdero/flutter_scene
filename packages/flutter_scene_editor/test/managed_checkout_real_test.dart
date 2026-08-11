@Timeout(Duration(minutes: 45))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real thing, network and all: creates a managed checkout at the
/// editor's build commit (clone, bootstrap, precache, ~1.5 GB of downloads).
/// Gated behind dart-defines so the normal suite never runs it:
///
///   flutter test test/managed_checkout_real_test.dart \
///     --dart-define=RUN_REAL_MANAGED_CHECKOUT=1 \
///     --dart-define=CHECKOUT_ROOT=/path/to/sdks \
///     --dart-define=BUILD_INFO_JSON=/path/to/editor_build_info.json
void main() {
  const enabled = String.fromEnvironment('RUN_REAL_MANAGED_CHECKOUT') == '1';
  const checkoutRoot = String.fromEnvironment('CHECKOUT_ROOT');
  const buildInfoJson = String.fromEnvironment('BUILD_INFO_JSON');

  test('creates a real managed checkout matching the editor build', () async {
    if (!enabled || checkoutRoot.isEmpty || buildInfoJson.isEmpty) {
      markTestSkipped(
        'Network-gated; pass RUN_REAL_MANAGED_CHECKOUT=1, CHECKOUT_ROOT, '
        'and BUILD_INFO_JSON dart-defines to run.',
      );
      return;
    }
    final decoded = (jsonDecode(File(buildInfoJson).readAsStringSync()) as Map)
        .cast<String, Object?>();
    final info = EditorBuildInfo(
      frameworkVersion: decoded['frameworkVersion'] as String?,
      frameworkRevision: decoded['frameworkRevision'] as String?,
      engineRevision: decoded['engineRevision'] as String?,
      engineContentHash: decoded['engineContentHash'] as String?,
      dartSdkVersion: decoded['dartSdkVersion'] as String?,
      repositoryUrl: decoded['repositoryUrl'] as String?,
      flutterSceneVersion: decoded['flutterSceneVersion'] as String?,
    );
    expect(info.frameworkRevision, isNotNull);

    final manager = ManagedCheckouts(paths: ManagedCheckoutPaths(checkoutRoot));
    final job = manager.create(info);
    var printed = 0;
    job.addListener(() {
      for (; printed < job.log.length; printed++) {
        // ignore: avoid_print
        print('| ${job.log[printed]}');
      }
    });
    while (!job.done) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(job.error, isNull);
    final installation = job.result;
    expect(installation, isNotNull);

    // The checkout validates clean against the editor's own identity (the
    // whole point of a managed checkout).
    final inspector = InstallationInspector();
    final validation = await inspector.validate(installation!, info);
    expect(
      validation.severity,
      InstallationSeverity.ok,
      reason: validation.summary,
    );

    // Its impellerc actually executes.
    final impellerc = installation.resolvedImpellerc;
    expect(impellerc, isNotNull);
    final help = await Process.run(impellerc!, ['--help']);
    expect(help.exitCode, anyOf(0, 1));

    // And its flutter CLI reports the pinned revision.
    final version = await Process.run(installation.flutterBin, [
      '--version',
      '--machine',
    ]);
    expect(version.exitCode, 0);
    expect('${version.stdout}', contains(info.frameworkRevision!));
  });
}
