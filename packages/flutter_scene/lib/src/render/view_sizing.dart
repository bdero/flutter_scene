import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

/// The view-projection of the view being rendered, which geometry sized in
/// screen pixels measures its width against.
///
/// Every pass inside the view reads the same value, so a shadow or
/// reflection pass, which draws with its own camera, sizes a pixel-wide
/// line as the view shows it.
final Float32List currentViewSizingTransform = Float32List(16)
  ..[0] = 1.0
  ..[5] = 1.0
  ..[10] = 1.0
  ..[15] = 1.0;

/// The logical width and height of the view being rendered.
final Float32List currentViewSizingSize = Float32List(2)
  ..[0] = 1.0
  ..[1] = 1.0;

/// Sets [currentViewSizingTransform] and [currentViewSizingSize] for the
/// passes of one view.
void setCurrentViewSizing(Matrix4 viewProjection, ui.Size size) {
  currentViewSizingTransform.setAll(0, viewProjection.storage);
  currentViewSizingSize[0] = size.width;
  currentViewSizingSize[1] = size.height;
}
