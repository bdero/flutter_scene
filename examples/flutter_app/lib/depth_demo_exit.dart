// Quits a recording run of the depth precision demo. Desktop only; the web
// build has no process to end.
export 'depth_demo_exit_io.dart'
    if (dart.library.js_interop) 'depth_demo_exit_web.dart';
