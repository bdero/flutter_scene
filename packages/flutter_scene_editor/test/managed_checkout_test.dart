import 'dart:async';
import 'dart:io';

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the managed checkout pipeline offline, a fake local "upstream"
/// whose committed `bin/flutter` script fabricates the bootstrap/precache
/// artifacts the real tool would download.
void main() {
  late Directory temp;
  late String upstream;
  late String revision;

  Future<ProcessResult> git(List<String> args, {String? cwd}) =>
      Process.run('git', args, workingDirectory: cwd);

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('managed_checkout_');
    upstream = '${temp.path}/upstream';
    Directory('$upstream/bin').createSync(recursive: true);
    final script = File('$upstream/bin/flutter');
    script.writeAsStringSync('''
#!/bin/sh
ROOT="\$(cd "\$(dirname "\$0")/.." && pwd)"
mkdir -p "\$ROOT/bin/cache/artifacts/engine/darwin-x64"
mkdir -p "\$ROOT/bin/cache/artifacts/engine/linux-x64"
echo '{"frameworkVersion":"9.9.9-test"}' > "\$ROOT/bin/cache/flutter.version.json"
touch "\$ROOT/bin/cache/artifacts/engine/darwin-x64/impellerc"
touch "\$ROOT/bin/cache/artifacts/engine/linux-x64/impellerc"
echo "fake flutter \$@"
''');
    await Process.run('chmod', ['+x', script.path]);
    await git(['init', '-q', '-b', 'master'], cwd: upstream);
    await git(['add', '-A'], cwd: upstream);
    await git([
      '-c',
      'user.email=t@t',
      '-c',
      'user.name=t',
      'commit',
      '-q',
      '-m',
      'fake sdk',
    ], cwd: upstream);
    final head = await git(['rev-parse', 'HEAD'], cwd: upstream);
    revision = '${head.stdout}'.trim();
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  Future<ManagedCheckoutJob> awaitJob(ManagedCheckoutJob job) async {
    final completer = Completer<void>();
    void check() {
      if (job.done && !completer.isCompleted) completer.complete();
    }

    job.addListener(check);
    check();
    await completer.future.timeout(const Duration(minutes: 2));
    job.removeListener(check);
    return job;
  }

  test('creates, reuses, and deletes a managed checkout', () async {
    final manager = ManagedCheckouts(
      paths: ManagedCheckoutPaths('${temp.path}/sdks'),
      upstreamUrl: upstream,
    );
    final info = EditorBuildInfo(
      frameworkVersion: '9.9.9-test',
      frameworkRevision: revision,
    );

    final job = await awaitJob(manager.create(info));
    expect(job.error, isNull);
    final installation = job.result;
    expect(installation, isNotNull);
    expect(installation!.managed, isTrue);
    expect(installation.name, contains('9.9.9-test'));
    expect(File(installation.flutterBin).existsSync(), isTrue);
    expect(installation.resolvedImpellerc, isNotNull);
    expect(manager.owns(installation), isTrue);

    // The second create reuses the checkout (no reclone; mirror untouched).
    final again = await awaitJob(manager.create(info));
    expect(again.error, isNull);
    expect(again.log.join('\n'), contains('Reusing the existing checkout'));

    // Sizes report both tiers, then deletion removes the checkout but keeps
    // the mirror.
    final (cacheBytes, checkoutBytes) = await manager.sizeOf(installation);
    expect(cacheBytes, greaterThan(0));
    expect(checkoutBytes, greaterThan(0));
    await manager.delete(installation);
    expect(Directory(installation.sdkRoot).existsSync(), isFalse);
    expect(Directory(manager.paths.mirror).existsSync(), isTrue);
  });

  test('fetches a fork-only commit into the mirror by pinned ref', () async {
    // A fork with one commit past upstream; the editor was "built" at the
    // fork commit, so the mirror must fetch it from the fork remote.
    final fork = '${temp.path}/fork';
    await Process.run('cp', ['-R', upstream, fork]);
    File('$fork/EXTRA').writeAsStringSync('fork change\n');
    await git(['add', '-A'], cwd: fork);
    await git([
      '-c',
      'user.email=t@t',
      '-c',
      'user.name=t',
      'commit',
      '-q',
      '-m',
      'fork commit',
    ], cwd: fork);
    final head = await git(['rev-parse', 'HEAD'], cwd: fork);
    final forkRevision = '${head.stdout}'.trim();

    final manager = ManagedCheckouts(
      paths: ManagedCheckoutPaths('${temp.path}/sdks_fork'),
      upstreamUrl: upstream,
    );
    final job = await awaitJob(
      manager.create(
        EditorBuildInfo(
          frameworkVersion: '9.9.9-fork',
          frameworkRevision: forkRevision,
          repositoryUrl: fork,
        ),
      ),
    );
    expect(job.error, isNull);
    expect(job.log.join('\n'), contains('Commit not upstream'));
    expect(job.result, isNotNull);
    // The checkout really sits at the fork commit.
    final at = await git(['-C', job.result!.sdkRoot, 'rev-parse', 'HEAD']);
    expect('${at.stdout}'.trim(), forkRevision);
  });

  test('fails cleanly for an unknown revision', () async {
    final manager = ManagedCheckouts(
      paths: ManagedCheckoutPaths('${temp.path}/sdks2'),
      upstreamUrl: upstream,
    );
    final job = await awaitJob(
      manager.create(
        EditorBuildInfo(frameworkVersion: 'x', frameworkRevision: 'f' * 40),
      ),
    );
    expect(job.result, isNull);
    expect(job.error, contains('not'));
  });

  test('refuses to delete an unmanaged installation', () async {
    final manager = ManagedCheckouts(
      paths: ManagedCheckoutPaths('${temp.path}/sdks3'),
      upstreamUrl: upstream,
    );
    expect(
      () => manager.delete(
        const FlutterInstallation(
          id: 'x',
          name: 'X',
          flutterBin: '/somewhere/else/bin/flutter',
        ),
      ),
      throwsArgumentError,
    );
  });
}
