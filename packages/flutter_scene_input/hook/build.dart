import 'package:hooks/hooks.dart';

import 'package:flutter_scene_input/src/pointer_lock/pointer_lock_hook.dart';

/// Compiles the desktop pointer lock library.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildPointerLockLibrary(input, output);
  });
}
