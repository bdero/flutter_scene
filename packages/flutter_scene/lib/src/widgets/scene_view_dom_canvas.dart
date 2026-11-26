// The DOM canvas a web SceneView presents to with ScenePresentation.domCanvas.
// Native has none, so the view always draws into Flutter's canvas.
export 'scene_view_dom_canvas_stub.dart'
    if (dart.library.js_interop) 'scene_view_dom_canvas_web.dart';
