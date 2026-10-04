/// The WebGL2 implementation of the web GPU shim.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

import '../../../generated_assets/generated_asset_fetch_web.dart';
import '../../shared/encoded_image_types.dart';
import '../../shared/glsl_transpile.dart';
import '../../shared/gpu_capabilities.dart';
import '../../shared/shader_library_sources.dart';
import '../_gpu.dart';
import '../shader_bundle_generated.dart' as fb;

part 'backend.dart';
part 'buffer.dart';
part 'command_buffer.dart';
part 'encoded_image.dart';
part 'gpu_context.dart';
part 'host.dart';
part 'mip_generator.dart';
part 'render_pass.dart';
part 'render_pipeline.dart';
part 'shader.dart';
part 'shader_library.dart';
part 'surface.dart';
part 'texture.dart';
