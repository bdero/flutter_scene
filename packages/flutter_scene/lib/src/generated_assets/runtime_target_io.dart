import 'dart:io' show Platform;

/// Spelled as `OS.name` spells it, which is what the build records.
String? get runtimeOperatingSystem => Platform.operatingSystem;
