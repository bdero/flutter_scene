import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

// Runs on the host (not in the app sandbox). The test base64-encodes each
// captured PNG into binding.reportData; here we decode and write them to
// build/smoke/<name> so CI can collect and upload them.
Future<void> main() => integrationDriver(
  // Write captures even when the sanity assertions fail: a failed gate is
  // exactly when the frames are wanted in Argos for visual triage, and the
  // workflow's upload step runs regardless of the test result.
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    if (data == null) return;
    final dir = Directory('build/smoke')..createSync(recursive: true);
    data.forEach((name, value) {
      if (value is String) {
        File('${dir.path}/$name').writeAsBytesSync(base64Decode(value));
      }
    });
  },
);
