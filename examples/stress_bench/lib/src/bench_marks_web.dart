import 'package:web/web.dart' as web;

/// Marks a point on the page's trace timeline (`blink.user_timing`).
void benchMark(String name) => web.window.performance.mark(name);

/// The WebGL renderer string, to confirm the page runs on the real GPU.
String gpuRendererName() {
  final canvas = web.OffscreenCanvas(1, 1);
  final gl = canvas.getContext('webgl2') as web.WebGL2RenderingContext?;
  if (gl == null) return 'no webgl2';
  final info = gl.getExtension('WEBGL_debug_renderer_info');
  if (info == null) return 'unknown';
  return '${gl.getParameter(0x9246)}'; // UNMASKED_RENDERER_WEBGL
}
