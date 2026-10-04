/// The web GPU shim: flutter_gpu's API over a browser backend, behind
/// backend-neutral interfaces. WebGL2 is the one backend today.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart' as vm;

import '../shared/encoded_image_types.dart';
import '../shared/gpu_capabilities.dart';
import 'webgl/_webgl.dart' show createWebGlBackend;

part 'backend.dart';
part 'formats.dart';
part 'types.dart';
part 'vertex_layout.dart';
