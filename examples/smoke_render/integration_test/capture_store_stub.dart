import 'dart:typed_data';

/// No device storage to write to; the host driver's report carries the frame.
Future<void> storeCapture(String name, Uint8List png) async {}

/// Always false, so every scene renders.
Future<bool> alreadyPassed(String id) async => false;

Future<void> markPassed(String id) async {}
