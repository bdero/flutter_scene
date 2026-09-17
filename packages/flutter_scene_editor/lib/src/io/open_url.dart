/// Opening web links in the platform browser.
library;

import 'dart:io';

/// Opens [url] in the default browser. Only http and https links are opened;
/// anything else is ignored so a manifest can never launch a local program.
Future<void> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
  if (Platform.isMacOS) {
    await Process.start('open', [url], mode: ProcessStartMode.detached);
  } else if (Platform.isWindows) {
    await Process.start('rundll32', [
      'url.dll,FileProtocolHandler',
      url,
    ], mode: ProcessStartMode.detached);
  } else {
    await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
  }
}
