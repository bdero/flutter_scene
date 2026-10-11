import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_scene/scene.dart';

/// Whether this run can render scenes.
///
/// False on the web, where the WebGL2 shim exists but `flutter test` serves
/// no built shader bundles, so `Scene.initializeStaticResources` never
/// completes.
bool gpuAvailable() {
  if (kIsWeb) return false;
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}
