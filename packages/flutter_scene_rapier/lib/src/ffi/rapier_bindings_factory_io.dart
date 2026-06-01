// Native backend factory: the shim is a dynamic library reached over
// dart:ffi, available the moment it is constructed, so readiness is a
// no-op.

import 'package:flutter_scene_rapier/src/ffi/rapier_bindings.dart';
import 'package:flutter_scene_rapier/src/ffi/rapier_bindings_native.dart';

/// Nothing to load: the native library is bundled and linked by the SDK.
Future<void> ensureRapierReady() async {}

/// Creates a world backed by the native shim.
RapierBindings createRapierBindings() => NativeRapierBindings();
