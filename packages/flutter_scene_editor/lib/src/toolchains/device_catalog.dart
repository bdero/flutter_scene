/// Devices reported by the selected Flutter installation, the source of the
/// toolbar's device dropdown and the `${DEVICE}`/`${BUILD_TARGET}` command
/// variables. Listing shells `flutter devices --machine` (a few seconds), so
/// results are cached per installation until an explicit refresh.
library;

import 'dart:convert';
import 'dart:io';

import 'flutter_installation.dart';

class FlutterDevice {
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    this.emulator = false,
  });

  /// The `-d` identifier (`macos`, `chrome`, a simulator UDID, ...).
  final String id;

  final String name;

  /// The tool's target platform string (`darwin`, `android-arm64`,
  /// `web-javascript`, ...).
  final String targetPlatform;

  final bool emulator;

  /// The `flutter build` subcommand for this device's platform.
  String get buildTarget => buildTargetFor(targetPlatform);

  /// Maps a tool target platform to its `flutter build` target.
  static String buildTargetFor(String targetPlatform) {
    if (targetPlatform.startsWith('darwin')) return 'macos';
    if (targetPlatform.startsWith('android')) return 'apk';
    if (targetPlatform.startsWith('ios')) return 'ios';
    if (targetPlatform.startsWith('linux')) return 'linux';
    if (targetPlatform.startsWith('windows')) return 'windows';
    if (targetPlatform.startsWith('web')) return 'web';
    return targetPlatform;
  }
}

/// Lists and caches devices per installation.
class DeviceCatalog {
  DeviceCatalog({
    Future<ProcessResult> Function(String executable, List<String> args)? run,
  }) : _run = run ?? _defaultRun;

  static Future<ProcessResult> _defaultRun(
    String executable,
    List<String> args,
  ) {
    // The same scrub every project subprocess gets; a stray IMPELLERC or
    // SDK-management variable never leaks into tool invocations.
    return Process.run(
      executable,
      args,
      environment: projectChildEnvironment(),
      includeParentEnvironment: false,
    );
  }

  final Future<ProcessResult> Function(String executable, List<String> args)
  _run;
  final _cache = <String, List<FlutterDevice>>{};

  /// Cached devices for [installation], or null before the first [list].
  List<FlutterDevice>? cached(FlutterInstallation installation) =>
      _cache[installation.flutterBin];

  /// Lists devices, shelling the tool when uncached or [refresh].
  Future<List<FlutterDevice>> list(
    FlutterInstallation installation, {
    bool refresh = false,
  }) async {
    final key = installation.flutterBin;
    if (!refresh && _cache.containsKey(key)) return _cache[key]!;
    final result = await _run(key, const ['devices', '--machine']);
    if (result.exitCode != 0) {
      throw ProcessException(
        key,
        const ['devices', '--machine'],
        '${result.stderr}\n${result.stdout}'.trim(),
        result.exitCode,
      );
    }
    final devices = parseDevicesJson('${result.stdout}');
    _cache[key] = devices;
    return devices;
  }

  void invalidate([String? flutterBin]) {
    if (flutterBin == null) {
      _cache.clear();
    } else {
      _cache.remove(flutterBin);
    }
  }

  /// Parses `flutter devices --machine` output, tolerating tool banner lines
  /// around the JSON array.
  static List<FlutterDevice> parseDevicesJson(String output) {
    final start = output.indexOf('[');
    final end = output.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final decoded = jsonDecode(output.substring(start, end + 1));
    if (decoded is! List) return const [];
    return [
      for (final entry in decoded)
        if (entry is Map && entry['id'] is String)
          FlutterDevice(
            id: entry['id'] as String,
            name: entry['name'] as String? ?? entry['id'] as String,
            targetPlatform: entry['targetPlatform'] as String? ?? '',
            emulator: entry['emulator'] == true,
          ),
    ];
  }
}
