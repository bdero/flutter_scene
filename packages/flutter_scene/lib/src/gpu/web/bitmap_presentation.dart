/// Shows a backend's frames on a DOM canvas, for a view that presents outside
/// Flutter's own canvas.
library;

import 'package:web/web.dart' as web;

/// Shows [bitmap] on [canvas], an `HTMLCanvasElement`, through its
/// `bitmaprenderer` context, which takes the bitmap without a copy.
void presentBitmapToCanvas(web.ImageBitmap bitmap, Object canvas) {
  final element = canvas as web.HTMLCanvasElement;
  if (element.width != bitmap.width) element.width = bitmap.width;
  if (element.height != bitmap.height) element.height = bitmap.height;
  final context = element.getContext('bitmaprenderer');
  if (context == null) {
    throw StateError('The canvas has no bitmaprenderer context.');
  }
  (context as web.ImageBitmapRenderingContext).transferFromImageBitmap(bitmap);
}
