/// Managed Flutter checkouts, created by the editor under its app data at the
/// exact commit the editor was built against. Creation is a six-phase
/// cancellable job (pre-flight artifact checks, shared mirror, local clone,
/// tool bootstrap, engine precache, verify), and deletion removes only the
/// checkout directory. A full bare mirror is kept as the shared object source
/// so additional checkouts clone locally (hardlinked, no network).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'editor_build_info.dart';
import 'flutter_installation.dart';

/// Where a managed checkout's pieces live under the app data directory.
class ManagedCheckoutPaths {
  const ManagedCheckoutPaths(this.sdksRoot);

  /// `<app data>/sdks`.
  final String sdksRoot;

  String get mirror => '$sdksRoot/shared.git';

  String checkoutFor(String revision) =>
      '$sdksRoot/versions/${shortRevision(revision)}';

  static String shortRevision(String revision) =>
      revision.length > 10 ? revision.substring(0, 10) : revision;
}

enum ManagedCheckoutPhase {
  preflight('Checking engine artifact availability'),
  mirror('Updating the shared Flutter mirror'),
  clone('Creating the checkout'),
  bootstrap('Bootstrapping the Flutter tool'),
  precache('Downloading engine artifacts'),
  verify('Verifying the toolchain');

  const ManagedCheckoutPhase(this.label);

  final String label;
}

/// A running (or finished) managed checkout creation. Listen for progress;
/// [result] is set on success.
class ManagedCheckoutJob extends ChangeNotifier {
  ManagedCheckoutJob._();

  static const int _maxLogLines = 500;
  // Trim in chunks; trimming one line per append is O(length) every line
  // once the buffer is at capacity.
  static const int _trimSlack = 128;

  ManagedCheckoutPhase _phase = ManagedCheckoutPhase.preflight;
  final List<String> log = [];
  String? error;
  bool done = false;
  bool cancelled = false;
  FlutterInstallation? result;
  Process? _current;
  bool _disposed = false;
  bool _notifyScheduled = false;

  ManagedCheckoutPhase get phase => _phase;

  void _setPhase(ManagedCheckoutPhase phase) {
    _phase = phase;
    _line('== ${phase.label}');
  }

