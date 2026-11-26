import 'dart:io';
import 'dart:typed_data';

/// Saves a captured frame as `<directory>/<name>.png`.
Future<void> benchSaveCapture(
  String directory,
  String name,
  Uint8List png,
) async {
  await Directory(directory).create(recursive: true);
  await File('$directory/$name.png').writeAsBytes(png);
}
