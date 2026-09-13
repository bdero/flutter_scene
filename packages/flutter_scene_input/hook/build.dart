import 'package:hooks/hooks.dart';

import 'package:flutter_scene_input/src/native_hook.dart';

/// Compiles the package's native input library.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildNativeLibrary(input, output);
  });
}
