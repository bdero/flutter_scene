import 'package:flutter_scene_xr/src/web/webxr_js_backend.dart';
import 'package:flutter_scene_xr/src/webxr/webxr_session.dart';
import 'package:flutter_scene_xr/src/xr_runtime.dart';

/// The runtime on the web, WebXR over the browser.
XrRuntime createRuntime() => WebXrRuntime(const JsWebXrBackend());
