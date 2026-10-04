/// The web GPU shim: flutter_gpu's API over a browser backend chosen per
/// build, WebGL2 by default or WebGPU with `--dart-define=flutter_scene.webgpu=true`.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart' as vm;

import '../shared/encoded_image_types.dart';
import '../shared/gpu_capabilities.dart';
import '../webgpu/webgpu_backend.dart' show createWebGpuBackend;
import 'webgl/_webgl.dart' show createWebGlBackend;

part 'backend.dart';
part 'formats.dart';
part 'types.dart';
part 'vertex_layout.dart';
