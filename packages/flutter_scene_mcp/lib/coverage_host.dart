/// Project-local coverage reading for native editor hosts. Kept separate from
/// flutter_scene_mcp.dart so the main tool surface remains usable on the web.
library;

import 'dart:convert';
import 'dart:io';

/// Reads an existing coverage summary from [projectRoot]. Does not run tests.
/// The conventional report is coverage/report/summary.json. Missing or invalid
/// reports are errors; absent coverage is not a measured zero percent result.
Future<Map<String, Object?>> readProjectTestCoverage(
  String projectRoot, {
  bool includeFiles = false,
}) async {
  try {
    final root = await Directory(projectRoot).resolveSymbolicLinks();
    final report = File.fromUri(
      Directory(root).uri.resolve('coverage/report/summary.json'),
    );
    if (!await report.exists()) {
      throw const FormatException(
        'No measured coverage/report/summary.json in the open project; generate test coverage first',
      );
    }
    final resolved = await report.resolveSymbolicLinks();
    final rootUri = Directory(root).uri;
    if (!File(resolved).uri.toString().startsWith(rootUri.toString())) {
      throw const FormatException(
        'Coverage report resolves outside the open project',
      );
    }
    final value = jsonDecode(await report.readAsString());
    if (value is! Map<String, dynamic> ||
        value['packages'] is! List ||
        (value['packages'] as List).isEmpty) {
      throw const FormatException(
        'Coverage summary needs a nonempty packages array',
      );
    }
    final packages = <Map<String, Object?>>[];
    for (final entry in value['packages'] as List) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid coverage package');
      }
      final hit = entry['hit'], found = entry['found'];
      if (hit is! int ||
          found is! int ||
          found <= 0 ||
          hit < 0 ||
          hit > found) {
        throw const FormatException(
          'Coverage requires 0 <= hit <= found and found > 0',
        );
      }
      packages.add(
        {...entry, 'percent': (hit * 10000 / found).round() / 100}
          ..removeWhere((key, _) => !includeFiles && key == 'files'),
      );
    }
    return {
      ...value,
      'packages': packages,
      'reportPath': resolved,
      'note':
          'Historical measured test lines, not widget rebuild or GPU qualification. Compare revision with the current source before using it as acceptance.',
    };
  } on FileSystemException {
    throw const FormatException('Cannot read the open project coverage report');
  }
}
