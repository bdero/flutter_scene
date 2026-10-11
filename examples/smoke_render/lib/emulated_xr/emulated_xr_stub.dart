import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

Never _unsupported() =>
    throw UnsupportedError('The emulated WebXR device exists on the web only.');

/// Whether the emulator script is loaded.
bool get emulatedXrSupported => false;

/// Installs the emulated device over `navigator.xr` with the given head pose.
Future<void> installEmulatedXr({
  required Vector3 position,
  required Quaternion orientation,
}) => _unsupported();

/// The pixel size the emulated layer renders at.
({int width, int height}) emulatedLayerSize() => _unsupported();

/// A framebuffer with an RGBA8 color store on the backend's own context.
({Object framebuffer, Object texture}) createBackendFramebuffer(
  int width,
  int height,
) => _unsupported();

/// The framebuffer's pixels, rows top-down.
Uint8List readBackendFramebuffer(Object framebuffer, int width, int height) =>
    _unsupported();

void deleteBackendFramebuffer(({Object framebuffer, Object texture}) target) =>
    _unsupported();