  void _line(String message) {
    log.add(message);
    if (log.length > _maxLogLines + _trimSlack) {
      log.removeRange(0, log.length - _maxLogLines);
    }
    // A clone/precache burst emits many lines per event; notify once per
    // burst, and never after dispose.
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _finish({String? error, FlutterInstallation? result}) {
    this.error = error;
    this.result = result;
    done = true;
    if (!_disposed) notifyListeners();
  }

  /// Stops the job; the partial checkout directory is removed.
  void cancel() {
    cancelled = true;
    _current?.kill();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Creates, measures, and deletes managed checkouts.
class ManagedCheckouts {
  ManagedCheckouts({
    required this.paths,
    HttpClient? httpClient,
    this.upstreamUrl = defaultUpstreamUrl,
  }) : _http = httpClient ?? HttpClient();

  static const defaultUpstreamUrl = 'https://github.com/flutter/flutter.git';
  static const storageBase = 'https://storage.googleapis.com';

  final ManagedCheckoutPaths paths;
  final HttpClient _http;

  /// The flutter repository cloned into the mirror (a local path in tests).
  final String upstreamUrl;

  /// Whether [installation] lives under this manager's checkout root.
  bool owns(FlutterInstallation installation) =>
      installation.flutterBin.startsWith('${paths.sdksRoot}/');

  /// Starts creating a checkout matching [buildInfo]'s framework revision.
  /// Returns immediately; observe the job for progress and the result.
  ManagedCheckoutJob create(EditorBuildInfo buildInfo) {
    final job = ManagedCheckoutJob._();
    unawaited(_create(job, buildInfo));
    return job;
  }

  Future<void> _create(ManagedCheckoutJob job, EditorBuildInfo info) async {
    final revision = info.frameworkRevision;
    if (revision == null) {
      job._finish(
        error:
            'The editor does not know its own Flutter revision (no build '
            'info was bundled), so a matching checkout cannot be created.',
      );
      return;
    }
    final dest = paths.checkoutFor(revision);
    try {
      // Pre-flight, fail fast when no prebuilt engine exists for the commit
      // (an engine-modifying fork build) before downloading anything.
      job._setPhase(ManagedCheckoutPhase.preflight);
      final contentHash = info.engineContentHash;
      if (contentHash != null) {
        await _checkArtifacts(job, contentHash);
      } else {
        job._line(
          'No engine content hash in the build info; skipping the '
          'availability pre-flight.',
        );
      }
      if (job.cancelled) return _abort(job, dest);

      // An existing healthy checkout is reused rather than recloned.
      if (File('$dest/bin/flutter').existsSync()) {
        job._line('Reusing the existing checkout at $dest');
      } else {
        job._setPhase(ManagedCheckoutPhase.mirror);
        await _updateMirror(job, info);
        if (job.cancelled) return _abort(job, dest);

        job._setPhase(ManagedCheckoutPhase.clone);
        Directory('${paths.sdksRoot}/versions').createSync(recursive: true);
        // A local clone hardlinks the mirror's objects, no network.
        await _git(job, [
          'clone',
          '--no-checkout',
          paths.mirror,
          dest,
        ], check: true);
        await _git(job, [
          '-C',
          dest,
          'remote',
          'set-url',
          'origin',
          upstreamUrl,
        ], check: true);
        await _git(job, [
          '-C',
          dest,
          'checkout',
          '--detach',
          revision,
        ], check: true);
      }
      if (job.cancelled) return _abort(job, dest);

      // Bootstrap and precache with the engine pinned to the pre-flighted
      // hash, short-circuiting the tool's git archaeology.
      final env = <String, String>{
        if (contentHash != null) 'FLUTTER_PREBUILT_ENGINE_VERSION': contentHash,
      };
      job._setPhase(ManagedCheckoutPhase.bootstrap);
      final flutterBin = '$dest/bin/flutter${Platform.isWindows ? '.bat' : ''}';
      final bootstrap = await _run(job, flutterBin, [
        '--version',
      ], environment: env);
      if (job.cancelled) return _abort(job, dest);
      if (bootstrap != 0) {
        return job._finish(
          error:
              'The Flutter tool failed to bootstrap (exit $bootstrap). See '
              'the log above; the checkout is kept for retry.',
        );
      }

      job._setPhase(ManagedCheckoutPhase.precache);
      final precache = await _run(job, flutterBin, [
        'precache',
        '--universal',
        if (Platform.isMacOS) '--macos',
        if (Platform.isLinux) '--linux',
        if (Platform.isWindows) '--windows',
      ], environment: env);
      if (job.cancelled) return _abort(job, dest);
      if (precache != 0) {
        return job._finish(
          error: 'flutter precache failed (exit $precache). See the log.',
        );
      }

      job._setPhase(ManagedCheckoutPhase.verify);
      final impellerc = impellercForSdkRoot(dest);
      if (impellerc == null) {
        return job._finish(
          error:
              'impellerc did not appear in the checkout\'s artifact cache '
              'after precache. The commit\'s artifacts may be incomplete.',
        );
      }
      job._line('impellerc at $impellerc');
      final short = ManagedCheckoutPaths.shortRevision(revision);
      job._finish(
        result: FlutterInstallation(
          id: 'managed-$short',
          name: 'Managed ${info.frameworkVersion ?? 'Flutter'} ($short)',
          flutterBin: flutterBin,
          managed: true,
        ),
      );
    } on Exception catch (e) {
      job._finish(error: '$e');
    }
  }

  void _abort(ManagedCheckoutJob job, String dest) {
    // A cancelled clone leaves a partial checkout; remove it. Bootstrap and
    // later phases keep the checkout (retry is cheap from there).
    if (job.phase == ManagedCheckoutPhase.clone) {
      try {
        Directory(dest).deleteSync(recursive: true);
      } on FileSystemException {
        // Leave the partial directory; recreation handles it.
      }
    }
    job._finish(error: 'Cancelled.');
  }

  /// HEAD-checks the Dart SDK and host engine artifacts for [contentHash].
  Future<void> _checkArtifacts(
    ManagedCheckoutJob job,
    String contentHash,
  ) async {
    final os = Platform.isMacOS
        ? 'darwin'
        : Platform.isWindows
        ? 'windows'
        : 'linux';
    final arch = Platform.version.contains('arm64') ? 'arm64' : 'x64';
    // The macOS host dir stays darwin-x64 on every Mac (historical naming).
    final hostDir = Platform.isMacOS ? 'darwin-x64' : '$os-$arch';
    final urls = [
      '$storageBase/flutter_infra_release/flutter/$contentHash/'
          'dart-sdk-$os-$arch.zip',
      '$storageBase/flutter_infra_release/flutter/$contentHash/'
          '$hostDir/artifacts.zip',
    ];
    for (final url in urls) {
      final ok = await _headOk(url);
      job._line('${ok ? 'found' : 'MISSING'}  $url');
      if (!ok) {
        throw Exception(
          'No prebuilt engine exists for this commit (content hash '
          '${ManagedCheckoutPaths.shortRevision(contentHash)}). Commits with '
          'engine changes need a locally built engine; register that SDK as '
          'a custom installation instead.',
        );
      }
    }
  }

  Future<bool> _headOk(String url) async {
    try {
      final request = await _http.headUrl(Uri.parse(url));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 400;
    } on Exception {
      return false;
    }
  }

  Future<void> _updateMirror(
    ManagedCheckoutJob job,
    EditorBuildInfo info,
  ) async {
    Directory(paths.sdksRoot).createSync(recursive: true);
    if (!Directory(paths.mirror).existsSync()) {
      await _git(job, [
        'clone',
        '--bare',
        upstreamUrl,
        paths.mirror,
      ], check: true);
    } else {
      await _git(job, [
        '-C',
        paths.mirror,
        'fetch',
        '--prune',
        '--tags',
        'origin',
        '+refs/heads/*:refs/heads/*',
      ], check: true);
    }
    // A fork-built editor's commit may not exist upstream; fetch it from the
    // fork into the mirror by SHA (GitHub serves arbitrary reachable SHAs).
    final revision = info.frameworkRevision!;
    final present = await _git(job, [
      '-C',
      paths.mirror,
      'cat-file',
      '-e',
      '$revision^{commit}',
    ]);
    if (present != 0) {
      final fork = _httpsUrl(info.repositoryUrl);
      if (fork == null || fork == upstreamUrl) {
        throw Exception(
          'Commit ${ManagedCheckoutPaths.shortRevision(revision)} was not '
          'found in flutter/flutter.',
        );
      }
      job._line('Commit not upstream; fetching from $fork');
      // Fetch into a pinned ref so the commit stays reachable in the mirror
      // (an unreferenced object would not survive gc and would not be
      // guaranteed present in clones).
      final fetched = await _git(job, [
        '-C',
        paths.mirror,
        'fetch',
        fork,
        '+$revision:refs/managed/$revision',
      ]);
      if (fetched != 0) {
        throw Exception(
          'Commit ${ManagedCheckoutPaths.shortRevision(revision)} was not '
          'found upstream or in $fork.',
        );
      }
    }
  }

  /// Normalizes a git remote (ssh or https) to a fetchable URL, passing
  /// local paths through (tests use a local fork repo), or null.
  static String? _httpsUrl(String? remote) {
    if (remote == null || remote.isEmpty) return null;
    if (remote.startsWith('https://') || remote.startsWith('/')) return remote;
    final ssh = RegExp(r'^git@([^:]+):(.+)$').firstMatch(remote);
    if (ssh != null) return 'https://${ssh.group(1)}/${ssh.group(2)}';
    return null;
  }

  Future<int> _git(
    ManagedCheckoutJob job,
    List<String> args, {
    bool check = false,
  }) => _run(job, 'git', args, check: check);

  Future<int> _run(
    ManagedCheckoutJob job,
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    bool check = false,
  }) async {
    job._line('+ $executable ${args.join(' ')}');
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      workingDirectory: paths.sdksRoot,
    );
    job._current = process;
    Future<void> tail(Stream<List<int>> stream) => stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isNotEmpty) job._line(line);
        });
    final drained = Future.wait([tail(process.stdout), tail(process.stderr)]);
    final exitCode = await process.exitCode;
    await drained;
    job._current = null;
    if (check && exitCode != 0 && !job.cancelled) {
      throw Exception('$executable exited with $exitCode');
    }
    return exitCode;
  }

  /// On-disk sizes of a managed checkout, the tool/artifact cache vs the git
  /// checkout, three different rebuild costs.
  Future<(int cacheBytes, int checkoutBytes)> sizeOf(
    FlutterInstallation installation,
  ) async {
    final root = installation.sdkRoot;
    final cache = await _directorySize('$root/bin/cache');
    final total = await _directorySize(root);
    return (cache, total - cache);
  }

  Future<int> _directorySize(String path) async {
    var total = 0;
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += entity.lengthSync();
        } on FileSystemException {
          // Unreadable entries only shrink the estimate.
        }
      }
    }
    return total;
  }

  /// Deletes the managed checkout from disk. The shared mirror stays (it
  /// makes recreation cheap and is small next to a checkout).
  Future<void> delete(FlutterInstallation installation) async {
    if (!owns(installation)) {
      throw ArgumentError(
        'Installation "${installation.name}" is not managed by the editor.',
      );
    }
    final root = installation.sdkRoot;
    if (Directory(root).existsSync()) {
      await Directory(root).delete(recursive: true);
    }
  }
}
