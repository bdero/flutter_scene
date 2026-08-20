// Locates the Draco fixture directory whether tests run from the package
// directory or the workspace root.

import 'dart:io';

final String fixtureDir = () {
  for (final candidate in [
    'test/fixtures/draco',
    'packages/flutter_scene/test/fixtures/draco',
  ]) {
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return 'test/fixtures/draco';
}();
