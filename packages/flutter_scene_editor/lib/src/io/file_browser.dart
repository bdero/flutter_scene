/// Revealing files in the platform file browser.
library;

import 'dart:io';

/// The platform file browser's reveal verb, matching each platform's
/// convention ("Reveal in Finder", "Reveal in File Explorer", and the
/// generic file-manager phrasing elsewhere).
String get revealInFileBrowserLabel => Platform.isMacOS
    ? 'Reveal in Finder'
    : Platform.isWindows
    ? 'Reveal in File Explorer'
    : 'Show in File Manager';

/// Opens the platform file browser with [path] selected, falling back to
/// opening the containing directory where no select verb exists.
Future<void> revealInFileBrowser(String path) async {
  if (Platform.isMacOS) {
    await Process.start('open', ['-R', path], mode: ProcessStartMode.detached);
  } else if (Platform.isWindows) {
    await Process.start('explorer', [
      '/select,$path',
    ], mode: ProcessStartMode.detached);
  } else {
    await Process.start('xdg-open', [
      File(path).parent.path,
    ], mode: ProcessStartMode.detached);
  }
}
