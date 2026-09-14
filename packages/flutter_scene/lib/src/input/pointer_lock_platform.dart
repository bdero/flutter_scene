export 'package:flutter_scene/src/input/pointer_lock_backend_stub.dart'
    if (dart.library.ffi) 'package:flutter_scene/src/input/pointer_lock_backend_native.dart'
    if (dart.library.js_interop) 'package:flutter_scene/src/input/pointer_lock_backend_web.dart';
